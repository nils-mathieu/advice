const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // ADVICE OBJECT
    //

    const advice_obj = b.addObject(.{
        .name = "advice",
        .root_source_file = b.path("src/root.zig"),
        .optimize = optimize,
        .target = target,
    });
    advice_obj.root_module.addImport("advice", advice_obj.root_module);
    b.modules.put("advice", advice_obj.root_module) catch @panic("OOM");

    switch (target.result.os.tag) {
        .macos, .ios => {
            advice_obj.linkFramework("CoreAudio");
            advice_obj.linkFramework("CoreFoundation");
            advice_obj.linkFramework("AudioToolbox");
        },
        .windows => {
            advice_obj.root_module.addImport("win32", b.lazyDependency("win32", .{}).?.module("zigwin32"));
        },
        else => {},
    }

    //
    // EXAMPLES
    //

    const examples = [_][]const u8{
        "simple-sinewave",
        "enumerate-devices",
    };

    for (examples) |example| {
        const example_exe = b.addExecutable(.{
            .name = example,
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example})),
            .target = target,
            .optimize = optimize,
        });
        example_exe.root_module.addImport("advice", advice_obj.root_module);

        b.installArtifact(example_exe);

        const run_example = b.step(
            b.fmt("example-{s}", .{example}),
            b.fmt("Run the `{s}` example", .{example}),
        );
        run_example.dependOn(&b.addRunArtifact(example_exe).step);
    }

    //
    // CHECK STEP
    //

    const check_step = b.step("check", "Ensures that the examples properly compile");

    for (examples) |example| {
        const example_exe = b.addExecutable(.{
            .name = example,
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example})),
            .target = target,
            .optimize = optimize,
        });
        example_exe.root_module.addImport("advice", advice_obj.root_module);

        check_step.dependOn(&example_exe.step);
    }

    //
    // DOCUMENTATION STEP
    //

    const install_doc = b.addInstallDirectory(.{
        .install_dir = .prefix,
        .install_subdir = "docs",
        .source_dir = advice_obj.getEmittedDocs(),
    });

    const doc_step = b.step("docs", "Generate documentation");
    doc_step.dependOn(&install_doc.step);
}
