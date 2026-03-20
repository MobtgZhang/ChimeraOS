/// VM Object — backing store abstraction for virtual memory.
/// Each VM object represents a contiguous region of pageable memory that
/// can be anonymous (zero-filled), copied-on-write, or device-mapped.

const log = @import("../../../lib/log.zig");
const SpinLock = @import("../../../lib/spinlock.zig").SpinLock;
const pmm = @import("../../mm/pmm.zig");

pub const PAGE_SIZE: u64 = 4096;

pub const ObjectType = enum(u8) {
    anonymous,
    copy_on_write,
    device,
};

pub const ResidentPage = struct {
    phys_addr: u64,
    offset: u64,
    dirty: bool,
    wired: bool,
    next: ?*ResidentPage,
};

const MAX_RESIDENT: usize = 4096;
var page_pool: [MAX_RESIDENT]ResidentPage = undefined;
var pool_next: usize = 0;
var pool_lock: SpinLock = .{};

fn allocResidentPage() ?*ResidentPage {
    pool_lock.acquire();
    defer pool_lock.release();
    if (pool_next >= MAX_RESIDENT) return null;
    const p = &page_pool[pool_next];
    pool_next += 1;
    return p;
}

pub const MAX_OBJECTS: usize = 512;

pub const VMObject = struct {
    obj_type: ObjectType,
    size: u64,
    ref_count: u32,
    resident_list: ?*ResidentPage,
    resident_count: u32,
    shadow: ?*VMObject,
    pager_offset: u64,
    lock: SpinLock,
    active: bool,

    pub fn initAnonymous(size: u64) VMObject {
        return .{
            .obj_type = .anonymous,
            .size = size,
            .ref_count = 1,
            .resident_list = null,
            .resident_count = 0,
            .shadow = null,
            .pager_offset = 0,
            .lock = .{},
            .active = true,
        };
    }

    pub fn initDevice(phys_base: u64, size: u64) VMObject {
        return .{
            .obj_type = .device,
            .size = size,
            .ref_count = 1,
            .resident_list = null,
            .resident_count = 0,
            .shadow = null,
            .pager_offset = phys_base,
            .lock = .{},
            .active = true,
        };
    }

    pub fn retain(self: *VMObject) void {
        self.lock.acquire();
        defer self.lock.release();
        self.ref_count += 1;
    }

    pub fn release(self: *VMObject) bool {
        self.lock.acquire();
        if (self.ref_count > 1) {
            self.ref_count -= 1;
            self.lock.release();
            return false;
        }
        self.ref_count = 0;
        self.active = false;
        self.lock.release();
        self.releasePages();
        return true;
    }

    /// Look up the physical page backing a given offset in this object.
    pub fn lookupPage(self: *VMObject, offset: u64) ?u64 {
        self.lock.acquire();
        defer self.lock.release();

        var cur = self.resident_list;
        while (cur) |rp| {
            if (rp.offset == offset) return rp.phys_addr;
            cur = rp.next;
        }

        if (self.shadow) |shadow| {
            return shadow.lookupPage(offset);
        }

        return null;
    }

    /// Allocate and insert a new physical page at `offset`.
    pub fn insertPage(self: *VMObject, offset: u64, phys: u64) bool {
        self.lock.acquire();
        defer self.lock.release();

        const rp = allocResidentPage() orelse return false;
        rp.* = .{
            .phys_addr = phys,
            .offset = offset,
            .dirty = false,
            .wired = false,
            .next = self.resident_list,
        };
        self.resident_list = rp;
        self.resident_count += 1;
        return true;
    }

    /// Fault handler: allocate a zero-filled page for anonymous objects.
    pub fn fault(self: *VMObject, offset: u64) ?u64 {
        if (self.lookupPage(offset)) |phys| return phys;

        switch (self.obj_type) {
            .anonymous => {
                const page_idx = pmm.allocPage() orelse return null;
                const phys = pmm.pageToPhysical(page_idx);
                const ptr: [*]volatile u8 = @ptrFromInt(phys);
                for (0..pmm.PAGE_SIZE) |i| ptr[i] = 0;
                if (!self.insertPage(offset, phys)) {
                    pmm.freePage(page_idx);
                    return null;
                }
                return phys;
            },
            .device => {
                return self.pager_offset + offset;
            },
            .copy_on_write => {
                if (self.shadow) |shadow| {
                    if (shadow.lookupPage(offset)) |src_phys| {
                        const page_idx = pmm.allocPage() orelse return null;
                        const dst_phys = pmm.pageToPhysical(page_idx);
                        const src: [*]const u8 = @ptrFromInt(src_phys);
                        const dst: [*]u8 = @ptrFromInt(dst_phys);
                        @memcpy(dst[0..pmm.PAGE_SIZE], src[0..pmm.PAGE_SIZE]);
                        _ = self.insertPage(offset, dst_phys);
                        return dst_phys;
                    }
                }
                return self.fault(offset);
            },
        }
    }

    pub fn createShadow(self: *VMObject) VMObject {
        self.retain();
        return .{
            .obj_type = .copy_on_write,
            .size = self.size,
            .ref_count = 1,
            .resident_list = null,
            .resident_count = 0,
            .shadow = self,
            .pager_offset = 0,
            .lock = .{},
            .active = true,
        };
    }

    fn releasePages(self: *VMObject) void {
        var cur = self.resident_list;
        while (cur) |rp| {
            if (self.obj_type != .device) {
                const page_idx = @as(usize, @intCast(rp.phys_addr / pmm.PAGE_SIZE));
                pmm.freePage(page_idx);
            }
            cur = rp.next;
        }
        self.resident_list = null;
        self.resident_count = 0;
    }
};

var objects: [MAX_OBJECTS]VMObject = undefined;
var objects_used: usize = 0;
var objects_lock: SpinLock = .{};

pub fn createAnonymous(size: u64) ?*VMObject {
    objects_lock.acquire();
    defer objects_lock.release();
    if (objects_used >= MAX_OBJECTS) return null;
    const idx = objects_used;
    objects[idx] = VMObject.initAnonymous(size);
    objects_used += 1;
    return &objects[idx];
}

pub fn createDevice(phys: u64, size: u64) ?*VMObject {
    objects_lock.acquire();
    defer objects_lock.release();
    if (objects_used >= MAX_OBJECTS) return null;
    const idx = objects_used;
    objects[idx] = VMObject.initDevice(phys, size);
    objects_used += 1;
    return &objects[idx];
}
