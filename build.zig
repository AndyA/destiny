const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const destiny = b.addExecutable(.{
        .name = "destiny",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    const cli = b.dependency("cli", .{});
    destiny.root_module.addImport("cli", cli.module("cli"));

    b.installArtifact(destiny);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(destiny);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

    const mule = b.addExecutable(.{
        .name = "mule",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mule.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });
    b.installArtifact(mule);

    const mule_step = b.step("mule", "Run the mule");
    const mule_cmd = b.addRunArtifact(mule);
    mule_step.dependOn(&mule_cmd.step);

    mule_cmd.step.dependOn(b.getInstallStep());

    mule_cmd.addPassthruArgs();

    const destiny_tests = b.addTest(.{
        .root_module = destiny.root_module,
    });

    const run_destiny_tests = b.addRunArtifact(destiny_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_destiny_tests.step);
}
