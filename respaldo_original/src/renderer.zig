//! Cámara orbital + render concurrente con acumulación progresiva.
//! Cada frame se lanza una muestra por píxel repartida entre varios hilos;
//! mientras la cámara no se mueva, las muestras se promedian y la imagen
//! se va limpiando (antialiasing, color bleeding y vidrio esmerilado).
const std = @import("std");
const m = @import("math.zig");
const sc = @import("scene.zig");
const Tracer = @import("tracer.zig").Tracer;
const Settings = @import("tracer.zig").Settings;
const Vec3 = m.Vec3;

pub const Camera = struct {
    target: Vec3 = Vec3.init(0, 0.8, -0.2),
    yaw: f32 = std.math.pi + 0.65, // rotación alrededor del diorama
    pitch: f32 = 0.42,
    dist: f32 = 9.0, // zoom
    fov_deg: f32 = 50,

    pub const MIN_DIST: f32 = 2.5;
    pub const MAX_DIST: f32 = 22.0;

    pub fn eye(self: Camera) Vec3 {
        const cp = @cos(self.pitch);
        return self.target.add(Vec3.init(cp * @sin(self.yaw), @sin(self.pitch), cp * @cos(self.yaw)).scale(self.dist));
    }

    pub fn eql(a: Camera, b: Camera) bool {
        return a.yaw == b.yaw and a.pitch == b.pitch and a.dist == b.dist and a.fov_deg == b.fov_deg;
    }
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    accum: []Vec3,
    pixels: []u8, // RGBA8 listo para subir a una textura
    samples: u32 = 0,
    max_samples: u32 = 2048,
    frame: u32 = 0,
    threads: usize,
    tracer: Tracer,
    exposure: f32 = 1.0,

    // Estado compartido durante un frame.
    next_row: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    eye: Vec3 = Vec3.zero,
    fwd: Vec3 = Vec3.zero,
    right: Vec3 = Vec3.zero,
    up: Vec3 = Vec3.zero,

    pub fn init(allocator: std.mem.Allocator, scene: *const sc.Scene, w: usize, h: usize, cfg: Settings) !Renderer {
        const accum = try allocator.alloc(Vec3, w * h);
        @memset(accum, Vec3.zero);
        const pixels = try allocator.alloc(u8, w * h * 4);
        @memset(pixels, 0);
        return .{
            .allocator = allocator,
            .width = w,
            .height = h,
            .accum = accum,
            .pixels = pixels,
            .threads = @max(1, std.Thread.getCpuCount() catch 4),
            .tracer = .{ .scene = scene, .cfg = cfg },
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.allocator.free(self.accum);
        self.allocator.free(self.pixels);
    }

    pub fn resize(self: *Renderer, w: usize, h: usize) !void {
        self.deinit();
        self.accum = try self.allocator.alloc(Vec3, w * h);
        self.pixels = try self.allocator.alloc(u8, w * h * 4);
        @memset(self.pixels, 0);
        self.width = w;
        self.height = h;
        self.reset();
    }

    /// Se llama cuando la cámara se mueve: se descarta lo acumulado.
    pub fn reset(self: *Renderer) void {
        @memset(self.accum, Vec3.zero);
        self.samples = 0;
    }

    /// Mientras la cámara se mueve no se borra todo: se conserva un poco del
    /// historial (keep muestras) para que el ruido del color bleeding no parpadee.
    pub fn decay(self: *Renderer, keep: u32) void {
        if (self.samples <= keep) return;
        const f = @as(f32, @floatFromInt(keep)) / @as(f32, @floatFromInt(self.samples));
        for (self.accum) |*a| a.* = a.scale(f);
        self.samples = keep;
    }

    pub fn done(self: *const Renderer) bool {
        return self.samples >= self.max_samples;
    }

    /// Agrega una muestra por píxel usando todos los hilos.
    pub fn renderSample(self: *Renderer, cam: Camera) void {
        if (self.done()) return;

        self.eye = cam.eye();
        self.fwd = cam.target.sub(self.eye).normalize();
        self.right = self.fwd.cross(Vec3.init(0, 1, 0)).normalize();
        self.up = self.right.cross(self.fwd);
        const tan_half = @tan(std.math.degreesToRadians(cam.fov_deg) * 0.5);
        const aspect = @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
        self.right = self.right.scale(tan_half * aspect);
        self.up = self.up.scale(tan_half);

        self.samples += 1;
        self.frame +%= 1;
        self.next_row.store(0, .monotonic);

        // CONCURRENCIA: N hilos se reparten las filas con un contador atómico.
        var pool: [64]std.Thread = undefined;
        const n = @min(self.threads, pool.len);
        var spawned: usize = 0;
        for (1..n) |_| {
            pool[spawned] = std.Thread.spawn(.{}, worker, .{self}) catch break;
            spawned += 1;
        }
        worker(self); // el hilo principal también trabaja
        for (pool[0..spawned]) |t| t.join();
    }

    fn worker(self: *Renderer) void {
        const w = self.width;
        const h = self.height;
        const inv_s = 1.0 / @as(f32, @floatFromInt(self.samples));
        while (true) {
            const row = self.next_row.fetchAdd(1, .monotonic);
            if (row >= h) break;
            var rng = m.Rng.init(row *% 9781 +% self.frame *% 6271 +% 1);
            for (0..w) |x| {
                // Jitter dentro del píxel -> antialiasing al acumular.
                const fx = (@as(f32, @floatFromInt(x)) + rng.next()) / @as(f32, @floatFromInt(w));
                const fy = (@as(f32, @floatFromInt(row)) + rng.next()) / @as(f32, @floatFromInt(h));
                const dir = self.fwd
                    .add(self.right.scale(2 * fx - 1))
                    .add(self.up.scale(1 - 2 * fy))
                    .normalize();
                var c = self.tracer.trace(self.eye, dir, 0, null, &rng);
                // Evita "luciérnagas" (muestras extremadamente brillantes).
                c = Vec3.init(@min(c.x, 16), @min(c.y, 16), @min(c.z, 16));
                if (std.math.isNan(c.x) or std.math.isNan(c.y) or std.math.isNan(c.z)) c = Vec3.zero;

                const i = row * w + x;
                self.accum[i] = self.accum[i].add(c);
                const avg = self.accum[i].scale(inv_s * self.exposure);
                self.pixels[i * 4 + 0] = toByte(avg.x);
                self.pixels[i * 4 + 1] = toByte(avg.y);
                self.pixels[i * 4 + 2] = toByte(avg.z);
                self.pixels[i * 4 + 3] = 255;
            }
        }
    }
};

/// Tone mapping ACES + corrección gamma.
fn toByte(x: f32) u8 {
    const a = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
    const g = std.math.pow(f32, m.clamp01(a), 1.0 / 2.2);
    return @intFromFloat(g * 255.0 + 0.5);
}
