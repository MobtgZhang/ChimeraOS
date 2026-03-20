/// MIPS64el TLB/page table support.
/// MIPS uses a software-managed TLB with EntryHi/EntryLo0/EntryLo1 in CP0.

const log = @import("../../../lib/log.zig");

pub const PAGE_SIZE: usize = 4096;

var initialized: bool = false;

pub fn init() void {
    log.info("[MMU]  MIPS64el software-managed TLB (4KB pages)", .{});
    initialized = true;
}

pub fn isInitialized() bool {
    return initialized;
}
