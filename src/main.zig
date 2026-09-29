const std = @import("std");
const c = @import("c");

const program = [_]u8{
    0xba, 0xf8, 0x03, // mov $0x3f8, %dx
    0x00, 0xd8, // add %bl, %al
    0x04, '0', // add $'0', %al
    0xee, // out %al, (%dx)
    0xb0, '\n', // mov $'\n', %al
    0xee, // out %al, (%dx)
    0x90,
    0x90,
    0x90,
    0x90,
    0x90,
    0x90,
    0x90,
    0x90,
    0x90,
    0x90,
    0x90,
    0x90,
    0x90,
    0x90,
    0x90, 0xf4, // hlt
};

const static_values = [_]struct { u32, u64 }{
    .{ c.VMCS_CTRL_EXC_BITMAP, 0xffffffff },
    .{ c.VMCS_CTRL_CR0_MASK, 0x60000000 },
    .{ c.VMCS_CTRL_CR0_SHADOW, 0 },
    .{ c.VMCS_CTRL_CR4_MASK, 0 },
    .{ c.VMCS_CTRL_CR4_SHADOW, 0 },
    .{ c.VMCS_GUEST_ES, 0 },
    .{ c.VMCS_GUEST_CS, 0 },
    .{ c.VMCS_GUEST_SS, 0 },
    .{ c.VMCS_GUEST_DS, 0 },
    .{ c.VMCS_GUEST_FS, 0 },
    .{ c.VMCS_GUEST_GS, 0 },
    .{ c.VMCS_GUEST_LDTR, 0 },
    .{ c.VMCS_GUEST_TR, 0 },
    .{ c.VMCS_GUEST_ES_LIMIT, 0xffff },
    .{ c.VMCS_GUEST_CS_LIMIT, 0xffff },
    .{ c.VMCS_GUEST_SS_LIMIT, 0xffff },
    .{ c.VMCS_GUEST_DS_LIMIT, 0xffff },
    .{ c.VMCS_GUEST_FS_LIMIT, 0xffff },
    .{ c.VMCS_GUEST_GS_LIMIT, 0xffff },
    .{ c.VMCS_GUEST_LDTR_LIMIT, 0 },
    .{ c.VMCS_GUEST_TR_LIMIT, 0 },
    .{ c.VMCS_GUEST_GDTR_LIMIT, 0 },
    .{ c.VMCS_GUEST_IDTR_LIMIT, 0 },
    .{ c.VMCS_GUEST_ES_AR, 0x93 },
    .{ c.VMCS_GUEST_CS_AR, 0x9b },
    .{ c.VMCS_GUEST_SS_AR, 0x93 },
    .{ c.VMCS_GUEST_DS_AR, 0x93 },
    .{ c.VMCS_GUEST_FS_AR, 0x93 },
    .{ c.VMCS_GUEST_GS_AR, 0x93 },
    .{ c.VMCS_GUEST_LDTR_AR, 0x10000 },
    .{ c.VMCS_GUEST_TR_AR, 0x83 },
    .{ c.VMCS_GUEST_ES_BASE, 0 },
    .{ c.VMCS_GUEST_CS_BASE, 0 },
    .{ c.VMCS_GUEST_SS_BASE, 0 },
    .{ c.VMCS_GUEST_DS_BASE, 0 },
    .{ c.VMCS_GUEST_FS_BASE, 0 },
    .{ c.VMCS_GUEST_GS_BASE, 0 },
    .{ c.VMCS_GUEST_LDTR_BASE, 0 },
    .{ c.VMCS_GUEST_TR_BASE, 0 },
    .{ c.VMCS_GUEST_GDTR_BASE, 0 },
    .{ c.VMCS_GUEST_IDTR_BASE, 0 },
    .{ c.VMCS_GUEST_CR0, 0x20 },
    .{ c.VMCS_GUEST_CR3, 0x0 },
    .{ c.VMCS_GUEST_CR4, 0x2000 },
};

const Control = packed struct(u64) {
    _a: u7 = 0,
    HLT: bool = false,
    _b: u11 = 0,
    CR8_LOAD: bool = false,
    CR8_STORE: bool = false,
    _c: u43 = 0,
};

fn wvcms(vcpu: u32, field: u32, value: u64) !void {
    try raise(
        c.hv_vmx_vcpu_write_vmcs(vcpu, field, value),
    );
}

fn rvcms(vcpu: u32, field: u32) !u64 {
    var target: u64 = undefined;

    try raise(c.hv_vmx_vcpu_read_vmcs(vcpu, field, &target));

    return target;
}

fn readRegister(vcpu: u32, reg: u32) !u64 {
    var target: u64 = undefined;

    try raise(c.hv_vcpu_read_register(vcpu, reg, &target));

    return target;
}

fn readCapability(cap: c_uint) !u64 {
    var target: u64 = undefined;

    try raise(c.hv_vmx_read_capability(cap, &target));

    return target;
}

fn capToCtrl(cap: u64, ctrl: union(enum) { num: u64, ctrl: Control }) u64 {
    const v: u64 = switch (ctrl) {
        .num => |vv| vv,
        .ctrl => |vv| @backingInt(vv),
    };
    return (v | (cap & 0xffffffff) & (cap >> 32));
}

const MemFlag = packed struct(c_int) {
    READ: bool,
    WRITE: bool,
    EXEC: bool,
};

