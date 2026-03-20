/// Window manager — macOS-style windows with title bars and traffic-light buttons.

const graphics = @import("graphics.zig");
const color_mod = @import("color.zig");
const font = @import("font.zig");
const Color = color_mod.Color;
const theme = color_mod.theme;

pub const MAX_WINDOWS: usize = 16;
pub const TITLE_BAR_H: u32 = 28;
pub const BTN_RADIUS: u32 = 6;
pub const BTN_Y_OFFSET: u32 = 8;
pub const BTN_SPACING: u32 = 20;
pub const TITLE_MAX_LEN: usize = 64;

pub const Window = struct {
    id: u16,
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    title: [TITLE_MAX_LEN]u8,
    title_len: usize,
    visible: bool,
    focused: bool,
    closable: bool,
    minimizable: bool,
    // Content callback slot
    content_type: ContentType,
    // Simple text content buffer
    text_buf: [2048]u8,
    text_len: usize,
    active: bool,
};

pub const ContentType = enum {
    empty,
    text_view,
    about_dialog,
    terminal,
    file_manager,
};

var windows: [MAX_WINDOWS]Window = undefined;
var window_count: usize = 0;
var z_order: [MAX_WINDOWS]u16 = undefined;
var z_count: usize = 0;
var drag_win: ?u16 = null;
var drag_offset_x: i32 = 0;
var drag_offset_y: i32 = 0;

pub fn init() void {
    window_count = 0;
    z_count = 0;
    for (&windows) |*w| w.active = false;
}

pub fn createWindow(title: []const u8, x: i32, y: i32, w: u32, h: u32, content: ContentType) ?u16 {
    if (window_count >= MAX_WINDOWS) return null;
    const id: u16 = @intCast(window_count);
    var win = &windows[window_count];
    win.* = .{
        .id = id,
        .x = x,
        .y = y,
        .width = w,
        .height = h,
        .title = [_]u8{0} ** TITLE_MAX_LEN,
        .title_len = @min(title.len, TITLE_MAX_LEN),
        .visible = true,
        .focused = true,
        .closable = true,
        .minimizable = true,
        .content_type = content,
        .text_buf = [_]u8{0} ** 2048,
        .text_len = 0,
        .active = true,
    };
    @memcpy(win.title[0..win.title_len], title[0..win.title_len]);

    // Unfocus all others
    for (windows[0..window_count]) |*other| {
        if (other.active) other.focused = false;
    }

    z_order[z_count] = id;
    z_count += 1;
    window_count += 1;
    return id;
}

pub fn setWindowText(id: u16, text: []const u8) void {
    if (id >= window_count) return;
    var win = &windows[id];
    const len = @min(text.len, win.text_buf.len);
    @memcpy(win.text_buf[0..len], text[0..len]);
    win.text_len = len;
}

pub fn closeWindow(id: u16) void {
    if (id >= window_count) return;
    windows[id].visible = false;
    windows[id].active = false;
    // Remove from z-order
    var i: usize = 0;
    while (i < z_count) {
        if (z_order[i] == id) {
            var j = i;
            while (j + 1 < z_count) : (j += 1) {
                z_order[j] = z_order[j + 1];
            }
            z_count -= 1;
        } else {
            i += 1;
        }
    }
}

pub fn focusWindow(id: u16) void {
    for (windows[0..window_count]) |*w| w.focused = false;
    if (id < window_count) windows[id].focused = true;
    // Move to top of z-order
    var i: usize = 0;
    while (i < z_count) : (i += 1) {
        if (z_order[i] == id) {
            var j = i;
            while (j + 1 < z_count) : (j += 1) {
                z_order[j] = z_order[j + 1];
            }
            z_order[z_count - 1] = id;
            break;
        }
    }
}

pub fn getWindowCount() usize {
    return window_count;
}

// ── Hit testing ──────────────────────────────────────────

pub const HitResult = enum {
    none,
    title_bar,
    close_btn,
    minimize_btn,
    maximize_btn,
    content,
};

pub fn hitTest(mx: i32, my: i32) ?struct { id: u16, hit: HitResult } {
    // Check in reverse z-order (top window first)
    var i = z_count;
    while (i > 0) {
        i -= 1;
        const wid = z_order[i];
        const win = &windows[wid];
        if (!win.visible or !win.active) continue;

        if (mx >= win.x and mx < win.x + @as(i32, @intCast(win.width)) and
            my >= win.y and my < win.y + @as(i32, @intCast(win.height)))
        {
            if (my < win.y + @as(i32, TITLE_BAR_H)) {
                // Check traffic-light buttons
                const btn_base_x = win.x + 12;
                const btn_cy = win.y + @as(i32, BTN_Y_OFFSET) + @as(i32, BTN_RADIUS);

                if (inCircle(mx, my, btn_base_x, btn_cy, BTN_RADIUS))
                    return .{ .id = wid, .hit = .close_btn };
                if (inCircle(mx, my, btn_base_x + @as(i32, BTN_SPACING), btn_cy, BTN_RADIUS))
                    return .{ .id = wid, .hit = .minimize_btn };
                if (inCircle(mx, my, btn_base_x + @as(i32, BTN_SPACING) * 2, btn_cy, BTN_RADIUS))
                    return .{ .id = wid, .hit = .maximize_btn };

                return .{ .id = wid, .hit = .title_bar };
            }
            return .{ .id = wid, .hit = .content };
        }
    }
    return null;
}

