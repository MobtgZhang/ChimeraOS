const std = @import("std");
const uefi = std.os.uefi;

pub const kernel = @import("kernel/main.zig");
pub const log = @import("lib/log.zig");

fn puts(con_out: *uefi.protocol.SimpleTextOutput, comptime msg: []const u8) void {
    _ = con_out.outputString(std.unicode.utf8ToUtf16LeStringLiteral(msg)) catch {};
}

pub fn main() void {
    const con_out = uefi.system_table.con_out orelse return;
    const boot_services = uefi.system_table.boot_services orelse return;

    con_out.clearScreen() catch {};

    puts(con_out, "==============================================\r\n");
    puts(con_out, "  ChimeraOS UEFI Bootloader v0.1.0\r\n");
    puts(con_out, "  A macOS-compatible OS written in Zig\r\n");
    puts(con_out, "==============================================\r\n\r\n");

    // --- Graphics Output Protocol ---
    var fb_info: ?kernel.FramebufferInfo = null;
    if (boot_services.locateProtocol(uefi.protocol.GraphicsOutput, null) catch null) |gop| {
        const mode = gop.mode;
        const info = mode.info;
        fb_info = .{
            .base = mode.frame_buffer_base,
            .size = mode.frame_buffer_size,
            .width = info.horizontal_resolution,
            .height = info.vertical_resolution,
            .stride = info.pixels_per_scan_line,
            .bpp = 32,
        };
        puts(con_out, "[BOOT] Graphics Output Protocol initialized\r\n");
    } else {
        puts(con_out, "[BOOT] WARNING: No Graphics Output Protocol\r\n");
    }

    // --- Memory Map ---
    const mmap_info = boot_services.getMemoryMapInfo() catch {
        puts(con_out, "[BOOT] FATAL: Cannot get memory map info\r\n");
        return;
    };

    const buf_size = (mmap_info.len + 8) * mmap_info.descriptor_size;
    const pool = boot_services.allocatePool(.loader_data, buf_size) catch {
        puts(con_out, "[BOOT] FATAL: Cannot allocate pool for memory map\r\n");
        return;
    };

    var mmap = boot_services.getMemoryMap(@alignCast(pool)) catch {
        puts(con_out, "[BOOT] FATAL: Cannot get memory map\r\n");
        return;
    };

    puts(con_out, "[BOOT] Memory map acquired\r\n");
    puts(con_out, "[BOOT] Exiting Boot Services...\r\n");

    // --- Exit Boot Services ---
    boot_services.exitBootServices(uefi.handle, mmap.info.key) catch {
        mmap = boot_services.getMemoryMap(@alignCast(pool)) catch return;
        boot_services.exitBootServices(uefi.handle, mmap.info.key) catch return;
    };

    // *** UEFI Boot Services are gone. We own the machine. ***

    const boot_info = kernel.BootInfo{
        .framebuffer = fb_info,
        .memory_map = mmap,
    };
    kernel.kernelMain(&boot_info);
}