pub fn main(init: std.process.Init) !void {
    _ = init;

    std.debug.print("Creating VM\n", .{});
    try raise(
        c.hv_vm_create(c.HV_VM_DEFAULT),
    );
    defer log(
        c.hv_vm_destroy(),
    );

    const cap_pinbased: u64 = try readCapability(c.HV_VMX_CAP_PINBASED);
    const cap_procbased: u64 = try readCapability(c.HV_VMX_CAP_PROCBASED);
    const cap_procbased2: u64 = try readCapability(c.HV_VMX_CAP_PROCBASED2);
    const cap_entry: u64 = try readCapability(c.HV_VMX_CAP_ENTRY);

    const mem_size: u64 = 1 * 1024 * 1024;
    const mem_start: u64 = 0;

    std.debug.print("Allocating memory\n", .{});
    const vm_mem: *anyopaque = std.c.mmap(
        null,
        mem_size,
        .{ .WRITE = true, .READ = true },
        .{ .ANONYMOUS = true, .NORESERVE = true, .TYPE = .PRIVATE },
        -1,
        0,
    );
    if (vm_mem == std.c.MAP_FAILED) {
        std.debug.print("Error mapping memory\n", .{});
        std.process.exit(1);
    }
    defer log(
        std.c.munmap(@ptrCast(@alignCast(vm_mem)), mem_size),
    );
    @memcpy(@as([*]u8, @ptrCast(vm_mem))[256 .. 256 + program.len], &program);

    std.debug.print("Mapping memory\n", .{});
    try raise(
        c.hv_vm_map(
            @ptrCast(vm_mem),
            mem_start,
            mem_size,
            c.HV_MEMORY_READ | c.HV_MEMORY_WRITE | c.HV_MEMORY_EXEC,
        ),
    );
    defer log(
        c.hv_vm_unmap(mem_start, mem_size),
    );

    var vcpu: u32 = undefined;
    std.debug.print("Creating vCPU\n", .{});
    try raise(
        c.hv_vcpu_create(&vcpu, c.HV_VCPU_DEFAULT),
    );
    defer log(
        c.hv_vcpu_destroy(vcpu),
    );

    try wvcms(vcpu, c.VMCS_CTRL_PIN_BASED, capToCtrl(cap_pinbased, .{ .num = 0 }));
    try wvcms(
        vcpu,
        c.VMCS_CTRL_CPU_BASED,
        capToCtrl(cap_procbased, .{ .ctrl = .{ .HLT = true, .CR8_LOAD = true, .CR8_STORE = true } }),
    );
    try wvcms(vcpu, c.VMCS_CTRL_CPU_BASED2, capToCtrl(cap_procbased2, .{ .num = 0 }));
    try wvcms(vcpu, c.VMCS_CTRL_VMENTRY_CONTROLS, capToCtrl(cap_entry, .{ .num = 0 }));

    for (static_values) |values| {
        const field, const value = values;
        try wvcms(vcpu, field, value);
    }

    try raise(c.hv_vcpu_write_register(vcpu, c.HV_X86_RIP, 0x100));
    try raise(c.hv_vcpu_write_register(vcpu, c.HV_X86_RFLAGS, 0x2));
    try raise(c.hv_vcpu_write_register(vcpu, c.HV_X86_RSP, 0x0));
    try raise(c.hv_vcpu_write_register(vcpu, c.HV_X86_RAX, 0x5));
    try raise(c.hv_vcpu_write_register(vcpu, c.HV_X86_RBX, 0x3));

    var chars: u32 = 0;
    wl: while (true) {
        try raise(c.hv_vcpu_run(vcpu));

        const exit_reason = try rvcms(vcpu, c.VMCS_RO_EXIT_REASON);
        std.debug.print("Exit reason: {}\n", .{exit_reason});

        const rip = try readRegister(vcpu, c.HV_X86_RIP);
        std.debug.print("RIP at: {}\n", .{rip});

        switch (exit_reason) {
            c.VMX_REASON_HLT => {
                std.debug.print("HLT\n", .{});
                break :wl;
            },
            c.VMX_REASON_IRQ => {
                std.debug.print("IRQ\n", .{});
            },
            c.VMX_REASON_EPT_VIOLATION => {
                std.debug.print("EPT VIOLATION, ignore\n", .{});
            },
            c.VMX_REASON_IO => {
                std.debug.print("IO\n", .{});

                if (chars > 2) {
                    std.debug.print("Serial port shouldn't return more than two characters", .{});
                }

                const qual = try rvcms(vcpu, c.VMCS_RO_EXIT_QUALIFIC);
                if ((qual >> 16) & 0xFFFF == 0x3F8) {
                    const rax = try readRegister(vcpu, c.HV_X86_RAX);
                    std.debug.print("RAX = {d}\n", .{rax});
                    const slice: []const u8 = &[_]u8{@as(u8, @intCast(rax))};
                    std.debug.print("got char: {f}, ", .{std.zig.fmtString(slice)});

                    if (chars == 0) {
                        std.debug.print("should be: '8'", .{});
                    }
                    if (chars == 1) {
                        std.debug.print("should be: '\\n'", .{});
                    }
                    std.debug.print("\n", .{});
                    chars += 1;

                    const instr_len = try rvcms(vcpu, c.VMCS_RO_VMEXIT_INSTR_LEN);
                    try raise(c.hv_vcpu_write_register(vcpu, c.HV_X86_RIP, rip + instr_len));
                } else {
                    std.debug.print("Unrecognised IO port, exit", .{});
                }
            },
            else => |er| {
                std.debug.print("Unexpected exit reason: {d}", .{er});
            },
        }
    }
}

fn raise(code: c_int) !void {
    if (code != c.HV_SUCCESS) {
        log(code);
        return error.HVError;
    }
}

fn log(code: c_int) void {
    if (code != c.HV_SUCCESS) {
        std.debug.print("Error occured: {d}", .{code});
    }
}
