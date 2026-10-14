//! Texturas procedurales 16x16 estilo Minecraft (pixel art generado por código).
//! No se cargan archivos: cada textura se "pinta" con ruido determinista.
const std = @import("std");
const m = @import("math.zig");
const Vec3 = m.Vec3;
const rgb = m.rgb;

pub const SIZE = 16;

pub const TexId = enum(u8) {
    grass_top,
    grass_side,
    dirt,
    fur_white,
    fur_black,
    panda_face,
    panda_snout,
    glass,
    emerald,
    alabaster,
    glowstone,
    iron,
    water,
    bamboo,
    bamboo_top,
};

pub const TEX_COUNT = @typeInfo(TexId).@"enum".fields.len;

pub const Texel = struct {
    color: Vec3, // lineal
    alpha: f32, // 1 = usa la transparencia del material, 0 = píxel opaco (marco del vidrio)
};

pub const Texture = struct {
    px: [SIZE * SIZE]Texel,

    /// Muestreo "nearest" para que se vean los pixeles (look Minecraft).
    pub inline fn sample(self: *const Texture, u: f32, v: f32) Texel {
        const fu = u - @floor(u);
        const fv = v - @floor(v);
        const x: usize = @min(SIZE - 1, @as(usize, @intFromFloat(fu * SIZE)));
        const y: usize = @min(SIZE - 1, @as(usize, @intFromFloat(fv * SIZE)));
        return self.px[y * SIZE + x];
    }
};

pub var all: [TEX_COUNT]Texture = undefined;

pub inline fn get(id: TexId) *const Texture {
    return &all[@intFromEnum(id)];
}

fn put(t: *Texture, x: usize, y: usize, c: Vec3, a: f32) void {
    t.px[y * SIZE + x] = .{ .color = m.srgbToLinear(Vec3.init(m.clamp01(c.x), m.clamp01(c.y), m.clamp01(c.z))), .alpha = a };
}

fn h(x: usize, y: usize, seed: u32) f32 {
    return m.hash2(@intCast(x), @intCast(y), seed);
}

