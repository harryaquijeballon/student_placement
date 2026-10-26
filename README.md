# Economics at GSMA Intelligence: student placement site

A small Quarto website for a one-week student work placement at GSMA Intelligence. It answers one question: what does it mean to be an economist at GSMA Intelligence? It is published on Posit Connect Cloud from the `main` branch of this repo.

## Pages

| Page | File |
|---|---|
| Economics at GSMA (home) | `index.qmd` |
| The week | `week.qmd` |
| Economic resources | `resources.qmd`, which includes one file per contributor from `contributors/` |
| Toolkit: glossary | `glossary.qmd` |
| Toolkit: public data | `data.qmd` |

## Ground rules

This site and its repo are public.

- First names only. No surnames, photos, emails or phone numbers.
- No internal or unpublished figures. Link to public sources instead of quoting numbers.
- No logos until approved.

The checks below enforce the first rule and the file list. The second rule needs a human read.

## One-time setup

1. Create `.privacy_denylist` in the repo root, with one surname (or other word that must never appear) per line. It is gitignored and never leaves your machine.
2. Install the pre-commit hook:

   ```bash
   cp scripts/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
   ```

3. In R, install rsconnect once: `install.packages("rsconnect")`.

## Add a colleague's recommendations

1. Copy `contributors/_template.qmd` to `contributors/_firstname.qmd` (lower case, keep the leading underscore) and paste in their answers.
2. Add one line to `resources.qmd`, after the existing ones:

   ```
   {{< include contributors/_firstname.qmd >}}
   ```

3. Publish (below).

## Publish

```bash
bash scripts/publish.sh                 # render, privacy check, allowlist check, manifest
Rscript scripts/check_site.R links      # check external links (needs internet)
git add -A && git commit -m "..." && git push
```

Connect Cloud republishes automatically when `main` changes. Some sites (gsma.com, JSTOR) refuse automated requests, so the link check reports them as warnings to open in a browser, not as failures.

## Preview locally

```bash
quarto preview
```

If `quarto` is not on your PATH, use the copy bundled with RStudio: `/Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto`.
