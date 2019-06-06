// gui-gtk.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const thread = @import("./thread.zig");
const util = @import("./util.zig");
const config = @import("./config.zig");
const simple_buffer = @import("./simple_buffer.zig");

const c = @cImport({
  @cInclude("gtk/gtk.h");
});

const GUIError = error{GtkInit, GladeLoad};
var allocator: *Allocator = undefined;
var settings: *config.Settings = undefined;
var stop = false;
pub const queue = std.ArrayList(u8).init(allocator);

pub const Column = struct {
  builder: [*c]c.GtkBuilder,
  columnbox: [*c]c.GtkWidget,
  config_window: [*c]c.GtkWidget,
  main: *config.ColumnInfo
};

var columns:std.ArrayList(*Column) = undefined;
var myBuilder: *c.GtkBuilder = undefined;
var myCssProvider: [*c]c.GtkCssProvider = undefined;

pub fn init(alloca: *Allocator, set: *config.Settings) !void {
  settings = set;
  allocator = alloca;
  columns = std.ArrayList(*Column).init(allocator);
  var argc: c_int = undefined;
  var argv: ?[*]?[*]?[*]u8 = null;
  var tf = c.gtk_init_check(@ptrCast([*]c_int, &argc), argv);
  if(tf != 1) return GUIError.GtkInit;
}

var myActor: *thread.Actor = undefined;
pub extern fn go(data: ?*c_void) ?*c_void {
  var data8 = @alignCast(@alignOf(thread.Actor), data);
  myActor = @ptrCast(*thread.Actor, data8);
  warn("gui-gtk thread start {*} {}\n", myActor, myActor);
  if (gui_setup()) {
    // mainloop
    while (!stop) {
        mainloop();
    }
    gui_end();
  } else |err| {
      warn("gui error {}\n", err);
  }
  return null;
}

pub fn gui_setup() !void {
  // GtkCssProvider *cssProvider = gtk_css_provider_new();
  myCssProvider = c.gtk_css_provider_new();
// gtk_css_provider_load_from_path(cssProvider, "theme.css", NULL);
  _ = c.gtk_css_provider_load_from_path(myCssProvider, c"theme.css", null);
// gtk_style_context_add_provider_for_screen(gdk_screen_get_default(),
//                                GTK_STYLE_PROVIDER(cssProvider),
//                                GTK_STYLE_PROVIDER_PRIORITY_USER);
  c.gtk_style_context_add_provider_for_screen(c.gdk_screen_get_default(),
    @ptrCast(*c.GtkStyleProvider, myCssProvider), c.GTK_STYLE_PROVIDER_PRIORITY_USER);

  myBuilder = c.gtk_builder_new();
  var ret = c.gtk_builder_add_from_file (myBuilder, c"glade/zootdeck.glade", @intToPtr([*c][*c]c._GError, 0));
  if (ret == 0) {
    warn("builder file fail");
    return GUIError.GladeLoad;
  }
  _ = c.gtk_builder_add_callback_symbol(myBuilder, c"login.chg", login_chg);
  _ = c.gtk_builder_add_callback_symbol(myBuilder, c"login.done", login_done);
  _ = c.gtk_builder_add_callback_symbol(myBuilder, c"actionbar.add", actionbar_add);
  _ = c.gtk_builder_add_callback_symbol(myBuilder, c"zoot_drag", zoot_drag);
  _ = c.gtk_builder_add_callback_symbol(myBuilder, c"main_check_resize",
                                        @ptrCast(?extern fn() void, main_check_resize));
  _ = c.gtk_builder_connect_signals(myBuilder, null);


  // set main size before resize callback happens
  var main_window = builder_get_widget(myBuilder, c"main");
  var w = @intCast(c.gint, settings.win_x);
  var h = @intCast(c.gint, settings.win_y);
  c.gtk_window_resize(@ptrCast([*c]c.GtkWindow, main_window), w, h);
}

