// GTK+
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const util = @import("../util.zig");
const config = @import("../config.zig");
const simple_buffer = @import("../simple_buffer.zig");
const toot_lib = @import("../toot.zig");
const thread = @import("../thread.zig");
const json_lib = @import("../json.zig");

const c = @cImport({
  @cInclude("gtk/gtk.h");
});

const GUIError = error{GtkInit, GladeLoad};
var allocator: *Allocator = undefined;
var settings: *config.Settings = undefined;
pub const queue = std.ArrayList(u8).init(allocator);
var myActor: *thread.Actor = undefined;
var myAllocation = c.GtkAllocation{.x=-1, .y=-1, .width=0, .height=0};

pub const Column = struct {
  builder: [*c]c.GtkBuilder,
  columnbox: [*c]c.GtkWidget,
  config_window: [*c]c.GtkWidget,
  main: *config.ColumnInfo,
  guitoots: std.hash_map.AutoHashMap([]const u8, *c.GtkBuilder)
};

var columns:std.ArrayList(*Column) = undefined;
var myBuilder: *c.GtkBuilder = undefined;
var myCssProvider: [*c]c.GtkCssProvider = undefined;

pub fn libname() []const u8 {
  return "GTK";
}

pub fn init(alloca: *Allocator, set: *config.Settings) !void {
  warn("{} started\n", libname());
  settings = set;
  allocator = alloca;
  columns = std.ArrayList(*Column).init(allocator);
  var argc: c_int = undefined;
  var argv: ?[*]?[*]?[*]u8 = null;
  var tf = c.gtk_init_check(@ptrCast([*]c_int, &argc), argv);
  if(tf != 1) return GUIError.GtkInit;
}

pub fn gui_setup(actor: *thread.Actor) !void {
  myActor = actor;
  // GtkCssProvider *cssProvider = gtk_css_provider_new();
  myCssProvider = c.gtk_css_provider_new();
  _ = c.gtk_css_provider_load_from_path(myCssProvider, c"theme.css", null);
  c.gtk_style_context_add_provider_for_screen(c.gdk_screen_get_default(),
                         @ptrCast(*c.GtkStyleProvider, myCssProvider),
                         c.GTK_STYLE_PROVIDER_PRIORITY_USER);

  myBuilder = c.gtk_builder_new();
  var ret = c.gtk_builder_add_from_file (myBuilder, c"glade/zootdeck.glade", @intToPtr([*c][*c]c._GError, 0));
  if (ret == 0) {
    warn("builder file fail");
    return GUIError.GladeLoad;
  }
  _ = c.gtk_builder_add_callback_symbol(myBuilder, c"actionbar.add", actionbar_add);
  _ = c.gtk_builder_add_callback_symbol(myBuilder, c"zoot_drag", zoot_drag);
  _ = c.gtk_builder_add_callback_symbol(myBuilder, c"main_check_resize",
                                        @ptrCast(?extern fn() void, main_check_resize));
  _ = c.gtk_builder_connect_signals(myBuilder, null);


  // set main size before resize callback happens
  var main_window = builder_get_widget(myBuilder, c"main");
  var w = @intCast(c.gint, settings.win_x);
  var h = @intCast(c.gint, settings.win_y);
//  c.gtk_widget_set_size_request(main_window, w, h);
  c.gtk_window_resize(@ptrCast([*c]c.GtkWindow, main_window), w, h);
  warn("{} gui_setup done\n", libname());
}

fn builder_get_widget(builder: *c.GtkBuilder, name: [*]const u8)[*]c.GtkWidget {
  var gobject = @ptrCast([*c]c.GTypeInstance, c.gtk_builder_get_object(builder, name));
  var gwidget = @ptrCast([*c]c.GtkWidget, c.g_type_check_instance_cast(gobject, c.gtk_widget_get_type()));
  return gwidget;
}

pub fn schedule(func: ?extern fn(*c_void) c_int, param: *c_void) void {
  _ = c.gdk_threads_add_idle(func, param);
}

