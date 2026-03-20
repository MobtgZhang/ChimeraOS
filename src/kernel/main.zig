const std = @import("std");
const uefi = std.os.uefi;

// ── Architecture ──────────────────────────────────────────
const gdt = @import("arch/x86_64/gdt.zig");
const idt = @import("arch/x86_64/idt.zig");
const serial = @import("arch/x86_64/serial.zig");
const paging = @import("arch/x86_64/paging.zig");

// ── Memory Management ─────────────────────────────────────
const pmm = @import("mm/pmm.zig");
const slab = @import("mm/slab.zig");

// ── Kernel Libraries ──────────────────────────────────────
const buddy = @import("lib/buddy.zig");
const rb_tree = @import("lib/rb_tree.zig");
const log = @import("../lib/log.zig");

// ── Mach Subsystem ────────────────────────────────────────
pub const mach_port = @import("mach/port.zig");
pub const mach_message = @import("mach/message.zig");
pub const mach_task = @import("mach/task.zig");
pub const mach_thread = @import("mach/thread.zig");
pub const mach_clock = @import("mach/clock.zig");
pub const mach_vm_object = @import("mach/vm/object.zig");
pub const mach_vm_map = @import("mach/vm/map.zig");
pub const mach_vm_pager = @import("mach/vm/pager.zig");

// ── BSD Layer ─────────────────────────────────────────────
pub const bsd_syscall = @import("bsd/syscall.zig");
pub const bsd_proc = @import("bsd/proc.zig");
pub const bsd_signal = @import("bsd/signal.zig");
pub const bsd_vnode = @import("bsd/vfs/vnode.zig");
pub const bsd_devfs = @import("bsd/vfs/devfs.zig");

// ── I/O Kit ───────────────────────────────────────────────
pub const iokit_registry = @import("iokit/registry.zig");
pub const iokit_service = @import("iokit/service.zig");
pub const iokit_pcie = @import("iokit/drivers/pcie.zig");

// ── Loader ────────────────────────────────────────────────
pub const macho_parser = @import("../loader/macho/parser.zig");
pub const macho_fat = @import("../loader/macho/fat.zig");
pub const macho_segments = @import("../loader/macho/segments.zig");

// ── Boot Info Structures ──────────────────────────────────

pub const FramebufferInfo = struct {
    base: u64,
    size: usize,
    width: u32,
    height: u32,
    stride: u32,
    bpp: u32,
};

pub const BootInfo = struct {
    framebuffer: ?FramebufferInfo,
    memory_map: uefi.tables.MemoryMapSlice,
};

// ── Kernel Entry Point ────────────────────────────────────

