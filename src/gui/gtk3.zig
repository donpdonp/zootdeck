// GTK+
const std = @import("std");
const util = @import("../util.zig");
const warn = util.log;
const config = @import("../config.zig");
const SimpleBuffer = @import("../simple_buffer.zig");
const toot_lib = @import("../toot.zig");
const thread = @import("../thread.zig");
const filter_lib = @import("../filter.zig");

const theme_css = @embedFile("theme.css");

const c = @cImport({
    @cInclude("gtk/gtk.h");
});

const GUIError = error{
    GtkInit,
    GladeLoad,
};

var allocator: std.mem.Allocator = undefined;
var settings: *config.Settings = undefined;
pub const queue = std.ArrayList(u8).init(allocator);
var myActor: *thread.Actor = undefined;
var myAllocation = c.GtkAllocation{ .x = -1, .y = -1, .width = 0, .height = 0 };

pub const Column = struct {
    builder: *c.GtkBuilder,
    columnbox: *c.GtkWidget,
    config_window: *c.GtkWidget,
    main: *config.ColumnInfo,
    guitoots: std.StringHashMap(*c.GtkBuilder),
};

var columns: std.ArrayList(*Column) = undefined;
var myBuilder: *c.GtkBuilder = undefined;
var myCssProvider: *c.GtkCssProvider = undefined;

pub fn libname() []const u8 {
    return "GTK";
}

pub fn init(alloca: std.mem.Allocator, set: *config.Settings) !void {
    warn("{s} init()", .{libname()});
    settings = set;
    allocator = alloca;
    columns = std.ArrayList(*Column).init(allocator);
    var argc: c_int = undefined;
    const argv: ?[*]?[*]?[*]u8 = null;
    const tf = c.gtk_init_check(@as([*]c_int, @ptrCast(&argc)), argv);
    if (tf != 1) return GUIError.GtkInit;
}

pub fn gui_setup(actor: *thread.Actor) !void {
    myActor = actor;
    // GtkCssProvider *cssProvider = gtk_css_provider_new();
    myCssProvider = c.gtk_css_provider_new();
    _ = c.gtk_css_provider_load_from_data(myCssProvider, theme_css, theme_css.len, null);
    c.gtk_style_context_add_provider_for_screen(c.gdk_screen_get_default(), @as(*c.GtkStyleProvider, @ptrCast(myCssProvider)), c.GTK_STYLE_PROVIDER_PRIORITY_USER);

    myBuilder = c.gtk_builder_new();
    const ret = c.gtk_builder_add_from_file(myBuilder, "glade/zootdeck.glade", @as([*c][*c]c._GError, @ptrFromInt(0)));
    if (ret == 0) {
        warn("builder file fail", .{});
        return GUIError.GladeLoad;
    }

    // Callbacks
    _ = c.gtk_builder_add_callback_symbol(myBuilder, "actionbar.add", actionbar_add);
    _ = c.gtk_builder_add_callback_symbol(myBuilder, "zoot_drag", zoot_drag);
    // captures all keys oh no
    // _ = c.gtk_builder_add_callback_symbol(myBuilder, "zoot.keypress",
    //                                       @ptrCast(?extern fn() void, zoot_keypress));
    _ = c.gtk_builder_add_callback_symbol(myBuilder, "main_check_resize", @ptrCast(&main_check_resize));
    _ = c.gtk_builder_connect_signals(myBuilder, null);

    // set main size before resize callback happens
    const main_window = builder_get_widget(myBuilder, "main");
    const w = @as(c.gint, @intCast(settings.win_x));
    const h = @as(c.gint, @intCast(settings.win_y));
    //  c.gtk_widget_set_size_request(main_window, w, h);
    c.gtk_window_resize(@as(*c.GtkWindow, @ptrCast(main_window)), w, h);
    _ = g_signal_connect(main_window, "destroy", gtk_quit, null);
}

fn builder_get_widget(builder: *c.GtkBuilder, name: [*]const u8) *c.GtkWidget {
    const gobject = @as(*c.GTypeInstance, @ptrCast(c.gtk_builder_get_object(builder, name)));
    const gwidget = @as(*c.GtkWidget, @ptrCast(c.g_type_check_instance_cast(gobject, c.gtk_widget_get_type())));
    return gwidget;
}

pub fn schedule(func: c.GSourceFunc, param: ?*anyopaque) void {
    _ = c.gdk_threads_add_idle(func, param);
}

fn hide_column_config(column: *Column) void {
    c.gtk_widget_hide(column.config_window);
}

pub fn show_login_schedule(in: *anyopaque) callconv(.C) c_int {
    _ = in;
    const login_window = builder_get_widget(myBuilder, "login");
    c.gtk_widget_show(login_window);
    return 0;
}

pub fn show_main_schedule(in: ?*anyopaque) callconv(.C) c_int {
    _ = in;
    const main_window = builder_get_widget(myBuilder, "main");
    c.gtk_widget_show(main_window);
    return 0;
}

pub fn column_config_oauth_url_schedule(in: ?*anyopaque) callconv(.C) c_int {
    const column = @as(*config.ColumnInfo, @ptrCast(@alignCast(in)));
    column_config_oauth_url(column);
    return 0;
}

