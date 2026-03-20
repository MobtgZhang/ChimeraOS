/// POSIX Signal Handling — signal delivery, masking, and action management.
/// Numbers follow Darwin/macOS conventions.

const log = @import("../../lib/log.zig");

pub const NSIG: usize = 32;

pub const Signal = enum(u8) {
    SIGHUP = 1,
    SIGINT = 2,
    SIGQUIT = 3,
    SIGILL = 4,
    SIGTRAP = 5,
    SIGABRT = 6,
    SIGEMT = 7,
    SIGFPE = 8,
    SIGKILL = 9,
    SIGBUS = 10,
    SIGSEGV = 11,
    SIGSYS = 12,
    SIGPIPE = 13,
    SIGALRM = 14,
    SIGTERM = 15,
    SIGURG = 16,
    SIGSTOP = 17,
    SIGTSTP = 18,
    SIGCONT = 19,
    SIGCHLD = 20,
    SIGTTIN = 21,
    SIGTTOU = 22,
    SIGIO = 23,
    SIGXCPU = 24,
    SIGXFSZ = 25,
    SIGVTALRM = 26,
    SIGPROF = 27,
    SIGWINCH = 28,
    SIGINFO = 29,
    SIGUSR1 = 30,
    SIGUSR2 = 31,
    _,
};

pub const SigAction = enum(u8) {
    default,
    ignore,
    handler,
};

pub const SignalDisposition = struct {
    action: SigAction,
    handler: ?*const fn (u8) void,
    flags: u32,

    pub const SA_RESTART: u32 = 0x0002;
    pub const SA_NOCLDSTOP: u32 = 0x0008;
    pub const SA_NODEFER: u32 = 0x0010;
    pub const SA_RESETHAND: u32 = 0x0004;
};

pub const SignalSet = packed struct(u32) {
    bits: u32 = 0,

    pub fn add(self: *SignalSet, sig: u8) void {
        if (sig == 0 or sig >= NSIG) return;
        self.bits |= @as(u32, 1) << @intCast(sig);
    }

    pub fn remove(self: *SignalSet, sig: u8) void {
        if (sig == 0 or sig >= NSIG) return;
        self.bits &= ~(@as(u32, 1) << @intCast(sig));
    }

    pub fn contains(self: SignalSet, sig: u8) bool {
        if (sig == 0 or sig >= NSIG) return false;
        return self.bits & (@as(u32, 1) << @intCast(sig)) != 0;
    }

    pub fn isEmpty(self: SignalSet) bool {
        return self.bits == 0;
    }

    pub fn firstPending(self: SignalSet) ?u8 {
        if (self.bits == 0) return null;
        var i: u8 = 1;
        while (i < NSIG) : (i += 1) {
            if (self.bits & (@as(u32, 1) << @intCast(i)) != 0) return i;
        }
        return null;
    }

    pub fn empty() SignalSet {
        return .{ .bits = 0 };
    }

    pub fn full() SignalSet {
        return .{ .bits = 0xFFFF_FFFE };
    }
};

pub const SignalState = struct {
    actions: [NSIG]SignalDisposition,
    pending: SignalSet,
    blocked: SignalSet,

    pub fn init() SignalState {
        var s: SignalState = undefined;
        for (&s.actions) |*a| {
            a.* = .{ .action = .default, .handler = null, .flags = 0 };
        }
        s.pending = SignalSet.empty();
        s.blocked = SignalSet.empty();
        return s;
    }

    pub fn setAction(self: *SignalState, sig: u8, action: SigAction, handler: ?*const fn (u8) void) bool {
        if (sig == 0 or sig >= NSIG) return false;
        if (sig == @intFromEnum(Signal.SIGKILL) or sig == @intFromEnum(Signal.SIGSTOP))
            return false; // cannot catch or ignore SIGKILL / SIGSTOP
        self.actions[sig] = .{ .action = action, .handler = handler, .flags = 0 };
        return true;
    }

    pub fn postSignal(self: *SignalState, sig: u8) void {
        if (sig == 0 or sig >= NSIG) return;
        self.pending.add(sig);
    }

    /// Return the next deliverable signal (pending & ~blocked).
    pub fn dequeueSignal(self: *SignalState) ?u8 {
        const deliverable = SignalSet{ .bits = self.pending.bits & ~self.blocked.bits };
        const sig = deliverable.firstPending() orelse return null;
        self.pending.remove(sig);
        return sig;
    }

    pub fn deliverPending(self: *SignalState) void {
        while (self.dequeueSignal()) |sig| {
            const disp = self.actions[sig];
            switch (disp.action) {
                .ignore => {},
                .handler => {
                    if (disp.handler) |h| h(sig);
                },
                .default => defaultAction(sig),
            }
        }
    }
};

fn defaultAction(sig: u8) void {
    switch (sig) {
        @intFromEnum(Signal.SIGCHLD),
        @intFromEnum(Signal.SIGURG),
        @intFromEnum(Signal.SIGWINCH),
        @intFromEnum(Signal.SIGINFO),
        => {}, // ignore by default

        @intFromEnum(Signal.SIGSTOP),
        @intFromEnum(Signal.SIGTSTP),
        @intFromEnum(Signal.SIGTTIN),
        @intFromEnum(Signal.SIGTTOU),
        => {
            log.debug("Signal {}: stop (stub)", .{sig});
        },

        @intFromEnum(Signal.SIGCONT) => {
            log.debug("Signal {}: continue (stub)", .{sig});
        },

        else => {
            log.info("Signal {}: terminate (default)", .{sig});
        },
    }
}
