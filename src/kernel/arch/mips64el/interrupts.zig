/// MIPS64el interrupt controller stub.
/// MIPS uses CP0 Status/Cause registers for interrupt management.
/// On Malta board, an i8259-compatible PIC or GIC may be present.

const log = @import("../../../lib/log.zig");

pub fn init() void {
    log.info("[IRQ]  MIPS64el CP0 interrupt controller initialized", .{});
}

pub fn enableIrq(irq: u32) void {
    _ = irq;
}

pub fn disableIrq(irq: u32) void {
    _ = irq;
}