pub fn update_author_photo_schedule(in: ?*anyopaque) callconv(.C) c_int {
    const cAcct = @as([*]const u8, @ptrCast(@alignCast(in)));
    const acct = util.cstrToSliceCopy(allocator, cAcct);
    update_author_photo(acct);
    return 0;
}

pub fn update_column_ui_schedule(in: ?*anyopaque) callconv(.C) c_int {
    const columnInfo = @as(*config.ColumnInfo, @ptrCast(@alignCast(in)));
    const column = findColumnByInfo(columnInfo);
    update_column_ui(column);
    return 0;
}

pub const TootPic = struct {
    toot: *toot_lib.Type,
    img: toot_lib.Img,
};

pub fn toot_media_schedule(in: ?*anyopaque) callconv(.C) c_int {
    const tootpic = @as(*TootPic, @ptrCast(@alignCast(in)));
    const toot = tootpic.toot;
    if (findColumnByTootId(toot.id())) |column| {
        const builder = column.guitoots.get(toot.id()).?;
        toot_media(column, builder, toot, tootpic.img.bytes);
    }
    return 0;
}

pub fn add_column_schedule(in: ?*anyopaque) callconv(.C) c_int {
    const column = @as(*config.ColumnInfo, @ptrCast(@alignCast(in)));
    add_column(column);
    return 0;
}

pub fn add_column(colInfo: *config.ColumnInfo) void {
    const container = builder_get_widget(myBuilder, "ZootColumns");
    const column = allocator.create(Column) catch unreachable;
    column.builder = c.gtk_builder_new_from_file("glade/column.glade");
    column.columnbox = builder_get_widget(column.builder, "column");
    column.main = colInfo;
    //var line_buf: []u8 = allocator.alloc(u8, 255) catch unreachable;
    column.config_window = builder_get_widget(column.builder, "column_config");
    c.gtk_window_resize(@as(*c.GtkWindow, @ptrCast(column.config_window)), 600, 200);
    column.guitoots = std.StringHashMap(*c.GtkBuilder).init(allocator);
    columns.append(column) catch unreachable;
    columns_resize();
    warn("gtk3.add_column {s}", .{util.json_stringify(column.main.makeTitle())});
    const filter = builder_get_widget(column.builder, "column_filter");
    const cFilter = util.sliceToCstr(allocator, column.main.config.filter);
    c.gtk_entry_set_text(@as(*c.GtkEntry, @ptrCast(filter)), cFilter);
    //const footer = builder_get_widget(column.builder, "column_footer");
    const config_icon = builder_get_widget(column.builder, "column_config_icon");
    c.gtk_misc_set_alignment(@as(*c.GtkMisc, @ptrCast(config_icon)), 1, 0);

    update_column_ui(column);

    c.gtk_grid_attach_next_to(@as(*c.GtkGrid, @ptrCast(container)), column.columnbox, null, c.GTK_POS_RIGHT, 1, 1);

    _ = c.gtk_builder_add_callback_symbol(column.builder, "column.title", @ptrCast(&column_top_label_title));
    _ = c.gtk_builder_add_callback_symbol(column.builder, "column.config", @ptrCast(&column_config_btn));
    _ = c.gtk_builder_add_callback_symbol(column.builder, "column.reload", @ptrCast(&column_reload));
    _ = c.gtk_builder_add_callback_symbol(column.builder, "column.imgonly", @ptrCast(&column_imgonly));
    _ = c.gtk_builder_add_callback_symbol(column.builder, "column.filter_done", @ptrCast(&column_filter_done));
    _ = c.gtk_builder_add_callback_symbol(column.builder, "column_config.done", @ptrCast(&column_config_done));
    _ = c.gtk_builder_add_callback_symbol(column.builder, "column_config.remove", @ptrCast(&column_remove_btn));
    _ = c.gtk_builder_add_callback_symbol(column.builder, "column_config.oauth_btn", @ptrCast(&column_config_oauth_btn));
    _ = c.gtk_builder_add_callback_symbol(column.builder, "column_config.oauth_auth_enter", @ptrCast(&column_config_oauth_activate));
    _ = c.gtk_builder_add_callback_symbol(column.builder, "zoot_drag", zoot_drag);
    _ = c.gtk_builder_connect_signals(column.builder, null);
    c.gtk_widget_show_all(container);
}

pub fn update_author_photo(acct: []const u8) void {
    // upodate all toots in all columns for this author
    for (columns.items) |column| {
        const toots = column.main.toots.author(acct, allocator);
        for (toots) |toot| {
            warn("update_author_photo column:{s} author:{s} toot#{s}", .{ column.main.filter.host(), acct, toot.id() });
            const tootbuilderMaybe = column.guitoots.get(toot.id());
            if (tootbuilderMaybe) |kv| {
                photo_refresh(acct, kv);
            }
        }
    }
}

