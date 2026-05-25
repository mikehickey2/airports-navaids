# Repo identity assets

Visual identity for `airports-navaids`. Three SVG sources, one regeneration
script, and one upload step.

## Files

| File | Purpose | Where it's used |
|---|---|---|
| `readme-header.svg` | 1000 x 300 dark banner | Top of `README.md` via `<img src>` |
| `social-preview.svg` | 1280 x 640 dark banner | Source for the Social Preview PNG |
| `social-preview.png` | Rasterized 1280 x 640 | Uploaded once via GitHub Settings |
| `hex-sticker.svg` | 200 x 231 hex sticker | Hand-authored hex used inline |
| `hex-sticker.png` | Rasterized hex | Laptop stickers, slides, social posts |

## Regenerating the Social Preview PNG

GitHub's Settings page accepts PNG/JPG/GIF only. Rasterize the SVG source:

```bash
brew install librsvg  # one-time
rsvg-convert -w 1280 -h 640 .github/assets/social-preview.svg \
  -o .github/assets/social-preview.png
```

Then upload via **Settings -> General -> Social preview -> Upload an image**.
The upload is a one-time manual step (the `gh` CLI does not cover it).

## Regenerating the README header PNG (optional)

GitHub renders SVG directly in markdown via `<img src>`, so the SVG source
is what `README.md` references. If you ever need a raster fallback (some
RSS readers or third-party clients strip SVG):

```bash
rsvg-convert -w 1000 -h 300 .github/assets/readme-header.svg \
  -o .github/assets/readme-header.png
```

## Regenerating the hex sticker (R hexSticker package)

The hand-authored `hex-sticker.svg` is the canonical version. To produce a
PNG via the R community's `hexSticker` package:

```bash
Rscript -e 'install.packages("hexSticker")'   # one-time, not snapshotted
Rscript -e 'Sys.setenv(REGENERATE_HEX="1"); source("R/generate_hex.R")'
```

`R/generate_hex.R` is gated so it only runs when `REGENERATE_HEX=1` or the
session is interactive. It never runs in CI and `hexSticker` never lands
in `renv.lock`.

## Design system reference

Palette and motifs locked during 2026-05-25 brainstorming:

| Token | Value | Use |
|---|---|---|
| Background | `#0d1117` | Banner background (GitHub native dark) |
| Foreground | `#f0f6fc` | Primary text |
| Muted | `#8b949e` | Tagline, secondary text |
| Accent | `#3fb950` | Accent bar, hex border, GET arrow |
| Code panel | `#161b22` | Code block background |
| Code border | `#21262d` | Code block stroke |
| Hex body | linear-gradient `#1f4e79` -> `#2d5f8d` | Hex sticker fill |

Typography: system sans (`-apple-system, BlinkMacSystemFont, "Segoe UI", ...`)
for headings and tagline; system mono (`ui-monospace, "SF Mono", Menlo, ...`)
for the code snippet. SVG inherits the viewer's installed fonts, so renders
crisply on every platform.
