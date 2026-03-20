const port_mod = @import("port.zig");

pub const MACH_MSG_SUCCESS: u32 = 0;
pub const MACH_SEND_INVALID_DEST: u32 = 0x10000002;
pub const MACH_SEND_INVALID_RIGHT: u32 = 0x10000007;
pub const MACH_RCV_INVALID_NAME: u32 = 0x10004002;

pub const MSG_MAX_BODY = 256;

pub const MsgBits = packed struct(u32) {
    remote_bits: u8 = 0,
    local_bits: u8 = 0,
    voucher_bits: u8 = 0,
    other: u8 = 0,
};

pub const MsgHeader = struct {
    bits: MsgBits,
    size: u32,
    remote_port: u32,
    local_port: u32,
    voucher_port: u32,
    id: u32,
};

pub const Message = struct {
    header: MsgHeader,
    body: [MSG_MAX_BODY]u8,
    body_len: usize,

    pub fn init(remote: u32, local: u32, id: u32) Message {
        return .{
            .header = .{
                .bits = .{},
                .size = @sizeOf(MsgHeader),
                .remote_port = remote,
                .local_port = local,
                .voucher_port = port_mod.MACH_PORT_NULL,
                .id = id,
            },
            .body = [_]u8{0} ** MSG_MAX_BODY,
            .body_len = 0,
        };
    }

    pub fn setBody(self: *Message, data: []const u8) void {
        const len = @min(data.len, MSG_MAX_BODY);
        @memcpy(self.body[0..len], data[0..len]);
        self.body_len = len;
        self.header.size = @intCast(@sizeOf(MsgHeader) + len);
    }

    pub fn getBody(self: *const Message) []const u8 {
        return self.body[0..self.body_len];
    }
};

/// Mach message queue (ring buffer)
pub const MessageQueue = struct {
    const CAPACITY = 64;

    buffer: [CAPACITY]Message = undefined,
    head: usize = 0,
    tail: usize = 0,
    count: usize = 0,

    pub fn enqueue(self: *MessageQueue, msg: Message) bool {
        if (self.count >= CAPACITY) return false;
        self.buffer[self.tail] = msg;
        self.tail = (self.tail + 1) % CAPACITY;
        self.count += 1;
        return true;
    }

    pub fn dequeue(self: *MessageQueue) ?Message {
        if (self.count == 0) return null;
        const msg = self.buffer[self.head];
        self.head = (self.head + 1) % CAPACITY;
        self.count -= 1;
        return msg;
    }

    pub fn isEmpty(self: *const MessageQueue) bool {
        return self.count == 0;
    }
};