pub fn columns_resize() void {
    if (columns.items.len > 0) {
        const container = builder_get_widget(myBuilder, "ZootColumns");
        const app_width = c.gtk_widget_get_allocated_width(container);
        const avg_col_width = @divTrunc(app_width, @as(c_int, @intCast(columns.items.len)));
        warn("columns_resize app_width {} col_width {} columns {}", .{ app_width, avg_col_width, columns.items.len });
        for (columns.items) |col| {
            c.gtk_widget_get_allocation(col.columnbox, &myAllocation);
        }
    }
}

pub fn update_column_ui(column: *Column) void {
    const label = builder_get_widget(column.builder, "column_top_label");
    //var topline_null: []u8 = undefined;
    const title_null = util.sliceAddNull(allocator, column.main.makeTitle());
    c.gtk_label_set_text(@as(*c.GtkLabel, @ptrCast(label)), title_null.ptr);
}

pub fn column_remove_schedule(in: ?*anyopaque) callconv(.C) c_int {
    column_remove(@as(*config.ColumnInfo, @ptrCast(@alignCast(in))));
    return 0;
}

pub fn column_remove(colInfo: *config.ColumnInfo) void {
    warn("gui.column_remove {s}\n", .{colInfo.config.title});
    const container = builder_get_widget(myBuilder, "ZootColumns");
    const column = findColumnByInfo(colInfo);
    hide_column_config(column);
    c.gtk_container_remove(@as(*c.GtkContainer, @ptrCast(container)), column.columnbox);
}

//pub const GCallback = ?extern fn() void;
fn column_top_label_title(p: *anyopaque) callconv(.C) void {
    warn("column_top_label_title {}\n", .{p});
}

pub fn update_column_toots_schedule(in: ?*anyopaque) callconv(.C) c_int {
    const c_column = @as(*config.ColumnInfo, @ptrCast(@alignCast(in)));
    const columnMaybe = find_gui_column(c_column);
    if (columnMaybe) |column| {
        update_column_toots(column);
    }
    return 0;
}

pub fn update_column_config_oauth_finalize_schedule(in: ?*anyopaque) callconv(.C) c_int {
    const c_column = @as(*config.ColumnInfo, @ptrCast(@alignCast(in)));
    const columnMaybe = find_gui_column(c_column);
    if (columnMaybe) |column| {
        column_config_oauth_finalize(column);
    }
    return 0;
}

pub fn update_column_netstatus_schedule(in: ?*anyopaque) callconv(.C) c_int {
    const http = @as(*config.HttpInfo, @ptrCast(@alignCast(in)));
    const columnMaybe = find_gui_column(http.column);
    if (columnMaybe) |column| {
        update_netstatus_column(http, column);
    }
    return 0;
}

fn find_gui_column(c_column: *config.ColumnInfo) ?*Column {
    //var column: *Column = undefined;
    for (columns.items) |col| {
        if (col.main == c_column) return col;
    }
    return null;
}

pub fn update_column_toots(column: *Column) void {
    warn("update_column_toots title: {s} toot count: {} guitoots: {} {s}", .{
        util.json_stringify(column.main.makeTitle()),
        column.main.toots.count(),
        column.guitoots.count(),
        if (column.main.inError) @as([]const u8, "INERROR") else @as([]const u8, ""),
    });
    const column_toot_zone = builder_get_widget(column.builder, "toot_zone");
    var current = column.main.toots.first();
    var idx: c_int = 0;
    if (current != null) {
        while (current) |node| {
            const toot: *toot_lib.Toot() = node.data;
            warn("update_column_toots building {*} #{s}", .{ toot, toot.id() });
            const tootbuilderMaybe = column.guitoots.get(toot.id());
            if (column.main.filter.match(toot)) {
                if (tootbuilderMaybe) |kv| {
                    const builder = kv;
                    destroyTootBox(builder);
                    warn("update_column_toots destroyTootBox toot #{s} {*} {*}", .{ toot.id(), toot, builder });
                }
                const tootbuilder = makeTootBox(toot, column);
                const tootbox = builder_get_widget(tootbuilder, "tootbox");
                _ = column.guitoots.put(toot.id(), tootbuilder) catch unreachable;
                c.gtk_box_pack_start(@as(*c.GtkBox, @ptrCast(column_toot_zone)), tootbox, c.gtk_true(), c.gtk_true(), 0);
                c.gtk_box_reorder_child(@as(*c.GtkBox, @ptrCast(column_toot_zone)), tootbox, idx);
            } else {
                if (tootbuilderMaybe) |kv| {
                    const builder = kv;
                    const tootbox = builder_get_widget(builder, "tootbox");
                    c.gtk_widget_hide(tootbox);
                    warn("update_column_toots hide toot #{s} {*} {*}", .{ toot.id(), toot, builder });
                }
            }

            current = node.next;
            idx += 1;
        }
    } else {
        // help? logo?
    }
    const column_footer_count_label = builder_get_widget(column.builder, "column_footer_count");
    const tootword = if (column.main.config.img_only) "images" else "posts";
    const countStr = std.fmt.allocPrint(allocator, "{} {s}", .{ column.main.toots.count(), tootword }) catch unreachable;
    const cCountStr = util.sliceToCstr(allocator, countStr);
    c.gtk_label_set_text(@ptrCast(column_footer_count_label), cCountStr);
}

