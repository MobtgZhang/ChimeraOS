/// 2D graphics primitives for the GUI compositor.
/// Supports double buffering: draws to a back buffer, then swaps to the
/// framebuffer in a single pass to eliminate visible tearing/flickering.

const font = @import("font.zig");
const color_mod = @import("color.zig");
const Color = color_mod.Color;

var fb: [*]volatile u32 = undefined;
var back: [*]u32 = undefined;
var has_back_buffer: bool = false;
var fb_w: u32 = 0;
var fb_h: u32 = 0;
var fb_stride: u32 = 0;
var ready: bool = false;

pub fn init(base: [*]volatile u32, w: u32, h: u32, stride: u32) void {
    fb = base;
    fb_w = w;
    fb_h = h;
    fb_stride = stride;
    has_back_buffer = false;
    ready = true;
}

pub fn enableDoubleBuffer(back_buf: [*]u32) void {
    back = back_buf;
    has_back_buffer = true;
}

pub fn swapBuffers() void {
    if (!has_back_buffer) return;
    const total = @as(usize, fb_stride) * fb_h;
    var i: usize = 0;
    while (i < total) : (i += 1) {
        fb[i] = back[i];
    }
}

pub fn screenWidth() u32 {
    return fb_w;
}
pub fn screenHeight() u32 {
    return fb_h;
}

inline fn writePixel(offset: usize, c: Color) void {
    if (has_back_buffer) {
        back[offset] = c;
    } else {
        fb[offset] = c;
    }
}

inline fn readPixel(offset: usize) Color {
    if (has_back_buffer) {
        return back[offset];
    } else {
        return fb[offset];
    }
}

pub fn putPixel(x: i32, y: i32, c: Color) void {
    if (x < 0 or y < 0) return;
    const ux: u32 = @intCast(x);
    const uy: u32 = @intCast(y);
    if (ux < fb_w and uy < fb_h) {
        writePixel(@as(usize, uy) * fb_stride + ux, c);
    }
}

pub fn putPixelBlend(x: i32, y: i32, c: Color, alpha: u8) void {
    if (x < 0 or y < 0) return;
    const ux: u32 = @intCast(x);
    const uy: u32 = @intCast(y);
    if (ux < fb_w and uy < fb_h) {
        const idx = @as(usize, uy) * fb_stride + ux;
        writePixel(idx, color_mod.blend(c, readPixel(idx), alpha));
    }
}

// ── Rectangles ───────────────────────────────────────────

pub fn fillRect(x: i32, y: i32, w: u32, h: u32, c: Color) void {
    var row: i32 = y;
    const end_y = y + @as(i32, @intCast(h));
    const end_x = x + @as(i32, @intCast(w));
    while (row < end_y) : (row += 1) {
        if (row < 0 or row >= @as(i32, @intCast(fb_h))) continue;
        var col: i32 = x;
        while (col < end_x) : (col += 1) {
            if (col >= 0 and col < @as(i32, @intCast(fb_w))) {
                writePixel(@as(usize, @intCast(row)) * fb_stride + @as(usize, @intCast(col)), c);
            }
        }
    }
}

pub fn fillRectAlpha(x: i32, y: i32, w: u32, h: u32, c: Color, alpha: u8) void {
    var row: i32 = y;
    const end_y = y + @as(i32, @intCast(h));
    const end_x = x + @as(i32, @intCast(w));
    while (row < end_y) : (row += 1) {
        if (row < 0 or row >= @as(i32, @intCast(fb_h))) continue;
        var col: i32 = x;
        while (col < end_x) : (col += 1) {
            if (col >= 0 and col < @as(i32, @intCast(fb_w))) {
                const idx = @as(usize, @intCast(row)) * fb_stride + @as(usize, @intCast(col));
                writePixel(idx, color_mod.blend(c, readPixel(idx), alpha));
            }
        }
    }
}

pub fn drawRect(x: i32, y: i32, w: u32, h: u32, c: Color) void {
    drawHLine(x, y, w, c);
    drawHLine(x, y + @as(i32, @intCast(h)) - 1, w, c);
    drawVLine(x, y, h, c);
    drawVLine(x + @as(i32, @intCast(w)) - 1, y, h, c);
}

