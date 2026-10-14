//! Skybox tipo cubemap: 6 caras (+X,-X,+Y,-Y,+Z,-Z) con cielo, nubes cuadradas y sol.
//! Las caras se generan una vez al inicio y luego se muestrean por dirección,
//! exactamente como un cubemap de imágenes.
const std = @import("std");
const m = @import("math.zig");
const Vec3 = m.Vec3;

pub const RES = 128;

pub const Face = enum(u3) { pos_x, neg_x, pos_y, neg_y, pos_z, neg_z };

pub var faces: [6][RES * RES]Vec3 = undefined;
pub var sun_dir: Vec3 = Vec3.init(0, 1, 0);
pub var night: bool = false;

/// Dirección de mundo para el texel (u,v) de una cara.
fn faceDir(face: Face, u: f32, v: f32) Vec3 {
    const sc = 2 * u - 1;
    const tc = 2 * v - 1;
    const d = switch (face) {
        .pos_x => Vec3.init(1, -tc, -sc),
        .neg_x => Vec3.init(-1, -tc, sc),
        .pos_y => Vec3.init(sc, 1, tc),
        .neg_y => Vec3.init(sc, -1, -tc),
        .pos_z => Vec3.init(sc, -tc, 1),
        .neg_z => Vec3.init(-sc, -tc, -1),
    };
    return d.normalize();
}

/// Lo que se "pinta" en el cubemap (solo se llama al generar las caras).
fn paint(d: Vec3) Vec3 {
    if (night) return paintNight(d);
    const top = m.srgbToLinear(m.rgb(0.36, 0.56, 0.98));
    const horizon = m.srgbToLinear(m.rgb(0.76, 0.86, 1.0));
    const below = m.srgbToLinear(m.rgb(0.22, 0.3, 0.48));

    var c: Vec3 = undefined;
    if (d.y >= 0) {
        c = horizon.lerp(top, std.math.pow(f32, d.y, 0.55));
    } else {
        c = horizon.lerp(below, m.clamp01(-d.y * 3));
    }

    // Nubes cuadradas tipo Minecraft proyectadas sobre un plano alto.
    if (d.y > 0.03) {
        const px = d.x / d.y * 2.2;
        const pz = d.z / d.y * 2.2;
        const cx: i32 = @intFromFloat(@floor(px));
        const cz: i32 = @intFromFloat(@floor(pz));
        const cloud = m.hash2(cx, cz, 2024) > 0.7 or (m.hash2(@divFloor(cx, 2), @divFloor(cz, 2), 7) > 0.78);
        if (cloud) {
            const fade = m.smoothstep(0.03, 0.25, d.y);
            c = c.lerp(Vec3.splat(1.0), 0.9 * fade);
        }
    }

    // Sol cuadrado (HDR: valor > 1 para que brille en reflejos).
    const sd = sun_dir;
    const cos_s = d.dot(sd);
    if (cos_s > 0) {
        const up = if (@abs(sd.y) > 0.99) Vec3.init(1, 0, 0) else Vec3.init(0, 1, 0);
        const t1 = up.cross(sd).normalize();
        const t2 = sd.cross(t1);
        const a = d.dot(t1) / cos_s;
        const b = d.dot(t2) / cos_s;
        if (@abs(a) < 0.07 and @abs(b) < 0.07) {
            c = m.rgb(9.0, 8.4, 6.5);
        } else {
            // Halo suave alrededor.
            const glow = std.math.pow(f32, @max(0, cos_s), 64) * 0.6;
            c = c.add(m.rgb(1.0, 0.85, 0.6).scale(glow));
        }
    }
    return c;
}

/// Versión de noche: cielo oscuro, estrellas cuadradas y luna.
fn paintNight(d: Vec3) Vec3 {
    const top = m.srgbToLinear(m.rgb(0.02, 0.03, 0.09));
    const horizon = m.srgbToLinear(m.rgb(0.1, 0.12, 0.25));
    var c = if (d.y >= 0) horizon.lerp(top, std.math.pow(f32, d.y, 0.5)) else horizon.scale(1 - m.clamp01(-d.y * 2) * 0.7);

    // Estrellas: celdas en una cuadrícula angular.
    if (d.y > 0.05) {
        const gx: i32 = @intFromFloat(@floor(d.x * 90));
        const gy: i32 = @intFromFloat(@floor(d.y * 90));
        const gz: i32 = @intFromFloat(@floor(d.z * 90));
        if (m.hash2(gx + gz * 977, gy, 31) > 0.985) c = Vec3.splat(1.4);
    }

    // Luna cuadrada (en la dirección de la luz principal).
    const sd = sun_dir;
    const cos_s = d.dot(sd);
    if (cos_s > 0) {
        const up = if (@abs(sd.y) > 0.99) Vec3.init(1, 0, 0) else Vec3.init(0, 1, 0);
        const t1 = up.cross(sd).normalize();
        const t2 = sd.cross(t1);
        const a = d.dot(t1) / cos_s;
        const b = d.dot(t2) / cos_s;
        if (@abs(a) < 0.06 and @abs(b) < 0.06) {
            const crater = m.hash2(@intFromFloat(@floor(a * 60)), @intFromFloat(@floor(b * 60)), 3) > 0.75;
            c = if (crater) m.rgb(1.2, 1.25, 1.4) else m.rgb(2.2, 2.3, 2.6);
        } else {
            c = c.add(m.rgb(0.3, 0.35, 0.6).scale(std.math.pow(f32, @max(0, cos_s), 48) * 0.4));
        }
    }
    return c;
}

pub fn generate(sun: Vec3, is_night: bool) void {
    night = is_night;
    sun_dir = sun.normalize();
    for (0..6) |f| {
        for (0..RES) |y| {
            for (0..RES) |x| {
                const u = (@as(f32, @floatFromInt(x)) + 0.5) / RES;
                const v = (@as(f32, @floatFromInt(y)) + 0.5) / RES;
                faces[f][y * RES + x] = paint(faceDir(@enumFromInt(f), u, v));
            }
        }
    }
}

/// Muestreo del cubemap: se elige la cara por el eje dominante de la dirección.
pub fn sample(d: Vec3) Vec3 {
    const ax = @abs(d.x);
    const ay = @abs(d.y);
    const az = @abs(d.z);
    var face: Face = undefined;
    var sc: f32 = undefined;
    var tc: f32 = undefined;
    var ma: f32 = undefined;
    if (ax >= ay and ax >= az) {
        ma = ax;
        if (d.x > 0) {
            face = .pos_x;
            sc = -d.z;
            tc = -d.y;
        } else {
            face = .neg_x;
            sc = d.z;
            tc = -d.y;
        }
    } else if (ay >= az) {
        ma = ay;
        if (d.y > 0) {
            face = .pos_y;
            sc = d.x;
            tc = d.z;
        } else {
            face = .neg_y;
            sc = d.x;
            tc = -d.z;
        }
    } else {
        ma = az;
        if (d.z > 0) {
            face = .pos_z;
            sc = d.x;
            tc = -d.y;
        } else {
            face = .neg_z;
            sc = -d.x;
            tc = -d.y;
        }
    }
    const u = (sc / ma + 1) * 0.5;
    const v = (tc / ma + 1) * 0.5;
    const x: usize = @min(RES - 1, @as(usize, @intFromFloat(@max(0, u * RES))));
    const y: usize = @min(RES - 1, @as(usize, @intFromFloat(@max(0, v * RES))));
    return faces[@intFromEnum(face)][y * RES + x];
}