pub fn update_netstatus_column(http: *config.HttpInfo, column: *Column) void {
    warn("update_netstatus_column {s} {s} status: {}", .{ column.main.filter.hostname, http.url, http.response_code });
    const column_footer_netstatus = builder_get_widget(column.builder, "column_footer_netstatus");
    const gtk_context_netstatus = c.gtk_widget_get_style_context(column_footer_netstatus);
    if (http.response_code == 0) { // active is a special case
        c.gtk_style_context_remove_class(gtk_context_netstatus, "net_error");
        c.gtk_style_context_add_class(gtk_context_netstatus, "net_active");
        c.gtk_label_set_text(@as(*c.GtkLabel, @ptrCast(column_footer_netstatus)), "GET");
    } else {
        c.gtk_style_context_remove_class(gtk_context_netstatus, "net_active");
    }
    if (http.response_code >= 200 and http.response_code < 300) {
        c.gtk_label_set_text(@as(*c.GtkLabel, @ptrCast(column_footer_netstatus)), "OK");
    } else if (http.response_code >= 300 and http.response_code < 400) {
        c.gtk_label_set_text(@as(*c.GtkLabel, @ptrCast(column_footer_netstatus)), "redirect");
    } else if (http.response_code >= 400 and http.response_code < 500) {
        column.main.inError = true;
        if (http.response_code == 401) {
            c.gtk_label_set_text(@as(*c.GtkLabel, @ptrCast(column_footer_netstatus)), "token bad");
        } else if (http.response_code == 404) {
            c.gtk_label_set_text(@as(*c.GtkLabel, @ptrCast(column_footer_netstatus)), "404 err");
        } else {
            c.gtk_label_set_text(@as(*c.GtkLabel, @ptrCast(column_footer_netstatus)), "4xx err");
        }
    } else if (http.response_code >= 500 and http.response_code < 600) {
        column.main.inError = true;
        c.gtk_label_set_text(@as(*c.GtkLabel, @ptrCast(column_footer_netstatus)), "5xx err");
    } else if (http.response_code >= 1000 and http.response_code < 1100) {
        column.main.inError = true;
        c.gtk_label_set_text(@as(*c.GtkLabel, @ptrCast(column_footer_netstatus)), "json err");
    } else if (http.response_code == 2100) {
        column.main.inError = true;
        c.gtk_label_set_text(@as(*c.GtkLabel, @ptrCast(column_footer_netstatus)), "DNS err");
    } else if (http.response_code == 2200) {
        column.main.inError = true;
        c.gtk_label_set_text(@as(*c.GtkLabel, @ptrCast(column_footer_netstatus)), "timeout");
    }
    if (column.main.inError) {
        c.gtk_style_context_add_class(gtk_context_netstatus, "net_error");
    } else {
        c.gtk_style_context_remove_class(gtk_context_netstatus, "net_error");
    }
}

fn widget_destroy(widget: *c.GtkWidget, userdata: ?*anyopaque) callconv(.C) void {
    //warn("destroying {*}\n", widget);
    _ = userdata;
    c.gtk_widget_destroy(widget);
}

pub fn destroyTootBox(builder: *c.GtkBuilder) void {
    const tootbox = builder_get_widget(builder, "tootbox");
    c.gtk_widget_destroy(tootbox);
    c.g_object_unref(builder);
}

pub fn makeTootBox(toot: *toot_lib.Type, column: *Column) *c.GtkBuilder {
    warn("maketootbox toot #{s} {*} gui building {} images", .{ toot.id(), toot, toot.imgList.items.len });
    const builder = c.gtk_builder_new_from_file("glade/toot.glade");

    //const id = toot.get("id").?.string;
    const account = toot.get("account").?.object;
    const author_acct = account.get("acct").?.string;

    const author_name = account.get("display_name").?.string;
    const author_url = account.get("url").?.string;
    const created_at = toot.get("created_at").?.string;

    warn("makeTootBox author_name {s}", .{author_name});
    const name_label = builder_get_widget(builder, "toot_author_name");
    labelBufPrint(@ptrCast(name_label), "{s}", .{author_name});
    const url_label = builder_get_widget(builder, "toot_author_url");
    labelBufPrint(@ptrCast(url_label), "{s}", .{author_url});
    const author_url_minimode_label = builder_get_widget(builder, "toot_author_url_minimode");
    labelBufPrint(@ptrCast(author_url_minimode_label), "{s}", .{author_url});
    const date_label = builder_get_widget(builder, "toot_date");
    labelBufPrint(@ptrCast(date_label), "{s}", .{created_at});
    photo_refresh(author_acct, builder);

    const hDecode = util.htmlEntityDecode(toot.content(), allocator) catch unreachable;
    const html_trim = util.htmlTagStrip(hDecode, allocator) catch unreachable;
    //var line_limit = 50 / columns.items.len;
    //const html_wrapped = hardWrap(html_trim, line_limit) catch unreachable;
    const cText = util.sliceToCstr(allocator, html_trim);

    const toottext_label = builder_get_widget(builder, "toot_text");
    c.gtk_label_set_line_wrap_mode(@as(*c.GtkLabel, @ptrCast(toottext_label)), c.PANGO_WRAP_WORD_CHAR);
    c.gtk_label_set_line_wrap(@as(*c.GtkLabel, @ptrCast(toottext_label)), 1);
    c.gtk_label_set_text(@as(*c.GtkLabel, @ptrCast(toottext_label)), cText);

    const tagBox = builder_get_widget(builder, "tag_flowbox");
    //var tagidx: usize = 0;
    for (toot.tagList.items) |tag| {
        const tag_len = if (tag.len > 40) 40 else tag.len;
        const cTag = util.sliceToCstr(allocator, tag[0..tag_len]);
        const tagLabel = c.gtk_label_new(cTag);
        const labelContext = c.gtk_widget_get_style_context(tagLabel);
        c.gtk_style_context_add_class(labelContext, "toot_tag");
        c.gtk_container_add(@as(*c.GtkContainer, @ptrCast(tagBox)), tagLabel);
        c.gtk_widget_show(tagLabel);
    }

    // show/hide parts to put widget into full or imgonly display
    const id_row = builder_get_widget(builder, "toot_id_row");
    const toot_separator = builder_get_widget(builder, "toot_separator");
    if (column.main.config.img_only) {
        c.gtk_widget_hide(toottext_label);
        c.gtk_widget_hide(id_row);
        if (toot.imgCount() == 0) {
            c.gtk_widget_hide(date_label);
            c.gtk_widget_hide(toot_separator);
        } else {
            c.gtk_widget_show(author_url_minimode_label);
            c.gtk_widget_show(date_label);
        }
    }

    for (toot.imgList.items) |img| {
        warn("toot #{s} rebuilding with img", .{toot.id()});
        toot_media(column, builder, toot, img.bytes);
    }

    return builder;
}

