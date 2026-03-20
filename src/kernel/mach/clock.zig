/// Mach Clock Service — monotonic time-keeping using x86_64 TSC and PIT.
/// Provides nanosecond-resolution timestamps and alarm scheduling.

const log = @import("../../lib/log.zig");
const SpinLock = @import("../../lib/spinlock.zig").SpinLock;

pub const NANOS_PER_SEC: u64 = 1_000_000_000;
pub const NANOS_PER_MS: u64 = 1_000_000;
pub const NANOS_PER_US: u64 = 1_000;

// ── PIT (Programmable Interval Timer) ─────────────────────

const PIT_FREQ: u32 = 1_193_182;
const PIT_CH0_DATA: u16 = 0x40;
const PIT_CMD: u16 = 0x43;

var pit_ticks: u64 = 0;
var pit_hz: u32 = 0;

pub fn initPIT(hz: u32) void {
    pit_hz = hz;
    const divisor: u16 = @intCast(PIT_FREQ / hz);

    outb(PIT_CMD, 0x36); // Channel 0, lobyte/hibyte, rate generator
    outb(PIT_CH0_DATA, @truncate(divisor));
    outb(PIT_CH0_DATA, @truncate(divisor >> 8));

    log.info("PIT initialized at {} Hz (divisor={})", .{ hz, divisor });
}

pub fn pitIrqHandler() void {
    pit_ticks += 1;
}

pub fn pitUptime() u64 {
    if (pit_hz == 0) return 0;
    return pit_ticks * NANOS_PER_SEC / pit_hz;
}

// ── TSC (Time Stamp Counter) ──────────────────────────────

var tsc_freq: u64 = 0;
var tsc_base: u64 = 0;

pub fn readTSC() u64 {
    var lo: u32 = undefined;
    var hi: u32 = undefined;
    asm volatile ("rdtsc"
        : [lo] "={eax}" (lo),
          [hi] "={edx}" (hi),
    );
    return @as(u64, hi) << 32 | lo;
}

/// Calibrate TSC against the PIT.
/// Call after PIT is initialised. Waits ~50 ms of PIT ticks.
pub fn calibrateTSC() void {
    if (pit_hz == 0) {
        log.warn("Cannot calibrate TSC: PIT not initialized", .{});
        return;
    }

    const wait_ticks: u64 = pit_hz / 20; // ~50 ms
    const start_pit = pit_ticks;
    const start_tsc = readTSC();

    while (pit_ticks - start_pit < wait_ticks) {
        asm volatile ("pause");
    }

    const elapsed_tsc = readTSC() - start_tsc;
    const elapsed_ns = (pit_ticks - start_pit) * NANOS_PER_SEC / pit_hz;

    if (elapsed_ns > 0) {
        tsc_freq = elapsed_tsc * NANOS_PER_SEC / elapsed_ns;
    }
    tsc_base = readTSC();

    log.info("TSC frequency: {} MHz", .{tsc_freq / 1_000_000});
}

/// Return nanoseconds since TSC calibration.
pub fn tscNanos() u64 {
    if (tsc_freq == 0) return pitUptime();
    const delta = readTSC() - tsc_base;
    return delta * NANOS_PER_SEC / tsc_freq;
}

// ── High-level clock API ──────────────────────────────────

pub const TimeSpec = struct {
    seconds: u64,
    nanoseconds: u32,
};

pub fn getTime() TimeSpec {
    const ns = tscNanos();
    return .{
        .seconds = ns / NANOS_PER_SEC,
        .nanoseconds = @intCast(ns % NANOS_PER_SEC),
    };
}

pub fn uptimeNanos() u64 {
    return tscNanos();
}

pub fn uptimeMs() u64 {
    return tscNanos() / NANOS_PER_MS;
}

// ── Alarm queue (simple sorted list) ──────────────────────

pub const MAX_ALARMS: usize = 64;

pub const Alarm = struct {
    deadline_ns: u64,
    callback: ?*const fn () void,
    active: bool,
};

var alarms: [MAX_ALARMS]Alarm = [_]Alarm{.{ .deadline_ns = 0, .callback = null, .active = false }} ** MAX_ALARMS;
var alarm_lock: SpinLock = .{};

pub fn setAlarm(deadline_ns: u64, callback: *const fn () void) bool {
    alarm_lock.acquire();
    defer alarm_lock.release();
    for (&alarms) |*a| {
        if (!a.active) {
            a.* = .{ .deadline_ns = deadline_ns, .callback = callback, .active = true };
            return true;
        }
    }
    return false;
}

pub fn processAlarms() void {
    const now = uptimeNanos();
    alarm_lock.acquire();
    defer alarm_lock.release();
    for (&alarms) |*a| {
        if (a.active and now >= a.deadline_ns) {
            if (a.callback) |cb| cb();
            a.active = false;
        }
    }
}

// ── Port I/O helpers ──────────────────────────────────────

fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
    );
}
