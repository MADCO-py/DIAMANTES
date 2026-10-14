//! El ray tracer: calcula el color que ve un rayo.
//!
//! Por cada choque el color se arma sumando:
//!   1. emisión (glowstone brilla solo)
//!   2. luz directa de cada luz (difusa + especular), con sombras
//!   3. translucidez (alabastro: luz que entra por atrás)
//!   4. color bleeding (luz que rebota en objetos cercanos)
//!   5. reflexión (rayo que rebota como espejo)
//!   6. refracción (rayo que atraviesa el material, ley de Snell)
const std = @import("std");
const m = @import("math.zig");
const mats = @import("materials.zig");
const scene = @import("scene.zig");
const sky = @import("skybox.zig");
const Vec3 = m.Vec3;
const Hit = scene.Hit;
const EPS = scene.EPS;
const INF = std.math.inf(f32);

const MAX_DEPTH = 5;
pub var color_bleeding = true;

/// `inside`: material dentro del cual viaja el rayo (null = aire).
pub fn trace(ro: Vec3, rd: Vec3, depth: u32, inside: ?mats.Mat, rng: *m.Rng) Vec3 {
    const hit = scene.intersect(ro, rd, INF) orelse return sky.sample(rd);
    var color = shade(hit, rd, depth, inside, rng);

    // Beer-Lambert: dentro de un material con color la luz se va tiñendo según
    // la distancia recorrida (por eso la esmeralda se ve verde por dentro).
    if (inside) |md| {
        const a = mats.get(md).absorption;
        color = color.mul(Vec3.init(@exp(-a.x * hit.t), @exp(-a.y * hit.t), @exp(-a.z * hit.t)));
    }
    return color;
}

fn shade(hit: Hit, rd: Vec3, depth: u32, inside: ?mats.Mat, rng: *m.Rng) Vec3 {
    const mt = mats.get(hit.mat);
    const col = mats.sample(hit.mat, hit.u, hit.v); // color de la textura en este punto

    // Si el rayo viene de adentro del objeto, la normal se da vuelta.
    const from_inside = hit.n.dot(rd) > 0;
    const n = if (from_inside) hit.n.neg() else hit.n;
    const out = hit.p.add(n.scale(EPS)); // un poquito afuera de la superficie

    // Cuánta luz se refleja (kr), se refracta (kt) y queda difusa (kd).
    // Fresnel: mientras más de costado se mira, más se refleja.
    const n1: f32 = if (from_inside) mt.ior else 1;
    const n2: f32 = if (from_inside) 1 else mt.ior;
    const f = if (mt.transparency > 0) m.fresnel(-rd.dot(n), n1, n2) else 0;
    const kr = mt.reflectivity + mt.transparency * f;
    const kt = mt.transparency * (1 - f);
    const kd = @max(0, 1 - kr - kt);

    // 1) Emisión
    var result = col.scale(mt.emission);

    if (!from_inside) {
        // 2) y 3) Luz directa, sombras y translucidez
        result = result.add(directLight(hit, n, rd, col).scale(kd));
        // 4) Color bleeding: un rayo en dirección al azar recoge la luz que
        //    devuelve el objeto de al lado (el pasto tiñe de verde al panda).
        if (color_bleeding and depth == 0) {
            const d = n.add(rng.unitVector()).normalize();
            result = result.add(col.mul(bounce(out, d)).scale(mt.albedo * kd));
        }
    }
    if (depth >= MAX_DEPTH) return result;

    // 5) Reflexión: el reflejo se tiñe con el color del material (esmeralda verde).
    if (kr > 0.01) {
        const rc = trace(out, m.reflect(rd, n), depth + 1, inside, rng);
        result = result.add(rc.mul(col).scale(kr));
    }

    // 6) Refracción: el rayo entra (o sale) del material doblándose.
    if (kt > 0.01) {
        if (m.refract(rd, n, n1 / n2)) |dir| {
            const next: ?mats.Mat = if (from_inside) null else hit.mat;
            const tc = trace(hit.p.sub(n.scale(EPS)), dir.normalize(), depth + 1, next, rng);
            result = result.add(tc.scale(kt));
        } else { // reflexión total interna
            result = result.add(trace(out, m.reflect(rd, n), depth + 1, inside, rng).scale(kt));
        }
    }
    return result;
}

