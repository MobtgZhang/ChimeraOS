/// Darwin/macOS BSD System Call Table (x86_64)
/// Implements syscall dispatch and individual syscall handlers for
/// POSIX / Darwin compatibility.

const log = @import("../../lib/log.zig");
const proc_mod = @import("proc.zig");
const signal_mod = @import("signal.zig");
const vnode_mod = @import("vfs/vnode.zig");
const devfs_mod = @import("vfs/devfs.zig");
const builtin = @import("builtin");
const serial = switch (builtin.cpu.arch) {
    .x86_64 => @import("../arch/x86_64/serial.zig"),
    .aarch64 => @import("../arch/aarch64/serial.zig"),
    .riscv64 => @import("../arch/riscv64/serial.zig"),
    .loongarch64 => @import("../arch/loong64/serial.zig"),
    .mips64el => @import("../arch/mips64el/serial.zig"),
    else => @compileError("Unsupported architecture"),
};

pub const SyscallNumber = enum(u32) {
    sys_exit = 1,
    sys_fork = 2,
    sys_read = 3,
    sys_write = 4,
    sys_open = 5,
    sys_close = 6,
    sys_wait4 = 7,
    sys_link = 9,
    sys_unlink = 10,
    sys_chdir = 12,
    sys_getpid = 20,
    sys_getuid = 24,
    sys_kill = 37,
    sys_getppid = 39,
    sys_dup = 41,
    sys_pipe = 42,
    sys_getgid = 47,
    sys_sigaction = 46,
    sys_sigprocmask = 48,
    sys_ioctl = 54,
    sys_execve = 59,
    sys_munmap = 73,
    sys_mprotect = 74,
    sys_madvise = 75,
    sys_socket = 97,
    sys_connect = 98,
    sys_accept = 30,
    sys_select = 93,
    sys_mmap = 197,
    sys_lseek = 199,
    sys_stat64 = 338,
    _,
};

pub const SyscallResult = union(enum) {
    success: u64,
    err: u32,
};

pub const SyscallArgs = struct {
    arg0: u64 = 0,
    arg1: u64 = 0,
    arg2: u64 = 0,
    arg3: u64 = 0,
    arg4: u64 = 0,
    arg5: u64 = 0,
};

/// POSIX errno constants (Darwin numbering).
pub const EPERM: u32 = 1;
pub const ENOENT: u32 = 2;
pub const ESRCH: u32 = 3;
pub const EINTR: u32 = 4;
pub const EIO: u32 = 5;
pub const EBADF: u32 = 9;
pub const ECHILD: u32 = 10;
pub const ENOMEM: u32 = 12;
pub const EACCES: u32 = 13;
pub const EFAULT: u32 = 14;
pub const EBUSY: u32 = 16;
pub const EEXIST: u32 = 17;
pub const ENOTDIR: u32 = 20;
pub const EISDIR: u32 = 21;
pub const EINVAL: u32 = 22;
pub const ENFILE: u32 = 23;
pub const EMFILE: u32 = 24;
pub const ENOSPC: u32 = 28;
pub const EPIPE: u32 = 32;
pub const ENOSYS: u32 = 78;

var initialized: bool = false;

pub fn init() void {
    initialized = true;
    log.debug("BSD syscall table registered ({} known entries)", .{
        @typeInfo(SyscallNumber).@"enum".fields.len,
    });
}

pub fn dispatch(number: u32, args: SyscallArgs) SyscallResult {
    if (!initialized) return .{ .err = ENOSYS };

    const syscall: SyscallNumber = @enumFromInt(number);

    return switch (syscall) {
        .sys_exit => sysExit(args),
        .sys_read => sysRead(args),
        .sys_write => sysWrite(args),
        .sys_open => sysOpen(args),
        .sys_close => sysClose(args),
        .sys_getpid => sysGetpid(),
        .sys_getppid => sysGetppid(),
        .sys_getuid => sysGetuid(),
        .sys_getgid => sysGetgid(),
        .sys_kill => sysKill(args),
        .sys_dup => sysDup(args),
        .sys_ioctl => sysIoctl(args),
        .sys_wait4 => sysWait4(args),
        .sys_fork => sysFork(),
        _ => {
            log.warn("Unimplemented syscall: {}", .{number});
            return .{ .err = ENOSYS };
        },
    };
}

