//! La escena: figuras (cubos y cilindros), cómo chocan los rayos con ellas,
//! las luces y el diorama del panda.
const std = @import("std");
const m = @import("math.zig");
const Mat = @import("materials.zig").Mat;
const Vec3 = m.Vec3;

pub const EPS: f32 = 1e-3;
const INF = std.math.inf(f32);

// ───────────────────────────── Figuras ─────────────────────────────

pub const Shape = union(enum) {
    /// Cubo alineado a los ejes: esquina mínima y máxima.
    box: struct { min: Vec3, max: Vec3 },
    /// Cilindro vertical con tapas (forma no vista en clase): centro (x, z),
    /// altura de y0 a y1 y radio r.
    cyl: struct { x: f32, z: f32, y0: f32, y1: f32, r: f32 },
};

pub const Object = struct { shape: Shape, mat: Mat };

pub const Hit = struct {
    t: f32, // distancia recorrida por el rayo
    p: Vec3, // punto de choque
    n: Vec3, // normal (hacia afuera)
    u: f32, // coordenadas de textura
    v: f32,
    mat: Mat,
    obj: usize, // índice del objeto en `objects`
};

fn box(x0: f32, y0: f32, z0: f32, x1: f32, y1: f32, z1: f32, mat: Mat) Object {
    return .{ .shape = .{ .box = .{ .min = Vec3.init(x0, y0, z0), .max = Vec3.init(x1, y1, z1) } }, .mat = mat };
}

fn bamboo(x: f32, z: f32, height: f32) Object {
    return .{ .shape = .{ .cyl = .{ .x = x, .z = z, .y0 = 0, .y1 = height, .r = 0.12 } }, .mat = .bamboo };
}

// ───────────────────────────── El diorama ─────────────────────────────
// Todo se arma con cubos: box(x0, y0, z0,  x1, y1, z1, material).
// El panda mira hacia -Z.

pub const objects = [_]Object{
    // Isla: una capa de pasto sobre tierra.
    box(-5, -0.25, -5, 5, 0, 5, .grass),
    box(-5, -1.5, -5, 5, -0.25, 5, .dirt),
    box(-3, -2.5, -3, 3, -1.5, 3, .dirt),

    // ─── Panda ───
    // Patas
    box(-0.6, 0, -0.55, -0.2, 0.55, -0.15, .fur_black),
    box(0.2, 0, -0.55, 0.6, 0.55, -0.15, .fur_black),
    box(-0.6, 0, 0.55, -0.2, 0.55, 0.95, .fur_black),
    box(0.2, 0, 0.55, 0.6, 0.55, 0.95, .fur_black),
    // Cuerpo: blanco / franja negra / blanco
    box(-0.62, 0.55, -0.65, 0.62, 1.42, -0.35, .fur_white),
    box(-0.62, 0.55, -0.35, 0.62, 1.42, 0.2, .fur_black),
    box(-0.62, 0.55, 0.2, 0.62, 1.42, 1.05, .fur_white),
    // Cabeza
    box(-0.5, 0.62, -1.3, 0.5, 1.38, -0.65, .fur_white),
    // Orejas
    box(-0.56, 1.38, -1.08, -0.28, 1.6, -0.9, .fur_black),
    box(0.28, 1.38, -1.08, 0.56, 1.6, -0.9, .fur_black),
    // Manchas de los ojos y ojos
    box(-0.4, 0.9, -1.32, -0.12, 1.2, -1.3, .fur_black),
    box(0.12, 0.9, -1.32, 0.4, 1.2, -1.3, .fur_black),
    box(-0.3, 1.04, -1.34, -0.2, 1.12, -1.32, .fur_white),
    box(0.2, 1.04, -1.34, 0.3, 1.12, -1.32, .fur_white),
    // Hocico y nariz
    box(-0.22, 0.66, -1.45, 0.22, 0.9, -1.3, .fur_white),
    box(-0.08, 0.8, -1.47, 0.08, 0.9, -1.45, .fur_black),

    // ─── Decoración ───
    box(2.1, 0, -3.9, 2.9, 0.8, -3.1, .emerald), // refracción + color
    box(-4, 0, -2.4, -3.6, 1.8, -0.4, .iron), // espejo
    box(2.55, 0, -1.3, 2.85, 1.3, 0.3, .alabaster), // translúcido...
    box(3.2, 0, -1, 4.2, 1, 0, .glowstone), // ...con una luz detrás
    box(-4, 0, 0.6, -3, 1, 1.6, .glowstone),
    bamboo(-3.3, 3.2, 2.6),
    bamboo(-2.6, 3.9, 3.3),
    bamboo(-4.0, 4.0, 2.0),
    bamboo(-1.8, 3.4, 1.5),
};

// ───────────────────────────── Luces ─────────────────────────────

pub const Light = struct {
    kind: enum { sun, point, spot },
    pos: Vec3 = Vec3.zero,
    dir: Vec3 = Vec3.zero, // sun: hacia dónde viaja la luz. spot: hacia dónde apunta.
    color: Vec3, // color * intensidad
    cone: f32 = 0, // spot: ángulo del cono en grados
};

const spot_pos = Vec3.init(-1.5, 5.5, -3.5);

pub const lights = [_]Light{
    .{ .kind = .sun, .dir = Vec3.init(-0.55, -0.75, -0.45).normalize(), .color = Vec3.init(1.0, 0.9, 0.75).scale(0.85) },
    // Reflector (luz no vista en clase) apuntando al panda como en un escenario.
    .{ .kind = .spot, .pos = spot_pos, .dir = Vec3.init(0, 0.6, -0.2).sub(spot_pos).normalize(), .color = Vec3.init(1.0, 0.8, 0.95).scale(60), .cone = 15 },
    // Cada glowstone también ilumina como una luz puntual.
    .{ .kind = .point, .pos = Vec3.init(3.7, 0.5, -0.5), .color = Vec3.init(1.0, 0.78, 0.4).scale(3) },
    .{ .kind = .point, .pos = Vec3.init(-3.5, 0.5, 1.1), .color = Vec3.init(1.0, 0.78, 0.4).scale(3) },
};