fn builder_get_widget(builder: *c.GtkBuilder, name: [*]const u8)[*]c.GtkWidget {
  var gobject = @ptrCast([*c]c.GTypeInstance, c.gtk_builder_get_object(builder, name));
  var gwidget = @ptrCast([*c]c.GtkWidget, c.g_type_check_instance_cast(gobject, c.gtk_widget_get_type()));
  return gwidget;
}

pub fn schedule(func: ?extern fn(*c_void) c_int, param: *c_void) void {
  _ = c.gdk_threads_add_idle(func, param);
}

fn show_column_config() void {
  var column_config_window = builder_get_widget(myBuilder, c"column_config");
  c.gtk_widget_show(column_config_window);
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
  column_config_oauth_url(@ptrCast(*config.ColumnInfo, @alignCast(8,in)));
  return 0;
}

pub extern fn add_column_schedule(in: *c_void) c_int {
  add_column(@ptrCast(*config.ColumnInfo, @alignCast(8,in)));
  return 0;
}

pub fn add_column(colInfo: *config.ColumnInfo) void {
  const container = builder_get_widget(myBuilder, c"ZootColumns");
  const colNew = allocator.create(Column) catch unreachable;
  colNew.builder = c.gtk_builder_new_from_file (c"glade/column.glade");
  colNew.columnbox = builder_get_widget(colNew.builder, c"column");
  colNew.main = colInfo;
  var line_buf: []u8 = allocator.alloc(u8, 255) catch unreachable;
  colNew.config_window = builder_get_widget(colNew.builder, c"column_config");
  c.gtk_window_resize(@ptrCast([*c]c.GtkWindow, colNew.config_window), 600, 200);
  columns.append(colNew) catch unreachable;
  warn("column added title:{} column:{}\n", colNew.main.config.title, colNew.columnbox);
  const footer = builder_get_widget(colNew.builder, c"column_footer");
  const config_icon = builder_get_widget(colNew.builder, c"column_config_icon");
  c.gtk_misc_set_alignment(@ptrCast([*c]c.GtkMisc,config_icon), 1, 0);
  const label = builder_get_widget(colNew.builder, c"column_top_label");
  const labele = builder_get_widget(colNew.builder, c"column_top_eventbox");
  var drag = c.gtk_gesture_drag_new(labele);
  const topline_null: []u8 = std.cstr.addNullByte(allocator, colNew.main.config.title) catch unreachable;
  c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel,label), topline_null.ptr);
  c.gtk_box_pack_end(@ptrCast([*c]c.GtkBox, container), colNew.columnbox, 1, 1, 0);
  _ = c.gtk_builder_add_callback_symbol(colNew.builder,
                                        c"column.title",
                                        @ptrCast(?extern fn() void, column_top_label_title));
  _ = c.gtk_builder_add_callback_symbol(colNew.builder,
                                        c"column.config",
                                        @ptrCast(?extern fn() void, column_top_label_config));
  _ = c.gtk_builder_add_callback_symbol(colNew.builder,
                                        c"column.reload",
                                        @ptrCast(?extern fn() void, column_reload));
  _ = c.gtk_builder_add_callback_symbol(colNew.builder,
                                        c"column_config.done",
                                        @ptrCast(?extern fn() void, column_config_done));
  _ = c.gtk_builder_add_callback_symbol(colNew.builder,
                                        c"column_config.remove",
                                        @ptrCast(?extern fn() void, column_remove_btn));
  _ = c.gtk_builder_add_callback_symbol(colNew.builder,
                                        c"column_config.oauth",
                                        @ptrCast(?extern fn() void, column_config_oauth));
  _ = c.gtk_builder_add_callback_symbol(colNew.builder, c"zoot_drag", zoot_drag);
  _ = c.gtk_builder_connect_signals(colNew.builder, null);
  c.gtk_widget_show_all(container);
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

