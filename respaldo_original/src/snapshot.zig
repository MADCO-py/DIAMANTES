//! Render sin ventana a alta resolución -> render.ppm (para entregar capturas).
//! Uso: zig build snapshot -- [ancho] [alto] [muestras]
const std = @import("std");
const tex = @import("textures.zig");
const sky = @import("skybox.zig");
const sc = @import("scene.zig");
const R = @import("renderer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    const w: usize = if (args.len > 1) try std.fmt.parseInt(usize, args[1], 10) else 1280;
    const h: usize = if (args.len > 2) try std.fmt.parseInt(usize, args[2], 10) else 720;
    const spp: u32 = if (args.len > 3) try std.fmt.parseInt(u32, args[3], 10) else 64;
    var cam = R.Camera{};
    if (args.len > 4) cam.yaw = try std.fmt.parseFloat(f32, args[4]);
    if (args.len > 5) cam.dist = try std.fmt.parseFloat(f32, args[5]);
    if (args.len > 6) cam.pitch = try std.fmt.parseFloat(f32, args[6]);

    tex.generateAll();
    var scene = sc.build();
    if (args.len > 7 and args[7][0] == 'n') scene.setNight(true);
    sky.generate(scene.sun_dir, scene.night);

    var r = try R.Renderer.init(alloc, &scene, w, h, .{});
    defer r.deinit();

    const t0 = std.time.milliTimestamp();
    for (0..spp) |i| {
        r.renderSample(cam);
        std.debug.print("\rmuestra {d}/{d}", .{ i + 1, spp });
    }
    std.debug.print("\nlisto en {d} ms\n", .{std.time.milliTimestamp() - t0});

    const file = try std.fs.cwd().createFile("render.ppm", .{});
    defer file.close();
    var bw = std.io.bufferedWriter(file.writer());
    const out = bw.writer();
    try out.print("P6\n{d} {d}\n255\n", .{ w, h });
    for (0..w * h) |i| try out.writeAll(r.pixels[i * 4 .. i * 4 + 3]);
    try bw.flush();
}
