const std = @import("std");
const log = @import("../../../lib/log.zig");
const pmm = @import("../../mm/pmm.zig");

pub const PAGE_SIZE: u64 = 4096;
pub const PAGE_MASK: u64 = ~@as(u64, PAGE_SIZE - 1);

pub const PTE_PRESENT: u64 = 1 << 0;
pub const PTE_WRITABLE: u64 = 1 << 1;
pub const PTE_USER: u64 = 1 << 2;
pub const PTE_WRITE_THROUGH: u64 = 1 << 3;
pub const PTE_CACHE_DISABLE: u64 = 1 << 4;
pub const PTE_ACCESSED: u64 = 1 << 5;
pub const PTE_DIRTY: u64 = 1 << 6;
pub const PTE_HUGE: u64 = 1 << 7;
pub const PTE_GLOBAL: u64 = 1 << 8;
pub const PTE_NO_EXECUTE: u64 = @as(u64, 1) << 63;

pub const PageTable = [512]u64;

pub fn readCr3() u64 {
    return asm volatile ("mov %%cr3, %[result]"
        : [result] "=r" (-> u64),
    );
}

pub fn writeCr3(addr: u64) void {
    asm volatile ("mov %[addr], %%cr3"
        :
        : [addr] "r" (addr),
        : .{ .memory = true }
    );
}

pub fn invlpg(addr: u64) void {
    asm volatile ("invlpg (%[addr])"
        :
        : [addr] "r" (addr),
        : .{ .memory = true }
    );
}

pub fn readCr2() u64 {
    return asm volatile ("mov %%cr2, %[result]"
        : [result] "=r" (-> u64),
    );
}

/// Extract PML4 index from virtual address (bits 39-47)
pub fn pml4Index(virt: u64) u9 {
    return @truncate(virt >> 39);
}

/// Extract PDPT index from virtual address (bits 30-38)
pub fn pdptIndex(virt: u64) u9 {
    return @truncate(virt >> 30);
}

/// Extract PD index from virtual address (bits 21-29)
pub fn pdIndex(virt: u64) u9 {
    return @truncate(virt >> 21);
}

/// Extract PT index from virtual address (bits 12-20)
pub fn ptIndex(virt: u64) u9 {
    return @truncate(virt >> 12);
}

/// Get PML4 table pointer from CR3
pub fn getPml4() *PageTable {
    const cr3 = readCr3();
    return @ptrFromInt(cr3 & PAGE_MASK);
}