fn hide_column_config(column: *Column) void {
  c.gtk_widget_hide(column.config_window);
}

pub extern fn show_login_schedule(in: *c_void) c_int {
  var login_window = builder_get_widget(myBuilder, c"login");
  c.gtk_widget_show(login_window);
  return 0;
}

pub extern fn show_main_schedule(in: *c_void) c_int {
  var main_window = builder_get_widget(myBuilder, c"main");
  c.gtk_widget_show(main_window);
  return 0;
}

pub extern fn column_config_oauth_url_schedule(in: *c_void) c_int {
  const column = @ptrCast(*config.ColumnInfo, @alignCast(8,in));
  column_config_oauth_url(column);
  return 0;
}

pub extern fn update_author_photo_schedule(in: *c_void) c_int {
  const cAcct = @ptrCast([*c]const u8, @alignCast(8,in));
  const acct = util.cstrToSliceCopy(allocator, cAcct);
  update_author_photo(acct);
  return 0;
}

pub extern fn update_column_ui_schedule(in: *c_void) c_int {
  const columnInfo = @ptrCast(*config.ColumnInfo, @alignCast(8,in));
  const column = findColumnByInfo(columnInfo);
  update_column_ui(column);
  return 0;
}

pub const TootPic = struct { toot: toot_lib.Toot(), pic: []const u8 };
pub extern fn toot_media_schedule(in: *c_void) c_int {
  const tootpic = @ptrCast(*TootPic, @alignCast(8,in));
  toot_media(tootpic.toot, tootpic.pic);
  return 0;
}

pub extern fn add_column_schedule(in: *c_void) c_int {
  const column = @ptrCast(*config.ColumnInfo, @alignCast(8,in));
  add_column(column);
  return 0;
}

pub fn add_column(colInfo: *config.ColumnInfo) void {
  const container = builder_get_widget(myBuilder, c"ZootColumns");
  const column = allocator.create(Column) catch unreachable;
  column.builder = c.gtk_builder_new_from_file (c"glade/column.glade");
  column.columnbox = builder_get_widget(column.builder, c"column");
  column.main = colInfo;
  var line_buf: []u8 = allocator.alloc(u8, 255) catch unreachable;
  column.config_window = builder_get_widget(column.builder, c"column_config");
  c.gtk_window_resize(@ptrCast([*c]c.GtkWindow, column.config_window), 600, 200);
  column.guitoots = std.hash_map.AutoHashMap([]const u8, *c.GtkBuilder).init(allocator);
  columns.append(column) catch unreachable;
  columns_resize();
  warn("column added {}\n", column.main.makeTitle());
  const footer = builder_get_widget(column.builder, c"column_footer");
  const config_icon = builder_get_widget(column.builder, c"column_config_icon");
  c.gtk_misc_set_alignment(@ptrCast([*c]c.GtkMisc,config_icon), 1, 0);

  update_column_ui(column);

  c.gtk_grid_attach_next_to(@ptrCast([*c]c.GtkGrid, container), column.columnbox, null, c.GtkPositionType.GTK_POS_LEFT, 1, 1);

  _ = c.gtk_builder_add_callback_symbol(column.builder,
                                        c"column.title",
                                        @ptrCast(?extern fn() void, column_top_label_title));
  _ = c.gtk_builder_add_callback_symbol(column.builder,
                                        c"column.config",
                                        @ptrCast(?extern fn() void, column_config_btn));
  _ = c.gtk_builder_add_callback_symbol(column.builder,
                                        c"column.reload",
                                        @ptrCast(?extern fn() void, column_reload));
  _ = c.gtk_builder_add_callback_symbol(column.builder,
                                        c"column.imgonly",
                                        @ptrCast(?extern fn() void, column_imgonly));
  _ = c.gtk_builder_add_callback_symbol(column.builder,
                                        c"column_config.done",
                                        @ptrCast(?extern fn() void, column_config_done));
  _ = c.gtk_builder_add_callback_symbol(column.builder,
                                        c"column_config.remove",
                                        @ptrCast(?extern fn() void, column_remove_btn));
  _ = c.gtk_builder_add_callback_symbol(column.builder,
                                        c"column_config.oauth_btn",
                                        @ptrCast(?extern fn() void, column_config_oauth_btn));
  _ = c.gtk_builder_add_callback_symbol(column.builder,
                                        c"column_config.oauth_auth_enter",
                                        @ptrCast(?extern fn() void, column_config_oauth_activate));
  _ = c.gtk_builder_add_callback_symbol(column.builder, c"zoot_drag", zoot_drag);
  _ = c.gtk_builder_connect_signals(column.builder, null);
  c.gtk_widget_show_all(container);
}

