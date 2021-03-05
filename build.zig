const std = @import("std");
const zbs = std.build;

const ScanProtocolsStep = @import("zig-wayland/build.zig").ScanProtocolsStep;

pub fn build(b: *zbs.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const scanner = ScanProtocolsStep.create(b);
    scanner.addProtocolPath("wlr-foreign-toplevel-management-unstable-v1.xml");

    const exe = b.addExecutable("ltoplevels", "ltoplevels.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    exe.step.dependOn(&scanner.step);
    exe.addPackage(scanner.getPkg());
    exe.linkLibC();
    exe.linkSystemLibrary("wayland-client");
    scanner.addCSource(exe);

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
