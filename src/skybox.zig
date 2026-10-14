//! Skybox con cubemap: un cubo gigante de 6 imágenes que rodea la escena.
//! Las 6 caras se pintan al iniciar y después, cuando un rayo no choca con nada,
//! se mira qué cara del cubo atraviesa y qué píxel de esa cara le toca.
const std = @import("std");
const m = @import("math.zig");
const Vec3 = m.Vec3;

const RES = 128; // cada cara es de 128x128
var faces: [6][RES * RES]Vec3 = undefined;

const sun_dir = Vec3.init(0.55, 0.75, 0.45).normalize(); // igual que la luz del sol

/// Cara 0..5 = +X, -X, +Y, -Y, +Z, -Z. Para la cara del eje `a`, las otras dos
/// coordenadas de la dirección (divididas por la del eje) dan el píxel.
fn otherAxes(a: usize) [2]usize {
    return .{ (a + 1) % 3, (a + 2) % 3 };
}

pub fn generate() void {
    for (0..6) |f| {
        const a = f / 2;
        const sign: f32 = if (f % 2 == 0) 1 else -1;
        const o = otherAxes(a);
        for (0..RES) |y| {
            for (0..RES) |x| {
                // Píxel -> dirección en el mundo.
                var d = Vec3.zero;
                d.set(a, sign);
                d.set(o[0], (@as(f32, @floatFromInt(x)) + 0.5) / RES * 2 - 1);
                d.set(o[1], (@as(f32, @floatFromInt(y)) + 0.5) / RES * 2 - 1);
                faces[f][y * RES + x] = paint(d.normalize());
            }
        }
    }
}

/// Dirección -> cara y píxel (lo inverso de `generate`).
pub fn sample(d: Vec3) Vec3 {
    var a: usize = 0;
    if (@abs(d.y) > @abs(d.get(a))) a = 1;
    if (@abs(d.z) > @abs(d.get(a))) a = 2;
    const f = a * 2 + @as(usize, if (d.get(a) > 0) 0 else 1);
    const o = otherAxes(a);
    const big = @abs(d.get(a));
    const x: usize = @intFromFloat(std.math.clamp((d.get(o[0]) / big + 1) / 2 * RES, 0, RES - 1));
    const y: usize = @intFromFloat(std.math.clamp((d.get(o[1]) / big + 1) / 2 * RES, 0, RES - 1));
    return faces[f][y * RES + x];
}

/// Lo que se pinta en el cielo para una dirección: degradado, nubes y sol.
fn paint(d: Vec3) Vec3 {
    const top = m.srgb(0.36, 0.56, 0.98);
    const horizon = m.srgb(0.76, 0.86, 1.0);
    const ground = m.srgb(0.22, 0.3, 0.48);
    var c = if (d.y > 0) horizon.lerp(top, @sqrt(d.y)) else horizon.lerp(ground, @min(1, -d.y * 3));

    // Nubes cuadradas: se proyecta la dirección sobre un plano alto y se
    // decide al azar qué celdas de ese plano tienen nube.
    if (d.y > 0.05) {
        const cx: i32 = @intFromFloat(@floor(d.x / d.y * 2));
        const cz: i32 = @intFromFloat(@floor(d.z / d.y * 2));
        if (m.hash(cx, cz, 2024) > 0.72) c = c.lerp(Vec3.one, 0.85);
    }

    // Sol: brilla más que 1 para que se note en los reflejos.
    if (d.dot(sun_dir) > 0.995) c = Vec3.init(9, 8.4, 6.5);
    return c;
}