fn inCircle(px: i32, py: i32, cx: i32, cy: i32, r: u32) bool {
    const dx = px - cx;
    const dy = py - cy;
    const ir: i32 = @intCast(r);
    return dx * dx + dy * dy <= ir * ir;
}

// ── Dragging ─────────────────────────────────────────────

pub fn beginDrag(id: u16, mx: i32, my: i32) void {
    drag_win = id;
    if (id < window_count) {
        drag_offset_x = mx - windows[id].x;
        drag_offset_y = my - windows[id].y;
    }
}

pub fn updateDrag(mx: i32, my: i32) void {
    if (drag_win) |id| {
        if (id < window_count) {
            windows[id].x = mx - drag_offset_x;
            windows[id].y = my - drag_offset_y;
        }
    }
}

pub fn endDrag() void {
    drag_win = null;
}

pub fn isDragging() bool {
    return drag_win != null;
}

// ── Rendering ────────────────────────────────────────────

pub fn renderAll() void {
    // Render in z-order (bottom to top)
    for (z_order[0..z_count]) |wid| {
        if (wid < window_count and windows[wid].visible and windows[wid].active) {
            renderWindow(&windows[wid]);
        }
    }
}

fn renderWindow(win: *const Window) void {
    const x = win.x;
    const y = win.y;
    const w = win.width;
    const h = win.height;

    // Shadow
    graphics.fillRectAlpha(x + 4, y + 4, w, h, theme.window_shadow, 60);

    // Window body
    graphics.fillRoundedRect(x, y, w, h, 8, theme.window_bg);

    // Title bar
    const tb_color = if (win.focused) theme.title_bar_active else theme.title_bar;
    graphics.fillRoundedRect(x, y, w, TITLE_BAR_H, 8, tb_color);
    // Bottom edge of title bar (straight line to connect to body)
    graphics.fillRect(x, y + @as(i32, TITLE_BAR_H) - 8, w, 8, tb_color);

    // Separator line
    graphics.drawHLine(x, y + @as(i32, TITLE_BAR_H) - 1, w, theme.window_border);

    // Traffic-light buttons
    const btn_x = x + 12;
    const btn_cy = y + @as(i32, BTN_Y_OFFSET) + @as(i32, BTN_RADIUS);

    if (win.focused) {
        graphics.fillCircle(btn_x, btn_cy, BTN_RADIUS, theme.btn_close);
        graphics.fillCircle(btn_x + @as(i32, BTN_SPACING), btn_cy, BTN_RADIUS, theme.btn_minimize);
        graphics.fillCircle(btn_x + @as(i32, BTN_SPACING) * 2, btn_cy, BTN_RADIUS, theme.btn_maximize);
    } else {
        graphics.fillCircle(btn_x, btn_cy, BTN_RADIUS, theme.btn_inactive);
        graphics.fillCircle(btn_x + @as(i32, BTN_SPACING), btn_cy, BTN_RADIUS, theme.btn_inactive);
        graphics.fillCircle(btn_x + @as(i32, BTN_SPACING) * 2, btn_cy, BTN_RADIUS, theme.btn_inactive);
    }

    // Title text (centered)
    const title_y = y + 6;
    graphics.drawStringCentered(x, title_y, w, win.title[0..win.title_len], theme.title_text);

    // Window border
    graphics.drawRect(x, y, w, h, theme.window_border);

    // Content area
    renderContent(win);
}

fn renderContent(win: *const Window) void {
    const cx = win.x + 8;
    const cy = win.y + @as(i32, TITLE_BAR_H) + 8;

    switch (win.content_type) {
        .text_view, .terminal => {
            if (win.text_len > 0) {
                drawWrappedText(cx, cy, win.width - 16, win.text_buf[0..win.text_len], theme.text_primary);
            }
        },
        .about_dialog => {
            const center_x = win.x + @as(i32, @intCast(win.width / 2));
            _ = center_x;
            graphics.drawStringCentered(win.x, cy + 20, win.width, "ChimeraOS", theme.text_primary);
            graphics.drawStringCentered(win.x, cy + 44, win.width, "Version 0.2.0", theme.text_secondary);
            graphics.drawStringCentered(win.x, cy + 68, win.width, "A macOS-compatible OS in Zig", theme.text_secondary);
            graphics.drawStringCentered(win.x, cy + 100, win.width, "XNU-style hybrid kernel", theme.accent);
            graphics.drawStringCentered(win.x, cy + 124, win.width, "Mach IPC + BSD + IOKit", theme.text_secondary);
        },
        .file_manager => {
            graphics.drawString(cx, cy, "Desktop", theme.text_primary);
            graphics.drawString(cx, cy + 24, "Documents", theme.text_primary);
            graphics.drawString(cx, cy + 48, "Applications", theme.text_primary);
            graphics.drawString(cx, cy + 72, "Downloads", theme.text_primary);
        },
        .empty => {},
    }
}

fn drawWrappedText(x: i32, y: i32, max_w: u32, text: []const u8, c: Color) void {
    var cx: i32 = x;
    var cy: i32 = y;
    const char_w: i32 = @intCast(font.GLYPH_W);
    const line_h: i32 = @intCast(font.GLYPH_H + 2);
    const limit = x + @as(i32, @intCast(max_w));

    for (text) |ch| {
        if (ch == '\n' or cx + char_w > limit) {
            cx = x;
            cy += line_h;
        }
        if (ch != '\n') {
            graphics.drawChar(cx, cy, ch, c);
            cx += char_w;
        }
    }
}
