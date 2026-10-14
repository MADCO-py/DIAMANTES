//! Materiales, figuras (cubos y cilindros), luces y la escena del diorama.
const std = @import("std");
const m = @import("math.zig");
const tex = @import("textures.zig");
const Vec3 = m.Vec3;
const TexId = tex.TexId;

pub const EPS: f32 = 1e-3;

// ─────────────────────────────── Materiales ───────────────────────────────

pub const MatId = enum(u8) {
    grass,
    dirt,
    fur_white,
    fur_black,
    glass,
    emerald,
    alabaster,
    glowstone,
    iron,
    water,
    bamboo,
};

pub const Material = struct {
    // Textura por tipo de cara (arriba / lados / abajo).
    tex_top: TexId,
    tex_side: TexId,
    tex_bottom: TexId,
    // Parámetros pedidos en la rúbrica.
    albedo: f32, // peso de la componente difusa
    specular: f32, // exponente de Blinn-Phong
    ks: f32, // intensidad especular
    transparency: f32, // fracción de luz que se refracta
    reflectivity: f32, // fracción de luz que se refleja
    // Extras.
    ior: f32 = 1.0, // índice de refracción
    roughness: f32 = 0, // desenfoque de reflexión/refracción (vidrio esmerilado)
    emission: f32 = 0, // > 0: el material brilla
    translucency: f32 = 0, // dispersión subsuperficial (alabastro)
    density: f32 = 0, // qué tan rápido se apaga la luz dentro del material translúcido
    absorption: Vec3 = Vec3.zero, // Beer-Lambert: color del interior del material
    tint_reflection: bool = false, // el reflejo toma el color del material

    fn uniform(t: TexId, base: Material) Material {
        var r = base;
        r.tex_top = t;
        r.tex_side = t;
        r.tex_bottom = t;
        return r;
    }
};

const D = Material{ .tex_top = .dirt, .tex_side = .dirt, .tex_bottom = .dirt, .albedo = 0.9, .specular = 8, .ks = 0.02, .transparency = 0, .reflectivity = 0 };

pub const materials = blk: {
    var mats: [@typeInfo(MatId).@"enum".fields.len]Material = undefined;
    mats[@intFromEnum(MatId.grass)] = .{ .tex_top = .grass_top, .tex_side = .grass_side, .tex_bottom = .dirt, .albedo = 0.9, .specular = 8, .ks = 0.03, .transparency = 0, .reflectivity = 0 };
    mats[@intFromEnum(MatId.dirt)] = D;
    mats[@intFromEnum(MatId.fur_white)] = Material.uniform(.fur_white, .{ .tex_top = .dirt, .tex_side = .dirt, .tex_bottom = .dirt, .albedo = 0.95, .specular = 16, .ks = 0.05, .transparency = 0, .reflectivity = 0 });
    mats[@intFromEnum(MatId.fur_black)] = Material.uniform(.fur_black, .{ .tex_top = .dirt, .tex_side = .dirt, .tex_bottom = .dirt, .albedo = 0.9, .specular = 24, .ks = 0.15, .transparency = 0, .reflectivity = 0 });
    mats[@intFromEnum(MatId.glass)] = Material.uniform(.glass, .{
        .tex_top = .dirt, .tex_side = .dirt, .tex_bottom = .dirt,
        .albedo = 0.15, .specular = 128, .ks = 0.8, .transparency = 0.92, .reflectivity = 0.04,
        .ior = 1.5, .absorption = Vec3.init(0.05, 0.02, 0.03),
    });
    mats[@intFromEnum(MatId.emerald)] = Material.uniform(.emerald, .{
        .tex_top = .dirt, .tex_side = .dirt, .tex_bottom = .dirt,
        .albedo = 0.1, .specular = 256, .ks = 1.0, .transparency = 0.8, .reflectivity = 0.15,
        .ior = 1.58, .absorption = Vec3.init(1.8, 0.25, 1.2), .tint_reflection = true,
    });
    mats[@intFromEnum(MatId.alabaster)] = Material.uniform(.alabaster, .{
        .tex_top = .dirt, .tex_side = .dirt, .tex_bottom = .dirt,
        .albedo = 0.7, .specular = 32, .ks = 0.15, .transparency = 0.12, .reflectivity = 0.03,
        .ior = 1.49, .roughness = 0.35, .translucency = 1.6, .density = 2.2,
    });
    mats[@intFromEnum(MatId.glowstone)] = Material.uniform(.glowstone, .{
        .tex_top = .dirt, .tex_side = .dirt, .tex_bottom = .dirt,
        .albedo = 0.6, .specular = 8, .ks = 0.05, .transparency = 0, .reflectivity = 0, .emission = 2.5,
    });
    mats[@intFromEnum(MatId.iron)] = Material.uniform(.iron, .{
        .tex_top = .dirt, .tex_side = .dirt, .tex_bottom = .dirt,
        .albedo = 0.25, .specular = 200, .ks = 0.9, .transparency = 0, .reflectivity = 0.72,
        .roughness = 0.015, .tint_reflection = true,
    });
    mats[@intFromEnum(MatId.water)] = Material.uniform(.water, .{
        .tex_top = .dirt, .tex_side = .dirt, .tex_bottom = .dirt,
        .albedo = 0.08, .specular = 300, .ks = 1.0, .transparency = 0.8, .reflectivity = 0.06,
        .ior = 1.33, .absorption = Vec3.init(0.55, 0.14, 0.06),
    });
    mats[@intFromEnum(MatId.bamboo)] = .{ .tex_top = .bamboo_top, .tex_side = .bamboo, .tex_bottom = .bamboo_top, .albedo = 0.9, .specular = 40, .ks = 0.2, .transparency = 0, .reflectivity = 0 };
    break :blk mats;
};

