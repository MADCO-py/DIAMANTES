//! Vectores 3D, fórmulas de óptica y números aleatorios.
const std = @import("std");

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub const zero = Vec3{ .x = 0, .y = 0, .z = 0 };
    pub const one = Vec3{ .x = 1, .y = 1, .z = 1 };

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }
    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }
    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }
    pub fn scale(a: Vec3, s: f32) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }
    /// Multiplicación componente a componente (se usa para mezclar colores).
    pub fn mul(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x * b.x, .y = a.y * b.y, .z = a.z * b.z };
    }
    pub fn dot(a: Vec3, b: Vec3) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }
    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.y * b.z - a.z * b.y, .y = a.z * b.x - a.x * b.z, .z = a.x * b.y - a.y * b.x };
    }
    pub fn length(a: Vec3) f32 {
        return @sqrt(a.dot(a));
    }
    pub fn normalize(a: Vec3) Vec3 {
        return a.scale(1 / a.length());
    }
    pub fn neg(a: Vec3) Vec3 {
        return a.scale(-1);
    }
    pub fn lerp(a: Vec3, b: Vec3, t: f32) Vec3 {
        return a.scale(1 - t).add(b.scale(t));
    }
    /// Componente 0 = x, 1 = y, 2 = z.
    pub fn get(a: Vec3, axis: usize) f32 {
        return switch (axis) {
            0 => a.x,
            1 => a.y,
            else => a.z,
        };
    }
    pub fn set(a: *Vec3, axis: usize, v: f32) void {
        switch (axis) {
            0 => a.x = v,
            1 => a.y = v,
            else => a.z = v,
        }
    }
};

/// Color escrito "como en un editor de imágenes" (0..1) convertido a luz lineal.
pub fn srgb(r: f32, g: f32, b: f32) Vec3 {
    return Vec3.init(std.math.pow(f32, r, 2.2), std.math.pow(f32, g, 2.2), std.math.pow(f32, b, 2.2));
}

/// Reflexión: d rebota en la superficie con normal n.
pub fn reflect(d: Vec3, n: Vec3) Vec3 {
    return d.sub(n.scale(2 * d.dot(n)));
}

/// Refracción con la ley de Snell. eta = n1 / n2.
/// Devuelve null si hay reflexión total interna.
pub fn refract(d: Vec3, n: Vec3, eta: f32) ?Vec3 {
    const cosi = -d.dot(n);
    const k = 1 - eta * eta * (1 - cosi * cosi);
    if (k < 0) return null;
    return d.scale(eta).add(n.scale(eta * cosi - @sqrt(k)));
}

/// Fresnel (aproximación de Schlick): qué fracción de luz se refleja
/// según el ángulo. De frente casi todo pasa, de costado casi todo rebota.
pub fn fresnel(cosi: f32, n1: f32, n2: f32) f32 {
    const r0 = std.math.pow(f32, (n1 - n2) / (n1 + n2), 2);
    return r0 + (1 - r0) * std.math.pow(f32, 1 - std.math.clamp(cosi, 0, 1), 5);
}

/// Número pseudoaleatorio en [0,1) a partir de dos enteros (siempre da lo mismo
/// para los mismos números). Con esto se "pintan" las texturas y las nubes.
pub fn hash(x: i32, y: i32, seed: u32) f32 {
    var h: u32 = @as(u32, @bitCast(x)) *% 374761393 +% @as(u32, @bitCast(y)) *% 668265263 +% seed *% 2246822519;
    h = (h ^ (h >> 13)) *% 1274126177;
    h ^= h >> 16;
    return @as(f32, @floatFromInt(h & 0xFFFFFF)) / 16777216.0;
}

/// Generador aleatorio xorshift. Cada hilo tiene el suyo.
pub const Rng = struct {
    state: u32,

    pub fn next(self: *Rng) f32 {
        self.state ^= self.state << 13;
        self.state ^= self.state >> 17;
        self.state ^= self.state << 5;
        return @as(f32, @floatFromInt(self.state >> 8)) / 16777216.0;
    }
    /// Dirección aleatoria uniforme sobre la esfera.
    pub fn unitVector(self: *Rng) Vec3 {
        const z = self.next() * 2 - 1;
        const a = self.next() * 2 * std.math.pi;
        const r = @sqrt(1 - z * z);
        return Vec3.init(r * @cos(a), r * @sin(a), z);
    }
};
