# Diorama Panda — Ray Tracing en Zig

Diorama estilo Minecraft con un panda al centro, renderizado con un **ray tracer en CPU** escrito en Zig.
raylib solo se usa para abrir la ventana, leer teclado/mouse y mostrar la imagen; todo el trazado de rayos está hecho a mano.

## Correr

Requiere **Zig 0.14.1**.

```bash
zig build run                      # ventana interactiva (compila en ReleaseFast)
zig build snapshot -- 1920 1080 256  # render en alta calidad -> render.ppm
```

`snapshot` acepta: `ancho alto muestras [yaw] [distancia] [pitch] [n]` (la `n` final = de noche).

> En Linux el `build.zig` fuerza X11 (`linux_display_backend = .X11`). Si tenés `wayland-scanner` instalado podés quitar esa línea.

## Controles

| Tecla | Acción |
|---|---|
| Arrastrar mouse / A D / ← → | Rotar alrededor del diorama |
| ↑ ↓ | Inclinar cámara |
| Rueda / W S | Zoom |
| R | Rotación automática |
| N | Día / noche |
| G | Activar / desactivar color bleeding |
| 1–4 | Resolución interna (320×180 a 960×540) |
| P | Captura (`captura.png`) |
| H | Ocultar HUD |

Mientras la cámara está quieta las muestras se **acumulan** (antialiasing y color bleeding sin ruido).

## Rúbrica

| Punto | Dónde |
|---|---|
| Rotación del diorama | Cámara orbital, `main.zig` + `Camera` en `renderer.zig` |
| Cámara con zoom | `Camera.dist`, rueda / W S |
| Materiales (11) | `scene.zig` → `materials`: pasto, tierra, pelaje blanco, pelaje negro, vidrio, esmeralda, alabastro, glowstone, hierro, agua, bambú. Cada uno con textura propia y `albedo`, `specular`, `transparency`, `reflectivity` |
| Refracción | Vidrio, agua, esmeralda — ley de Snell + Fresnel (Schlick), `tracer.zig` paso 6 |
| Reflexión | Espejo de hierro, agua, esmeralda — `tracer.zig` paso 5 |
| Sombras | Rayos de sombra con transmitancia (`Tracer.shadow`) |
| Skybox | Cubemap de 6 caras (`skybox.zig`), versión de día y de noche |
| Concurrencia | `Renderer.renderSample`: N hilos con contador atómico de filas |
| Material traslúcido | Alabastro: dispersión subsuperficial por grosor `e^(-densidad·grosor)` + refracción esmerilada |
| Forma no vista en clase | Cilindro con tapas (bambú), `Scene.intersectCyl` |
| Luz no vista en clase | Reflector tipo **spotlight** con cono suave (`LightKind.spot`) |
| Translúcidos/reflectivos con color | Esmeralda: absorción Beer-Lambert verde, reflejo teñido y sombra verde. Agua: absorción azul |
| Materiales que brillan | Glowstone: emisión + luz puntual propia |
| Color bleeding | Rebote difuso con muestreo coseno (`Tracer.indirect`), se acumula entre frames |

## Estructura

```
src/
  main.zig       ventana, controles, HUD (raylib)
  renderer.zig   cámara, hilos, acumulación, tone mapping ACES
  tracer.zig     sombreado, sombras, reflexión, refracción, translucidez, GI
  scene.zig      materiales, cubos, cilindros, luces y el diorama
  skybox.zig     cubemap procedural
  textures.zig   texturas 16×16 estilo Minecraft generadas por código
  math.zig       vectores, Snell, Fresnel, aleatorios
  snapshot.zig   render sin ventana a archivo
```
