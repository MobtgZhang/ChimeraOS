/// macOS-style menu bar — always at the top of the screen.
/// Displays: Apple logo | App name | menus... | clock (right-aligned)

const graphics = @import("graphics.zig");
const color_mod = @import("color.zig");
const font_mod = @import("font.zig");
const icons = @import("icons.zig");
const Color = color_mod.Color;
const theme = color_mod.theme;

pub const MENUBAR_H: u32 = 24;

const MAX_MENUS = 8;
const MAX_LABEL_LEN = 32;

pub const MenuItem = struct {
    label: [MAX_LABEL_LEN]u8,
    label_len: usize,
    x: i32,
    width: u32,
    active: bool,
};

var menus: [MAX_MENUS]MenuItem = undefined;
var menu_count: usize = 0;

var clock_text: [8]u8 = "00:00   ".*;
var clock_len: usize = 5;
var active_app: [MAX_LABEL_LEN]u8 = "Finder                          ".*;
var active_app_len: usize = 6;

pub fn init() void {
    menu_count = 0;
    addMenu("File");
    addMenu("Edit");
    addMenu("View");
    addMenu("Window");
    addMenu("Help");
}

fn addMenu(label: []const u8) void {
    if (menu_count >= MAX_MENUS) return;
    var m = &menus[menu_count];
    m.active = true;
    m.label_len = @min(label.len, MAX_LABEL_LEN);
    @memcpy(m.label[0..m.label_len], label[0..m.label_len]);
    m.width = @intCast(m.label_len * font_mod.GLYPH_W + 16);
    menu_count += 1;
    layoutMenus();
}

fn layoutMenus() void {
    // Apple logo: 28px, bold app name, then menus
    var x: i32 = 28 + @as(i32, @intCast(active_app_len * font_mod.GLYPH_W)) + 16;
    for (menus[0..menu_count]) |*m| {
        m.x = x;
        x += @intCast(m.width);
    }
}

pub fn setActiveApp(name: []const u8) void {
    active_app_len = @min(name.len, MAX_LABEL_LEN);
    @memcpy(active_app[0..active_app_len], name[0..active_app_len]);
    layoutMenus();
}

pub fn updateClock(hour: u8, minute: u8) void {
    clock_text[0] = '0' + hour / 10;
    clock_text[1] = '0' + hour % 10;
    clock_text[2] = ':';
    clock_text[3] = '0' + minute / 10;
    clock_text[4] = '0' + minute % 10;
    clock_len = 5;
}

pub fn render() void {
    const sw = graphics.screenWidth();

    // Background
    graphics.fillRect(0, 0, sw, MENUBAR_H, theme.menubar_bg);
    // Bottom border
    graphics.drawHLine(0, @intCast(MENUBAR_H - 1), sw, theme.window_border);

    // Apple icon (simplified — draw a small icon glyph)
    drawIcon(6, 4);

    // Active app name (bold position)
    graphics.drawString(28, 4, active_app[0..active_app_len], theme.menubar_text);

    // Menu items
    for (menus[0..menu_count]) |m| {
        if (!m.active) continue;
        const text_x = m.x + 8;
        graphics.drawString(text_x, 4, m.label[0..m.label_len], theme.menubar_text);
    }

    // Clock (right-aligned)
    const clock_w: i32 = @intCast(clock_len * font_mod.GLYPH_W);
    graphics.drawString(@as(i32, @intCast(sw)) - clock_w - 12, 4, clock_text[0..clock_len], theme.menubar_text);
}

/// Hit-test: returns the menu index if a menu label was clicked, or null.
pub fn hitTest(mx: i32, my: i32) ?usize {
    if (my < 0 or my >= @as(i32, MENUBAR_H)) return null;

    for (menus[0..menu_count], 0..) |m, i| {
        if (mx >= m.x and mx < m.x + @as(i32, @intCast(m.width))) {
            return i;
        }
    }

    // Check apple icon region
    if (mx >= 0 and mx < 28) return null; // apple icon area (special)

    return null;
}

pub fn isInMenuBar(my: i32) bool {
    return my >= 0 and my < @as(i32, MENUBAR_H);
}

fn drawIcon(x: i32, y: i32) void {
    const data = icons.getIcon(.apple_logo);
    var row: u32 = 0;
    while (row < icons.ICON_SIZE) : (row += 1) {
        var col: u32 = 0;
        while (col < icons.ICON_SIZE) : (col += 1) {
            const idx = data[row * icons.ICON_SIZE + col];
            if (idx != 0) {
                graphics.putPixel(x + @as(i32, @intCast(col)), y + @as(i32, @intCast(row)), theme.menubar_text);
            }
        }
    }
}
