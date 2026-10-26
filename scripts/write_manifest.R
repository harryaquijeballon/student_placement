# write_manifest.R: write manifest.json, the file list Posit Connect Cloud
# reads to publish the site. Run after rendering; publish.sh calls it.
# The manifest holds a checksum per file, so it must be rewritten after
# every render or Connect Cloud sees stale content.

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("rsconnect is not installed. In R, run: install.packages('rsconnect')")
}

# Site sources plus the rendered site. Scripts and fixtures are not needed
# to serve the site, so they stay out of the manifest.
files <- c(
  list.files(".", pattern = "[.](qmd|yml|css)$"),
  list.files("contributors", full.names = TRUE),
  list.files("_site", recursive = TRUE, full.names = TRUE)
)

rsconnect::writeManifest(
  appDir = ".",
  appFiles = files,
  appPrimaryDoc = "index.qmd",
  quarto = TRUE  # rsconnect finds Quarto through QUARTO_PATH, set in publish.sh
)
