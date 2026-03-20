/// LoongArch64 16550-compatible UART driver.
/// On QEMU loongarch64 virt machine the UART is at 0x1FE0_01E0.

const UART_BASE: u64 = 0x1FE001E0;

const THR: *volatile u8 = @ptrFromInt(UART_BASE + 0);
const RBR: *volatile u8 = @ptrFromInt(UART_BASE + 0);
const IER: *volatile u8 = @ptrFromInt(UART_BASE + 1);
const FCR: *volatile u8 = @ptrFromInt(UART_BASE + 2);
const LCR: *volatile u8 = @ptrFromInt(UART_BASE + 3);
const MCR: *volatile u8 = @ptrFromInt(UART_BASE + 4);
const LSR: *volatile u8 = @ptrFromInt(UART_BASE + 5);
const DLL: *volatile u8 = @ptrFromInt(UART_BASE + 0);
const DLM: *volatile u8 = @ptrFromInt(UART_BASE + 1);

pub fn init() void {
    IER.* = 0x00;
    LCR.* = 0x80;
    DLL.* = 0x01;
    DLM.* = 0x00;
    LCR.* = 0x03;
    FCR.* = 0xC7;
    MCR.* = 0x0B;
}

pub fn writeByte(byte: u8) void {
    while (LSR.* & 0x20 == 0) {
        asm volatile ("");
    }
    THR.* = byte;
}

pub fn writeString(s: []const u8) void {
    for (s) |c| {
        if (c == '\n') writeByte('\r');
        writeByte(c);
    }
}

pub fn readByte() u8 {
    while (LSR.* & 0x01 == 0) {
        asm volatile ("");
    }
    return RBR.*;
}
