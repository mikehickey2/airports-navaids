# generate_hex.R
# Dev-only generator for the airports-navaids hex sticker PNG.
#
# This script is intentionally NOT part of the runtime pipeline. It is gated
# so it never runs in CI and the hexSticker package never lands in the
# runtime path. To regenerate the hex sticker:
#
#   Rscript -e 'Sys.setenv(REGENERATE_HEX = "1"); source("R/generate_hex.R")'
#
# Or in an interactive session:
#
#   source("R/generate_hex.R")
#
# Requirements (install ad hoc, do not snapshot into renv.lock):
#
#   install.packages("hexSticker")
#
# A hand-authored SVG version of the same hex lives at
# .github/assets/hex-sticker.svg and is what the README references. Running
# this script overwrites .github/assets/hex-sticker.png with a PNG generated
# by the hexSticker package, which is the format expected by environments
# that need rasterized output (laptop stickers, slide decks, social posts).

is_regen_run <- interactive() || nzchar(Sys.getenv("REGENERATE_HEX"))

if (!is_regen_run) {
  message(
    "generate_hex.R sourced non-interactively without REGENERATE_HEX=1; ",
    "skipping. This is expected during normal pipeline runs."
  )
} else {
  if (!requireNamespace("hexSticker", quietly = TRUE)) {
    stop(
      "hexSticker is not installed. Install it with ",
      "install.packages(\"hexSticker\") before regenerating."
    )
  }

  output_path <- ".github/assets/hex-sticker.png"

  hexSticker::sticker(
    subplane <- function() {
      grid::grid.text("✈", gp = grid::gpar(fontsize = 96, col = "white"))
    },
    package = "airports\nnavaids",
    p_size = 18,
    p_y = 1.45,
    p_color = "#ffffff",
    s_x = 1.0,
    s_y = 0.85,
    s_width = 1.2,
    s_height = 1.0,
    h_fill = "#1f4e79",
    h_color = "#3fb950",
    h_size = 1.8,
    url = "FAA · NASR",
    u_color = "#a8c8e8",
    u_size = 5,
    filename = output_path,
    dpi = 600
  )

  message("Wrote ", output_path)
}
