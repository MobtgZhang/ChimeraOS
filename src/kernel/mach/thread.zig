/// Mach Thread — the schedulable unit of execution.
/// Each thread belongs to exactly one Task and carries its own kernel stack
/// and saved CPU context for preemptive context switching.

const log = @import("../../lib/log.zig");
const SpinLock = @import("../../lib/spinlock.zig").SpinLock;
const task_mod = @import("task.zig");
const pmm = @import("../mm/pmm.zig");

pub const KERNEL_STACK_PAGES: usize = 4;
pub const KERNEL_STACK_SIZE: usize = KERNEL_STACK_PAGES * pmm.PAGE_SIZE;
pub const MAX_THREADS: usize = 256;

pub const ThreadState = enum(u8) {
    created,
    runnable,
    running,
    blocked,
    terminated,
};

pub const Priority = struct {
    pub const IDLE: u8 = 0;
    pub const LOW: u8 = 16;
    pub const NORMAL: u8 = 31;
    pub const HIGH: u8 = 48;
    pub const REALTIME: u8 = 63;
};

/// Saved CPU state pushed on the kernel stack during context switch.
/// Layout must match the assembly in `contextSwitch`.
pub const CpuContext = extern struct {
    r15: u64 = 0,
    r14: u64 = 0,
    r13: u64 = 0,
    r12: u64 = 0,
    rbx: u64 = 0,
    rbp: u64 = 0,
    rdi: u64 = 0,
    rsi: u64 = 0,
    rip: u64 = 0,
};

pub const Thread = struct {
    tid: u32,
    task_pid: u32,
    state: ThreadState,
    priority: u8,
    time_slice: u32,
    time_remaining: u32,

    kernel_stack_base: u64,
    kernel_stack_top: u64,
    saved_rsp: u64,

    name: [32]u8,
    name_len: usize,
    active: bool,

    pub fn getName(self: *const Thread) []const u8 {
        return self.name[0..self.name_len];
    }
};

var threads: [MAX_THREADS]Thread = undefined;
var thread_active: [MAX_THREADS]bool = [_]bool{false} ** MAX_THREADS;
var next_tid: u32 = 0;
var sched_lock: SpinLock = .{};

var current_tid: u32 = 0;
var idle_tid: u32 = 0;

pub fn init() void {
    for (&thread_active) |*a| a.* = false;
    next_tid = 0;

    idle_tid = createKernelThread("idle", Priority.IDLE, &idleEntry) orelse 0;
    threads[idle_tid].state = .running;
    current_tid = idle_tid;

    log.info("Thread subsystem initialized (idle tid={})", .{idle_tid});
}

pub fn createKernelThread(name: []const u8, priority: u8, entry: *const fn () void) ?u32 {
    sched_lock.acquire();
    defer sched_lock.release();

    if (next_tid >= MAX_THREADS) return null;

    const stack_start = pmm.allocPages(KERNEL_STACK_PAGES) orelse return null;
    const stack_base = pmm.pageToPhysical(stack_start);
    const stack_top = stack_base + KERNEL_STACK_SIZE;

    var sp = stack_top;
    sp -= @sizeOf(CpuContext);
    const ctx: *CpuContext = @ptrFromInt(sp);
    ctx.* = .{
        .rip = @intFromPtr(entry),
        .rbp = stack_top,
    };

    const tid = next_tid;
    var t = &threads[tid];
    t.* = .{
        .tid = tid,
        .task_pid = 0,
        .state = .runnable,
        .priority = priority,
        .time_slice = 10,
        .time_remaining = 10,
        .kernel_stack_base = stack_base,
        .kernel_stack_top = stack_top,
        .saved_rsp = sp,
        .name = [_]u8{0} ** 32,
        .name_len = @min(name.len, 32),
        .active = true,
    };
    @memcpy(t.name[0..t.name_len], name[0..t.name_len]);
    thread_active[tid] = true;
    next_tid += 1;

    log.debug("Thread created: tid={}, stack=0x{x}", .{ tid, stack_base });
    return tid;
}

pub fn currentThread() ?*Thread {
    if (current_tid < MAX_THREADS and thread_active[current_tid])
        return &threads[current_tid];
    return null;
}

pub fn lookupThread(tid: u32) ?*Thread {
    if (tid >= MAX_THREADS or !thread_active[tid]) return null;
    return &threads[tid];
}

pub fn terminateThread(tid: u32) void {
    sched_lock.acquire();
    defer sched_lock.release();
    if (tid >= MAX_THREADS or !thread_active[tid]) return;
    threads[tid].state = .terminated;
    if (tid == current_tid) schedule();
}

pub fn blockThread(tid: u32) void {
    sched_lock.acquire();
    defer sched_lock.release();
    if (tid >= MAX_THREADS or !thread_active[tid]) return;
    threads[tid].state = .blocked;
}

pub fn unblockThread(tid: u32) void {
    sched_lock.acquire();
    defer sched_lock.release();
    if (tid >= MAX_THREADS or !thread_active[tid]) return;
    if (threads[tid].state == .blocked) {
        threads[tid].state = .runnable;
    }
}

// ── Scheduler (priority round-robin) ─────────────────────

pub fn schedule() void {
    sched_lock.acquire();

    const old_tid = current_tid;
    var best_tid: u32 = idle_tid;
    var best_pri: u8 = 0;

    for (0..next_tid) |i| {
        if (!thread_active[i]) continue;
        const t = &threads[i];
        if (t.state != .runnable) continue;
        if (t.priority > best_pri or
            (t.priority == best_pri and @as(u32, @intCast(i)) > old_tid))
        {
            best_tid = @intCast(i);
            best_pri = t.priority;
        }
    }

    if (best_tid == old_tid) {
        sched_lock.release();
        return;
    }

    if (threads[old_tid].state == .running)
        threads[old_tid].state = .runnable;
    threads[best_tid].state = .running;
    threads[best_tid].time_remaining = threads[best_tid].time_slice;
    current_tid = best_tid;

    const old_rsp_ptr = &threads[old_tid].saved_rsp;
    const new_rsp = threads[best_tid].saved_rsp;

    sched_lock.release();
    contextSwitch(old_rsp_ptr, new_rsp);
}

pub fn timerTick() void {
    if (current_tid >= MAX_THREADS) return;
    var t = &threads[current_tid];
    if (t.time_remaining > 0) {
        t.time_remaining -= 1;
        if (t.time_remaining == 0) schedule();
    }
}

/// Low-level context switch.
/// Saves callee-saved registers on the old stack, switches RSP,
/// restores registers from the new stack and returns.
fn contextSwitch(old_rsp: *u64, new_rsp: u64) void {
    // On UEFI x86_64 target the Zig-internal ABI may differ from System V.
    // This inline assembly manually handles register save/restore so it is
    // ABI-agnostic: we simply save everything we need.
    asm volatile (
        \\push %%rbp
        \\push %%rbx
        \\push %%r12
        \\push %%r13
        \\push %%r14
        \\push %%r15
        \\push %%rdi
        \\push %%rsi
        // Save current RSP into *old_rsp
        \\mov %%rsp, (%[old])
        // Load new RSP
        \\mov %[new], %%rsp
        \\pop %%rsi
        \\pop %%rdi
        \\pop %%r15
        \\pop %%r14
        \\pop %%r13
        \\pop %%r12
        \\pop %%rbx
        \\pop %%rbp
        \\ret
        :
        : [old] "r" (old_rsp),
          [new] "r" (new_rsp),
        : .{ .memory = true }
    );
}

fn idleEntry() void {
    while (true) {
        asm volatile ("hlt");
    }
}