pub fn generateAll() void {
    for (0..TEX_COUNT) |i| {
        const id: TexId = @enumFromInt(i);
        const t = &all[i];
        for (0..SIZE) |y| {
            for (0..SIZE) |x| {
                const n = h(x, y, @intCast(i * 31 + 7));
                switch (id) {
                    .grass_top => put(t, x, y, rgb(0.33, 0.58, 0.20).scale(0.78 + 0.4 * n), 1),
                    .dirt => dirt(t, x, y, n),
                    .grass_side => {
                        // Tierra con franja de pasto arriba que "gotea" un poco.
                        const drip: usize = if (h(x, 0, 99) > 0.55) 4 else 3;
                        if (y < drip) put(t, x, y, rgb(0.33, 0.58, 0.20).scale(0.78 + 0.4 * n), 1) else dirt(t, x, y, n);
                    },
                    .fur_white => put(t, x, y, rgb(0.95, 0.94, 0.92).scale(0.86 + 0.14 * n), 1),
                    .fur_black => put(t, x, y, rgb(0.13, 0.13, 0.14).scale(0.65 + 0.7 * n), 1),
                    .panda_face => pandaFace(t, x, y, n),
                    .panda_snout => {
                        const nose = y < 6 and x >= 5 and x <= 10;
                        if (nose) put(t, x, y, rgb(0.08, 0.08, 0.09), 1) else put(t, x, y, rgb(0.95, 0.94, 0.92).scale(0.86 + 0.14 * n), 1);
                    },
                    .glass => {
                        // Marco opaco + reflejos diagonales, centro transparente.
                        const border = x == 0 or y == 0 or x == SIZE - 1 or y == SIZE - 1;
                        const streak = (x + y == 7 and x >= 2 and x <= 5) or (x + y == 9 and x >= 3 and x <= 5) or (x + y == 22 and x >= 10 and x <= 12);
                        if (border) put(t, x, y, rgb(0.78, 0.86, 0.9), 0) else if (streak) put(t, x, y, rgb(1, 1, 1), 0.55) else put(t, x, y, rgb(1, 1, 1), 1);
                    },
                    .emerald => {
                        // Facetas: bandas diagonales más claras.
                        const fx: f32 = @floatFromInt(x);
                        const fy: f32 = @floatFromInt(y);
                        const facet = @abs(@mod(fx + fy, 8.0) - 4.0) / 4.0;
                        const edge = x == 0 or y == 0 or x == SIZE - 1 or y == SIZE - 1;
                        var c = rgb(0.12, 0.85, 0.38).scale(0.65 + 0.35 * facet + 0.1 * n);
                        if (edge) c = rgb(0.05, 0.45, 0.2);
                        put(t, x, y, c, 1);
                    },
                    .alabaster => {
                        // Piedra crema con vetas suaves.
                        const fx: f32 = @floatFromInt(x);
                        const fy: f32 = @floatFromInt(y);
                        const vein = @abs(@sin(fx * 0.7 + fy * 0.35 + 3 * h(x / 4, y / 4, 5)));
                        var c = rgb(0.96, 0.93, 0.86).scale(0.9 + 0.1 * n);
                        if (vein < 0.12) c = rgb(0.84, 0.8, 0.74);
                        put(t, x, y, c, 1);
                    },
                    .glowstone => {
                        // Manchas de 2x2 claras/oscuras.
                        const b = h(x / 2, y / 2, 77);
                        const c = if (b > 0.62) rgb(1.0, 0.93, 0.62) else if (b > 0.3) rgb(0.86, 0.64, 0.3) else rgb(0.55, 0.38, 0.16);
                        put(t, x, y, c.scale(0.9 + 0.1 * n), 1);
                    },
                    .iron => {
                        const border = x == 0 or y == 0 or x == SIZE - 1 or y == SIZE - 1;
                        const rivet = (x == 2 or x == 13) and (y == 2 or y == 13);
                        var c = rgb(0.88, 0.89, 0.92).scale(0.93 + 0.07 * n);
                        if (border) c = rgb(0.62, 0.63, 0.66);
                        if (rivet) c = rgb(0.5, 0.5, 0.53);
                        put(t, x, y, c, 1);
                    },
                    .water => {
                        const fx: f32 = @floatFromInt(x);
                        const fy: f32 = @floatFromInt(y);
                        const w = 0.5 + 0.5 * @sin(fx * 0.8 + @sin(fy * 0.6) * 2);
                        put(t, x, y, rgb(0.55, 0.75, 1.0).scale(0.85 + 0.15 * w), 1);
                    },
                    .bamboo => {
                        const node = y == 4 or y == 12;
                        const stripe = x % 5 == 1;
                        var c = rgb(0.45, 0.68, 0.22).scale(0.85 + 0.2 * n);
                        if (stripe) c = c.scale(0.8);
                        if (node) c = rgb(0.32, 0.5, 0.15);
                        put(t, x, y, c, 1);
                    },
                    .bamboo_top => put(t, x, y, rgb(0.78, 0.82, 0.45).scale(0.85 + 0.15 * n), 1),
                }
            }
        }
    }
}

fn dirt(t: *Texture, x: usize, y: usize, n: f32) void {
    var c = rgb(0.53, 0.38, 0.26).scale(0.75 + 0.35 * n);
    if (h(x, y, 1234) > 0.88) c = rgb(0.38, 0.27, 0.18);
    if (h(x, y, 4321) > 0.93) c = rgb(0.62, 0.5, 0.4);
    put(t, x, y, c, 1);
}

fn pandaFace(t: *Texture, x: usize, y: usize, n: f32) void {
    const white = rgb(0.95, 0.94, 0.92).scale(0.86 + 0.14 * n);
    const black = rgb(0.1, 0.1, 0.11).scale(0.8 + 0.4 * n);
    // Parches de los ojos (inclinados como el panda de Minecraft).
    const left = x >= 2 and x <= 5 and y >= 5 and y <= 10 and !(x == 2 and y == 5) and !(x == 5 and y == 10);
    const right = x >= 10 and x <= 13 and y >= 5 and y <= 10 and !(x == 13 and y == 5) and !(x == 10 and y == 10);
    const eye = (x == 4 and y == 7) or (x == 11 and y == 7);
    const pupil = (x == 4 and y == 8) or (x == 11 and y == 8);
    if (eye) {
        put(t, x, y, rgb(0.9, 0.9, 0.92), 1);
    } else if (pupil) {
        put(t, x, y, rgb(0.02, 0.02, 0.02), 1);
    } else if (left or right) {
        put(t, x, y, black, 1);
    } else {
        put(t, x, y, white, 1);
    }
}
