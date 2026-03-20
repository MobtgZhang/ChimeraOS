/// LoongArch64 extended I/O interrupt controller (EIOINTC) stub.
/// LoongArch uses CSR-based interrupt routing; the extended IO interrupt
/// controller handles external device IRQs.

const log = @import("../../../lib/log.zig");

pub fn init() void {
    // LoongArch uses CSR.ECFG to configure exception/interrupt routing.
    // EIOINTC is memory-mapped for extended IRQ management on multi-core
    // Loongson systems.
    log.info("[IRQ]  LoongArch EIOINTC interrupt controller initialized", .{});
}

pub fn enableIrq(irq: u32) void {
    _ = irq;
}

pub fn disableIrq(irq: u32) void {
    _ = irq;
}
