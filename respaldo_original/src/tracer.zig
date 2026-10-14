//! El ray tracer: sombras, reflexión, refracción, Fresnel, Beer-Lambert,
//! translucidez (alabastro), emisión y color bleeding (iluminación indirecta).
const std = @import("std");
const m = @import("math.zig");
const tex = @import("textures.zig");
const sky = @import("skybox.zig");
const sc = @import("scene.zig");
const Vec3 = m.Vec3;
const Scene = sc.Scene;
const Hit = sc.Hit;
const EPS = sc.EPS;
const INF = std.math.inf(f32);

pub const Settings = struct {
    max_depth: u32 = 5,
    color_bleeding: bool = true,
    gi_strength: f32 = 1.0,
    shadows: bool = true,
};

pub const Tracer = struct {
    scene: *const Scene,
    cfg: Settings,

    // ─────────────────────── Rayo principal ───────────────────────

    /// medium: material dentro del cual viaja el rayo (null = aire).
    pub fn trace(self: *const Tracer, ro: Vec3, rd: Vec3, depth: u32, medium: ?sc.MatId, rng: *m.Rng) Vec3 {
        const hit = self.scene.intersect(ro, rd, INF) orelse return sky.sample(rd);

        var color = self.shade(hit, rd, depth, medium, rng);

        // Beer-Lambert: si el rayo viajaba dentro de un material con color, se tiñe
        // según la distancia recorrida (por eso la esmeralda se ve verde por dentro).
        if (medium) |md| {
            const a = sc.mat(md).absorption;
            color = color.mul(a.scale(hit.t).expNeg());
        }
        return color;
    }

    fn shade(self: *const Tracer, hit: Hit, rd: Vec3, depth: u32, medium: ?sc.MatId, rng: *m.Rng) Vec3 {
        const mt = sc.mat(hit.mat);
        const tx = tex.get(hit.tex).sample(hit.u, hit.v);
        const col = tx.color;

        var n = hit.n;
        const inside = n.dot(rd) > 0;
        if (inside) n = n.neg();

        var result = Vec3.zero;

        // 1) Emisión (materiales que brillan).
        if (mt.emission > 0 and !inside) result = result.add(col.scale(mt.emission));

        // 2) Pesos de reflexión / refracción con Fresnel.
        const trans = mt.transparency * tx.alpha;
        var kr = mt.reflectivity;
        var kt: f32 = 0;
        const n1: f32 = if (inside) mt.ior else 1.0;
        const n2: f32 = if (inside) 1.0 else mt.ior;
        if (trans > 0) {
            const fres = m.schlick(-rd.dot(n), n1, n2);
            kr += trans * fres;
            kt = trans * (1 - fres);
        }
        const kd = @max(0, 1 - kr - kt);

        // 3) Iluminación local (difusa + especular + sombras + translucidez).
        if (!inside and kd > 0.001) {
            result = result.add(self.directLight(hit, n, rd, col, mt, true).scale(kd));

            // 4) Color bleeding: un rayo indirecto por muestra, se acumula entre frames.
            if (self.cfg.color_bleeding and depth <= 1 and mt.albedo > 0) {
                const gi = self.indirect(hit.p.add(n.scale(EPS)), n, rng);
                result = result.add(col.mul(gi).scale(mt.albedo * kd * self.cfg.gi_strength));
            }
        }

        if (depth >= self.cfg.max_depth) return result;

        // 5) Reflexión.
        if (kr > 0.002) {
            var rdir = m.reflect(rd, n);
            if (mt.roughness > 0) rdir = rdir.add(rng.unitVector().scale(mt.roughness)).normalize();
            if (rdir.dot(n) < 0) rdir = m.reflect(rd, n);
            const rc = self.trace(hit.p.add(n.scale(EPS)), rdir, depth + 1, medium, rng);
            const tint = if (mt.tint_reflection) col else Vec3.one;
            result = result.add(rc.mul(tint).scale(kr));
        }

        // 6) Refracción (ley de Snell). Si hay reflexión total interna, se refleja.
        if (kt > 0.002) {
            if (m.refract(rd, n, n1 / n2)) |tdir_raw| {
                var tdir = tdir_raw;
                if (mt.roughness > 0) tdir = tdir.add(rng.unitVector().scale(mt.roughness)).normalize();
                const next_medium: ?sc.MatId = if (inside) null else hit.mat;
                const tc = self.trace(hit.p.sub(n.scale(EPS)), tdir, depth + 1, next_medium, rng);
                result = result.add(tc.mul(col).scale(kt));
            } else {
                const rc = self.trace(hit.p.add(n.scale(EPS)), m.reflect(rd, n), depth + 1, medium, rng);
                result = result.add(rc.scale(kt));
            }
        }
        return result;
    }

    // ─────────────────────── Luz directa ───────────────────────

    fn directLight(self: *const Tracer, hit: Hit, n: Vec3, rd: Vec3, col: Vec3, mt: *const sc.Material, with_spec: bool) Vec3 {
        const s = self.scene;
        var sum = s.ambient.mul(col).scale(mt.albedo);
        const p = hit.p;
        const origin = p.add(n.scale(EPS));

        for (s.lights[0..s.n_lights]) |light| {
            var L: Vec3 = undefined;
            var dist: f32 = INF;
            var radiance = light.color;

            switch (light.kind) {
                .directional => L = light.dir.neg(),
                .point, .spot => {
                    const d = light.pos.sub(p);
                    dist = d.length();
                    L = d.scale(1 / dist);
                    radiance = radiance.scale(1 / @max(dist * dist, 0.3));
                    if (light.kind == .spot) {
                        // Atenuación suave del cono del reflector.
                        const cos_a = L.neg().dot(light.dir);
                        const f = m.smoothstep(light.cos_outer, light.cos_inner, cos_a);
                        if (f <= 0) continue;
                        radiance = radiance.scale(f);
                    }
                },
            }

            const ndl = n.dot(L);

            // Difusa + especular (Lambert + Blinn-Phong).
            const wrap: f32 = if (mt.translucency > 0) 0.4 else 0;
            const diff = (ndl + wrap) / (1 + wrap);
            if (diff > 0) {
                const T = self.shadow(origin, L, dist);
                if (T.maxComp() > 0) {
                    const lit = radiance.mul(T);
                    sum = sum.add(col.mul(lit).scale(mt.albedo * diff));
                    if (with_spec and ndl > 0 and mt.ks > 0) {
                        const hv = L.sub(rd).normalize();
                        const sp = std.math.pow(f32, @max(0, n.dot(hv)), mt.specular);
                        sum = sum.add(lit.scale(mt.ks * sp));
                    }
                }
            }

            // Translucidez (alabastro): luz que entra por atrás, viaja por dentro
            // y se apaga según el grosor -> e^(-densidad * grosor).
            if (mt.translucency > 0 and ndl < 0.2) {
                const inner = p.sub(n.scale(EPS));
                const thick = s.thicknessInside(hit.obj, inner, L);
                const exit = inner.add(L.scale(thick + EPS));
                const T = self.shadow(exit, L, dist - thick);
                const att = @exp(-mt.density * thick);
                const back = m.clamp01(0.2 - ndl * 0.8);
                sum = sum.add(col.mul(radiance).mul(T).scale(mt.translucency * att * back));
            }
        }
        return sum;
    }

    // ─────────────────────── Sombras ───────────────────────

    /// Transmitancia hacia la luz. Los objetos transparentes dejan pasar luz
    /// teñida de su color (sombras verdes de la esmeralda); los que brillan
    /// no bloquean porque ellos mismos son la luz.
    fn shadow(self: *const Tracer, o: Vec3, L: Vec3, max_dist: f32) Vec3 {
        if (!self.cfg.shadows) return Vec3.one;
        var T = Vec3.one;
        var origin = o;
        var remaining = max_dist;
        var i: u32 = 0;
        while (i < 8) : (i += 1) {
            const hit = self.scene.intersect(origin, L, remaining) orelse return T;
            const mt = sc.mat(hit.mat);
            if (mt.emission <= 0) {
                const tx = tex.get(hit.tex).sample(hit.u, hit.v);
                const trans = mt.transparency * tx.alpha;
                if (trans < 0.05) return Vec3.zero;
                T = T.mul(tx.color.scale(trans));
                if (T.maxComp() < 0.01) return Vec3.zero;
            }
            origin = hit.p.add(L.scale(EPS));
            remaining -= hit.t + EPS;
            if (remaining <= 0) return T;
        }
        return T;
    }

    // ─────────────────────── Color bleeding ───────────────────────

    /// Un rebote difuso: se lanza un rayo en dirección aleatoria (coseno) y se
    /// toma la luz que ESE objeto refleja. Así el pasto pinta de verde la panza
    /// del panda y el glowstone tiñe de naranja lo que tiene cerca.
    fn indirect(self: *const Tracer, o: Vec3, n: Vec3, rng: *m.Rng) Vec3 {
        const d = rng.cosineHemisphere(n);
        const hit = self.scene.intersect(o, d, INF) orelse {
            const sky_c = sky.sample(d);
            return Vec3.init(@min(sky_c.x, 1.5), @min(sky_c.y, 1.5), @min(sky_c.z, 1.5));
        };
        const mt = sc.mat(hit.mat);
        const tx = tex.get(hit.tex).sample(hit.u, hit.v);
        var n2 = hit.n;
        if (n2.dot(d) > 0) n2 = n2.neg();
        var c = tx.color.scale(mt.emission);
        const solid = @max(0, 1 - mt.transparency * tx.alpha - mt.reflectivity);
        c = c.add(self.directLight(hit, n2, d, tx.color, mt, false).scale(solid));
        return c;
    }
};
