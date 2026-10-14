//! Diorama Minecraft: panda con ray tracing en CPU (Zig + raylib).
//! raylib solo se usa para abrir la ventana, leer el teclado y mostrar la imagen;
//! el ray tracing lo hace nuestro código.
const std = @import("std");
const rl = @import("raylib");
const mats = @import("materials.zig");
const sky = @import("skybox.zig");
const tracer = @import("tracer.zig");
const render = @import("render.zig");

pub fn main() !void {
    mats.generateTextures();
    sky.generate();

    rl.initWindow(render.W * 2, render.H * 2, "Diorama Panda - Ray Tracing");
    defer rl.closeWindow();
    if (!rl.isWindowReady()) return error.NoSePudoAbrirLaVentana;
    rl.setTargetFPS(60);

    // Textura de raylib donde se copia la imagen del ray tracer cada frame.
    const img = rl.genImageColor(render.W, render.H, rl.Color.black);
    const screen = try rl.loadTextureFromImage(img);
    rl.unloadImage(img);
    defer rl.unloadTexture(screen);

    var cam = render.Camera{};
    var auto_rotate = false;
    var bleeding = true;
    var was_moving = false;

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        const before = cam;

        // ─── Controles ───
        if (rl.isKeyDown(.left)) cam.yaw -= 1.5 * dt; // rotación
        if (rl.isKeyDown(.right)) cam.yaw += 1.5 * dt;
        if (rl.isKeyDown(.up)) cam.pitch += 1.0 * dt; // inclinación
        if (rl.isKeyDown(.down)) cam.pitch -= 1.0 * dt;
        if (rl.isKeyDown(.w)) cam.dist -= 6 * dt; // zoom
        if (rl.isKeyDown(.s)) cam.dist += 6 * dt;
        if (rl.isKeyPressed(.r)) auto_rotate = !auto_rotate; // gira solo alrededor del panda
        if (auto_rotate) cam.yaw += 0.5 * dt;
        if (rl.isKeyPressed(.g)) bleeding = !bleeding;
        cam.pitch = std.math.clamp(cam.pitch, -0.2, 1.45);
        cam.dist = std.math.clamp(cam.dist, 2.5, 20);

        // Si la cámara se mueve se empieza a acumular de nuevo. Mientras se mueve
        // se apaga el color bleeding: va más rápido y no se ve ruido.
        const moving = cam.yaw != before.yaw or cam.pitch != before.pitch or cam.dist != before.dist;
        if (moving or was_moving or rl.isKeyPressed(.g)) render.reset();
        was_moving = moving;
        tracer.color_bleeding = bleeding and !moving;

        // ─── Ray tracing ───
        render.renderFrame(cam);
        rl.updateTexture(screen, &render.pixels);

        // ─── Dibujar ───
        rl.beginDrawing();
        defer rl.endDrawing();
        const src = rl.Rectangle{ .x = 0, .y = 0, .width = render.W, .height = render.H };
        const dst = rl.Rectangle{ .x = 0, .y = 0, .width = render.W * 2, .height = render.H * 2 };
        rl.drawTexturePro(screen, src, dst, .{ .x = 0, .y = 0 }, 0, rl.Color.white);
        rl.drawFPS(10, 10);
        rl.drawText("Flechas: rotar/inclinar   W S: zoom   R: girar solo   G: color bleeding", 10, render.H * 2 - 24, 16, rl.Color.white);
    }
}