/// Suma la luz que llega directo de cada fuente de luz.
fn directLight(hit: Hit, n: Vec3, rd: Vec3, col: Vec3) Vec3 {
    const mt = mats.get(hit.mat);
    var sum = scene.ambient.mul(col).scale(mt.albedo);

    for (scene.lights) |light| {
        // Dirección hacia la luz (L), distancia y cuánta luz llega.
        var L = light.dir.neg();
        var dist = INF;
        var power = light.color;
        if (light.kind != .sun) {
            const to_light = light.pos.sub(hit.p);
            dist = to_light.length();
            L = to_light.scale(1 / dist);
            power = power.scale(1 / @max(dist * dist, 0.3)); // se apaga con la distancia²
        }
        if (light.kind == .spot) {
            // Reflector: solo ilumina dentro de su cono, con el borde suavizado.
            const angle = std.math.radiansToDegrees(std.math.acos(std.math.clamp(L.neg().dot(light.dir), -1, 1)));
            const f = std.math.clamp((light.cone - angle) / 5, 0, 1);
            if (f == 0) continue;
            power = power.scale(f);
        }

        const ndl = n.dot(L);
        if (ndl > 0) {
            const lit = power.mul(shadow(hit.p.add(n.scale(EPS)), L, dist));
            // Difusa (Lambert) + especular (Blinn-Phong).
            const half = L.sub(rd).normalize();
            const spec = mt.specular * std.math.pow(f32, @max(0, n.dot(half)), 50);
            sum = sum.add(col.mul(lit).scale(mt.albedo * ndl)).add(lit.scale(spec));
        } else if (mt.translucency > 0) {
            // Translucidez (alabastro): la luz que pega por detrás atraviesa el
            // material y sale por este lado, más débil mientras más grueso es.
            const inner = hit.p.sub(n.scale(EPS));
            const thick = scene.distance(hit.obj, inner, L) orelse continue;
            const lit = power.mul(shadow(inner.add(L.scale(thick + EPS)), L, dist - thick));
            sum = sum.add(col.mul(lit).scale(mt.translucency * @exp(-2.2 * thick) * -ndl));
        }
    }
    return sum;
}

/// Sombras: cuánta luz llega desde `o` hasta la luz. Un objeto opaco la tapa
/// toda; uno transparente la deja pasar teñida de su color (sombra verde de la
/// esmeralda). Los que brillan no tapan porque ellos mismos son la luz.
fn shadow(o: Vec3, L: Vec3, max_dist: f32) Vec3 {
    var light = Vec3.one;
    var origin = o;
    var remaining = max_dist;
    for (0..8) |_| {
        const hit = scene.intersect(origin, L, remaining) orelse return light;
        const mt = mats.get(hit.mat);
        if (mt.emission == 0) {
            if (mt.transparency == 0) return Vec3.zero;
            light = light.mul(mats.sample(hit.mat, hit.u, hit.v).scale(mt.transparency));
        }
        origin = hit.p.add(L.scale(EPS));
        remaining -= hit.t;
    }
    return light;
}

/// Color bleeding: luz que devuelve lo primero que encuentra el rayo d.
/// Se limita a 1 para que los rebotes muy brillantes (sol, reflector) no dejen
/// puntos blancos sueltos.
fn bounce(o: Vec3, d: Vec3) Vec3 {
    var c = sky.sample(d);
    if (scene.intersect(o, d, INF)) |hit| {
        const mt = mats.get(hit.mat);
        const col = mats.sample(hit.mat, hit.u, hit.v);
        const n = if (hit.n.dot(d) > 0) hit.n.neg() else hit.n;
        const solid = @max(0, 1 - mt.transparency - mt.reflectivity);
        c = col.scale(mt.emission).add(directLight(hit, n, d, col).scale(solid));
    }
    return Vec3.init(@min(c.x, 1), @min(c.y, 1), @min(c.z, 1));
}