pub inline fn mat(id: MatId) *const Material {
    return &materials[@intFromEnum(id)];
}

// ──────────────────────────────── Figuras ────────────────────────────────

/// Cubo alineado a los ejes (AABB).
pub const Box = struct {
    min: Vec3,
    max: Vec3,
    mat: MatId,
    /// true: la textura se repite cada 1 unidad (bloques del suelo).
    /// false: la textura se estira sobre la cara (partes del panda).
    tile: bool = false,
    /// Textura especial para la cara que mira a -Z (cara del panda).
    front_tex: ?TexId = null,
    /// Ondas en la normal de la cara superior (agua).
    ripple: bool = false,
};

/// Cilindro vertical con tapas (forma no vista en clase).
pub const Cylinder = struct {
    cx: f32,
    cz: f32,
    y0: f32,
    y1: f32,
    r: f32,
    mat: MatId,
};

pub const ObjKind = enum(u1) { box, cyl };
pub const ObjRef = struct { kind: ObjKind, idx: u16 };

pub const Hit = struct {
    t: f32,
    p: Vec3,
    n: Vec3, // normal hacia afuera del objeto
    u: f32,
    v: f32,
    mat: MatId,
    tex: TexId,
    obj: ObjRef,
};

// ──────────────────────────────── Luces ────────────────────────────────

pub const LightKind = enum { directional, point, spot };

pub const Light = struct {
    kind: LightKind,
    pos: Vec3 = Vec3.zero,
    /// directional: hacia dónde viaja la luz. spot: hacia dónde apunta.
    dir: Vec3 = Vec3.init(0, -1, 0),
    color: Vec3, // ya incluye la intensidad
    cos_inner: f32 = 1, // spot: dentro de este cono la luz es completa
    cos_outer: f32 = 1, // spot: fuera de este cono no hay luz
};

// ──────────────────────────────── Escena ────────────────────────────────

pub const MAX_BOXES = 64;
pub const MAX_CYLS = 16;
pub const MAX_LIGHTS = 8;