fn photo_refresh(acct: []const u8, builder: *c.GtkBuilder) void {
    const avatar = builder_get_widget(builder, "toot_author_avatar");
    const avatar_path = std.fmt.allocPrint(allocator, "./cache/accounts/{s}/photo", .{acct}) catch unreachable;
    const pixbuf = c.gdk_pixbuf_new_from_file_at_scale(util.sliceToCstr(allocator, avatar_path), 50, -1, 1, null);
    c.gtk_image_set_from_pixbuf(@ptrCast(avatar), pixbuf);
}

fn toot_media(column: *Column, builder: *c.GtkBuilder, toot: *toot_lib.Type, pic: []const u8) void {
    const imageBox = builder_get_widget(builder, "image_box");
    c.gtk_widget_get_allocation(column.columnbox, &myAllocation);
    const loader = c.gdk_pixbuf_loader_new();
    // todo: size-prepared signal
    const colWidth = @as(c_int, @intFromFloat(@as(f32, @floatFromInt(myAllocation.width)) / @as(f32, @floatFromInt(columns.items.len)) * 0.9));
    const colHeight: c_int = -1; // seems to work
    const colWidth_ptr = allocator.create(c_int) catch unreachable;
    colWidth_ptr.* = colWidth;
    _ = g_signal_connect(loader, "size-prepared", pixloaderSizePrepared, colWidth_ptr);
    const loadYN = c.gdk_pixbuf_loader_write(loader, pic.ptr, pic.len, null);
    if (loadYN == c.gtk_true()) {
        const pixbuf = c.gdk_pixbuf_loader_get_pixbuf(loader);
        //const account = toot.get("account").?.Object;
        //const acct = account.get("acct").?.String;
        const pixbufWidth = c.gdk_pixbuf_get_width(pixbuf);
        warn("toot_media #{s} {} images. win {}x{} col {}x{}px pixbuf {}px", .{
            toot.id(),
            toot.imgCount(),
            myAllocation.width,
            myAllocation.height,
            colWidth,
            colHeight,
            pixbufWidth,
        });
        _ = c.gdk_pixbuf_loader_close(loader, null);
        if (pixbuf != null) {
            const new_img = c.gtk_image_new_from_pixbuf(pixbuf);
            c.gtk_box_pack_start(@as(*c.GtkBox, @ptrCast(imageBox)), new_img, c.gtk_false(), c.gtk_false(), 0);
            c.gtk_widget_show(new_img);
        } else {
            warn("toot_media img from pixbuf FAILED", .{});
        }
    } else {
        warn("pixbuf load FAILED of {} bytes", .{pic.len});
    }
}

fn pixloaderSizePrepared(loader: *c.GdkPixbufLoader, img_width: c.gint, img_height: c.gint, data_ptr: *anyopaque) void {
    if (img_width > 0 and img_width < 65535 and img_height > 0 and img_height < 65535) {
        const colWidth = @as(*c_int, @ptrCast(@alignCast(data_ptr))).*;
        var scaleWidth = img_width;
        var scaleHeight = img_height;
        if (img_width > colWidth) {
            scaleWidth = colWidth;
            //const scale_factor = @divFloor(img_width, colWidth);
            const scale_factor = @as(f32, @floatFromInt(colWidth)) / @as(f32, @floatFromInt(img_width));
            scaleHeight = @as(c_int, @intFromFloat(@as(f32, @floatFromInt(img_height)) * scale_factor));
        }
        warn("toot_media pixloaderSizePrepared col width {}px img {}x{} scaled {}x{}", .{ colWidth, img_width, img_height, scaleWidth, scaleHeight });
        c.gdk_pixbuf_loader_set_size(loader, scaleWidth, scaleHeight);
    } else {
        warn("pixloaderSizePrepared img {}x{} was out of bounds", .{ img_width, img_height });
    }
}