// ── Syscall Implementations ───────────────────────────────

fn sysExit(args: SyscallArgs) SyscallResult {
    const status: i32 = @intCast(@as(i64, @bitCast(args.arg0)));
    log.info("sys_exit(status={})", .{status});
    proc_mod.exitProcess(0, status); // TODO: use current PID
    return .{ .success = 0 };
}

fn sysRead(args: SyscallArgs) SyscallResult {
    const fd: usize = @intCast(args.arg0);
    const buf: [*]u8 = @ptrFromInt(args.arg1);
    const count: usize = @intCast(args.arg2);

    const p = proc_mod.lookupProcess(0) orelse return .{ .err = ESRCH };
    const fde = p.lookupFd(fd) orelse return .{ .err = EBADF };

    // Route through devfs for device-backed fds
    _ = fde;
    _ = buf;

    log.debug("sys_read(fd={}, count={}) stub", .{ fd, count });
    return .{ .err = ENOSYS };
}

fn sysWrite(args: SyscallArgs) SyscallResult {
    const fd: usize = @intCast(args.arg0);
    const buf: [*]const u8 = @ptrFromInt(args.arg1);
    const count: usize = @intCast(args.arg2);

    if (fd == 1 or fd == 2) {
        serial.writeString(buf[0..count]);
        return .{ .success = count };
    }

    log.debug("sys_write(fd={}, count={}) stub", .{ fd, count });
    return .{ .err = EBADF };
}

fn sysOpen(args: SyscallArgs) SyscallResult {
    _ = args;
    log.debug("sys_open stub", .{});
    return .{ .err = ENOSYS };
}

fn sysClose(args: SyscallArgs) SyscallResult {
    const fd: usize = @intCast(args.arg0);
    const p = proc_mod.lookupProcess(0) orelse return .{ .err = ESRCH };
    if (p.closeFd(fd)) {
        return .{ .success = 0 };
    }
    return .{ .err = EBADF };
}

fn sysGetpid() SyscallResult {
    return .{ .success = 0 }; // kernel task
}

fn sysGetppid() SyscallResult {
    return .{ .success = 0 };
}

fn sysGetuid() SyscallResult {
    const p = proc_mod.lookupProcess(0) orelse return .{ .success = 0 };
    return .{ .success = p.cred.uid };
}

fn sysGetgid() SyscallResult {
    const p = proc_mod.lookupProcess(0) orelse return .{ .success = 0 };
    return .{ .success = p.cred.gid };
}

fn sysKill(args: SyscallArgs) SyscallResult {
    const pid: u32 = @intCast(args.arg0);
    const sig: u8 = @intCast(args.arg1);

    const p = proc_mod.lookupProcess(pid) orelse return .{ .err = ESRCH };
    p.sig_state.postSignal(sig);
    log.debug("sys_kill(pid={}, sig={})", .{ pid, sig });
    return .{ .success = 0 };
}

fn sysDup(args: SyscallArgs) SyscallResult {
    const old_fd: usize = @intCast(args.arg0);
    const p = proc_mod.lookupProcess(0) orelse return .{ .err = ESRCH };
    const src = p.lookupFd(old_fd) orelse return .{ .err = EBADF };
    const new_fd = p.allocFd() orelse return .{ .err = EMFILE };
    p.fds[new_fd] = src.*;
    return .{ .success = new_fd };
}

fn sysIoctl(args: SyscallArgs) SyscallResult {
    _ = args;
    log.debug("sys_ioctl stub", .{});
    return .{ .err = ENOSYS };
}

fn sysWait4(args: SyscallArgs) SyscallResult {
    _ = args;
    if (proc_mod.waitProcess(0)) |w| {
        return .{ .success = w.pid };
    }
    return .{ .err = ECHILD };
}

fn sysFork() SyscallResult {
    log.debug("sys_fork stub", .{});
    return .{ .err = ENOSYS };
}