pub const Scene = struct {
    boxes: [MAX_BOXES]Box = undefined,
    n_boxes: usize = 0,
    cyls: [MAX_CYLS]Cylinder = undefined,
    n_cyls: usize = 0,
    lights: [MAX_LIGHTS]Light = undefined,
    n_lights: usize = 0,
    ambient: Vec3 = Vec3.splat(0.02),
    sun_dir: Vec3 = Vec3.init(0, 1, 0), // hacia el sol (o la luna)
    night: bool = false,

    /// Cambia entre día y noche (la luz 0 es el sol / la luna).
    pub fn setNight(s: *Scene, night: bool) void {
        s.night = night;
        if (night) {
            s.sun_dir = Vec3.init(-0.5, 0.7, 0.5).normalize();
            s.lights[0].color = m.rgb(0.55, 0.65, 1.0).scale(0.12);
            s.ambient = Vec3.splat(0.004);
        } else {
            s.sun_dir = Vec3.init(0.55, 0.75, 0.45).normalize();
            s.lights[0].color = m.rgb(1.0, 0.9, 0.75).scale(0.85);
            s.ambient = Vec3.splat(0.02);
        }
        s.lights[0].dir = s.sun_dir.neg();
    }

    fn box(s: *Scene, b: Box) void {
        s.boxes[s.n_boxes] = b;
        s.n_boxes += 1;
    }
    fn cyl(s: *Scene, c: Cylinder) void {
        s.cyls[s.n_cyls] = c;
        s.n_cyls += 1;
    }
    fn light(s: *Scene, l: Light) void {
        s.lights[s.n_lights] = l;
        s.n_lights += 1;
    }

    // ─────── Intersección ───────

    const BoxT = struct { t: f32, axis: u2, sign: f32 };

    /// Método de "slabs" para AABB. Si el rayo nace adentro, devuelve la salida.
    fn intersectBox(b: *const Box, ro: Vec3, inv: Vec3) ?BoxT {
        var tnear: f32 = -std.math.inf(f32);
        var tfar: f32 = std.math.inf(f32);
        var ax_near: u2 = 0;
        var ax_far: u2 = 0;
        var s_near: f32 = 1;
        var s_far: f32 = 1;
        inline for (0..3) |a| {
            const o = ro.get(a);
            const id = inv.get(a);
            const t1 = (b.min.get(a) - o) * id;
            const t2 = (b.max.get(a) - o) * id;
            const lo = @min(t1, t2);
            const hi = @max(t1, t2);
            if (lo > tnear) {
                tnear = lo;
                ax_near = a;
                s_near = if (id > 0) -1 else 1;
            }
            if (hi < tfar) {
                tfar = hi;
                ax_far = a;
                s_far = if (id > 0) 1 else -1;
            }
        }
        if (tnear > tfar or tfar < EPS) return null;
        if (tnear > EPS) return .{ .t = tnear, .axis = ax_near, .sign = s_near };
        return .{ .t = tfar, .axis = ax_far, .sign = s_far };
    }

    const CylT = struct { t: f32, part: u2 }; // 0 = lado, 1 = tapa arriba, 2 = tapa abajo

    /// Cilindro: cuadrática en XZ para el lado + dos planos para las tapas.
    fn intersectCyl(c: *const Cylinder, ro: Vec3, rd: Vec3) ?CylT {
        var best: f32 = std.math.inf(f32);
        var part: u2 = 0;
        const ox = ro.x - c.cx;
        const oz = ro.z - c.cz;
        const a = rd.x * rd.x + rd.z * rd.z;
        if (a > 1e-8) {
            const b = 2 * (ox * rd.x + oz * rd.z);
            const cc = ox * ox + oz * oz - c.r * c.r;
            const disc = b * b - 4 * a * cc;
            if (disc >= 0) {
                const sq = @sqrt(disc);
                const roots = [2]f32{ (-b - sq) / (2 * a), (-b + sq) / (2 * a) };
                for (roots) |t| {
                    if (t > EPS and t < best) {
                        const y = ro.y + rd.y * t;
                        if (y >= c.y0 and y <= c.y1) {
                            best = t;
                            part = 0;
                            break;
                        }
                    }
                }
            }
        }
        if (@abs(rd.y) > 1e-8) {
            const caps = [2]f32{ c.y1, c.y0 };
            for (caps, 0..) |yc, i| {
                const t = (yc - ro.y) / rd.y;
                if (t > EPS and t < best) {
                    const x = ox + rd.x * t;
                    const z = oz + rd.z * t;
                    if (x * x + z * z <= c.r * c.r) {
                        best = t;
                        part = @intCast(i + 1);
                    }
                }
            }
        }
        if (best == std.math.inf(f32)) return null;
        return .{ .t = best, .part = part };
    }

    /// Intersección más cercana con toda la escena.
    pub fn intersect(s: *const Scene, ro: Vec3, rd: Vec3, tmax: f32) ?Hit {
        const inv = Vec3.init(1 / rd.x, 1 / rd.y, 1 / rd.z);
        var best_t = tmax;
        var found = false;
        var ref: ObjRef = undefined;
        var bt: BoxT = undefined;
        var ct: CylT = undefined;

        for (s.boxes[0..s.n_boxes], 0..) |*b, i| {
            if (intersectBox(b, ro, inv)) |r| {
                if (r.t < best_t) {
                    best_t = r.t;
                    found = true;
                    ref = .{ .kind = .box, .idx = @intCast(i) };
                    bt = r;
                }
            }
        }
        for (s.cyls[0..s.n_cyls], 0..) |*c, i| {
            if (intersectCyl(c, ro, rd)) |r| {
                if (r.t < best_t) {
                    best_t = r.t;
                    found = true;
                    ref = .{ .kind = .cyl, .idx = @intCast(i) };
                    ct = r;
                }
            }
        }
        if (!found) return null;

        const p = ro.add(rd.scale(best_t));
        var hit = switch (ref.kind) {
            .box => s.finishBox(&s.boxes[ref.idx], ref, bt, p),
            .cyl => finishCyl(&s.cyls[ref.idx], ref, ct, p),
        };
        hit.t = best_t;
        return hit;
    }

    fn finishBox(_: *const Scene, b: *const Box, ref: ObjRef, r: BoxT, p: Vec3) Hit {
        const mt = mat(b.mat);
        var n = Vec3.zero;
        var t_id: TexId = mt.tex_side;
        var u: f32 = 0;
        var v: f32 = 0;
        const size = b.max.sub(b.min);
        switch (r.axis) {
            0 => {
                n.x = r.sign;
                if (b.tile) {
                    u = p.z;
                    v = -p.y;
                } else {
                    u = (p.z - b.min.z) / size.z;
                    v = (b.max.y - p.y) / size.y;
                }
            },
            1 => {
                n.y = r.sign;
                t_id = if (r.sign > 0) mt.tex_top else mt.tex_bottom;
                if (b.tile) {
                    u = p.x;
                    v = p.z;
                } else {
                    u = (p.x - b.min.x) / size.x;
                    v = (p.z - b.min.z) / size.z;
                }
            },
            else => {
                n.z = r.sign;
                if (r.sign < 0) if (b.front_tex) |ft| {
                    t_id = ft;
                };
                if (b.tile) {
                    u = p.x;
                    v = -p.y;
                } else {
                    u = (b.max.x - p.x) / size.x;
                    v = (b.max.y - p.y) / size.y;
                }
            },
        }
        if (!b.tile) {
            u = std.math.clamp(u, 0, 0.9999);
            v = std.math.clamp(v, 0, 0.9999);
        }
        // Ondas del agua: se perturba la normal de la cara de arriba.
        if (b.ripple and r.axis == 1 and r.sign > 0) {
            n = Vec3.init(
                0.035 * @sin(p.x * 9 + p.z * 4),
                1,
                0.035 * @sin(p.z * 11 - p.x * 3),
            ).normalize();
        }
        return .{ .t = 0, .p = p, .n = n, .u = u, .v = v, .mat = b.mat, .tex = t_id, .obj = ref };
    }

    fn finishCyl(c: *const Cylinder, ref: ObjRef, r: CylT, p: Vec3) Hit {
        const mt = mat(c.mat);
        var hit = Hit{ .t = 0, .p = p, .n = undefined, .u = 0, .v = 0, .mat = c.mat, .tex = mt.tex_side, .obj = ref };
        switch (r.part) {
            0 => {
                hit.n = Vec3.init((p.x - c.cx) / c.r, 0, (p.z - c.cz) / c.r);
                hit.u = std.math.atan2(p.z - c.cz, p.x - c.cx) / (2 * std.math.pi) + 0.5;
                hit.v = -p.y;
            },
            else => {
                hit.n = if (r.part == 1) Vec3.init(0, 1, 0) else Vec3.init(0, -1, 0);
                hit.tex = if (r.part == 1) mt.tex_top else mt.tex_bottom;
                hit.u = (p.x - c.cx) / (2 * c.r) + 0.5;
                hit.v = (p.z - c.cz) / (2 * c.r) + 0.5;
            },
        }
        return hit;
    }

    /// Distancia que recorre un rayo dentro de UN objeto (grosor para el alabastro).
    pub fn thicknessInside(s: *const Scene, obj: ObjRef, ro: Vec3, rd: Vec3) f32 {
        switch (obj.kind) {
            .box => {
                const inv = Vec3.init(1 / rd.x, 1 / rd.y, 1 / rd.z);
                if (intersectBox(&s.boxes[obj.idx], ro, inv)) |r| return r.t;
                return 0;
            },
            .cyl => {
                if (intersectCyl(&s.cyls[obj.idx], ro, rd)) |r| return r.t;
                return 0;
            },
        }
    }
};

