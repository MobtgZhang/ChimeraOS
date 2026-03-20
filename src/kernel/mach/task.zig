const std = @import("std");
const port_mod = @import("port.zig");
const log = @import("../../lib/log.zig");

pub const TaskState = enum {
    created,
    running,
    suspended,
    terminated,
};

pub const MAX_TASKS = 64;

pub const Task = struct {
    pid: u32,
    name: [64]u8,
    name_len: usize,
    state: TaskState,
    port_namespace: port_mod.PortNamespace,
    task_port: u32,
    parent_pid: u32,
    priority: u8,

    pub fn init(pid: u32, name: []const u8) Task {
        var task = Task{
            .pid = pid,
            .name = [_]u8{0} ** 64,
            .name_len = @min(name.len, 64),
            .state = .created,
            .port_namespace = port_mod.PortNamespace.init(),
            .task_port = port_mod.MACH_PORT_NULL,
            .parent_pid = 0,
            .priority = 31,
        };
        @memcpy(task.name[0..task.name_len], name[0..task.name_len]);
        return task;
    }

    pub fn getName(self: *const Task) []const u8 {
        return self.name[0..self.name_len];
    }
};

var tasks: [MAX_TASKS]?Task = [_]?Task{null} ** MAX_TASKS;
var next_pid: u32 = 0;

pub fn initKernelTask() void {
    tasks[0] = Task.init(0, "kernel_task");
    tasks[0].?.state = .running;

    if (tasks[0].?.port_namespace.allocatePort(.receive)) |tp| {
        tasks[0].?.task_port = tp;
    }

    next_pid = 1;
    log.debug("kernel_task created with PID 0, task_port={}", .{tasks[0].?.task_port});
}

pub fn createTask(name: []const u8, parent: u32) ?u32 {
    if (next_pid >= MAX_TASKS) return null;

    const pid = next_pid;
    tasks[pid] = Task.init(pid, name);
    tasks[pid].?.parent_pid = parent;

    if (tasks[pid].?.port_namespace.allocatePort(.receive)) |tp| {
        tasks[pid].?.task_port = tp;
    }

    next_pid += 1;
    return pid;
}

pub fn lookupTask(pid: u32) ?*Task {
    if (pid >= MAX_TASKS) return null;
    if (tasks[pid]) |*task| return task;
    return null;
}

pub fn terminateTask(pid: u32) bool {
    if (pid == 0) return false; // Cannot terminate kernel_task
    if (pid >= MAX_TASKS) return false;
    if (tasks[pid]) |*task| {
        task.state = .terminated;
        return true;
    }
    return false;
}
