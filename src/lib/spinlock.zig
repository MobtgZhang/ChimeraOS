const builtin = @import("builtin");

pub const SpinLock = struct {
    state: u32 align(4) = 0,

    pub fn acquire(self: *SpinLock) void {
        while (@cmpxchgWeak(u32, &self.state, 0, 1, .acquire, .monotonic) != null) {
            spinHint();
        }
    }

    pub fn release(self: *SpinLock) void {
        @atomicStore(u32, &self.state, 0, .release);
    }

    pub fn tryAcquire(self: *SpinLock) bool {
        return @cmpxchgWeak(u32, &self.state, 0, 1, .acquire, .monotonic) == null;
    }
};

inline fn spinHint() void {
    switch (builtin.cpu.arch) {
        .x86_64 => asm volatile ("pause"),
        .aarch64 => asm volatile ("yield"),
        .riscv64 => asm volatile (""),
        else => asm volatile (""),
    }
}
