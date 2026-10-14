//! Vectores 3D, utilidades y generador aleatorio por hilo.
const std = @import("std");

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub const zero = Vec3{ .x = 0, .y = 0, .z = 0 };
    pub const one = Vec3{ .x = 1, .y = 1, .z = 1 };

    pub inline fn init(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }
    pub inline fn splat(s: f32) Vec3 {
        return .{ .x = s, .y = s, .z = s };
    }
    pub inline fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }
    pub inline fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }
    pub inline fn scale(a: Vec3, s: f32) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }
    /// Multiplicación componente a componente (para colores).
    pub inline fn mul(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x * b.x, .y = a.y * b.y, .z = a.z * b.z };
    }
    pub inline fn dot(a: Vec3, b: Vec3) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }
    pub inline fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }
    pub inline fn length(a: Vec3) f32 {
        return @sqrt(a.dot(a));
    }
    pub inline fn normalize(a: Vec3) Vec3 {
        const l = a.length();
        if (l == 0) return a;
        return a.scale(1.0 / l);
    }
    pub inline fn neg(a: Vec3) Vec3 {
        return .{ .x = -a.x, .y = -a.y, .z = -a.z };
    }
    pub inline fn lerp(a: Vec3, b: Vec3, t: f32) Vec3 {
        return a.scale(1 - t).add(b.scale(t));
    }
    pub inline fn maxComp(a: Vec3) f32 {
        return @max(a.x, @max(a.y, a.z));
    }
    pub inline fn get(a: Vec3, axis: usize) f32 {
        return switch (axis) {
            0 => a.x,
            1 => a.y,
            else => a.z,
        };
    }
    /// e^(-k) por componente (ley de Beer-Lambert).
    pub inline fn expNeg(a: Vec3) Vec3 {
        return .{ .x = @exp(-a.x), .y = @exp(-a.y), .z = @exp(-a.z) };
    }
};

pub inline fn rgb(r: f32, g: f32, b: f32) Vec3 {
    return Vec3.init(r, g, b);
}

/// Convierte un color sRGB (0..1) a espacio lineal para iluminar correctamente.
pub fn srgbToLinear(c: Vec3) Vec3 {
    return .{
        .x = std.math.pow(f32, c.x, 2.2),
        .y = std.math.pow(f32, c.y, 2.2),
        .z = std.math.pow(f32, c.z, 2.2),
    };
}

pub inline fn clamp01(v: f32) f32 {
    return std.math.clamp(v, 0.0, 1.0);
}

pub inline fn smoothstep(e0: f32, e1: f32, x: f32) f32 {
    const t = clamp01((x - e0) / (e1 - e0));
    return t * t * (3 - 2 * t);
}

/// Reflexión de d respecto a la normal n.
pub inline fn reflect(d: Vec3, n: Vec3) Vec3 {
    return d.sub(n.scale(2 * d.dot(n)));
}

/// Refracción (ley de Snell). eta = n1/n2. Devuelve null si hay reflexión total interna.
pub fn refract(d: Vec3, n: Vec3, eta: f32) ?Vec3 {
    const cosi = -d.dot(n);
    const k = 1 - eta * eta * (1 - cosi * cosi);
    if (k < 0) return null;
    return d.scale(eta).add(n.scale(eta * cosi - @sqrt(k))).normalize();
}

/// Aproximación de Schlick para Fresnel.
pub fn schlick(cosi: f32, n1: f32, n2: f32) f32 {
    var r0 = (n1 - n2) / (n1 + n2);
    r0 *= r0;
    const x = 1 - clamp01(cosi);
    return r0 + (1 - r0) * x * x * x * x * x;
}

/// Hash entero -> [0,1). Se usa para las texturas procedurales.
pub fn hash2(x: i32, y: i32, seed: u32) f32 {
    var h: u32 = @as(u32, @bitCast(x)) *% 374761393 +% @as(u32, @bitCast(y)) *% 668265263 +% seed *% 2246822519;
    h = (h ^ (h >> 13)) *% 1274126177;
    h ^= h >> 16;
    return @as(f32, @floatFromInt(h & 0xFFFFFF)) / 16777216.0;
}

/// Generador xorshift, uno por hilo (no se comparte entre hilos).
pub const Rng = struct {
    state: u32,

    pub fn init(seed: u32) Rng {
        var s = seed *% 747796405 +% 2891336453;
        s = ((s >> @as(u5, @intCast((s >> 28) + 4))) ^ s) *% 277803737;
        return .{ .state = if (s == 0) 1 else s };
    }
    pub inline fn next(self: *Rng) f32 {
        var x = self.state;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.state = x;
        return @as(f32, @floatFromInt(x >> 8)) / 16777216.0;
    }
    /// Dirección aleatoria en la esfera unitaria.
    pub fn unitVector(self: *Rng) Vec3 {
        const z = self.next() * 2 - 1;
        const a = self.next() * 2 * std.math.pi;
        const r = @sqrt(@max(0, 1 - z * z));
        return Vec3.init(r * @cos(a), r * @sin(a), z);
    }
    /// Dirección en el hemisferio de n con distribución coseno (para color bleeding).
    pub fn cosineHemisphere(self: *Rng, n: Vec3) Vec3 {
        const d = n.add(self.unitVector());
        if (d.dot(d) < 1e-6) return n;
        return d.normalize();
    }
};
