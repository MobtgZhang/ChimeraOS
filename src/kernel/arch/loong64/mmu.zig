/// LoongArch64 MMU / TLB management.
///
/// LoongArch supports two address-translation modes controlled by CRMD:
///   DA=1, PG=0 : Direct Address — VA == PA (used at boot, no TLB)
///   DA=0, PG=1 : Paged — multi-level page table with STLB/MTLB
///
/// In addition, four Direct Map Windows (DMW0–DMW3) provide fixed
/// VA→PA mappings without TLB lookups, which is how the Linux kernel
/// maps its own linear address space on LoongArch.
///
/// At boot (QEMU -kernel), DA=1.  We switch to DMW-based mapping so
/// the kernel can access all physical memory through a known VA prefix
/// while leaving PG available for user-space later.
///
/// DMW0: 0x9000_xxxx_xxxx_xxxx → PA (Coherent Cached, PLV0)
/// DMW1: 0x8000_xxxx_xxxx_xxxx → PA (Strongly-ordered Uncached, PLV0)

const csr = @import("csr.zig");
const log = @import("../../../lib/log.zig");

pub const PAGE_SIZE: usize = 4096; // 4 KB (16 KB optional on some cores)

var initialized: bool = false;

pub fn init() void {
    // Configure Direct Map Windows for kernel address space.
    //
    // DMW0: cached mapping    — VSEG=0x9, MAT=CC, PLV0
    //   VA 0x9000_xxxx_xxxx_xxxx → PA xxxx_xxxx_xxxx_xxxx
    //
    // DMW1: uncached mapping  — VSEG=0x8, MAT=SUC, PLV0
    //   VA 0x8000_xxxx_xxxx_xxxx → PA xxxx_xxxx_xxxx_xxxx
    //
    // DMW2/DMW3: disabled (cleared)

    csr.write(csr.DMW0, csr.dmwVseg(0x9) | csr.DMW_MAT_CC | csr.DMW_PLV0);
    csr.write(csr.DMW1, csr.dmwVseg(0x8) | csr.DMW_MAT_SUC | csr.DMW_PLV0);
    csr.write(csr.DMW2, 0);
    csr.write(csr.DMW3, 0);

    // Read back for verification
    const dmw0_val = csr.read(csr.DMW0);
    const dmw1_val = csr.read(csr.DMW1);

    log.info("[MMU]  LoongArch64 Direct Map Windows configured", .{});
    log.info("[MMU]    DMW0 = 0x{x} (0x9000_xxxx cached)", .{dmw0_val});
    log.info("[MMU]    DMW1 = 0x{x} (0x8000_xxxx uncached)", .{dmw1_val});

    // For now, stay in DA mode (direct address).  Switching to PG mode
    // requires a fully populated page table for user-space, which is
    // set up later when the process subsystem is ready.

    // Report TLB capabilities from PRCFG1/PRCFG2
    const prcfg1 = csr.read(csr.PRCFG1);
    const stlb_ways = (prcfg1 >> 8) & 0xFF;
    const stlb_sets_log2 = prcfg1 & 0xFF;
    log.info("[MMU]    STLB: {} ways, {} sets", .{ stlb_ways, @as(u64, 1) << @as(u6, @intCast(stlb_sets_log2)) });

    initialized = true;
}

pub fn isInitialized() bool {
    return initialized;
}

/// Convert a physical address to the kernel cached virtual address
/// (via DMW0 at VSEG 0x9).
pub inline fn physToVirtCached(paddr: u64) u64 {
    return paddr | (@as(u64, 0x9) << 60);
}

/// Convert a physical address to the kernel uncached virtual address
/// (via DMW1 at VSEG 0x8).
pub inline fn physToVirtUncached(paddr: u64) u64 {
    return paddr | (@as(u64, 0x8) << 60);
}

/// Strip the DMW VSEG prefix to recover the physical address.
pub inline fn virtToPhys(vaddr: u64) u64 {
    return vaddr & 0x0FFF_FFFF_FFFF_FFFF;
}