pub fn update_author_photo(acct: []const u8) void {
  warn("Update_author_photo {}\n", acct);
  // all toots in all columns :O
  for(columns.toSlice()) |column| {
    const toots = column.main.toots.author(acct, allocator);
    for(toots) |toot| {
      warn("update_author_photo {} {} {}\n", column.main.config.url, acct, toot.id());
      var tootbuilderMaybe = column.guitoots.get(toot.id());
      if(tootbuilderMaybe) |kv| {
        photo_refresh(acct, kv.value);
      }
    }
  }
}

pub fn columns_resize() void {
  if(columns.len > 0) {
    const container = builder_get_widget(myBuilder, c"ZootColumns");
    var app_width = c.gtk_widget_get_allocated_width(container);
    var avg_col_width = @divTrunc(app_width, @intCast(c_int, columns.len));
    warn("columns_resize app_width {} col_len {} avg_col_width {}\n", app_width, columns.len, avg_col_width);
    for(columns.toSlice()) |col| {
      //c.gtk_widget_set_size_request(col.columnbox, col_width, -1);
      //var gnomeFunny = c.GtkAllocation{x=0, y=0,width=0,height=0};
      c.gtk_widget_get_allocation(col.columnbox, &myAllocation);
      warn("columns_resize {}\n", myAllocation);
      //var col_width = c.gtk_widget_get_allocated_width(col.columnbox);
      //warn("columns_resize get_allocated_width {}\n", col_width);
    }
  }
}

pub fn update_column_ui(column: *Column) void {
  const label = builder_get_widget(column.builder, c"column_top_label");
  var topline_null: []u8 = undefined;
  const title_null = util.sliceAddNull(allocator, column.main.makeTitle());
  c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel,label), title_null.ptr);
}

pub extern fn column_remove_schedule(in: *c_void) c_int {
  column_remove(@ptrCast(*config.ColumnInfo, @alignCast(8,in)));
  return 0;
}

pub fn column_remove(colInfo: *config.ColumnInfo) void {
  warn("gui.column_remove {}\n", colInfo.config.title);
  const container = builder_get_widget(myBuilder, c"ZootColumns");
  const column = findColumnByInfo(colInfo);
  hide_column_config(column);
  c.gtk_container_remove(@ptrCast([*c]c.GtkContainer, container), column.columnbox);
}

//pub const GCallback = ?extern fn() void;
extern fn column_top_label_title(p: *c_void) void {
  warn("column_top_label_title {}\n", p);
}

pub extern fn update_column_toots_schedule(in: *c_void) c_int {
  const c_column = @ptrCast(*config.ColumnInfo, @alignCast(8,in));
  var columnMaybe = find_gui_column(c_column);
  if(columnMaybe) |column| {
    update_column_toots(column);
  }
  return 0;
}

pub extern fn update_column_config_oauth_finalize_schedule(in: *c_void) c_int {
  const c_column = @ptrCast(*config.ColumnInfo, @alignCast(8,in));
  var columnMaybe = find_gui_column(c_column);
  if(columnMaybe) |column| {
    column_config_oauth_finalize(column);
  }
  return 0;
}

pub extern fn update_column_netstatus_schedule(in: *c_void) c_int {
  const http = @ptrCast(*config.HttpInfo, @alignCast(8,in));
  var columnMaybe = find_gui_column(http.column);
  if(columnMaybe) |column| {
    update_netstatus_column(http, column);
  }
  return 0;
}

