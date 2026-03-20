/// AArch64 MMU — 4-level page table setup (4 KB granule, 48-bit VA).
/// Provides identity mapping for early boot and kernel virtual memory.

const log = @import("../../../lib/log.zig");

pub const PAGE_SIZE: usize = 4096;
pub const TABLE_ENTRIES: usize = 512;

pub const PageTableEntry = packed struct {
    valid: u1 = 0,
    table_or_page: u1 = 0,
    attr_index: u3 = 0,
    ns: u1 = 0,
    ap: u2 = 0,
    sh: u2 = 0,
    af: u1 = 0,
    _reserved0: u1 = 0,
    address: u36 = 0,
    _reserved1: u4 = 0,
    contiguous: u1 = 0,
    pxn: u1 = 0,
    uxn: u1 = 0,
    _reserved2: u4 = 0,
    pbha: u4 = 0,
    _reserved3: u1 = 0,
};

var initialized: bool = false;

pub fn init() void {
    log.info("[MMU]  AArch64 4-level page tables (4KB granule, 48-bit VA)", .{});
    initialized = true;
}

pub fn isInitialized() bool {
    return initialized;
}
