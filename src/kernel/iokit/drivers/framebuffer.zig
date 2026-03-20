/// Framebuffer display driver.
/// Wraps the UEFI GOP framebuffer and provides a pixel-level API
/// for the GUI compositor.

const log = @import("../../../lib/log.zig");
const registry = @import("../registry.zig");

pub const FramebufferInfo = struct {
    base: [*]volatile u32,
    width: u32,
    height: u32,
    stride: u32,
    size: usize,
};

var fb: FramebufferInfo = undefined;
var ready: bool = false;

pub fn init(base: u64, width: u32, height: u32, stride: u32, size: usize) void {
    fb = .{
        .base = @ptrFromInt(base),
        .width = width,
        .height = height,
        .stride = stride,
        .size = size,
    };
    ready = true;

    if (registry.allocNode("IOFramebuffer", "GOP-Display")) |node| {
        _ = node.setProperty("IOProviderClass", "IOGraphicsDevice");
        _ = node.setPropertyInt("width", width);
        _ = node.setPropertyInt("height", height);
        _ = node.setPropertyInt("stride", stride);
        _ = node.setPropertyInt("bpp", 32);
        if (registry.getRoot()) |root| root.addChild(node);
    }

    log.info("[FB]   Framebuffer driver: {}x{} stride={} @ 0x{x}", .{ width, height, stride, base });
}

pub fn isReady() bool {
    return ready;
}

pub fn getInfo() FramebufferInfo {
    return fb;
}

pub fn getWidth() u32 {
    return fb.width;
}

pub fn getHeight() u32 {
    return fb.height;
}

pub fn putPixel(x: u32, y: u32, color: u32) void {
    if (x < fb.width and y < fb.height) {
        fb.base[@as(usize, y) * fb.stride + x] = color;
    }
}

pub fn getPixel(x: u32, y: u32) u32 {
    if (x < fb.width and y < fb.height) {
        return fb.base[@as(usize, y) * fb.stride + x];
    }
    return 0;
}

pub fn fillRect(x: u32, y: u32, w: u32, h: u32, color: u32) void {
    var row: u32 = y;
    while (row < y + h and row < fb.height) : (row += 1) {
        var col: u32 = x;
        while (col < x + w and col < fb.width) : (col += 1) {
            fb.base[@as(usize, row) * fb.stride + col] = color;
        }
    }
}

pub fn clear(color: u32) void {
    fillRect(0, 0, fb.width, fb.height, color);
}
