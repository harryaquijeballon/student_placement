# check_site.R
#
# A fast, deterministic check that runs before anything reaches the public
# repo or the live site. The site is public and names a student, so a mistake
# that is pushed is a mistake that is permanent.
#
# Three modes:
#
#   Rscript scripts/check_site.R privacy [--denylist PATH] [FILES...]
#       Offline. Scans text for personal data and private links.
#       With no FILES, scans every source file and the rendered _site pages.
#
#   Rscript scripts/check_site.R allowlist [FILES...]
#       Offline. Fails if any file is not one the repo is meant to hold, so a
#       stray file from the private workspace cannot slip in.
#
#   Rscript scripts/check_site.R links
#       Online. Requests every external link in _site and reports dead ones.
#       Run it from your own Terminal (the Claude sandbox filters the network).
#
# Every problem prints as one line, "file: rule: match", and any failure makes
# the script exit with status 1, so the pre-commit hook and publish.sh stop.

# ---- Settings: edit here ---------------------------------------------------

# Default list of words that must never appear (surnames, school names).
# It is gitignored, so it never reaches the public repo.
default_denylist <- ".privacy_denylist"

# Files the repo is allowed to hold. Anything else fails the allowlist check.
allowed_files <- c(
  "^_quarto\\.yml$", "^styles\\.css$", "^README\\.md$", "^\\.gitignore$",
  "^manifest\\.json$",
  "^(index|week|resources|glossary|data)\\.qmd$",
  "^contributors/_[a-z0-9_-]+\\.qmd$",
  "^scripts/(check_site\\.R|write_manifest\\.R|publish\\.sh|pre-commit)$",
  "^scripts/fixtures/(bad_page\\.html|denylist_fixture\\.txt)$",
  "^_site/"
)

# Phrases that would identify the student beyond his first name.
identifying_phrases <- c(
  "sixth form", "secondary school", "his school", "my school",
  "university offer", "offer from", "years old", "year-old", "aged [0-9]+",
  "date of birth", "home address"
)

# Hosts that only work inside the organisation, or point at a local disk.
private_link_patterns <- c(
  "sharepoint\\.com", "onedrive", "teams\\.microsoft\\.com", "intranet",
  "file://", "/Users/", "OneDrive-"
)

# The student is not a contributor, so his first name is added here.
extra_first_names <- c("Isaac")

# A browser-like user agent: some sites refuse requests from scripts.
user_agent <- "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

# ---- Helpers -----------------------------------------------------------------

problems <- character(0)

report <- function(file, rule, match) {
  problems <<- c(problems, sprintf("%s: %s: %s", file, rule, match))
}

