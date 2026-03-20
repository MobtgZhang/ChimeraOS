/// LoongArch64 page table support.
/// LoongArch uses a multi-level page table (configurable 3 or 4 levels)
/// with TLB refill handled via CSR.TLBRENTRY.

const log = @import("../../../lib/log.zig");

pub const PAGE_SIZE: usize = 4096; // 4 KB default (16 KB optional)

var initialized: bool = false;

pub fn init() void {
    log.info("[MMU]  LoongArch64 page tables (4KB pages, STLB/MTLB)", .{});
    initialized = true;
}

pub fn isInitialized() bool {
    return initialized;
}
