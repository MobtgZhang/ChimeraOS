pub const SpinLock = struct {
    state: u32 align(4) = 0,

    pub fn acquire(self: *SpinLock) void {
        while (@cmpxchgWeak(u32, &self.state, 0, 1, .acquire, .monotonic) != null) {
            asm volatile ("pause");
        }
    }

    pub fn release(self: *SpinLock) void {
        @atomicStore(u32, &self.state, 0, .release);
    }

    pub fn tryAcquire(self: *SpinLock) bool {
        return @cmpxchgWeak(u32, &self.state, 0, 1, .acquire, .monotonic) == null;
    }
};
