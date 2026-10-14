//! Diorama Minecraft: panda con ray tracing en CPU (Zig + raylib).
//! raylib solo se usa para la ventana, el teclado/mouse y mostrar la imagen.
//! Todo el ray tracing está en tracer.zig / scene.zig.
const std = @import("std");
const rl = @import("raylib");
const tex = @import("textures.zig");
const sky = @import("skybox.zig");
const sc = @import("scene.zig");
const R = @import("renderer.zig");

const WIN_W = 1280;
const WIN_H = 720;

const Res = struct { w: usize, h: usize };
const resolutions = [_]Res{
    .{ .w = 320, .h = 180 },
    .{ .w = 480, .h = 270 },
    .{ .w = 640, .h = 360 },
    .{ .w = 960, .h = 540 },
};


/// Algunas versiones de raylib-zig devuelven error union en loadTextureFromImage y otras no.
fn makeTexture(w: usize, h: usize) !rl.Texture2D {
    const img = rl.genImageColor(@intCast(w), @intCast(h), rl.Color.black);
    defer rl.unloadImage(img);
    const result = rl.loadTextureFromImage(img);
    const t = if (@typeInfo(@TypeOf(result)) == .error_union) try result else result;
    rl.setTextureFilter(t, .point); // pixeles nítidos, estilo Minecraft
    return t;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Preparación: texturas, escena y skybox.
    tex.generateAll();
    var scene = sc.build();
    sky.generate(scene.sun_dir, scene.night);

    var res_idx: usize = 1;
    var renderer = try R.Renderer.init(alloc, &scene, resolutions[res_idx].w, resolutions[res_idx].h, .{});
    defer renderer.deinit();

    rl.initWindow(WIN_W, WIN_H, "Diorama Panda - Ray Tracing (Zig)");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var screen = try makeTexture(renderer.width, renderer.height);
    defer rl.unloadTexture(screen);

    var cam = R.Camera{};
    var auto_rotate = false;
    var show_hud = true;
    var buf: [256]u8 = undefined;

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        const prev = cam;
        var hard_reset = false;

        // ───── Rotación del diorama (cámara orbital) ─────
        if (rl.isMouseButtonDown(.left)) {
            const d = rl.getMouseDelta();
            cam.yaw -= d.x * 0.008;
            cam.pitch += d.y * 0.006;
        }
        if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) cam.yaw += 1.6 * dt;
        if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) cam.yaw -= 1.6 * dt;
        if (rl.isKeyDown(.up)) cam.pitch += 1.0 * dt;
        if (rl.isKeyDown(.down)) cam.pitch -= 1.0 * dt;
        if (rl.isKeyPressed(.r)) auto_rotate = !auto_rotate;
        if (auto_rotate) cam.yaw += 0.5 * dt;
        cam.pitch = std.math.clamp(cam.pitch, -0.2, 1.45);

        // ───── Zoom ─────
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) cam.dist *= std.math.pow(f32, 0.9, wheel);
        if (rl.isKeyDown(.w)) cam.dist *= 1 - 1.2 * dt;
        if (rl.isKeyDown(.s)) cam.dist *= 1 + 1.2 * dt;
        cam.dist = std.math.clamp(cam.dist, R.Camera.MIN_DIST, R.Camera.MAX_DIST);

        // ───── Opciones ─────
        if (rl.isKeyPressed(.n)) {
            scene.setNight(!scene.night);
            sky.generate(scene.sun_dir, scene.night);
            hard_reset = true;
        }
        if (rl.isKeyPressed(.g)) {
            renderer.tracer.cfg.color_bleeding = !renderer.tracer.cfg.color_bleeding;
            hard_reset = true;
        }
        if (rl.isKeyPressed(.h)) show_hud = !show_hud;
        if (rl.isKeyPressed(.p)) rl.takeScreenshot("captura.png");
        const keys = [_]rl.KeyboardKey{ .one, .two, .three, .four };
        for (keys, 0..) |k, i| {
            if (rl.isKeyPressed(k) and i != res_idx) {
                res_idx = i;
                try renderer.resize(resolutions[i].w, resolutions[i].h);
                rl.unloadTexture(screen);
                screen = try makeTexture(renderer.width, renderer.height);
            }
        }

        if (hard_reset) {
            renderer.reset();
        } else if (!cam.eql(prev)) {
            renderer.decay(2);
        }

        // ───── Ray tracing (concurrente) ─────
        renderer.renderSample(cam);
        rl.updateTexture(screen, renderer.pixels.ptr);

        // ───── Dibujar ─────
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);
        const src = rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(renderer.width), .height = @floatFromInt(renderer.height) };
        const dst = rl.Rectangle{ .x = 0, .y = 0, .width = WIN_W, .height = WIN_H };
        rl.drawTexturePro(screen, src, dst, .{ .x = 0, .y = 0 }, 0, rl.Color.white);

        if (show_hud) {
            rl.drawRectangle(10, 10, 370, 196, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 150 });
            rl.drawFPS(20, 18);
            const info = std.fmt.bufPrintZ(&buf, "Muestras: {d}   Hilos: {d}\nResolucion: {d}x{d}", .{
                renderer.samples, renderer.threads, renderer.width, renderer.height,
            }) catch "";
            rl.drawText(info, 20, 44, 18, rl.Color.white);
            const opts = std.fmt.bufPrintZ(&buf, "Auto-rotar [R]: {s}   Noche [N]: {s}\nColor bleeding [G]: {s}", .{
                if (auto_rotate) "si" else "no",
                if (scene.night) "si" else "no",
                if (renderer.tracer.cfg.color_bleeding) "si" else "no",
            }) catch "";
            rl.drawText(opts, 20, 92, 18, rl.Color.light_gray);
            rl.drawText("Arrastrar / A D flechas: rotar\nRueda / W S: zoom   1-4: resolucion\nP: captura   H: ocultar", 20, 140, 16, rl.Color.gray);
        }
    }
}