// ──────────────────────────── El diorama ────────────────────────────

fn v3(x: f32, y: f32, z: f32) Vec3 {
    return Vec3.init(x, y, z);
}

pub fn build() Scene {
    var s = Scene{};

    // Isla flotante de bloques (pasto arriba, tierra abajo, en escalones).
    // La piscina (2x2) queda en la esquina x[2,4] z[2,4], por eso el pasto va en 4 pedazos.
    s.box(.{ .min = v3(-5, -1, -5), .max = v3(5, 0, 2), .mat = .grass, .tile = true });
    s.box(.{ .min = v3(-5, -1, 2), .max = v3(2, 0, 5), .mat = .grass, .tile = true });
    s.box(.{ .min = v3(4, -1, 2), .max = v3(5, 0, 5), .mat = .grass, .tile = true });
    s.box(.{ .min = v3(2, -1, 4), .max = v3(4, 0, 5), .mat = .grass, .tile = true });
    s.box(.{ .min = v3(2, -1, 2), .max = v3(4, -0.12, 4), .mat = .water, .tile = true, .ripple = true });
    s.box(.{ .min = v3(-5, -2, -5), .max = v3(5, -1, 5), .mat = .dirt, .tile = true });
    s.box(.{ .min = v3(-4, -3, -4), .max = v3(4, -2, 4), .mat = .dirt, .tile = true });
    s.box(.{ .min = v3(-2, -4, -3), .max = v3(3, -3, 2), .mat = .dirt, .tile = true });
    s.box(.{ .min = v3(-1, -5, -1), .max = v3(1, -4, 1), .mat = .dirt, .tile = true });

    // ─── Panda (mirando hacia -Z) ───
    // Patas negras.
    s.box(.{ .min = v3(-0.6, 0, -0.55), .max = v3(-0.2, 0.55, -0.15), .mat = .fur_black });
    s.box(.{ .min = v3(0.2, 0, -0.55), .max = v3(0.6, 0.55, -0.15), .mat = .fur_black });
    s.box(.{ .min = v3(-0.6, 0, 0.55), .max = v3(-0.2, 0.55, 0.95), .mat = .fur_black });
    s.box(.{ .min = v3(0.2, 0, 0.55), .max = v3(0.6, 0.55, 0.95), .mat = .fur_black });
    // Cuerpo: blanco / franja negra / blanco.
    s.box(.{ .min = v3(-0.62, 0.55, -0.65), .max = v3(0.62, 1.42, -0.35), .mat = .fur_white });
    s.box(.{ .min = v3(-0.62, 0.55, -0.35), .max = v3(0.62, 1.42, 0.2), .mat = .fur_black });
    s.box(.{ .min = v3(-0.62, 0.55, 0.2), .max = v3(0.62, 1.42, 1.05), .mat = .fur_white });
    // Cabeza con la textura de la cara al frente.
    s.box(.{ .min = v3(-0.5, 0.62, -1.3), .max = v3(0.5, 1.38, -0.65), .mat = .fur_white, .front_tex = .panda_face });
    // Hocico.
    s.box(.{ .min = v3(-0.22, 0.66, -1.45), .max = v3(0.22, 0.92, -1.3), .mat = .fur_white, .front_tex = .panda_snout });
    // Orejas.
    s.box(.{ .min = v3(-0.56, 1.38, -1.08), .max = v3(-0.28, 1.6, -0.9), .mat = .fur_black });
    s.box(.{ .min = v3(0.28, 1.38, -1.08), .max = v3(0.56, 1.6, -0.9), .mat = .fur_black });

    // ─── Decoración ───
    // Vidrio (refracción) y esmeralda (refracción + reflejo con color).
    s.box(.{ .min = v3(-3, 0, -4), .max = v3(-2, 1, -3), .mat = .glass });
    s.box(.{ .min = v3(2.1, 0, -3.9), .max = v3(2.9, 0.8, -3.1), .mat = .emerald });
    // Espejo de hierro (reflexión).
    s.box(.{ .min = v3(-4, 0, -2.4), .max = v3(-3.6, 1.8, -0.4), .mat = .iron });
    // Losa de alabastro (translúcido) con glowstone atrás para que se ilumine a contraluz.
    s.box(.{ .min = v3(2.55, 0, -1.3), .max = v3(2.85, 1.3, 0.3), .mat = .alabaster });
    s.box(.{ .min = v3(3.2, 0, -1), .max = v3(4.2, 1, 0), .mat = .glowstone });
    // Segundo glowstone junto al bambú.
    s.box(.{ .min = v3(-4, 0, 0.6), .max = v3(-3, 1, 1.6), .mat = .glowstone });

    // Bambú (cilindros).
    s.cyl(.{ .cx = -3.3, .cz = 3.2, .y0 = 0, .y1 = 2.6, .r = 0.12, .mat = .bamboo });
    s.cyl(.{ .cx = -2.6, .cz = 3.9, .y0 = 0, .y1 = 3.3, .r = 0.12, .mat = .bamboo });
    s.cyl(.{ .cx = -4.0, .cz = 4.0, .y0 = 0, .y1 = 2.0, .r = 0.12, .mat = .bamboo });
    s.cyl(.{ .cx = -1.8, .cz = 3.4, .y0 = 0, .y1 = 1.5, .r = 0.12, .mat = .bamboo });

    // ─── Luces ───
    s.light(.{ .kind = .directional, .color = Vec3.zero }); // sol/luna, se configura en setNight

    // Reflector (spotlight) apuntando al panda como en un escenario.
    const spot_pos = v3(-1.5, 5.5, -3.5);
    s.light(.{
        .kind = .spot,
        .pos = spot_pos,
        .dir = v3(0, 0.6, -0.2).sub(spot_pos).normalize(),
        .color = m.rgb(1.0, 0.8, 0.95).scale(60),
        .cos_inner = @cos(std.math.degreesToRadians(10)),
        .cos_outer = @cos(std.math.degreesToRadians(17)),
    });
    // Los glowstone también son luces puntuales.
    s.light(.{ .kind = .point, .pos = v3(3.7, 0.5, -0.5), .color = m.rgb(1.0, 0.78, 0.4).scale(3.0) });
    s.light(.{ .kind = .point, .pos = v3(-3.5, 0.5, 1.1), .color = m.rgb(1.0, 0.78, 0.4).scale(3.0) });

    s.setNight(false);
    return s;
}
