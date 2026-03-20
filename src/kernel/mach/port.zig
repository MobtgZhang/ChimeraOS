const SpinLock = @import("../../lib/spinlock.zig").SpinLock;

pub const PortRight = enum(u32) {
    send,
    receive,
    send_once,
    port_set,
    dead_name,
};

pub const MACH_PORT_NULL: u32 = 0;
pub const MAX_PORTS: usize = 256;

pub const Port = struct {
    name: u32,
    right: PortRight,
    ref_count: u32,
    msg_count: u32,
    active: bool,

    pub fn init(name: u32, right: PortRight) Port {
        return .{
            .name = name,
            .right = right,
            .ref_count = 1,
            .msg_count = 0,
            .active = true,
        };
    }

    pub fn retain(self: *Port) void {
        self.ref_count += 1;
    }

    pub fn release(self: *Port) bool {
        if (self.ref_count > 0) {
            self.ref_count -= 1;
        }
        return self.ref_count == 0;
    }
};

pub const PortNamespace = struct {
    ports: [MAX_PORTS]?Port,
    next_name: u32,
    lock: SpinLock,

    pub fn init() PortNamespace {
        return .{
            .ports = [_]?Port{null} ** MAX_PORTS,
            .next_name = 1,
            .lock = .{},
        };
    }

    pub fn allocatePort(self: *PortNamespace, right: PortRight) ?u32 {
        self.lock.acquire();
        defer self.lock.release();

        const name = self.next_name;
        if (name >= MAX_PORTS) return null;

        self.ports[name] = Port.init(name, right);
        self.next_name += 1;
        return name;
    }

    pub fn lookupPort(self: *PortNamespace, name: u32) ?*Port {
        if (name >= MAX_PORTS) return null;
        if (self.ports[name]) |*port| {
            if (port.active) return port;
        }
        return null;
    }

    pub fn deallocatePort(self: *PortNamespace, name: u32) bool {
        self.lock.acquire();
        defer self.lock.release();

        if (name >= MAX_PORTS) return false;
        if (self.ports[name]) |*port| {
            port.active = false;
            return true;
        }
        return false;
    }
};
