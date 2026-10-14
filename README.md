# Diorama Panda — Ray Tracing en Zig

Diorama estilo Minecraft con un panda al centro, renderizado con un **ray tracer en CPU** escrito en Zig.
raylib solo se usa para abrir la ventana, leer el teclado y mostrar la imagen; todo el trazado de rayos está hecho a mano.

## Correr

Requiere **Zig 0.14.1**.

```bash
zig build run   # compila en ReleaseFast y abre la ventana
```

> En Linux el `build.zig` fuerza X11 (`linux_display_backend = .X11`).

## Controles

| Tecla | Acción |
|---|---|
| ← → | Rotar alrededor del panda |
| ↑ ↓ | Inclinar cámara |
| W / S | Zoom (acercar / alejar) |
| R | Girar solo alrededor del panda |
| G | Activar / desactivar color bleeding |

Mientras la cámara está quieta los frames se **acumulan** (promedian), así desaparece el ruido.

## Cómo funciona

1. **Cubos** — todo el diorama es una lista de `box(x0, y0, z0, x1, y1, z1, material)` en `scene.zig` (el panda son ~16 cubos). El bambú son cilindros.
2. **Colores** — cada material tiene un color base. Su textura es una cuadrícula de 16×16 píxeles: cada píxel es el color base por un brillo que sale de un patrón (ruido, bordes, manchas…). Ver `materials.zig`.
3. **Rayos** — por cada píxel de la pantalla sale un rayo desde la cámara (`render.zig`). Se busca el cubo más cercano que toca (`scene.intersect`), se lee el color de la textura en ese punto y se ilumina (`tracer.zig`).
4. **Si no toca nada** — se toma el color del cielo (`skybox.zig`).

## Rúbrica

| Punto | Dónde |
|---|---|
| Rotación del diorama | Cámara orbital (`Camera` en `render.zig`), flechas y tecla R |
| Cámara con zoom | `Camera.dist`, teclas W / S |
| Materiales (9) | `materials.zig`: pasto, tierra, pelaje blanco, pelaje negro, esmeralda, alabastro, glowstone, hierro, bambú. Cada uno con textura propia y `albedo`, `specular`, `transparency`, `reflectivity` |
| Refracción | Esmeralda y alabastro — ley de Snell + Fresnel, `tracer.zig` paso 6 |
| Reflexión | Espejo de hierro y esmeralda — `tracer.zig` paso 5 |
| Sombras | Rayos de sombra hacia cada luz (`shadow` en `tracer.zig`) |
| Skybox | Cubemap de 6 caras (`skybox.zig`) |
| Concurrencia | `renderFrame` en `render.zig`: un hilo por núcleo con contador atómico de filas |
| Material traslúcido | Alabastro: la luz de atrás lo atraviesa y se apaga con el grosor `e^(-2.2·grosor)` |
| Forma no vista en clase | Cilindro con tapas (bambú), `hitCyl` en `scene.zig` |
| Luz no vista en clase | Reflector tipo **spotlight** con cono (`.spot` en `scene.zig`) |
| Translúcidos/reflectivos con color | Esmeralda: por dentro absorbe rojo y azul (Beer-Lambert), reflejo verde y sombra verde |
| Materiales que brillan | Glowstone: emisión + luz puntual propia |
| Color bleeding | Rebote difuso al azar (`bounce` en `tracer.zig`), tecla G para compararlo |

## Estructura

```
src/
  main.zig        ventana y teclas (raylib)
  render.zig      cámara, hilos y acumulación
  tracer.zig      color de un rayo: luces, sombras, reflexión, refracción, translucidez, color bleeding
  scene.zig       cubos, cilindros, luces y el diorama
  materials.zig   materiales y texturas 16×16
  skybox.zig      cubemap del cielo
  math.zig        vectores, Snell, Fresnel, aleatorios
```
