# p3lu.video-background — Plugin de wallpaper de video (Ruta A)

Superconjunto de `omarchy.background`: pinta la imagen de fondo igual que el
stock (symlink `current/background`, IPC `themeTransition`, transiciones) y, si
el **tema activo** trae `videos/`, reproduce ese clip en **bucle y mudo** sobre
la capa de fondo.

## Estado
- **v0.1.0** — base = `omarchy.background` stock (render de imagen). La rama de
  video se añade en **Fase 2** (ver `../PLAN.md`).

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
- Requiere `QtMultimedia` (Qt6) para la rama de video.
- HW decode por Vulkan (recomendado): `vulkanh264dec`/`vulkanh265dec`.