pub extern fn update_column_schedule(in: *c_void) c_int {
  const c_column = @ptrCast(*config.ColumnInfo, @alignCast(8,in));
  var columnMaybe = find_gui_column(c_column);
  if(columnMaybe) |column| {
    update_column(column);
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

pub fn update_column(column: *Column) void {
  warn("update_column {} {} toots {}\n", column.main.config.title,
                util.listCount(config.TootType, column.main.toots),
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
  var current = column.main.toots.first;
  if (current != null) {
    while(current) |node| {
      var tootbox = makeTootBox(node.data);
      c.gtk_box_pack_start(@ptrCast([*c]c.GtkBox, column_toot_zone), tootbox, 1, 1, 0);
      current = node.next;
    }
  } else {
    // help? logo?
  }
  c.gtk_widget_show(column_toot_zone);

  const count = util.listCount(config.TootType, column.main.toots);
  const countBuf = allocator.alloc(u8, 256) catch unreachable;
  const countStr = std.fmt.bufPrint(countBuf, "{} toots", count) catch unreachable;
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

pub fn makeTootBox(toot: config.TootType) [*c]c.GtkWidget {
  const builder = c.gtk_builder_new_from_file (c"glade/toot.glade");
  const tootbox = builder_get_widget(builder, c"tootbox");

  const id = toot.get("id").?.value.String;
  const content = toot.get("content").?.value.String;
  var jDecode = util.jsonStrDecode(content, allocator)  catch unreachable;
  //var hDecode = util.htmlEntityDecode(jDecode, allocator)  catch unreachable;
  const html_trim = util.htmlTagStrip(jDecode, allocator) catch unreachable;

  const toottext_label = builder_get_widget(builder, c"toot_text");
  //c.gtk_label_set_max_width_chars(@ptrCast([*c]c.GtkLabel, toottext_label), 10);
  c.gtk_label_set_line_wrap(@ptrCast([*c]c.GtkLabel, toottext_label), 1);
  var cText = util.sliceToCstr(allocator, html_trim);
  c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, toottext_label), cText);

  const author_name = toot.get("account").?.value.Object.get("display_name").?.value.String;
  const author_url = toot.get("account").?.value.Object.get("url").?.value.String;
  const created_at = toot.get("created_at").?.value.String;

  const name_label = builder_get_widget(builder, c"toot_author_name");
  labelBufPrint(name_label, "{}", author_name);
  const url_label = builder_get_widget(builder, c"toot_author_url");
  labelBufPrint(url_label, "{}", author_url);
  const date_label = builder_get_widget(builder, c"toot_date");
  labelBufPrint(date_label, "{}", created_at);
  return tootbox;
}

pub fn labelBufPrint(label: [*c]c.GtkWidget, comptime fmt: []const u8, args: ...) void {
  const buf = allocator.alloc(u8, 256) catch unreachable;
  const str = std.fmt.bufPrint(buf, fmt, args) catch unreachable;
  const cStr = util.sliceToCstr(allocator, str);
  c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel, label), cStr);
}

extern fn column_top_label_config(columnptr: ?*c_void) void {
  var columnbox = @ptrCast([*c]c.GtkWidget, @alignCast(8,columnptr));
  var name = c.g_type_name_from_instance(@ptrCast([*c]c.GTypeInstance, columnbox));
  var namelen = std.mem.len(u8, name);
  var column: *Column = findColumnByBox(columnbox);
  warn("column_top_label_config callback found {} {}\n", name[0..namelen], column.main.config.title);
  var column_config_window = builder_get_widget(column.builder, c"column_config");

  var url_entry = builder_get_widget(column.builder, c"column_config_url_entry");
  var cUrl = util.sliceToCstr(allocator, column.main.config.url);
  c.gtk_entry_set_text(@ptrCast([*c]c.GtkEntry, url_entry), cUrl);

  var token_entry = builder_get_widget(column.builder, c"column_config_token_entry");
  if(column.main.config.token) |tkn| {
    var cToken = util.sliceToCstr(allocator, tkn);
    c.gtk_entry_set_text(@ptrCast([*c]c.GtkEntry, token_entry), cToken);
  }

  var title_entry = builder_get_widget(column.builder, c"column_config_title_entry");
  var cTitle = util.sliceToCstr(allocator, column.main.config.title);
  c.gtk_entry_set_text(@ptrCast([*c]c.GtkEntry, title_entry), cTitle);

  c.gtk_widget_show(column_config_window);
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
  settings.win_x = w;
  settings.win_y = h;
}