fn hardWrap(str: []const u8, limit: usize) ![]const u8 {
    var wrapped = try SimpleBuffer.SimpleU8.initSize(allocator, 0);
    const short_lines = str.len / limit;
    const extra_bytes = str.len % limit;
    var idx: usize = 0;
    while (idx < short_lines) : (idx += 1) {
        try wrapped.append(str[limit * idx .. limit * (idx + 1)]);
        try wrapped.append("\n");
    }
    try wrapped.append(str[limit * idx .. (limit * idx) + extra_bytes]);
    return wrapped.toSliceConst();
}

fn escapeGtkString(str: []const u8) []const u8 {
    const str_esc_null = c.g_markup_escape_text(str.ptr, @as(c_long, @intCast(str.len)));
    const str_esc = util.cstrToSlice(allocator, str_esc_null);
    return str_esc;
}

pub fn labelBufPrint(label: *c.GtkLabel, comptime format: []const u8, text: anytype) void {
    const str = std.fmt.allocPrint(allocator, format, text) catch unreachable;
    const cstr = util.sliceToCstr(allocator, str);
    c.gtk_label_set_text(label, @ptrCast(cstr));
}

fn column_config_btn(columnptr: ?*anyopaque) callconv(.C) void {
    const columnbox = @as(*c.GtkWidget, @ptrCast(@alignCast(columnptr)));
    const column: *Column = findColumnByBox(columnbox);

    columnConfigWriteGui(column);

    c.gtk_widget_show(column.config_window);
}

fn findColumnByTootId(toot_id: []const u8) ?*Column {
    for (columns.items) |column| {
        const kvMaybe = column.guitoots.get(toot_id);
        if (kvMaybe) |_| {
            return column;
        }
    }
    return null;
}

fn findColumnByInfo(info: *config.ColumnInfo) *Column {
    for (columns.items) |col| {
        if (col.main == info) {
            return col;
        }
    }
    unreachable;
}

fn findColumnByBox(box: *c.GtkWidget) *Column {
    for (columns.items) |col| {
        if (col.columnbox == box) {
            return col;
        }
    }
    unreachable;
}

fn findColumnByConfigWindow(widget: *c.GtkWidget) *Column {
    const parent = c.gtk_widget_get_toplevel(widget);
    for (columns.items) |col| {
        if (col.config_window == parent) {
            return col;
        }
    }
    warn("Config window not found for widget {*} parent {*}\n", .{ widget, parent });
    unreachable;
}

fn main_check_resize(selfptr: *anyopaque) callconv(.C) void {
    const self = @as(*c.GtkWidget, @ptrCast(@alignCast(selfptr)));
    var h: c.gint = undefined;
    var w: c.gint = undefined;
    c.gtk_window_get_size(@as(*c.GtkWindow, @ptrCast(self)), &w, &h);
    if (w != settings.win_x) {
        warn("main_check_resize() win_x {} != gtk_width {}\n", .{ settings.win_x, w });
        settings.win_x = w;
        var verb = allocator.create(thread.CommandVerb) catch unreachable;
        verb.idle = undefined;
        var command = allocator.create(thread.Command) catch unreachable;
        command.id = 10;
        command.verb = verb;
        warn("main_check_resize() verb {*}\n", .{verb});
        thread.signal(myActor, command);
    }
    if (h != settings.win_y) {
        warn("main_check_resize, win_y {} != gtk_height {}\n", .{ settings.win_x, w });
        settings.win_y = h;
        var verb = allocator.create(thread.CommandVerb) catch unreachable;
        verb.idle = undefined;
        var command = allocator.create(thread.Command) catch unreachable;
        command.id = 10;
        command.verb = verb;
        thread.signal(myActor, command);
    }
}

fn actionbar_add() callconv(.C) void {
    warn("actionbar_add()", .{});
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    verb.idle = undefined;
    var command = allocator.create(thread.Command) catch unreachable;
    command.id = 3;
    command.verb = verb;
    thread.signal(myActor, command);
}

fn zoot_drag() callconv(.C) void {
    warn("zoot_drag\n", .{});
}

// rebulid half of GdkEventKey, avoiding bitfield
const EventKey = packed struct {
    _type: i32,
    window: *c.GtkWindow,
    send_event: i8,
    time: u32,
    state: u32,
    keyval: u32,
};

fn zoot_keypress(widgetptr: *anyopaque, evtptr: *EventKey) callconv(.C) void {
    _ = widgetptr;
    warn("zoot_keypress {}\n", .{evtptr});
}

fn column_reload(columnptr: *anyopaque) callconv(.C) void {
    const column_widget = @as(*c.GtkWidget, @ptrCast(@alignCast(columnptr)));
    const column: *Column = findColumnByBox(column_widget);
    warn("column reload found {s}\n", .{column.main.config.title});

    // signal crazy
    var command = allocator.create(thread.Command) catch unreachable;
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    verb.column = column.main;
    command.id = 2;
    command.verb = verb;
    thread.signal(myActor, command);
}

