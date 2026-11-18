const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("cli", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    b.default_step.dependOn(&run_mod_tests.step);

    const exe = b.addExecutable(.{
        .name = "simple",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example/simple.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cli", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);
    const run_step = b.step("run-example", "run the simple example");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    b.default_step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    const fmt_check_step = b.step("fmt-check", "check project code formatting");
    const fmt_check = b.addFmt(.{ .check = true, .paths = &.{b.path(".")}, .exclude_paths = &.{b.path("zig-pkg/")} });
    fmt_check_step.dependOn(&fmt_check.step);
    b.default_step.dependOn(&fmt_check.step);
}
