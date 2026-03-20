/// Mouse cursor rendering — draws a standard arrow cursor at the given position.
/// Designed for full-scene redraws: call draw() at the end of each render pass.

const graphics = @import("graphics.zig");
const color_mod = @import("color.zig");
const Color = color_mod.Color;

pub const CURSOR_W: u32 = 12;
pub const CURSOR_H: u32 = 18;

/// Standard arrow cursor (1 = white fill, 2 = black outline, 0 = transparent)
const cursor_bitmap = [CURSOR_H][CURSOR_W]u8{
    .{ 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 2, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 2, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 2, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0 },
    .{ 2, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0 },
    .{ 2, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0 },
    .{ 2, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0 },
    .{ 2, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0 },
    .{ 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0 },
    .{ 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0 },
    .{ 2, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 0 },
    .{ 2, 1, 1, 1, 2, 1, 1, 2, 0, 0, 0, 0 },
    .{ 2, 1, 1, 2, 0, 2, 1, 1, 2, 0, 0, 0 },
    .{ 2, 1, 2, 0, 0, 2, 1, 1, 2, 0, 0, 0 },
    .{ 2, 2, 0, 0, 0, 0, 2, 1, 1, 2, 0, 0 },
    .{ 0, 0, 0, 0, 0, 0, 2, 1, 1, 2, 0, 0 },
    .{ 0, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0, 0 },
};

pub fn draw(x: i32, y: i32) void {
    var row: u32 = 0;
    while (row < CURSOR_H) : (row += 1) {
        var col: u32 = 0;
        while (col < CURSOR_W) : (col += 1) {
            const pixel = cursor_bitmap[row][col];
            if (pixel != 0) {
                const c: Color = if (pixel == 1) color_mod.theme.white else color_mod.theme.black;
                graphics.putPixel(x + @as(i32, @intCast(col)), y + @as(i32, @intCast(row)), c);
            }
        }
    }
}