fn column_imgonly(columnptr: *anyopaque) callconv(.C) void {
    const column_widget = @as(*c.GtkWidget, @ptrCast(@alignCast(columnptr)));
    const column: *Column = findColumnByBox(column_widget);

    // signal crazy
    var command = allocator.create(thread.Command) catch unreachable;
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    verb.column = column.main;
    command.id = 9; //imgonly button press
    command.verb = verb;
    thread.signal(myActor, command);
}

fn column_remove_btn(selfptr: *anyopaque) callconv(.C) void {
    const self = @as(*c.GtkWidget, @ptrCast(@alignCast(selfptr)));
    const column: *Column = findColumnByConfigWindow(self);

    // signal crazy
    var command = allocator.create(thread.Command) catch unreachable;
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    verb.column = column.main;
    command.id = 5; // col remove button press
    command.verb = verb;
    thread.signal(myActor, command);
}

fn column_config_oauth_btn(selfptr: *anyopaque) callconv(.C) void {
    const self = @as(*c.GtkWidget, @ptrCast(@alignCast(selfptr)));
    var column: *Column = findColumnByConfigWindow(self);

    const oauth_box = builder_get_widget(column.builder, "column_config_oauth_box");
    const host_box = builder_get_widget(column.builder, "column_config_host_box");
    c.gtk_box_pack_end(@as(*c.GtkBox, @ptrCast(host_box)), oauth_box, 1, 0, 0);
    const oauth_label = builder_get_widget(column.builder, "column_config_oauth_label");
    c.gtk_label_set_markup(@as(*c.GtkLabel, @ptrCast(oauth_label)), "contacting server...");

    columnConfigReadGui(column);
    column.main.filter = filter_lib.parse(allocator, column.main.config.filter);

    // signal crazy
    var command = allocator.create(thread.Command) catch unreachable;
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    verb.column = column.main;
    command.id = 6;
    command.verb = verb;
    warn("column_config_oauth_btn cmd vrb {*}\n", .{command.verb.column});
    thread.signal(myActor, command);
}

pub fn column_config_oauth_url(colInfo: *config.ColumnInfo) void {
    warn("gui.column_config_oauth_url {s}\n", .{colInfo.config.title});
    //const container = builder_get_widget(myBuilder, "ZootColumns");
    const column = findColumnByInfo(colInfo);

    //var oauth_box = builder_get_widget(column.builder, "column_config_oauth_box");

    //const oauth_label = builder_get_widget(column.builder, "column_config_oauth_label");
    var oauth_url_buf = SimpleBuffer.SimpleU8.initSize(allocator, 0) catch unreachable;
    oauth_url_buf.append("https://") catch unreachable;
    oauth_url_buf.append(column.main.filter.host()) catch unreachable;
    oauth_url_buf.append("/oauth/authorize") catch unreachable;
    oauth_url_buf.append("?client_id=") catch unreachable;
    oauth_url_buf.append(column.main.oauthClientId.?) catch unreachable;
    oauth_url_buf.append("&amp;scope=read+write") catch unreachable;
    oauth_url_buf.append("&amp;response_type=code") catch unreachable;
    oauth_url_buf.append("&amp;redirect_uri=urn:ietf:wg:oauth:2.0:oob") catch unreachable;

    const oauth_label = builder_get_widget(column.builder, "column_config_oauth_label");
    const markupBuf = allocator.alloc(u8, 512) catch unreachable;
    const markup = std.fmt.bufPrint(markupBuf, "<a href=\"{s}\">{s} oauth</a>", .{ oauth_url_buf.toSliceConst(), column.main.filter.host() }) catch unreachable;
    const cLabel = util.sliceToCstr(allocator, markup);
    c.gtk_label_set_markup(@ptrCast(oauth_label), cLabel);
}

fn column_config_oauth_activate(selfptr: *anyopaque) callconv(.C) void {
    const self = @as(*c.GtkWidget, @ptrCast(@alignCast(selfptr)));
    const column: *Column = findColumnByConfigWindow(self);

    const token_entry = builder_get_widget(column.builder, "column_config_authorization_entry");
    const cAuthorization = c.gtk_entry_get_text(@as(*c.GtkEntry, @ptrCast(token_entry)));
    const authorization = util.cstrToSliceCopy(allocator, cAuthorization);

    // signal crazy
    var command = allocator.create(thread.Command) catch unreachable;
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    var auth = allocator.create(config.ColumnAuth) catch unreachable;
    auth.code = authorization;
    auth.column = column.main;
    verb.auth = auth;
    command.id = 7;
    command.verb = verb;
    thread.signal(myActor, command);
}

pub fn column_config_oauth_finalize(column: *Column) void {
    const oauth_box = builder_get_widget(column.builder, "column_config_oauth_box");
    const host_box = builder_get_widget(column.builder, "column_config_host_box");
    c.gtk_container_remove(@as(*c.GtkContainer, @ptrCast(host_box)), oauth_box);
    columnConfigWriteGui(column);
    update_column_ui(column);
}