pub const ambient = Vec3.init(0.02, 0.02, 0.02);

// ───────────────────────────── Intersecciones ─────────────────────────────

/// Choque más cercano del rayo (ro + t·rd) con toda la escena.
/// Primero solo se buscan distancias (rápido) y al final se calculan la normal
/// y la textura una sola vez, para el objeto más cercano.
pub fn intersect(ro: Vec3, rd: Vec3, tmax: f32) ?Hit {
    var best_t = tmax;
    var best_i: ?usize = null;
    for (0..objects.len) |i| {
        if (distance(i, ro, rd)) |t| {
            if (t < best_t) {
                best_t = t;
                best_i = i;
            }
        }
    }
    const i = best_i orelse return null;
    return surface(i, ro.add(rd.scale(best_t)), best_t);
}

/// Distancia desde ro hasta el objeto i siguiendo rd (null si no lo toca).
pub fn distance(i: usize, ro: Vec3, rd: Vec3) ?f32 {
    return switch (objects[i].shape) {
        .box => |b| distBox(b.min, b.max, ro, rd),
        .cyl => |c| distCyl(c.x, c.z, c.y0, c.y1, c.r, ro, rd),
    };
}

/// Cubo con el método de "slabs": en cada eje se calcula cuándo el rayo entra
/// y sale de la franja [min, max]. El rayo está dentro del cubo cuando está
/// dentro de las tres franjas a la vez.
fn distBox(min: Vec3, max: Vec3, ro: Vec3, rd: Vec3) ?f32 {
    var t_in = -INF;
    var t_out = INF;
    for (0..3) |a| {
        const t1 = (min.get(a) - ro.get(a)) / rd.get(a);
        const t2 = (max.get(a) - ro.get(a)) / rd.get(a);
        t_in = @max(t_in, @min(t1, t2));
        t_out = @min(t_out, @max(t1, t2));
    }
    if (t_in > t_out or t_out < EPS) return null;
    // Si el rayo empieza adentro (esmeralda, alabastro) se usa la salida.
    return if (t_in > EPS) t_in else t_out;
}

/// Cilindro: el lado es un círculo en XZ (ecuación cuadrática) y las tapas son
/// dos planos horizontales recortados por el círculo.
fn distCyl(cx: f32, cz: f32, y0: f32, y1: f32, r: f32, ro: Vec3, rd: Vec3) ?f32 {
    var best = INF;
    const ox = ro.x - cx;
    const oz = ro.z - cz;

    // Lado: (ox + t·dx)² + (oz + t·dz)² = r²  ->  a·t² + b·t + c = 0
    const a = rd.x * rd.x + rd.z * rd.z;
    const b = 2 * (ox * rd.x + oz * rd.z);
    const c = ox * ox + oz * oz - r * r;
    const disc = b * b - 4 * a * c;
    if (a > 1e-8 and disc >= 0) {
        for ([2]f32{ (-b - @sqrt(disc)) / (2 * a), (-b + @sqrt(disc)) / (2 * a) }) |t| {
            const y = ro.y + rd.y * t;
            if (t > EPS and y >= y0 and y <= y1) {
                best = t;
                break;
            }
        }
    }
    // Tapas.
    for ([2]f32{ y0, y1 }) |yc| {
        const t = (yc - ro.y) / rd.y;
        const x = ox + rd.x * t;
        const z = oz + rd.z * t;
        if (t > EPS and t < best and x * x + z * z <= r * r) best = t;
    }
    return if (best == INF) null else best;
}

/// Normal y coordenadas de textura en el punto p de la superficie del objeto i.
fn surface(i: usize, p: Vec3, t: f32) Hit {
    var h = Hit{ .t = t, .p = p, .n = Vec3.zero, .u = 0, .v = 0, .mat = objects[i].mat, .obj = i };
    switch (objects[i].shape) {
        .box => |b| {
            // La cara tocada es la del eje donde p está más lejos del centro
            // (medido en proporción al tamaño del cubo).
            var axis: usize = 0;
            var far: f32 = 0;
            for (0..3) |a| {
                const center = (b.min.get(a) + b.max.get(a)) / 2;
                const d = (p.get(a) - center) / (b.max.get(a) - b.min.get(a));
                if (@abs(d) > far) {
                    far = @abs(d);
                    axis = a;
                }
            }
            h.n.set(axis, std.math.sign(p.get(axis) - (b.min.get(axis) + b.max.get(axis)) / 2));
            // Textura: se usan las coordenadas del mundo sobre la cara.
            h.u = if (axis == 1) p.x else p.x + p.z;
            h.v = if (axis == 1) p.z else -p.y;
        },
        .cyl => |c| {
            if (p.y > c.y1 - EPS or p.y < c.y0 + EPS) { // tapas
                h.n = Vec3.init(0, if (p.y > c.y1 - EPS) 1 else -1, 0);
                h.u = p.x;
                h.v = p.z;
            } else { // lado
                h.n = Vec3.init((p.x - c.x) / c.r, 0, (p.z - c.z) / c.r);
                h.u = std.math.atan2(h.n.z, h.n.x) / (2 * std.math.pi); // vuelta alrededor del tallo
                h.v = -p.y;
            }
        },
    }
    return h;
}
