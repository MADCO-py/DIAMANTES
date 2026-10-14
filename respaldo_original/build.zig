const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // Por defecto ReleaseFast: un ray tracer en Debug es MUY lento.
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Modo de compilación") orelse .ReleaseFast;

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = .X11,
    });
    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    // Ejecutable principal (ventana interactiva con raylib).
    const exe = b.addExecutable(.{
        .name = "panda_raytracer",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Abrir el diorama").dependOn(&run_cmd.step);

    // Render sin ventana en alta resolución (no usa raylib).
    const snap = b.addExecutable(.{
        .name = "snapshot",
        .root_source_file = b.path("src/snapshot.zig"),
        .target = target,
        .optimize = optimize,
    });
    const snap_cmd = b.addRunArtifact(snap);
    if (b.args) |args| snap_cmd.addArgs(args);
    b.step("snapshot", "Renderizar render.ppm en alta calidad").dependOn(&snap_cmd.step);
}
