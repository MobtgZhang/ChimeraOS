const std = @import("std");
const build_options = @import("build_options");
const serial = @import("../kernel/arch/x86_64/serial.zig");

pub fn info(comptime fmt: []const u8, args: anytype) void {
    if (comptime !build_options.enable_logging) return;
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch "[log fmt error]";
    serial.writeString("[INFO] ");
    serial.writeString(msg);
    serial.writeString("\r\n");
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (comptime !build_options.enable_logging) return;
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch "[log fmt error]";
    serial.writeString("[WARN] ");
    serial.writeString(msg);
    serial.writeString("\r\n");
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    if (comptime !build_options.enable_logging) return;
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch "[log fmt error]";
    serial.writeString("[ERR]  ");
    serial.writeString(msg);
    serial.writeString("\r\n");
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (comptime !build_options.enable_logging) return;
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch "[log fmt error]";
    serial.writeString("[DBG]  ");
    serial.writeString(msg);
    serial.writeString("\r\n");
}
