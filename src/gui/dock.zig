/// macOS-style Dock — a row of application icons at the bottom of the screen.

const graphics = @import("graphics.zig");
const color_mod = @import("color.zig");
const icons = @import("icons.zig");
const font_mod = @import("font.zig");
const Color = color_mod.Color;
const theme = color_mod.theme;

pub const DOCK_H: u32 = 58;
const DOCK_PADDING: u32 = 8;
const ICON_SLOT_SIZE: u32 = 40;
const DOCK_RADIUS: u32 = 12;
const MAX_DOCK_ITEMS = 8;

pub const DockItem = struct {
    icon_id: icons.IconId,
    label: [32]u8,
    label_len: usize,
    primary_color: Color,
    secondary_color: Color,
    accent_color: Color,
    highlight_color: Color,
    running: bool,
    active: bool,
};

var items: [MAX_DOCK_ITEMS]DockItem = undefined;
var item_count: usize = 0;
var hovered_idx: ?usize = null;

pub fn init() void {
    item_count = 0;
    addItem(.finder, "Finder", color_mod.rgb(60, 120, 220), color_mod.rgb(30, 80, 180), color_mod.rgb(100, 160, 255), theme.white);
    addItem(.terminal, "Terminal", color_mod.rgb(40, 40, 40), color_mod.rgb(20, 20, 20), color_mod.rgb(0, 200, 80), theme.white);
    addItem(.settings, "Settings", color_mod.rgb(120, 120, 120), color_mod.rgb(80, 80, 80), color_mod.rgb(0, 122, 255), theme.white);
    addItem(.file_text, "TextEdit", color_mod.rgb(80, 80, 80), color_mod.rgb(50, 50, 50), color_mod.rgb(200, 200, 200), theme.white);
    addItem(.info, "About", color_mod.rgb(0, 100, 200), color_mod.rgb(0, 60, 140), color_mod.rgb(0, 122, 255), theme.white);
}

fn addItem(icon_id: icons.IconId, label: []const u8, primary: Color, secondary: Color, accent: Color, highlight: Color) void {
    if (item_count >= MAX_DOCK_ITEMS) return;
    var item = &items[item_count];
    item.icon_id = icon_id;
    item.label_len = @min(label.len, 32);
    @memcpy(item.label[0..item.label_len], label[0..item.label_len]);
    item.primary_color = primary;
    item.secondary_color = secondary;
    item.accent_color = accent;
    item.highlight_color = highlight;
    item.running = false;
    item.active = true;
    item_count += 1;
}

pub fn render() void {
    if (item_count == 0) return;

    const sw = graphics.screenWidth();
    const sh = graphics.screenHeight();

    const dock_w: u32 = @intCast(item_count * ICON_SLOT_SIZE + DOCK_PADDING * 2);
    const dock_x: i32 = @intCast((sw - dock_w) / 2);
    const dock_y: i32 = @intCast(sh - DOCK_H - 6);

    // Dock background (semi-transparent rounded rect)
    graphics.fillRoundedRect(dock_x, dock_y, dock_w, DOCK_H, DOCK_RADIUS, color_mod.blend(theme.dock_bg, theme.white, 180));
    graphics.drawRect(dock_x, dock_y, dock_w, DOCK_H, theme.dock_border);

    // Icons
    var i: usize = 0;
    while (i < item_count) : (i += 1) {
        const item = &items[i];
        if (!item.active) continue;

        const ix: i32 = dock_x + @as(i32, @intCast(DOCK_PADDING + i * ICON_SLOT_SIZE + (ICON_SLOT_SIZE - icons.ICON_SIZE) / 2));
        const iy: i32 = dock_y + @as(i32, @intCast((DOCK_H - icons.ICON_SIZE - 14) / 2));

        // Hover effect
        if (hovered_idx != null and hovered_idx.? == i) {
            graphics.fillRoundedRect(
                dock_x + @as(i32, @intCast(DOCK_PADDING + i * ICON_SLOT_SIZE)),
                dock_y + 4,
                ICON_SLOT_SIZE,
                DOCK_H - 8,
                6,
                color_mod.blend(theme.accent, theme.white, 40),
            );
        }

        // Draw icon
        drawDockIcon(ix, iy, item);

        // Running indicator dot
        if (item.running) {
            const dot_x = ix + @as(i32, @intCast(icons.ICON_SIZE / 2));
            const dot_y = dock_y + @as(i32, @intCast(DOCK_H - 8));
            graphics.fillCircle(dot_x, dot_y, 2, theme.text_primary);
        }
    }
}

fn drawDockIcon(x: i32, y: i32, item: *const DockItem) void {
    // Icon background (rounded square)
    graphics.fillRoundedRect(x - 4, y - 4, icons.ICON_SIZE + 8, icons.ICON_SIZE + 8, 6, item.secondary_color);

    const data = icons.getIcon(item.icon_id);
    var row: u32 = 0;
    while (row < icons.ICON_SIZE) : (row += 1) {
        var col: u32 = 0;
        while (col < icons.ICON_SIZE) : (col += 1) {
            const idx = data[row * icons.ICON_SIZE + col];
            if (idx != 0) {
                const c = icons.paletteColor(idx, item.primary_color, item.secondary_color, item.accent_color, item.highlight_color);
                graphics.putPixel(x + @as(i32, @intCast(col)), y + @as(i32, @intCast(row)), c);
            }
        }
    }
}

// ── Hit testing ──────────────────────────────────────────

pub fn hitTest(mx: i32, my: i32) ?usize {
    const sw = graphics.screenWidth();
    const sh = graphics.screenHeight();

    const dock_w: u32 = @intCast(item_count * ICON_SLOT_SIZE + DOCK_PADDING * 2);
    const dock_x: i32 = @intCast((sw - dock_w) / 2);
    const dock_y: i32 = @intCast(sh - DOCK_H - 6);

    if (my < dock_y or my >= dock_y + @as(i32, DOCK_H)) return null;
    if (mx < dock_x or mx >= dock_x + @as(i32, @intCast(dock_w))) return null;

    const rel_x = mx - dock_x - @as(i32, DOCK_PADDING);
    if (rel_x < 0) return null;
    const idx: usize = @intCast(@divTrunc(rel_x, @as(i32, ICON_SLOT_SIZE)));
    if (idx < item_count) return idx;
    return null;
}

pub fn updateHover(mx: i32, my: i32) void {
    hovered_idx = hitTest(mx, my);
}

pub fn setRunning(idx: usize, running: bool) void {
    if (idx < item_count) items[idx].running = running;
}

pub fn getItemLabel(idx: usize) ?[]const u8 {
    if (idx >= item_count) return null;
    return items[idx].label[0..items[idx].label_len];
}

pub fn getItemCount() usize {
    return item_count;
}

pub fn isInDock(my: i32) bool {
    const sh = graphics.screenHeight();
    const dock_y: i32 = @intCast(sh - DOCK_H - 6);
    return my >= dock_y;
}