pub fn columnConfigWriteGui(column: *Column) void {
    const url_entry = builder_get_widget(column.builder, "column_config_url_entry");
    const cUrl = util.sliceToCstr(allocator, column.main.filter.host());
    c.gtk_entry_set_text(@as(*c.GtkEntry, @ptrCast(url_entry)), cUrl);

    const token_image = builder_get_widget(column.builder, "column_config_token_image");
    var icon_name: []const u8 = undefined;
    if (column.main.config.token) |_| {
        icon_name = "gtk-apply";
    } else {
        icon_name = "gtk-close";
    }
    c.gtk_image_set_from_icon_name(@as(*c.GtkImage, @ptrCast(token_image)), util.sliceToCstr(allocator, icon_name), c.GTK_ICON_SIZE_BUTTON);
}

pub fn columnReadFilter(column: *Column) []const u8 {
    const filter_entry = builder_get_widget(column.builder, "column_filter");
    const cFilter = c.gtk_entry_get_text(@as(*c.GtkEntry, @ptrCast(filter_entry)));
    const filter = util.cstrToSliceCopy(allocator, cFilter); // edit in guithread--
    warn("columnReadFilter: ({}){s} ({}){s}\n", .{ column.main.config.title.len, column.main.config.title, filter.len, filter });
    return filter;
}

pub fn columnConfigReadGui(column: *Column) void {
    const url_entry = builder_get_widget(column.builder, "column_config_url_entry");
    const cUrl = c.gtk_entry_get_text(@as(*c.GtkEntry, @ptrCast(url_entry)));
    const newFilter = util.cstrToSliceCopy(allocator, cUrl); // edit in guithread--
    column.main.filter = filter_lib.parse(allocator, newFilter);
}

fn column_filter_done(selfptr: *anyopaque) callconv(.C) void {
    const self = @as(*c.GtkWidget, @ptrCast(@alignCast(selfptr)));
    var column: *Column = findColumnByBox(self);

    column.main.config.filter = columnReadFilter(column);
    column.main.filter = filter_lib.parse(allocator, column.main.config.filter);
    update_column_ui(column);

    // signal crazy
    var command = allocator.create(thread.Command) catch unreachable;
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    verb.column = column.main;
    command.id = 4; // save config
    command.verb = verb;
    thread.signal(myActor, command);

    // signal crazy
    command = allocator.create(thread.Command) catch unreachable;
    verb = allocator.create(thread.CommandVerb) catch unreachable;
    verb.column = column.main;
    command.id = 8; // update column UI
    command.verb = verb;
    thread.signal(myActor, command);
}

fn column_config_done(selfptr: *anyopaque) callconv(.C) void {
    const self = @as(*c.GtkWidget, @ptrCast(@alignCast(selfptr)));
    var column: *Column = findColumnByConfigWindow(self);

    columnConfigReadGui(column);
    column.main.filter = filter_lib.parse(allocator, column.main.config.filter);
    hide_column_config(column);

    // signal crazy
    var command = allocator.create(thread.Command) catch unreachable;
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    verb.column = column.main;
    command.id = 4; // save config
    command.verb = verb;
    thread.signal(myActor, command);
    // signal crazy
    command = allocator.create(thread.Command) catch unreachable;
    verb = allocator.create(thread.CommandVerb) catch unreachable;
    verb.column = column.main;
    command.id = 8; // update column UI
    command.verb = verb;
    thread.signal(myActor, command);
}

fn g_signal_connect(instance: anytype, signal_name: []const u8, callback: anytype, data: anytype) c.gulong {
    // pub extern fn g_signal_connect_data(instance: gpointer,
    // detailed_signal: [*]const gchar,
    // c_handler: GCallback,
    // data: gpointer,
    // destroy_data: GClosureNotify,
    // connect_flags: GConnectFlags) gulong;
    // connect_flags: GConnectFlags) gulong;
    // typedef void* gpointer;
    const signal_name_null: []const u8 = util.sliceAddNull(allocator, signal_name);
    const data_ptr: ?*anyopaque = data;
    const thing = @as(c.gpointer, @ptrCast(instance));
    return c.g_signal_connect_data(thing, signal_name_null.ptr, @ptrCast(&callback), data_ptr, null, c.G_CONNECT_AFTER);
}

pub fn mainloop() bool {
    var stop = false;
    //warn("gtk pending {}\n", .{c.gtk_events_pending()});
    //warn("gtk main level {}\n", .{c.gtk_main_level()});
    const exitcode = c.gtk_main_iteration();
    //warn("gtk main interaction return {}\n", .{exitcode});
    //if(c.gtk_events_pending() != 0) {
    if (exitcode == 0) {
        stop = true;
    }
    return stop;
}

pub fn gtk_quit() callconv(.C) void {
    warn("gtk signal destroy called.\n", .{});
    c.g_object_unref(myBuilder);
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    verb.idle = undefined;
    var command = allocator.create(thread.Command) catch unreachable;
    command.id = 11;
    command.verb = verb;
    thread.signal(myActor, command);
}

pub fn gui_end() void {
    warn("gui ended\n", .{});
}
