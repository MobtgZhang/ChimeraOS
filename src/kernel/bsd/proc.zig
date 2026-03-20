/// BSD Process — the user-visible process abstraction layered on top of
/// Mach Tasks.  Adds file descriptor tables, credentials, process groups,
/// and wait/exit semantics.

const log = @import("../../lib/log.zig");
const SpinLock = @import("../../lib/spinlock.zig").SpinLock;
const task_mod = @import("../mach/task.zig");
const signal_mod = @import("signal.zig");

pub const MAX_PROCS: usize = task_mod.MAX_TASKS;
pub const MAX_FDS: usize = 256;

pub const ProcState = enum(u8) {
    embryo,
    runnable,
    sleeping,
    stopped,
    zombie,
};

pub const FileDescriptor = struct {
    vnode_id: u32,
    offset: u64,
    flags: u32,
    active: bool,

    pub const O_RDONLY: u32 = 0x0000;
    pub const O_WRONLY: u32 = 0x0001;
    pub const O_RDWR: u32 = 0x0002;
    pub const O_APPEND: u32 = 0x0008;
    pub const O_CREAT: u32 = 0x0200;
    pub const O_TRUNC: u32 = 0x0400;
    pub const O_NONBLOCK: u32 = 0x0004;
    pub const O_CLOEXEC: u32 = 0x1000000;
};

pub const Credentials = struct {
    uid: u32,
    gid: u32,
    euid: u32,
    egid: u32,
};

pub const Process = struct {
    pid: u32,
    ppid: u32,
    pgid: u32,
    sid: u32,
    state: ProcState,
    exit_status: i32,

    cred: Credentials,
    fds: [MAX_FDS]FileDescriptor,
    fd_count: usize,

    sig_state: signal_mod.SignalState,

    name: [64]u8,
    name_len: usize,
    active: bool,

    pub fn getName(self: *const Process) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn allocFd(self: *Process) ?usize {
        for (0..MAX_FDS) |i| {
            if (!self.fds[i].active) {
                self.fds[i].active = true;
                self.fd_count += 1;
                return i;
            }
        }
        return null;
    }

    pub fn closeFd(self: *Process, fd: usize) bool {
        if (fd >= MAX_FDS or !self.fds[fd].active) return false;
        self.fds[fd].active = false;
        self.fd_count -|= 1;
        return true;
    }

    pub fn lookupFd(self: *Process, fd: usize) ?*FileDescriptor {
        if (fd >= MAX_FDS or !self.fds[fd].active) return null;
        return &self.fds[fd];
    }
};

var procs: [MAX_PROCS]Process = undefined;
var proc_active: [MAX_PROCS]bool = [_]bool{false} ** MAX_PROCS;
var next_pid: u32 = 0;
var lock: SpinLock = .{};

pub fn init() void {
    for (&proc_active) |*a| a.* = false;
    next_pid = 0;
    _ = createProcess("kernel", 0, 0) orelse {};
    log.info("BSD process table initialized", .{});
}

pub fn createProcess(name: []const u8, ppid: u32, pgid: u32) ?u32 {
    lock.acquire();
    defer lock.release();

    if (next_pid >= MAX_PROCS) return null;
    const pid = next_pid;

    var p = &procs[pid];
    p.* = .{
        .pid = pid,
        .ppid = ppid,
        .pgid = if (pgid != 0) pgid else pid,
        .sid = pid,
        .state = .embryo,
        .exit_status = 0,
        .cred = .{ .uid = 0, .gid = 0, .euid = 0, .egid = 0 },
        .fds = undefined,
        .fd_count = 0,
        .sig_state = signal_mod.SignalState.init(),
        .name = [_]u8{0} ** 64,
        .name_len = @min(name.len, 64),
        .active = true,
    };
    for (&p.fds) |*fd| fd.active = false;
    @memcpy(p.name[0..p.name_len], name[0..p.name_len]);

    // Standard file descriptors (stdin=0, stdout=1, stderr=2)
    setupStdFds(p);

    proc_active[pid] = true;
    p.state = .runnable;
    next_pid += 1;

    log.debug("Process created: pid={}", .{pid});
    return pid;
}

fn setupStdFds(p: *Process) void {
    // fd 0 – stdin (console device)
    p.fds[0] = .{ .vnode_id = 0, .offset = 0, .flags = FileDescriptor.O_RDONLY, .active = true };
    // fd 1 – stdout
    p.fds[1] = .{ .vnode_id = 1, .offset = 0, .flags = FileDescriptor.O_WRONLY, .active = true };
    // fd 2 – stderr
    p.fds[2] = .{ .vnode_id = 1, .offset = 0, .flags = FileDescriptor.O_WRONLY, .active = true };
    p.fd_count = 3;
}

pub fn lookupProcess(pid: u32) ?*Process {
    if (pid >= MAX_PROCS or !proc_active[pid]) return null;
    return &procs[pid];
}

pub fn exitProcess(pid: u32, status: i32) void {
    lock.acquire();
    defer lock.release();
    if (pid == 0) return; // Cannot exit PID 0
    if (pid >= MAX_PROCS or !proc_active[pid]) return;

    var p = &procs[pid];
    p.exit_status = status;
    p.state = .zombie;

    // Close all file descriptors
    for (&p.fds) |*fd| fd.active = false;
    p.fd_count = 0;

    // Reparent children to PID 0 (init)
    for (0..next_pid) |i| {
        if (proc_active[i] and procs[i].ppid == pid) {
            procs[i].ppid = 0;
        }
    }
}

pub fn waitProcess(ppid: u32) ?struct { pid: u32, status: i32 } {
    lock.acquire();
    defer lock.release();

    for (0..next_pid) |i| {
        if (!proc_active[i]) continue;
        const p = &procs[i];
        if (p.ppid == ppid and p.state == .zombie) {
            const result = .{ .pid = p.pid, .status = p.exit_status };
            p.active = false;
            proc_active[i] = false;
            return result;
        }
    }
    return null;
}
