/// RISC-V Sv48 page table support (4-level, 48-bit virtual address).

const log = @import("../../../lib/log.zig");

pub const PAGE_SIZE: usize = 4096;
pub const TABLE_ENTRIES: usize = 512;

pub const PageTableEntry = packed struct {
    v: u1 = 0,
    r: u1 = 0,
    w: u1 = 0,
    x: u1 = 0,
    u: u1 = 0,
    g: u1 = 0,
    a: u1 = 0,
    d: u1 = 0,
    rsw: u2 = 0,
    ppn: u44 = 0,
    _reserved: u7 = 0,
    pbmt: u2 = 0,
    n: u1 = 0,
};

var initialized: bool = false;

pub fn init() void {
    log.info("[MMU]  RISC-V Sv48 page tables (4KB pages, 48-bit VA)", .{});
    initialized = true;
}

pub fn isInitialized() bool {
    return initialized;
}
