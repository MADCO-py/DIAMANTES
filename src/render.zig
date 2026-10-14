//! Cámara orbital y render concurrente.
//!
//! Cada frame se lanza un rayo por píxel, repartiendo las filas de la imagen
//! entre varios hilos. Mientras la cámara está quieta los frames se promedian
//! (acumulación), así desaparece el ruido del color bleeding y de los bordes.
const std = @import("std");
const m = @import("math.zig");
const tracer = @import("tracer.zig");
const Vec3 = m.Vec3;

pub const W = 480; // resolución interna del ray tracing
pub const H = 270;

/// Cámara que gira alrededor del panda.
pub const Camera = struct {
    target: Vec3 = Vec3.init(0, 0.8, -0.2), // el panda
    yaw: f32 = std.math.pi + 0.65, // rotación alrededor del diorama
    pitch: f32 = 0.42, // inclinación
    dist: f32 = 9, // zoom: distancia al panda

    pub fn eye(c: Camera) Vec3 {
        const dir = Vec3.init(@cos(c.pitch) * @sin(c.yaw), @sin(c.pitch), @cos(c.pitch) * @cos(c.yaw));
        return c.target.add(dir.scale(c.dist));
    }
};

var accum: [W * H]Vec3 = undefined; // suma de todos los frames
pub var pixels: [W * H * 4]u8 = undefined; // imagen final RGBA para raylib
pub var samples: u32 = 0;

var next_row = std.atomic.Value(u32).init(0);
var eye: Vec3 = undefined;
var fwd: Vec3 = undefined;
var right: Vec3 = undefined;
var up: Vec3 = undefined;

/// Descarta lo acumulado (se llama cuando la cámara se mueve).
pub fn reset() void {
    @memset(&accum, Vec3.zero);
    samples = 0;
}

/// Agrega un frame usando todos los núcleos del procesador.
pub fn renderFrame(cam: Camera) void {
    // Ejes de la cámara: hacia adelante, derecha y arriba (fov de 50°).
    eye = cam.eye();
    fwd = cam.target.sub(eye).normalize();
    const tan_half = @tan(std.math.degreesToRadians(25.0));
    right = fwd.cross(Vec3.init(0, 1, 0)).normalize().scale(tan_half * @as(f32, W) / H);
    up = right.cross(fwd).normalize().scale(tan_half);

    samples += 1;
    next_row.store(0, .monotonic);

    // CONCURRENCIA: cada hilo toma la siguiente fila libre con un contador
    // atómico hasta que no quedan filas.
    var threads: [64]std.Thread = undefined;
    const n = @min(std.Thread.getCpuCount() catch 4, threads.len);
    for (0..n) |i| threads[i] = std.Thread.spawn(.{}, worker, .{}) catch unreachable;
    for (threads[0..n]) |t| t.join();
}

fn worker() void {
    while (true) {
        const y = next_row.fetchAdd(1, .monotonic);
        if (y >= H) return;
        var rng = m.Rng{ .state = y *% 9781 +% samples *% 6271 +% 1 };
        for (0..W) |x| {
            // Punto al azar dentro del píxel -> antialiasing al promediar.
            const px = (@as(f32, @floatFromInt(x)) + rng.next()) / W * 2 - 1;
            const py = 1 - (@as(f32, @floatFromInt(y)) + rng.next()) / H * 2;
            const dir = fwd.add(right.scale(px)).add(up.scale(py)).normalize();
            const c = tracer.trace(eye, dir, 0, null, &rng);

            const i = y * W + x;
            if (!std.math.isNan(c.x + c.y + c.z)) accum[i] = accum[i].add(c);
            const avg = accum[i].scale(1 / @as(f32, @floatFromInt(samples)));
            pixels[i * 4 + 0] = toByte(avg.x);
            pixels[i * 4 + 1] = toByte(avg.y);
            pixels[i * 4 + 2] = toByte(avg.z);
            pixels[i * 4 + 3] = 255;
        }
    }
}

/// Luz (puede ser > 1) -> byte 0..255: tone mapping ACES y corrección gamma.
fn toByte(x: f32) u8 {
    const a = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
    return @intFromFloat(std.math.pow(f32, std.math.clamp(a, 0, 1), 1.0 / 2.2) * 255);
}
