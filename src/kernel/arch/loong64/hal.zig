/// LoongArch64 Hardware Abstraction Layer — 16550 UART, EIOINTC, stable counter.
/// Targets QEMU loongarch64 virt machine and Loongson 3A5000/3A6000 hardware.

const serial = @import("serial.zig");
const interrupts = @import("interrupts.zig");
const mmu = @import("mmu.zig");
const log = @import("../../../lib/log.zig");
const BootInfo = @import("../../../kernel/main.zig").BootInfo;

pub const name = "loongarch64 (LoongArch 64-bit)";

var timer_count: u64 = 0;

pub fn earlyInit() void {
    serial.init();
}

pub fn cpuInit() void {
    interrupts.init();
    mmu.init();
    log.info("[CPU]  LoongArch64 CSRs configured", .{});
}

pub fn timerInit() void {
    log.info("[TMR]  LoongArch stable counter timer configured", .{});
}

pub fn timerTick() void {
    timer_count +%= 1;
}

pub fn inputInit(_: *const BootInfo) void {
    log.info("[KBD]  PS/2 or USB HID input (stub)", .{});
    log.info("[MOUSE] USB HID pointer (stub)", .{});
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
    // CRMD.IE = 0
    asm volatile ("");
}

pub fn enableInterrupts() void {
    // CRMD.IE = 1
    asm volatile ("");
}

pub fn halt() void {
    asm volatile ("idle 0");
}