fn find_gui_column(c_column: *config.ColumnInfo) ?*Column {
  var column: *Column = undefined;
  for(columns.toSlice()) |col| {
    if(col.main == c_column) return col;
  }
  return null;
}

pub fn update_column_toots(column: *Column) void {
  warn("update_column {} {} toots {}\n", column.main.config.title,
                column.main.toots.count(),
                if(column.main.inError) "ERROR" else "");
  const column_toot_zone = builder_get_widget(column.builder, c"toot_zone");
  const column_footer_count_label = builder_get_widget(column.builder, c"column_footer_count");
  var gtk_context = c.gtk_widget_get_style_context(column_footer_count_label);
  c.gtk_container_foreach(@ptrCast([*c]c.GtkContainer, column_toot_zone), widget_destroy, null); // todo: avoid this
  if(column.main.inError) {
    c.gtk_style_context_add_class(gtk_context, c"net_error");
  } else {
    c.gtk_style_context_remove_class(gtk_context, c"net_error");
  }
  var current = column.main.toots.first();
  if (current != null) {
    while(current) |node| {
      const toot = node.data;
      const tootbuilder =  makeTootBox(toot, column.main.config);
      var tootbox = builder_get_widget(tootbuilder, c"tootbox");
      c.gtk_box_pack_start(@ptrCast([*c]c.GtkBox, column_toot_zone), tootbox,
                          c.gtk_true(), c.gtk_true(), 0);
      _ = column.guitoots.put(toot.id(), tootbuilder) catch unreachable;
      current = node.next;
    }
  } else {
    // help? logo?
  }
  c.gtk_widget_show(column_toot_zone);

  const countStr = std.fmt.allocPrint(allocator, "{} toots", column.main.toots.count()) catch unreachable;
  const cCountStr = util.sliceToCstr(allocator, countStr);
  c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, column_footer_count_label), cCountStr);
}

pub fn update_netstatus_column(http: *config.HttpInfo, column: *Column) void {
  warn("update_netstatus_column {} {}\n", http.url, http.response_code);
  const column_footer_netstatus = builder_get_widget(column.builder, c"column_footer_netstatus");
  var netmsg: [*c]const u8 = undefined;
  if(http.response_code == 0) {
    c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, column_footer_netstatus), c"GET");
  } else if (http.response_code >= 200 and http.response_code < 300) {
    c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, column_footer_netstatus), c"OK");
  } else if (http.response_code >= 300 and http.response_code < 400) {
    c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, column_footer_netstatus), c"redirect");
  } else if (http.response_code >= 400 and http.response_code < 500) {
    if(http.response_code == 401) {
      c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, column_footer_netstatus), c"token bad");
    } else if(http.response_code == 404) {
      c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, column_footer_netstatus), c"404 err");
    } else {
      c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, column_footer_netstatus), c"4xx err");
    }
  } else if (http.response_code >= 500 and http.response_code < 600) {
    c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, column_footer_netstatus), c"5xx err");
  } else if (http.response_code >= 1000 and http.response_code < 1100) {
    c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, column_footer_netstatus), c"json err");
  } else if (http.response_code == 2100) {
    c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, column_footer_netstatus), c"DNS err");
  } else if (http.response_code == 2200) {
    c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, column_footer_netstatus), c"timeout err");
  }
}

extern fn widget_destroy(widget: [*c]c.GtkWidget, userdata: ?*c_void) void {
  //warn("destroying {*}\n", widget);
  c.gtk_widget_destroy(widget);
}

