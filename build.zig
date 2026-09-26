const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const translate = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
    });
    const translate_mod = translate.createModule();
    translate_mod.linkFramework("Hypervisor", .{});

    main_mod.addImport("c", translate_mod);

    const main_exe = b.addExecutable(.{
        .name = "sdctl",
        .root_module = main_mod,
    });
    b.installArtifact(main_exe);

    const run_main = b.addRunArtifact(main_exe);
    const run_main_step = b.step("run", "Run stardust");
    run_main_step.dependOn(&run_main.step);
}
