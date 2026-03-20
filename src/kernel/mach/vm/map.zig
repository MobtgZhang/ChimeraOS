/// VM Map — manages the virtual address space for a Mach task.
/// Each entry maps a contiguous virtual address range to a VM object + offset.

const builtin = @import("builtin");
const log = @import("../../../lib/log.zig");
const SpinLock = @import("../../../lib/spinlock.zig").SpinLock;
const vm_object = @import("object.zig");
const pmm = @import("../../mm/pmm.zig");

const PAGE_SIZE: u64 = 4096;

fn readPageTableBase() u64 {
    if (builtin.cpu.arch == .x86_64) {
        return @import("../../arch/x86_64/paging.zig").readCr3();
    }
    return 0;
}

pub const VMProt = packed struct(u8) {
    read: bool = false,
    write: bool = false,
    execute: bool = false,
    _pad: u5 = 0,
};

pub const VM_PROT_READ = VMProt{ .read = true };
pub const VM_PROT_RW = VMProt{ .read = true, .write = true };
pub const VM_PROT_RX = VMProt{ .read = true, .execute = true };
pub const VM_PROT_RWX = VMProt{ .read = true, .write = true, .execute = true };
pub const VM_PROT_NONE = VMProt{};

pub const InheritFlag = enum(u8) {
    share,
    copy,
    none,
};

pub const MAX_ENTRIES: usize = 1024;

pub const VMEntry = struct {
    start: u64,
    end: u64,
    object: ?*vm_object.VMObject,
    offset: u64,
    protection: VMProt,
    max_protection: VMProt,
    inherit: InheritFlag,
    wired: bool,
    active: bool,

    pub fn size(self: *const VMEntry) u64 {
        return self.end - self.start;
    }

    pub fn containsAddr(self: *const VMEntry, addr: u64) bool {
        return self.active and addr >= self.start and addr < self.end;
    }
};

pub const VMMap = struct {
    entries: [MAX_ENTRIES]VMEntry,
    entry_count: usize,
    min_addr: u64,
    max_addr: u64,
    pml4_phys: u64,
    lock: SpinLock,

    pub fn init(min: u64, max: u64) VMMap {
        @setEvalBranchQuota(10000);
        var map = VMMap{
            .entries = undefined,
            .entry_count = 0,
            .min_addr = min,
            .max_addr = max,
            .pml4_phys = 0,
            .lock = .{},
        };
        for (&map.entries) |*e| e.active = false;
        return map;
    }

    pub fn initWithPageTable(min: u64, max: u64, pml4: u64) VMMap {
        var map = init(min, max);
        map.pml4_phys = pml4;
        return map;
    }

    /// Insert a mapping.  Returns the virtual base on success.
    pub fn mapEntry(
        self: *VMMap,
        addr_hint: ?u64,
        size: u64,
        object: ?*vm_object.VMObject,
        offset: u64,
        prot: VMProt,
    ) ?u64 {
        self.lock.acquire();
        defer self.lock.release();

        const aligned_size = alignUp(size, PAGE_SIZE);
        const start = if (addr_hint) |hint|
            alignUp(hint, PAGE_SIZE)
        else
            self.findFreeRegion(aligned_size) orelse return null;

        if (start < self.min_addr or start + aligned_size > self.max_addr) return null;
        if (self.overlaps(start, start + aligned_size)) return null;

        const slot = self.allocSlot() orelse return null;
        slot.* = .{
            .start = start,
            .end = start + aligned_size,
            .object = object,
            .offset = offset,
            .protection = prot,
            .max_protection = VM_PROT_RWX,
            .inherit = .copy,
            .wired = false,
            .active = true,
        };
        self.entry_count += 1;
        return start;
    }

    pub fn unmap(self: *VMMap, addr: u64, size: u64) bool {
        self.lock.acquire();
        defer self.lock.release();

        const end = addr + alignUp(size, PAGE_SIZE);
        for (&self.entries) |*e| {
            if (!e.active) continue;
            if (e.start >= addr and e.end <= end) {
                if (e.object) |obj| _ = obj.release();
                e.active = false;
                self.entry_count -= 1;
            }
        }
        return true;
    }

    pub fn lookup(self: *VMMap, addr: u64) ?*VMEntry {
        for (&self.entries) |*e| {
            if (e.containsAddr(addr)) return e;
        }
        return null;
    }

    /// Handle a page fault at `fault_addr`.
    pub fn handleFault(self: *VMMap, fault_addr: u64) bool {
        const entry = self.lookup(fault_addr) orelse return false;
        const obj = entry.object orelse return false;

        const page_offset = alignDown(fault_addr, PAGE_SIZE) - entry.start;
        const phys = obj.fault(entry.offset + page_offset) orelse return false;

        _ = phys;
        // Actual page-table insertion deferred to arch-specific code.
        return true;
    }

    pub fn protect(self: *VMMap, addr: u64, size: u64, prot: VMProt) bool {
        self.lock.acquire();
        defer self.lock.release();

        const end = addr + size;
        var changed = false;
        for (&self.entries) |*e| {
            if (!e.active) continue;
            if (e.start >= addr and e.end <= end) {
                e.protection = prot;
                changed = true;
            }
        }
        return changed;
    }

    // ── Internal helpers ──────────────────────────────────────

    fn allocSlot(self: *VMMap) ?*VMEntry {
        for (&self.entries) |*e| {
            if (!e.active) return e;
        }
        return null;
    }

    fn findFreeRegion(self: *VMMap, size: u64) ?u64 {
        var candidate = self.min_addr;
        while (candidate + size <= self.max_addr) {
            var conflict = false;
            for (&self.entries) |*e| {
                if (!e.active) continue;
                if (candidate < e.end and candidate + size > e.start) {
                    candidate = alignUp(e.end, PAGE_SIZE);
                    conflict = true;
                    break;
                }
            }
            if (!conflict) return candidate;
        }
        return null;
    }

    fn overlaps(self: *VMMap, start: u64, end: u64) bool {
        for (&self.entries) |*e| {
            if (!e.active) continue;
            if (start < e.end and end > e.start) return true;
        }
        return false;
    }
};

fn alignUp(val: u64, alignment: u64) u64 {
    return (val + alignment - 1) & ~(alignment - 1);
}

fn alignDown(val: u64, alignment: u64) u64 {
    return val & ~(alignment - 1);
}

// ── Kernel VM map singleton ───────────────────────────────

const KERNEL_VM_BASE: u64 = 0xFFFF_8000_0000_0000;
const KERNEL_VM_TOP: u64 = 0xFFFF_FFFF_FFFF_0000;

var kernel_map: VMMap = VMMap.init(KERNEL_VM_BASE, KERNEL_VM_TOP);

pub fn getKernelMap() *VMMap {
    return &kernel_map;
}

pub fn initKernelMap() void {
    kernel_map = VMMap.initWithPageTable(KERNEL_VM_BASE, KERNEL_VM_TOP, readPageTableBase());
    log.info("Kernel VM map: 0x{x} – 0x{x}", .{ KERNEL_VM_BASE, KERNEL_VM_TOP });
}
