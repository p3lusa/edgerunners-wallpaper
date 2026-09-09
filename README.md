# p3lu.video-background — Plugin de wallpaper de video (Ruta A)

Superconjunto de `omarchy.background`: pinta la imagen de fondo igual que el
stock (symlink `current/background`, IPC `themeTransition`, transiciones) y, si
el **tema activo** trae `videos/*.mp4`, reproduce ese clip en **bucle
infinito** sobre la capa de fondo.

## Estado
- **v0.1.0** — base = `omarchy.background` stock (render de imagen).
- **v0.2.0** — rama de video (Fase 2 del plan):
  - Resuelve `videos/*.mp4` del tema activo (`current/theme`).
  - `MediaPlayer` por panel (multi-monitor) + `VideoOutput`
    (`KeepAspectRatioByExpanding`).
  - Fallback a imagen: sin `videos/`, con MP4 corrupto o con error de
    decode → se ve la imagen, nunca pantalla negra.
  - Se re-resuelve el video en cada cambio de fondo/tema (IPC + poll), así
    `omarchy theme set` y `omarchy theme bg next` lo mantienen en sync.

## Instalar (comandos internos de Omarchy)
```bash
omarchy plugin add <este-repo> --enable
omarchy plugin disable omarchy.background   # una vez: ceder la capa de fondo
```

## Desinstalar
```bash
omarchy plugin remove p3lu.video-background --yes
omarchy plugin enable omarchy.background    # restaura el render de imagen stock
```

## Notas
- Usa el mismo `WlrLayer.Background` / namespace `omarchy-background` que el
  stock → **solo uno debe estar activo** (Diseño A, reemplazo).
- **API Qt 6.11 (backend FFmpeg):** `MediaPlayer` usa `loops: -1` (infinito)
  y se enlaza con `videoOutput` (la propiedad `videoSink` de `VideoOutput`
  es read-only). No existe `muted`/`volume` en este backend → **los assets
  deben ser sin pista de audio** (la spec del tema los exige).
- HW decode verificado (AMD 780M, H.264 1080p 30fps): **~3-4% de un núcleo**.
- **Limitación conocida:** el video sigue decodificando con la pantalla
  bloqueada (el lock screen lo cubre). Pausa en lock/idle = iteración futura.
- Si `omarchy refresh shell` se ejecuta, el plugin queda desactivado y el
  escritorio degrada a imagen (seguro). Re-aplicar con:
  ```bash
  omarchy plugin enable p3lu.video-background
  omarchy plugin disable omarchy.background
  ```
  El hook `hooks/post-update` (instalarlo con
  `omarchy hook install post-update <script>`) re-asegura el estado tras
  `omarchy update` cuando el tema activo es `edgerunners`.