read_text <- function(path) {
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

# Visible text of an HTML page: drop scripts, styles, comments and tags.
visible_text <- function(html) {
  html <- gsub("(?s)<script.*?</script>", " ", html, perl = TRUE)
  html <- gsub("(?s)<style.*?</style>", " ", html, perl = TRUE)
  html <- gsub("(?s)<!--.*?-->", " ", html, perl = TRUE)
  html <- gsub("<[^>]+>", " ", html)
  html <- gsub("&nbsp;|&#160;", " ", html)
  gsub("[ \t]+", " ", html)
}

# Markdown text without link targets, so DOIs and URLs are not read as
# phone numbers. The links themselves are still checked on the raw text.
markdown_text <- function(md) {
  gsub("\\]\\([^)]*\\)", "]", md)
}

find_all <- function(pattern, text, ignore_case = FALSE) {
  m <- gregexpr(pattern, text, perl = TRUE, ignore.case = ignore_case)
  unique(trimws(regmatches(text, m)[[1]]))
}

# Repo files: tracked and staged files when this folder is a git repo,
# otherwise everything on disk except caches.
repo_files <- function() {
  inside_git <- dir.exists(".git")
  files <- if (inside_git) {
    system2("git", c("ls-files", "--cached", "--others", "--exclude-standard"),
            stdout = TRUE)
  } else {
    list.files(".", recursive = TRUE, all.files = TRUE)
  }
  # Caches and the local files .gitignore keeps out of the repo.
  files[!grepl("^(\\.git/|\\.quarto/|_site/site_libs/|\\.Rproj\\.user/)|^\\.privacy_denylist$|(^|/)\\.DS_Store$|^\\.Rhistory$", files)]
}

# First names of everyone on the site: the "## Name" heading of each
# contributor file, plus the student.
first_names <- function() {
  files <- list.files("contributors", pattern = "^_.*\\.qmd$", full.names = TRUE)
  files <- files[basename(files) != "_template.qmd"]
  headings <- unlist(lapply(files, function(f) {
    sub("^##\\s+", "", grep("^##\\s+\\S", readLines(f, warn = FALSE), value = TRUE)[1])
  }))
  headings <- sub("\\s*\\{[^}]*\\}\\s*$", "", headings)  # drop "{.contributor}"
  unique(c(extra_first_names, trimws(headings)))
}

# ---- Mode: privacy -----------------------------------------------------------

check_privacy <- function(files, denylist_path) {
  denylist <- character(0)
  if (!file.exists(denylist_path)) {
    report(denylist_path, "denylist", "file missing; create it with one surname per line")
  } else {
    denylist <- trimws(readLines(denylist_path, warn = FALSE))
    denylist <- denylist[denylist != "" & !startsWith(denylist, "#")]
  }

  names_on_site <- first_names()
  text_ext <- "\\.(qmd|md|html|yml|yaml|css|json|txt)$"

  # Quarto's bundled libraries (Bootstrap, search) are third-party code, not
  # our content, and their minified digits look like phone numbers.
  files <- files[!grepl("(^|/)site_libs/", files)]

  for (f in files[grepl(text_ext, files)]) {
    raw <- read_text(f)
    text <- if (grepl("\\.html$", f)) visible_text(raw) else markdown_text(raw)

    for (m in find_all("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", raw))
      report(f, "email", m)

    # International (+44 ...) or UK-style (0xx ...) numbers of 10 or more digits.
    phone <- "(\\+[0-9][0-9 ()-]{8,16}[0-9])|(\\b0[0-9]{2,4}[ -]?[0-9]{3,4}[ -]?[0-9]{3,4}\\b)"
    for (m in find_all(phone, text)) report(f, "phone", m)

    # A first name followed, on the same line, by a capitalised word is
    # probably a full name.
    for (n in names_on_site) {
      for (m in find_all(paste0("\\b", n, "[ \\t]+[A-Z][a-z]+"), text)) {
        report(f, "full-name", m)
      }
    }

    for (p in identifying_phrases)
      for (m in find_all(p, text, ignore_case = TRUE)) report(f, "identifying", m)

    for (p in private_link_patterns)
      for (m in find_all(paste0("\\S*", p, "\\S*"), raw, ignore_case = TRUE))
        report(f, "private-link", substr(m, 1, 80))

    for (d in denylist)
      for (m in find_all(paste0("\\b", d, "\\b"), text, ignore_case = TRUE))
        report(f, "denylist", m)
  }
}

# ---- Mode: allowlist ---------------------------------------------------------

check_allowlist <- function(files) {
  ok <- Reduce(`|`, lapply(allowed_files, grepl, x = files), FALSE)
  for (f in files[!ok]) report(f, "allowlist", "file is not expected in this repo")
}

# ---- Mode: links -------------------------------------------------------------

check_links <- function() {
  pages <- list.files("_site", pattern = "\\.html$", full.names = TRUE)
  links <- unique(unlist(lapply(pages, function(p) {
    hrefs <- find_all('href="https?://[^"]+"', read_text(p))
    gsub('^href="|"$', "", hrefs)
  })))
  warnings <- character(0)
  for (url in sort(links)) {
    code <- suppressWarnings(system2(
      "curl", c("-sL", "-o", "/dev/null", "-w", "%{http_code}", "-A",
                shQuote(user_agent), "--max-time", "20", shQuote(url)),
      stdout = TRUE))
    code <- as.integer(code[length(code)])
    if (is.na(code) || code == 0 || code == 404 || code >= 500) {
      report("_site", "dead-link", paste(code, url))
    } else if (code %in% c(401, 403, 429)) {
      warnings <- c(warnings, sprintf("_site: link-warning: %s %s (check in a browser)", code, url))
    }
  }
  if (length(warnings)) message(paste(warnings, collapse = "\n"))
  message(sprintf("Checked %d external links.", length(links)))
}

# ---- Main --------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args)) args[1] else "privacy"
rest <- args[-1]

denylist_path <- default_denylist
if ("--denylist" %in% rest) {
  i <- which(rest == "--denylist")
  denylist_path <- rest[i + 1]
  rest <- rest[-c(i, i + 1)]
}

# Default scan: every repo file except the checker and its deliberately bad fixtures.
default_scan <- function() {
  files <- repo_files()
  files <- files[!grepl("^scripts/", files)]
  c(files, list.files("_site", pattern = "\\.html$", full.names = TRUE))
}

if (mode == "privacy") {
  check_privacy(if (length(rest)) rest else unique(default_scan()), denylist_path)
} else if (mode == "allowlist") {
  check_allowlist(if (length(rest)) rest else repo_files())
} else if (mode == "links") {
  check_links()
} else {
  stop("Unknown mode. Use privacy, allowlist or links.")
}

if (length(problems)) {
  cat(problems, sep = "\n")
  cat(sprintf("\n%d problem(s) found by the %s check.\n", length(problems), mode))
  quit(status = 1)
}
cat(sprintf("%s check passed.\n", mode))