pub fn makeTootBox(toot: toot_lib.Toot(), colconfig: *config.ColumnConfig) [*c]c.GtkBuilder {
  const builder = c.gtk_builder_new_from_file (c"glade/toot.glade");
  const tootbox = builder_get_widget(builder, c"tootbox");

  const id = toot.get("id").?.value.String;
  const account = toot.get("account").?.value.Object;
  const author_acct = account.get("acct").?.value.String;

  const author_name = account.get("display_name").?.value.String;
  const author_url = account.get("url").?.value.String;
  const created_at = toot.get("created_at").?.value.String;

  const name_label = builder_get_widget(builder, c"toot_author_name");
  labelBufPrint(name_label, "{}", author_name);
  const url_label = builder_get_widget(builder, c"toot_author_url");
  labelBufPrint(url_label, "{}", author_url);
  const author_url_minimode_label = builder_get_widget(builder, c"toot_author_url_minimode");
  labelBufPrint(author_url_minimode_label, "{}", author_url);
  const date_label = builder_get_widget(builder, c"toot_date");
  labelBufPrint(date_label, "{}", created_at);

  const content = toot.get("content").?.value.String;
  var jDecode = json_lib.jsonStrDecode(content, allocator)  catch unreachable;
  var hDecode = util.htmlEntityDecode(jDecode, allocator)  catch unreachable;
  const html_trim = util.htmlTagStrip(hDecode, allocator) catch unreachable;
  var line_limit = 50 / columns.len;
  const html_wrapped = hardWrap(html_trim, line_limit) catch unreachable;
  var cText = util.sliceToCstr(allocator, html_trim);

  const toottext_label = builder_get_widget(builder, c"toot_text");
  c.gtk_label_set_line_wrap_mode(@ptrCast([*c]c.GtkLabel, toottext_label), c.PangoWrapMode.PANGO_WRAP_WORD_CHAR);
  c.gtk_label_set_line_wrap(@ptrCast([*c]c.GtkLabel, toottext_label), 1);
  c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, toottext_label), cText);


  if(colconfig.img_only) {
    c.gtk_widget_hide(toottext_label);
    const id_row = builder_get_widget(builder, c"toot_id_row");
    c.gtk_widget_hide(id_row);
    c.gtk_widget_show(author_url_minimode_label);
  }
  photo_refresh(author_acct, builder);

  return builder;
}

fn photo_refresh(acct: []const u8, builder: *c.GtkBuilder) void {
  const avatar = builder_get_widget(builder, c"toot_author_avatar");
  const avatar_path = std.fmt.allocPrint(allocator, "./cache/{}/photo", acct) catch unreachable;
  var pixbuf = c.gdk_pixbuf_new_from_file_at_scale(util.sliceToCstr(allocator, avatar_path),
                                                   50, -1, 1, null);
  c.gtk_image_set_from_pixbuf(@ptrCast([*c]c.GtkImage, avatar), pixbuf);
}

fn toot_media(toot: toot_lib.Toot(), pic: []const u8) void {
  for(columns.toSlice()) |column| {
    var kvMaybe = column.guitoots.get(toot.id());
    if(kvMaybe) |kv| {
      const tootbuilder = kv.value;
      const imageBox = builder_get_widget(tootbuilder, c"image_box");
      c.gtk_widget_get_allocation(imageBox, &myAllocation);
      warn("toot_media image_box {}\n", myAllocation);
      var loader = c.gdk_pixbuf_loader_new();
      // todo: size-prepared signal
      var frameWidth = @floatToInt(c_int, @intToFloat(f32, myAllocation.width) * 0.9);
      c.gdk_pixbuf_loader_set_size(loader, frameWidth, frameWidth);
      const loadYN = c.gdk_pixbuf_loader_write(loader, pic.ptr, pic.len, null);
      if(loadYN == c.gtk_true()) {
        const account = toot.get("account").?.value.Object;
        const acct = account.get("acct").?.value.String;
        warn("toot_media pic data LOADED {} {}\n", acct, toot.id());
        var pixbuf = c.gdk_pixbuf_loader_get_pixbuf(loader);
        _ = c.gdk_pixbuf_loader_close(loader, null);
        if(pixbuf != null) {
          var new_img = c.gtk_image_new_from_pixbuf(pixbuf);
          c.gtk_box_pack_start(@ptrCast([*c]c.GtkBox, imageBox), new_img,
                              c.gtk_true(), c.gtk_true(), 0);
          c.gtk_widget_show(new_img);
        } else {
          warn("toot_media img from pixbuf FAILED\n");
        }
      } else {
        warn("pixbuf load FAILED of {} bytes\n", pic.len);
      }
    }
  }
}


