/// Default Pager — handles page-in / page-out for VM objects.
/// The default pager fulfils anonymous memory requests with zero-filled pages
/// and provides the interface for future swap-backed paging.

const log = @import("../../../lib/log.zig");
const pmm = @import("../../mm/pmm.zig");
const vm_object = @import("object.zig");

pub const PagerError = error{
    OutOfMemory,
    InvalidOffset,
    IoError,
};

pub const PagerOps = struct {
    page_in: *const fn (obj: *vm_object.VMObject, offset: u64) PagerError!u64,
    page_out: *const fn (phys: u64, offset: u64) PagerError!void,
};

// ── Default anonymous pager ───────────────────────────────

fn defaultPageIn(obj: *vm_object.VMObject, offset: u64) PagerError!u64 {
    if (offset >= obj.size) return PagerError.InvalidOffset;

    if (obj.lookupPage(offset)) |phys| return phys;

    const page_idx = pmm.allocPage() orelse return PagerError.OutOfMemory;
    const phys = pmm.pageToPhysical(page_idx);

    const ptr: [*]volatile u8 = @ptrFromInt(phys);
    for (0..pmm.PAGE_SIZE) |i| ptr[i] = 0;

    if (!obj.insertPage(offset, phys)) {
        pmm.freePage(page_idx);
        return PagerError.OutOfMemory;
    }
    return phys;
}

fn defaultPageOut(phys: u64, offset: u64) PagerError!void {
    _ = offset;
    const page_idx: usize = @intCast(phys / pmm.PAGE_SIZE);
    pmm.freePage(page_idx);
}

pub const default_pager = PagerOps{
    .page_in = &defaultPageIn,
    .page_out = &defaultPageOut,
};

// ── Device pager (identity-mapped, no real paging) ────────

fn devicePageIn(obj: *vm_object.VMObject, offset: u64) PagerError!u64 {
    if (offset >= obj.size) return PagerError.InvalidOffset;
    return obj.pager_offset + offset;
}

fn devicePageOut(_: u64, _: u64) PagerError!void {}

pub const device_pager = PagerOps{
    .page_in = &devicePageIn,
    .page_out = &devicePageOut,
};

// ── Swap pager stub ───────────────────────────────────────

const SWAP_SLOT_COUNT: usize = 8192;
var swap_bitmap: [SWAP_SLOT_COUNT / 8]u8 = [_]u8{0} ** (SWAP_SLOT_COUNT / 8);
var swap_initialized: bool = false;

pub fn initSwap() void {
    @memset(&swap_bitmap, 0);
    swap_initialized = true;
    log.info("Swap pager initialized ({} slots)", .{SWAP_SLOT_COUNT});
}

pub fn allocSwapSlot() ?usize {
    if (!swap_initialized) return null;
    for (0..SWAP_SLOT_COUNT) |i| {
        const byte = i / 8;
        const bit: u3 = @intCast(i % 8);
        if (swap_bitmap[byte] & (@as(u8, 1) << bit) == 0) {
            swap_bitmap[byte] |= @as(u8, 1) << bit;
            return i;
        }
    }
    return null;
}

pub fn freeSwapSlot(slot: usize) void {
    if (slot >= SWAP_SLOT_COUNT) return;
    const byte = slot / 8;
    const bit: u3 = @intCast(slot % 8);
    swap_bitmap[byte] &= ~(@as(u8, 1) << bit);
}
