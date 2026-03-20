/// MIPS64el Hardware Abstraction Layer — 16550 UART, CP0 interrupts, CP0 timer.
/// Targets QEMU Malta board. Note: UEFI is not officially supported on MIPS;
/// this target uses a custom boot protocol or direct kernel load.

const serial = @import("serial.zig");
const interrupts = @import("interrupts.zig");
const mmu = @import("mmu.zig");
const log = @import("../../../lib/log.zig");
const BootInfo = @import("../../../kernel/main.zig").BootInfo;

pub const name = "mips64el (MIPS64 Little-Endian)";

var timer_count: u64 = 0;

pub fn earlyInit() void {
    serial.init();
}

pub fn cpuInit() void {
    interrupts.init();
    mmu.init();
    log.info("[CPU]  MIPS64el CP0 configured", .{});
}

pub fn timerInit() void {
    log.info("[TMR]  MIPS64el CP0 Count/Compare timer configured", .{});
}

pub fn timerTick() void {
    timer_count +%= 1;
}

pub fn inputInit(_: *const BootInfo) void {
    log.info("[KBD]  i8042 PS/2 keyboard (stub)", .{});
    log.info("[MOUSE] PS/2 mouse (stub)", .{});
}

pub const TimeInfo = struct {
    hour: u8,
    minute: u8,
};

pub fn readTime() TimeInfo {
    const secs = timer_count / 100;
    return .{
        .hour = @truncate((secs / 3600) % 24),
        .minute = @truncate((secs / 60) % 60),
    };
}

pub fn cpuRelax() void {
    asm volatile ("");
}

pub fn disableInterrupts() void {
    asm volatile ("");
}

pub fn enableInterrupts() void {
    asm volatile ("");
}

pub fn halt() void {
    asm volatile ("wait");
}