fn hardWrap(str: []const u8, limit: usize) ![]const u8 {
  var wrapped = try simple_buffer.SimpleU8.initSize(allocator, 0);
  var short_lines = str.len / limit;
  var extra_bytes = str.len % limit;
  var idx = usize(0);
  while(idx < short_lines) : (idx += 1) {
    try wrapped.append(str[limit*idx .. limit*(idx+1)]);
    try wrapped.append("\n");
  }
  try wrapped.append(str[limit*idx .. (limit*idx)+extra_bytes]);
  return wrapped.toSliceConst();
}

fn escapeGtkString(str: []const u8) []const u8 {
  const str_esc_null = c.g_markup_escape_text(str.ptr, @intCast(c_long, str.len));
  const str_esc = util.cstrToSlice(allocator, str_esc_null);
  return str_esc;
}

pub fn labelBufPrint(label: [*c]c.GtkWidget, comptime fmt: []const u8, args: ...) void {
  const buf = allocator.alloc(u8, 256) catch unreachable;
  const str = std.fmt.bufPrint(buf, fmt, args) catch unreachable;
  const cStr = util.sliceToCstr(allocator, str);
  c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, label), cStr);
}

extern fn column_config_btn(columnptr: ?*c_void) void {
  var columnbox = @ptrCast([*c]c.GtkWidget, @alignCast(8,columnptr));
  var column: *Column = findColumnByBox(columnbox);

  columnConfigWriteGui(column);

  c.gtk_widget_show(column.config_window);
}

fn findColumnByInfo(info: *config.ColumnInfo) *Column {
  for(columns.toSlice()) |col| {
    if (col.main == info) {
      return col;
    }
  }
  unreachable;
}

fn findColumnByBox(box: [*c]c.GtkWidget) *Column {
  for(columns.toSlice()) |col| {
    if (col.columnbox == box) {
      return col;
    }
  }
  unreachable;
}

fn findColumnByConfigWindow(widget: [*c]c.GtkWidget) *Column {
  const parent = c.gtk_widget_get_toplevel(widget);
  for(columns.toSlice()) |col| {
    if (col.config_window == parent) {
      return col;
    }
  }
  warn("Config window not found for widget {} parent {}\n", widget, parent);
  unreachable;
}

extern fn main_check_resize(selfptr: *c_void) void {
  var self = @ptrCast([*c]c.GtkWidget, @alignCast(8,selfptr));
  var h: c.gint = undefined;
  var w: c.gint = undefined;
  c.gtk_window_get_size(@ptrCast([*c]c.GtkWindow, self), &w, &h);
  warn("main_check_resize, gtk_window_get_size {} x {}\n", w, h);
  if(w != settings.win_x) {
    warn("main_check_resize, win_x {} != w {}\n", settings.win_x, w);
    settings.win_x = w;
//    columns_resize();
  }
  if(h != settings.win_y) {
    warn("main_check_resize, win_x {} != w {}\n", settings.win_x, w);
    settings.win_y = h;
//    columns_resize();
  }
}

extern fn actionbar_add() void {
  warn("actionbar_add\n");
  thread.signal(myActor, &thread.Command{.id = 3, .verb = &thread.CommandVerb{.idle = undefined}});
}

extern fn zoot_drag() void {
  warn("zoot_drag\n");
}

extern fn column_reload(columnptr: *c_void) void {
  var column_widget = @ptrCast([*c]c.GtkWidget, @alignCast(8,columnptr));
  var column: *Column = findColumnByBox(column_widget);
  warn("column reload found {}\n", column.main.config.title);

  // signal crazy
  var command = allocator.create(thread.Command) catch unreachable;
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  verb.column = column.main;
  command.id = 2;
  command.verb = verb;
  thread.signal(myActor, command);
}

