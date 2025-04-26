const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pcre2 = b.dependency("pcre2", .{
        .target = target,
        .optimize = optimize,
    });

    const root_mod = b.addModule("root", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{},
    });
    root_mod.linkLibrary(pcre2.artifact("pcre2-8"));

    const lib = b.addStaticLibrary(.{
        .name = "zpcre2",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);
    lib.linkLibrary(pcre2.artifact("pcre2-8"));

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.linkLibrary(pcre2.artifact("pcre2-8"));

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
