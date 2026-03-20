const pmm = @import("pmm.zig");

const FreeSlot = struct {
    next: ?*FreeSlot,
};

const SlabHeader = struct {
    next: ?*SlabHeader,
    cache: *SlabCache,
    used_count: usize,
};

pub const SlabCache = struct {
    name: []const u8,
    object_size: usize,
    objects_per_slab: usize,
    free_list: ?*FreeSlot,
    slab_list: ?*SlabHeader,
    total_allocated: usize,
    total_freed: usize,

    pub fn create(name: []const u8, object_size: usize) SlabCache {
        const real_size = @max(object_size, @sizeOf(FreeSlot));
        const usable = pmm.PAGE_SIZE - @sizeOf(SlabHeader);
        return .{
            .name = name,
            .object_size = real_size,
            .objects_per_slab = usable / real_size,
            .free_list = null,
            .slab_list = null,
            .total_allocated = 0,
            .total_freed = 0,
        };
    }

    pub fn alloc(self: *SlabCache) ?[*]u8 {
        if (self.free_list) |slot| {
            self.free_list = slot.next;
            self.total_allocated += 1;
            return @ptrCast(slot);
        }

        if (!self.grow()) return null;
        return self.alloc();
    }

    pub fn free(self: *SlabCache, ptr: [*]u8) void {
        const slot: *FreeSlot = @ptrCast(@alignCast(ptr));
        slot.next = self.free_list;
        self.free_list = slot;
        self.total_freed += 1;
    }

    fn grow(self: *SlabCache) bool {
        const page = pmm.allocPage() orelse return false;
        const base_addr = pmm.pageToPhysical(page);

        const header: *SlabHeader = @ptrFromInt(base_addr);
        header.next = self.slab_list;
        header.cache = self;
        header.used_count = 0;
        self.slab_list = header;

        const data_start = base_addr + @sizeOf(SlabHeader);
        var offset: u64 = 0;
        while (offset + self.object_size <= pmm.PAGE_SIZE - @sizeOf(SlabHeader)) : (offset += self.object_size) {
            const slot: *FreeSlot = @ptrFromInt(data_start + offset);
            slot.next = self.free_list;
            self.free_list = slot;
        }

        return true;
    }
};

// Pre-defined caches for common kernel object sizes
pub var cache_32: SlabCache = SlabCache.create("slab-32", 32);
pub var cache_64: SlabCache = SlabCache.create("slab-64", 64);
pub var cache_128: SlabCache = SlabCache.create("slab-128", 128);
pub var cache_256: SlabCache = SlabCache.create("slab-256", 256);
pub var cache_512: SlabCache = SlabCache.create("slab-512", 512);
pub var cache_1024: SlabCache = SlabCache.create("slab-1024", 1024);

pub fn kmalloc(size: usize) ?[*]u8 {
    if (size <= 32) return cache_32.alloc();
    if (size <= 64) return cache_64.alloc();
    if (size <= 128) return cache_128.alloc();
    if (size <= 256) return cache_256.alloc();
    if (size <= 512) return cache_512.alloc();
    if (size <= 1024) return cache_1024.alloc();
    return null;
}