extern fn column_imgonly(columnptr: *c_void) void {
  var column_widget = @ptrCast([*c]c.GtkWidget, @alignCast(8,columnptr));
  var column: *Column = findColumnByBox(column_widget);

  // signal crazy
  var command = allocator.create(thread.Command) catch unreachable;
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  verb.column = column.main;
  command.id = 9; //imgonly button
  command.verb = verb;
  thread.signal(myActor, command);
}

extern fn column_remove_btn(selfptr: *c_void) void {
  var self = @ptrCast([*c]c.GtkWidget, @alignCast(8,selfptr));
  var column: *Column = findColumnByConfigWindow(self);
  warn("column remove {*}\n", column);

  // signal crazy
  var command = allocator.create(thread.Command) catch unreachable;
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  verb.column = column.main;
  command.id = 5;
  command.verb = verb;
  thread.signal(myActor, command);
}

extern fn column_config_oauth_btn(selfptr: *c_void) void {
  var self = @ptrCast([*c]c.GtkWidget, @alignCast(8,selfptr));
  var column: *Column = findColumnByConfigWindow(self);

  var oauth_box = builder_get_widget(column.builder, c"column_config_oauth_box");
  var host_box = builder_get_widget(column.builder, c"column_config_host_box");
  c.gtk_box_pack_end(@ptrCast([*c]c.GtkBox, host_box), oauth_box, 1, 0, 0);
  var oauth_label = builder_get_widget(column.builder, c"column_config_oauth_label");
  c.gtk_label_set_markup(@ptrCast([*c]c.GtkLabel, oauth_label), c"contacting server...");

  columnConfigReadGui(column);

  // signal crazy
  var command = allocator.create(thread.Command) catch unreachable;
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  verb.column = column.main;
  command.id = 6;
  command.verb = verb;
  warn("column_config_oauth_btn cmd vrb {*}\n", command.verb.column);
  thread.signal(myActor, command);
}

pub fn column_config_oauth_url(colInfo: *config.ColumnInfo) void {
  warn("gui.column_config_oauth_url {}\n", colInfo.config.title);
  const container = builder_get_widget(myBuilder, c"ZootColumns");
  const column = findColumnByInfo(colInfo);

  var oauth_box = builder_get_widget(column.builder, c"column_config_oauth_box");

  var oauth_label = builder_get_widget(column.builder, c"column_config_oauth_label");
  var oauth_url_buf = simple_buffer.SimpleU8.initSize(allocator, 0) catch unreachable;
  oauth_url_buf.append("https://") catch unreachable;
  oauth_url_buf.append(column.main.config.url) catch unreachable;
  oauth_url_buf.append("/oauth/authorize") catch unreachable;
  oauth_url_buf.append("?client_id=") catch unreachable;
  oauth_url_buf.append(column.main.oauthClientId.?) catch unreachable;
  oauth_url_buf.append("&amp;scope=read+write") catch unreachable;
  oauth_url_buf.append("&amp;response_type=code") catch unreachable;
  oauth_url_buf.append("&amp;redirect_uri=urn:ietf:wg:oauth:2.0:oob") catch unreachable;
  var markupBuf = allocator.alloc(u8, 512) catch unreachable;
  var markup = std.fmt.bufPrint(markupBuf, "<a href=\"{}\">{} oauth</a>",
    oauth_url_buf.toSliceConst(), column.main.config.url) catch unreachable;
  var cLabel = util.sliceToCstr(allocator, markup);
  c.gtk_label_set_markup(@ptrCast([*c]c.GtkLabel, oauth_label), cLabel);
}

extern fn column_config_oauth_activate(selfptr: *c_void) void {
  var self = @ptrCast([*c]c.GtkWidget, @alignCast(8,selfptr));
  var column: *Column = findColumnByConfigWindow(self);

  var token_entry = builder_get_widget(column.builder, c"column_config_authorization_entry");
  const cAuthorization = c.gtk_entry_get_text(@ptrCast([*c]c.GtkEntry, token_entry));
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
  var oauth_box = builder_get_widget(column.builder, c"column_config_oauth_box");
  var host_box = builder_get_widget(column.builder, c"column_config_host_box");
  c.gtk_container_remove(@ptrCast([*c]c.GtkContainer, host_box), oauth_box);
  columnConfigWriteGui(column);
  update_column_ui(column);
}