extern fn actionbar_add() void {
  warn("actionbar_add\n");
  thread.signal(myActor, &thread.Command{.id = 3, .verb = &thread.CommandVerb{.idle = undefined}});
}

extern fn login_chg() void {
//  warn("login_chg {}\n", text);
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

extern fn column_config_oauth(selfptr: *c_void) void {
  var self = @ptrCast([*c]c.GtkWidget, @alignCast(8,selfptr));
  var column: *Column = findColumnByConfigWindow(self);

  // signal crazy
  var command = allocator.create(thread.Command) catch unreachable;
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  verb.column = column.main;
  command.id = 6;
  command.verb = verb;
  thread.signal(myActor, command);
}

pub fn column_config_oauth_url(colInfo: *config.ColumnInfo) void {
  warn("gui.column_config_oauth_url {}\n", colInfo.config.title);
  const container = builder_get_widget(myBuilder, c"ZootColumns");
  const column = findColumnByInfo(colInfo);

  var oauth_box = builder_get_widget(column.builder, c"column_config_oauth_box");
  var host_box = builder_get_widget(column.builder, c"column_config_host_box");
  c.gtk_box_pack_end(@ptrCast([*c]c.GtkBox, host_box), oauth_box, 1, 0, 0);

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

extern fn column_config_done(selfptr: *c_void) void {
  var self = @ptrCast([*c]c.GtkWidget, @alignCast(8,selfptr));
  var column: *Column = findColumnByConfigWindow(self);

  var token_entry = builder_get_widget(column.builder, c"column_config_token_entry");
  var cToken = c.gtk_entry_get_text(@ptrCast([*c]c.GtkEntry, token_entry));
  column.main.config.token = util.cstrToSlice(allocator, cToken); // edit in guithread--

  var url_entry = builder_get_widget(column.builder, c"column_config_url_entry");
  var cUrl = c.gtk_entry_get_text(@ptrCast([*c]c.GtkEntry, url_entry));
  column.main.config.url = util.cstrToSlice(allocator, cUrl); // edit in guithread--

  var title_entry = builder_get_widget(column.builder, c"column_config_title_entry");
  var cTitle = c.gtk_entry_get_text(@ptrCast([*c]c.GtkEntry, title_entry));
  column.main.config.title = util.cstrToSlice(allocator, cTitle); // edit in guithread--

  const label = builder_get_widget(column.builder, c"column_top_label");
  c.gtk_label_set_text(@ptrCast([*c]c.GtkLabel,label), cTitle);
  hide_column_config(column);

  // signal crazy
  var command = allocator.create(thread.Command) catch unreachable;
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  verb.guiColumnConfig = column.main;
  command.id = 4;
  command.verb = verb;
  thread.signal(myActor, command);
}

extern fn login_done() void {
  var login_entry = builder_get_widget(myBuilder, c"login_label");
  var ctext: [*c]const u8 = c.gtk_entry_get_text(@ptrCast([*c]c.GtkEntry, login_entry));
  var text = util.cstrToSlice(allocator, ctext);
  warn("login_done {}\n", text);
  thread.signal(myActor, &thread.Command{.id = 5,
                                        .verb = &thread.CommandVerb{
                                          .login = &config.LoginInfo{.username = "a", .password = "b"}}});
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