pub fn kernelMain(boot_info: *const BootInfo) noreturn {
    // Phase 0: Serial & logging
    serial.init();
    log.info("", .{});
    log.info("========================================", .{});
    log.info("  ChimeraOS Z-Kernel v0.2.0", .{});
    log.info("  A macOS-compatible OS written in Zig", .{});
    log.info("========================================", .{});
    log.info("", .{});

    // Phase 1: CPU tables
    gdt.init();
    log.info("[CPU]  GDT loaded (null + kernel CS/DS + user CS/DS)", .{});

    idt.init();
    log.info("[CPU]  IDT loaded (256 vectors)", .{});

    // Phase 2: Physical memory
    pmm.init(boot_info.memory_map);
    log.info("[MEM]  PMM: {} pages free ({} MB)", .{
        pmm.freePageCount(),
        pmm.freePageCount() * 4096 / (1024 * 1024),
    });

    initBuddyZone();

    // Phase 3: Framebuffer
    if (boot_info.framebuffer) |fb| {
        log.info("[GFX]  Framebuffer: {}x{} stride={} @ 0x{x}", .{
            fb.width, fb.height, fb.stride, fb.base,
        });
        drawBootScreen(fb);
    }

    // Phase 4: Virtual memory
    mach_vm_map.initKernelMap();
    log.info("[VM]   Kernel VM map initialized", .{});

    // Phase 5: Mach subsystem
    mach_task.initKernelTask();
    log.info("[MACH] kernel_task created (PID 0)", .{});

    mach_thread.init();
    log.info("[MACH] Thread scheduler initialized", .{});

    // Phase 6: BSD layer
    bsd_syscall.init();
    log.info("[BSD]  Syscall dispatch table ready ({} entries)", .{
        @typeInfo(bsd_syscall.SyscallNumber).@"enum".fields.len,
    });

    bsd_proc.init();
    log.info("[BSD]  Process table initialized", .{});

    bsd_vnode.init();
    bsd_devfs.init();
    log.info("[VFS]  VFS + DevFS mounted (/dev/null, /dev/zero, /dev/console)", .{});

    // Phase 7: I/O Kit
    iokit_registry.init();
    iokit_service.init();
    log.info("[IOK]  IOKit registry and service manager ready", .{});

    iokit_pcie.init();

    // Phase 8: Summary
    log.info("", .{});
    log.info("=== ChimeraOS Z-Kernel initialized ===", .{});
    log.info("  Architecture : x86_64", .{});
    log.info("  Build        : {s}", .{
        if (@import("build_options").enable_logging) "Debug (logging ON)" else "Release (logging OFF)",
    });
    log.info("  Free memory  : {} MB", .{pmm.freePageCount() * 4096 / (1024 * 1024)});
    log.info("  Subsystems   : Mach IPC, VM, BSD, VFS, IOKit, Mach-O Loader", .{});
    log.info("", .{});
    log.info("Entering idle loop.  Waiting for work.", .{});

    while (true) {
        mach_clock.processAlarms();
        asm volatile ("hlt");
    }
}

// ── Buddy Zone Initialisation ─────────────────────────────

fn initBuddyZone() void {
    const zone_order: u5 = 10; // 1024 pages = 4 MB
    if (pmm.allocPages(1024)) |start_page| {
        const base = pmm.pageToPhysical(start_page);
        buddy.init(base, 1024);
        log.info("[MEM]  Buddy zone: {} pages at 0x{x}", .{ 1024, base });
    } else {
        log.warn("[MEM]  Not enough memory for buddy zone", .{});
        _ = zone_order;
    }
}

// ── Boot Screen Drawing ───────────────────────────────────

fn drawBootScreen(fb: FramebufferInfo) void {
    const pixel_base: [*]volatile u32 = @ptrFromInt(fb.base);
    const bg_color: u32 = 0x001E1E2E; // Catppuccin Mocha base
    const accent: u32 = 0x0089B4FA; // blue accent
    const text_bg: u32 = 0x00313244;

    // Fill background
    var y: u32 = 0;
    while (y < fb.height) : (y += 1) {
        var x: u32 = 0;
        while (x < fb.width) : (x += 1) {
            pixel_base[@as(usize, y) * fb.stride + x] = bg_color;
        }
    }

    // Gradient accent bar at top (6 pixels)
    y = 0;
    while (y < @min(fb.height, 6)) : (y += 1) {
        var x: u32 = 0;
        while (x < fb.width) : (x += 1) {
            pixel_base[@as(usize, y) * fb.stride + x] = accent;
        }
    }

    // Center logo box (160x100)
    const logo_w: u32 = 160;
    const logo_h: u32 = 100;
    if (fb.width > logo_w and fb.height > logo_h + 40) {
        const cx = (fb.width - logo_w) / 2;
        const cy = (fb.height - logo_h) / 2;
        y = cy;
        while (y < cy + logo_h) : (y += 1) {
            var x: u32 = cx;
            while (x < cx + logo_w) : (x += 1) {
                const dx = x - cx;
                const dy = y - cy;
                const is_border = dx < 3 or dx >= logo_w - 3 or dy < 3 or dy >= logo_h - 3;
                pixel_base[@as(usize, y) * fb.stride + x] = if (is_border) accent else text_bg;
            }
        }

        // Bottom status bar
        const bar_y = fb.height - 24;
        var by: u32 = bar_y;
        while (by < fb.height) : (by += 1) {
            var bx: u32 = 0;
            while (bx < fb.width) : (bx += 1) {
                pixel_base[@as(usize, by) * fb.stride + bx] = text_bg;
            }
        }
    }
}
