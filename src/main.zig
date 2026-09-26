const std = @import("std");
const c = @import("c");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var vCPUMax: u64 = undefined;
    _ = c.hv_capability(c.HV_CAP_VCPUMAX, &vCPUMax);

    var addrSpaceMax: u64 = undefined;
    _ = c.hv_capability(c.HV_CAP_ADDRSPACEMAX, &addrSpaceMax);

    var stdout_buffer: [512]u8 = undefined;
    const stdout_file = std.Io.File.stdout();
    var stdout_writer = stdout_file.writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Max vCPUs: {d}\nAvailable address spaces: {d}\n", .{ vCPUMax, addrSpaceMax });
    try stdout.flush();
}
