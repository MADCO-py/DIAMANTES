//! Materiales y sus texturas.
//!
//! De dónde sale el color de un punto:
//!   1. Cada material tiene un color base (`color`).
//!   2. Su textura es una cuadrícula de 16x16 "píxeles" estilo Minecraft.
//!      Cada píxel = color base * un brillo que depende del patrón del material
//!      (ruido aleatorio, bordes, manchas...). Se pinta una sola vez al iniciar.
//!   3. Al chocar un rayo con un cubo se toma el píxel de la textura que toca
//!      (ver `sample`), y el tracer lo ilumina con los parámetros del material.
const std = @import("std");
const m = @import("math.zig");
const Vec3 = m.Vec3;

pub const Mat = enum { grass, dirt, fur_white, fur_black, emerald, alabaster, glowstone, iron, bamboo };

pub const Material = struct {
    color: Vec3, // color base de la textura (0..1, como en un editor de imágenes)
    albedo: f32, // cuánta luz difusa devuelve la superficie
    specular: f32, // intensidad del brillo especular (Blinn-Phong)
    transparency: f32, // fracción de luz que atraviesa (refracción)
    reflectivity: f32, // fracción de luz que se refleja como espejo
    ior: f32 = 1, // índice de refracción (Snell)
    absorption: Vec3 = Vec3.zero, // color que "se come" por dentro (Beer-Lambert)
    emission: f32 = 0, // > 0: el material brilla por sí mismo
    translucency: f32 = 0, // > 0: deja pasar luz por dentro (alabastro)
};

pub const materials = std.enums.EnumArray(Mat, Material).init(.{
    .grass = .{ .color = Vec3.init(0.36, 0.62, 0.22), .albedo = 0.9, .specular = 0.02, .transparency = 0, .reflectivity = 0 },
    .dirt = .{ .color = Vec3.init(0.55, 0.39, 0.26), .albedo = 0.9, .specular = 0.02, .transparency = 0, .reflectivity = 0 },
    .fur_white = .{ .color = Vec3.init(0.95, 0.94, 0.92), .albedo = 0.95, .specular = 0.05, .transparency = 0, .reflectivity = 0 },
    .fur_black = .{ .color = Vec3.init(0.14, 0.14, 0.15), .albedo = 0.9, .specular = 0.15, .transparency = 0, .reflectivity = 0 },
    // Esmeralda: refracta, refleja, y por dentro absorbe rojo y azul -> se ve verde.
    .emerald = .{ .color = Vec3.init(0.2, 0.9, 0.45), .albedo = 0.1, .specular = 1.0, .transparency = 0.8, .reflectivity = 0.15, .ior = 1.58, .absorption = Vec3.init(1.8, 0.25, 1.2) },
    // Alabastro: piedra translúcida, la luz de atrás se ve a través de ella.
    .alabaster = .{ .color = Vec3.init(0.96, 0.93, 0.86), .albedo = 0.75, .specular = 0.15, .transparency = 0.1, .reflectivity = 0.03, .ior = 1.49, .translucency = 1.6 },
    .glowstone = .{ .color = Vec3.init(1.0, 0.8, 0.45), .albedo = 0.6, .specular = 0.05, .transparency = 0, .reflectivity = 0, .emission = 2.5 },
    // Hierro: un espejo con un toque gris.
    .iron = .{ .color = Vec3.init(0.88, 0.89, 0.92), .albedo = 0.25, .specular = 0.9, .transparency = 0, .reflectivity = 0.75 },
    .bamboo = .{ .color = Vec3.init(0.45, 0.68, 0.22), .albedo = 0.9, .specular = 0.2, .transparency = 0, .reflectivity = 0 },
});

pub fn get(mat: Mat) Material {
    return materials.get(mat);
}

// ───────────────────────────── Texturas ─────────────────────────────

const SIZE = 16;
var textures = std.enums.EnumArray(Mat, [SIZE * SIZE]Vec3).initUndefined();

/// Brillo del píxel (x, y) según el patrón de cada material.
/// `n` es ruido aleatorio en [0,1) distinto para cada píxel.
fn pattern(mat: Mat, x: usize, y: usize, n: f32) f32 {
    const border = x == 0 or y == 0 or x == SIZE - 1 or y == SIZE - 1;
    return switch (mat) {
        .grass, .dirt => 0.75 + 0.45 * n, // ruido fuerte
        .fur_white, .fur_black => 0.85 + 0.3 * n, // ruido suave
        .emerald => if (border) 0.5 else 0.7 + 0.3 * @as(f32, @floatFromInt((x + y) % 8)) / 8, // facetas diagonales
        .alabaster => if ((x * 2 + y) % 11 == 0) 0.85 else 0.95 + 0.05 * n, // vetas
        .glowstone => 0.6 + 0.5 * m.hash(@intCast(x / 2), @intCast(y / 2), 7), // manchas de 2x2
        .iron => if (border) 0.7 else 0.95 + 0.05 * n, // placa con marco
        .bamboo => if (y == 4 or y == 12) 0.7 else 0.85 + 0.2 * n, // nudos del tallo
    };
}

pub fn generateTextures() void {
    for (std.enums.values(Mat)) |mat| {
        const base = get(mat).color;
        for (0..SIZE) |y| {
            for (0..SIZE) |x| {
                const n = m.hash(@intCast(x), @intCast(y), @intFromEnum(mat));
                const c = base.scale(pattern(mat, x, y, n));
                textures.getPtr(mat)[y * SIZE + x] = m.srgb(@min(c.x, 1), @min(c.y, 1), @min(c.z, 1));
            }
        }
    }
}

/// Color de la textura en las coordenadas (u, v). Una unidad del mundo = 16 píxeles,
/// y la textura se repite como los bloques de Minecraft.
pub fn sample(mat: Mat, u: f32, v: f32) Vec3 {
    const x: usize = @intFromFloat(@mod(@floor(u * SIZE), SIZE));
    const y: usize = @intFromFloat(@mod(@floor(v * SIZE), SIZE));
    return textures.getPtrConst(mat)[y * SIZE + x];
}
