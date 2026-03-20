const log = @import("../../lib/log.zig");
const SpinLock = @import("../../lib/spinlock.zig").SpinLock;
const MemoryRegion = @import("../main.zig").MemoryRegion;

pub const PAGE_SIZE: usize = 4096;

var bitmap: [*]u8 = undefined;
var bitmap_size: usize = 0;
var total_pages: usize = 0;
var used_pages: usize = 0;
var lock: SpinLock = .{};

pub fn init(regions: []const MemoryRegion) void {
    // Pass 1: find the highest physical address to determine bitmap size
    var max_addr: u64 = 0;
    for (regions) |r| {
        const end = r.base + r.length;
        if (end > max_addr) max_addr = end;
    }

    total_pages = @intCast(max_addr / PAGE_SIZE);
    bitmap_size = (total_pages + 7) / 8;
    used_pages = total_pages;

    // Pass 2: find a suitable usable memory region for the bitmap
    for (regions) |r| {
        if (r.kind == .usable and r.length >= bitmap_size) {
            bitmap = @ptrFromInt(r.base);
            break;
        }
    }

    // Mark all pages as used
    @memset(bitmap[0..bitmap_size], 0xFF);

    // Pass 3: free pages in usable memory regions
    for (regions) |r| {
        if (r.kind == .usable) {
            const start_page: usize = @intCast(r.base / PAGE_SIZE);
            const count: usize = @intCast(r.length / PAGE_SIZE);
            var i: usize = 0;
            while (i < count) : (i += 1) {
                clearBit(start_page + i);
                used_pages -= 1;
            }
        }
    }

    // Mark the bitmap's own pages as used
    const bitmap_start_page = @intFromPtr(bitmap) / PAGE_SIZE;
    const bitmap_page_count = (bitmap_size + PAGE_SIZE - 1) / PAGE_SIZE;
    var i: usize = 0;
    while (i < bitmap_page_count) : (i += 1) {
        if (!testBit(bitmap_start_page + i)) {
            setBit(bitmap_start_page + i);
            used_pages += 1;
        }
    }

    // Reserve first 1MB (256 pages) for legacy hardware / firmware
    i = 0;
    while (i < 256 and i < total_pages) : (i += 1) {
        if (!testBit(i)) {
            setBit(i);
            used_pages += 1;
        }
    }
}

pub fn allocPage() ?usize {
    lock.acquire();
    defer lock.release();

    var i: usize = 0;
    while (i < bitmap_size) : (i += 1) {
        if (bitmap[i] != 0xFF) {
            var bit: u3 = 0;
            while (true) : (bit += 1) {
                const page = i * 8 + @as(usize, bit);
                if (page >= total_pages) return null;
                if (bitmap[i] & (@as(u8, 1) << bit) == 0) {
                    bitmap[i] |= @as(u8, 1) << bit;
                    used_pages += 1;
                    return page;
                }
                if (bit == 7) break;
            }
        }
    }
    return null;
}

pub fn freePage(page: usize) void {
    lock.acquire();
    defer lock.release();

    if (page < total_pages and testBit(page)) {
        clearBit(page);
        used_pages -= 1;
    }
}

pub fn allocPages(count: usize) ?usize {
    lock.acquire();
    defer lock.release();

    if (count == 0) return null;

    var start: usize = 0;
    while (start + count <= total_pages) {
        var found = true;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            if (testBit(start + i)) {
                start = start + i + 1;
                found = false;
                break;
            }
        }
        if (found) {
            var j: usize = 0;
            while (j < count) : (j += 1) {
                setBit(start + j);
            }
            used_pages += count;
            return start;
        }
    }
    return null;
}

pub fn freePageCount() usize {
    return total_pages - used_pages;
}

pub fn totalPageCount() usize {
    return total_pages;
}

pub fn pageToPhysical(page: usize) u64 {
    return @as(u64, @intCast(page)) * PAGE_SIZE;
}

inline fn testBit(page: usize) bool {
    return bitmap[page / 8] & (@as(u8, 1) << @as(u3, @intCast(page % 8))) != 0;
}

inline fn setBit(page: usize) void {
    bitmap[page / 8] |= @as(u8, 1) << @as(u3, @intCast(page % 8));
}

inline fn clearBit(page: usize) void {
    bitmap[page / 8] &= ~(@as(u8, 1) << @as(u3, @intCast(page % 8)));
}