/// Rounded rectangle (macOS-style window corners).
pub fn fillRoundedRect(x: i32, y: i32, w: u32, h: u32, radius: u32, c: Color) void {
    const r: i32 = @intCast(@min(radius, @min(w / 2, h / 2)));
    const iw: i32 = @intCast(w);
    const ih: i32 = @intCast(h);

    // Main body (excluding corners)
    fillRect(x + r, y, w - @as(u32, @intCast(r)) * 2, h, c);
    fillRect(x, y + r, w, h - @as(u32, @intCast(r)) * 2, c);

    // Four rounded corners
    fillCorner(x + r, y + r, r, c, true, true);
    fillCorner(x + iw - r - 1, y + r, r, c, false, true);
    fillCorner(x + r, y + ih - r - 1, r, c, true, false);
    fillCorner(x + iw - r - 1, y + ih - r - 1, r, c, false, false);
}

fn fillCorner(cx: i32, cy: i32, r: i32, c: Color, left: bool, top: bool) void {
    var dy: i32 = 0;
    while (dy <= r) : (dy += 1) {
        // Integer circle approximation: x² + y² ≤ r²
        var dx: i32 = 0;
        while (dx <= r) : (dx += 1) {
            if (dx * dx + dy * dy <= r * r) {
                const px = if (left) cx - dx else cx + dx;
                const py = if (top) cy - dy else cy + dy;
                putPixel(px, py, c);
            }
        }
    }
}

// ── Lines ────────────────────────────────────────────────

pub fn drawHLine(x: i32, y: i32, w: u32, c: Color) void {
    if (y < 0 or y >= @as(i32, @intCast(fb_h))) return;
    var col: i32 = x;
    const end = x + @as(i32, @intCast(w));
    while (col < end) : (col += 1) {
        if (col >= 0 and col < @as(i32, @intCast(fb_w))) {
            writePixel(@as(usize, @intCast(y)) * fb_stride + @as(usize, @intCast(col)), c);
        }
    }
}

pub fn drawVLine(x: i32, y: i32, h: u32, c: Color) void {
    if (x < 0 or x >= @as(i32, @intCast(fb_w))) return;
    var row: i32 = y;
    const end = y + @as(i32, @intCast(h));
    while (row < end) : (row += 1) {
        if (row >= 0 and row < @as(i32, @intCast(fb_h))) {
            writePixel(@as(usize, @intCast(row)) * fb_stride + @as(usize, @intCast(x)), c);
        }
    }
}

// ── Circle ───────────────────────────────────────────────

pub fn fillCircle(cx: i32, cy: i32, r: u32, c: Color) void {
    const ir: i32 = @intCast(r);
    var dy: i32 = -ir;
    while (dy <= ir) : (dy += 1) {
        var dx: i32 = -ir;
        while (dx <= ir) : (dx += 1) {
            if (dx * dx + dy * dy <= ir * ir) {
                putPixel(cx + dx, cy + dy, c);
            }
        }
    }
}

// ── Text rendering ───────────────────────────────────────

pub fn drawChar(x: i32, y: i32, ch: u8, c: Color) void {
    const glyph = font.getGlyph(ch) orelse font.getGlyph('?') orelse return;
    var row: u32 = 0;
    while (row < font.GLYPH_H) : (row += 1) {
        const bits = glyph[row];
        var col: u32 = 0;
        while (col < font.GLYPH_W) : (col += 1) {
            if (bits & (@as(u8, 0x80) >> @intCast(col)) != 0) {
                putPixel(x + @as(i32, @intCast(col)), y + @as(i32, @intCast(row)), c);
            }
        }
    }
}

pub fn drawString(x: i32, y: i32, str: []const u8, c: Color) void {
    var cx: i32 = x;
    for (str) |ch| {
        if (ch == '\n') {
            cx = x;
            continue;
        }
        drawChar(cx, y, ch, c);
        cx += @intCast(font.GLYPH_W);
    }
}

pub fn drawStringCentered(x: i32, y: i32, w: u32, str: []const u8, c: Color) void {
    const text_w: i32 = @intCast(str.len * font.GLYPH_W);
    const offset = @divTrunc(@as(i32, @intCast(w)) - text_w, 2);
    drawString(x + offset, y, str, c);
}

/// Vertical gradient fill.
pub fn fillGradientV(x: i32, y: i32, w: u32, h: u32, top: Color, bottom: Color) void {
    var row: u32 = 0;
    while (row < h) : (row += 1) {
        const t: u8 = @intCast((@as(u32, row) * 255) / (if (h > 1) h - 1 else 1));
        const c = color_mod.lerp(top, bottom, t);
        drawHLine(x, y + @as(i32, @intCast(row)), w, c);
    }
}

pub fn clear(c: Color) void {
    fillRect(0, 0, fb_w, fb_h, c);
}