pub fn columnConfigWriteGui(column: *Column) void {
  var url_entry = builder_get_widget(column.builder, c"column_config_url_entry");
  var cUrl = util.sliceToCstr(allocator, column.main.config.url);
  c.gtk_entry_set_text(@ptrCast([*c]c.GtkEntry, url_entry), cUrl);

  var token_image = builder_get_widget(column.builder, c"column_config_token_image");
  var icon_name: [*c]const u8 = undefined;
  if(column.main.config.token) |tkn| {
    icon_name = c"gtk-apply";
  } else {
    icon_name = c"gtk-close";
  }
  c.gtk_image_set_from_icon_name (@ptrCast([*c]c.GtkImage, token_image),
                                  icon_name, c.GtkIconSize.GTK_ICON_SIZE_BUTTON);
}

pub fn columnConfigReadGui(column: *Column) void {
  var url_entry = builder_get_widget(column.builder, c"column_config_url_entry");
  var cUrl = c.gtk_entry_get_text(@ptrCast([*c]c.GtkEntry, url_entry));
  const newUrl =  util.cstrToSliceCopy(allocator, cUrl); // edit in guithread--
  if(std.mem.compare(u8, column.main.config.url, newUrl) != std.mem.Compare.Equal) {
    // host change
    column.main.config.url = newUrl;

    // signal crazy
    var command = allocator.create(thread.Command) catch unreachable;
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    verb.column = column.main;
    command.id = 8;
    command.verb = verb;
    thread.signal(myActor, command);
  }
}

extern fn column_config_done(selfptr: *c_void) void {
  var self = @ptrCast([*c]c.GtkWidget, @alignCast(8,selfptr));
  var column: *Column = findColumnByConfigWindow(self);

  columnConfigReadGui(column);

  update_column_ui(column);
  hide_column_config(column);

  // signal crazy
  var command = allocator.create(thread.Command) catch unreachable;
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  verb.column = column.main;
  command.id = 4;
  command.verb = verb;
  thread.signal(myActor, command);
}

fn signal_connect(window: [*c]c.GtkWidget, action: []const u8, fun: fn() void) !void {
  //var ret = g_signal_connect(@ptrCast(?*c.GtkWidget, window), action, fun, @ptrCast(?*c_void, window) );
  var ret = "".len;
  if(ret != 0) {
    warn("ERR signal connect {}\n", ret);
    return error.BadValue;
  }
}

fn g_signal_connect(instance: ?*c.GtkWidget, signal_name: []const u8, callback: fn () void, data: ?*c_void) c.gulong {
  //pub extern fn g_signal_connect_object(instance: gpointer,
  // detailed_signal: ?&const gchar, c_handler: GCallback, gobject: gpointer,
  // connect_flags: GConnectFlags) gulong;
  // typedef void* gpointer;
  var signal_name_null: []u8 = std.cstr.addNullByte(allocator, signal_name) catch unreachable;
  return c.g_signal_connect_object(@ptrCast(c.gpointer, instance), signal_name_null.ptr,
    @ptrCast(c.GCallback, callback), data, c.GConnectFlags.G_CONNECT_AFTER);
}

pub fn mainloop() void {
  //  if(c.gtk_events_pending() != 0) {
  //  warn("gtk pending {}\n", c.gtk_events_pending());
  var exitcode = c.gtk_main_iteration();
  //    warn("gtk iteration exit {}\n", exitcode);
  //stop = false;
  //  }
  //  return false;
}

pub fn gtk_quit() void {
  warn("gtk signal destroy - gtk_main_quit\n");
  c.g_object_unref(myBuilder);
  //var window = @ptrCast(?&c.GtkWindow, data);
  //c.gtk_main_quit();
}

pub fn gtk_delete_event() void {
  warn("gtk signal delete-event\n");
  stop = true;
}

pub fn gui_end() void {
  warn("gui ended\n");
}
