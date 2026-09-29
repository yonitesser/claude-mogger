#!/usr/bin/env bash
# a11y.sh — static accessibility + mobile check over HTML / JSX / TSX / Vue /
# Svelte / template files. REPORT-ONLY: never modifies the project. Always exits 0.
#
# Everything here is a STATIC heuristic: it reads source text, it does not
# render the page. Tap-target size (44px) and colour contrast are NOT
# statically knowable: run axe / Lighthouse (scripts/a11y-browser.mjs runs axe
# at 375px when playwright + axe-core are already installed).
#
# Usage (from project root):  bash scripts/checks/a11y.sh [project-dir]
# Output: one line per finding  LEVEL|check-id|message   (PASS WARN FAIL SKIP)
set -u
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { printf 'SKIP|a11y-img-alt|cannot cd to %s\n' "$ROOT"; exit 0; }
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t mogger)
[ -n "$TMP" ] && [ -d "$TMP" ] || { printf 'SKIP|a11y-img-alt|no temp dir available\n'; exit 0; }
trap 'rm -rf "$TMP"' EXIT

out() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }

find . \( -name node_modules -o -name .git -o -name dist -o -name build -o -name venv -o -name .venv \
  -o -name __pycache__ -o -name .next -o -name coverage -o -name .claude -o -name target -o -name vendor \
  -o -name .cache \) -prune -o -type f -print 2>/dev/null | sed 's|^\./||' | head -8000 > "$TMP/all"
: > "$TMP/tsl"; : > "$TMP/markup"; : > "$TMP/css"; : > "$TMP/jscand"; : > "$TMP/styled"
while IFS= read -r f; do
  case "$f" in
    *.min.js|*.min.css|*.map) continue;;
    */test/*|*/tests/*|*/__tests__/*|*.test.*|*.spec.*|*/fixtures/*) continue;;
  esac
  case "$f" in
    *.html|*.htm|*.jsx|*.tsx|*.vue|*.svelte|*.astro|*.erb|*.ejs|*.hbs|*.njk|*.twig|*.php|*.liquid|*.jinja|*.j2|*.mustache) printf '%s\n' "$f" >> "$TMP/markup";;
    *.js|*.mjs) printf '%s\n' "$f" >> "$TMP/jscand";;
    *.ts) printf '%s\n' "$f" >> "$TMP/tsl";;
  esac
  case "$f" in
    *.css|*.scss|*.sass|*.less|*.html|*.htm|*.vue|*.svelte|*.astro) printf '%s\n' "$f" >> "$TMP/css";;
  esac
done < "$TMP/all"
# plain .js files count as markup only if they look like React code
if [ -s "$TMP/jscand" ]; then
  tr '\n' '\0' < "$TMP/jscand" | xargs -0 grep -l -I -E -e "from .react.|require[(].react.[)]|React[.]createElement" -- 2>/dev/null >> "$TMP/markup"
fi
NM=$(wc -l < "$TMP/markup" | tr -d ' ')
NC=$(wc -l < "$TMP/css" | tr -d ' ')

scan() {  # scan <listfile> <ere>  -> file:line:text (case-insensitive)
  [ -s "$1" ] || return 0
  tr '\n' '\0' < "$1" | xargs -0 grep -H -n -I -i -E -e "$2" -- 2>/dev/null | head -300
}
cite() {
  awk -F: '{ n++; if (n <= 3) s = s (n > 1 ? ", " : "") $1 ":" $2 } END { if (n > 3) s = s " (+" (n - 3) " more)"; print s }'
}

# ---- awk: tag-level parser (handles multi-line tags, JSX {..} and quotes) ---
cat > "$TMP/tags.awk" <<'AWK'
function hasattr(t, name) {
  return (t ~ ("[[:space:]:[]" name "[]]?[[:space:]]*=") || t ~ ("[[:space:]]" name "([[:space:]]|/?>|$)"))
}
function attrval(t, o, name,    s, q, e, r) {
  if (!match(t, "[[:space:]:[]" name "[]]?[[:space:]]*=[[:space:]]*")) return ""
  s = RSTART + RLENGTH
  q = substr(o, s, 1)
  if (q == "\"" || q == "'") { r = substr(o, s + 1); e = index(r, q); if (e == 0) return ""; return substr(r, 1, e - 1) }
  if (q == "{") return "{dynamic}"
  r = substr(o, s); e = match(r, /[[:space:]>]/)
  if (e == 0) return r
  return substr(r, 1, e - 1)
}
function bad(chk, ln, msg) { print "B|" chk "|" F ":" ln "|" msg }
function seen(chk) { print "S|" chk }
BEGIN {
  WANT["img"] = 1; WANT["image"] = 1; WANT["input"] = 1; WANT["select"] = 1; WANT["textarea"] = 1
  WANT["button"] = 1; WANT["a"] = 1; WANT["html"] = 1; WANT["meta"] = 1; WANT["div"] = 1; WANT["span"] = 1; WANT["label"] = 1
  nl = 0; nin = 0; sawhtml = 0; sawvp = 0
}
{ all = all $0 "\n" }
END {
  n = length(all); lall = tolower(all); line = 1; intag = 0
  for (i = 1; i <= n; i++) {
    c = substr(all, i, 1)
    if (!intag) {
      if (c == "\n") { line++; continue }
      if (c != "<") continue
      j = i + 1; name = ""
      while (j <= n) { d = substr(all, j, 1); if (d ~ /[[:alnum:]._:-]/) { name = name d; j++ } else break }
      if (name == "") continue
      ln = tolower(name)
      if (!(ln in WANT)) continue
      intag = 1; tstart = i; tline = line; depth = 0; q = ""; tname = name; lname = ln
      continue
    }
    if (c == "\n") line++
    if (i - tstart > 2500) { intag = 0; i = tstart; line = tline; continue }
    if (q != "") { if (c == q) q = ""; continue }
    if (c == "\"" || c == "'" || c == "`") { q = c; continue }
    if (c == "{") { depth++; continue }
    if (c == "}") { depth--; continue }
    if (c != ">" || depth > 0) continue
    # ---- a complete opening tag ends at i ----
    intag = 0
    tag = substr(all, tstart, i - tstart + 1)
    gsub(/[\n\t]/, " ", tag)
    tl = tolower(tag)
    spread = (tag ~ /[{][[:space:]]*[.][.][.]/)
    selfclose = (substr(tag, length(tag) - 1) == "/>")

    if (lname == "img" || (lname == "image" && tname == "Image")) {
      seen("img-alt")
      if (!hasattr(tl, "alt") && !spread && tl !~ /aria-hidden[[:space:]]*=[[:space:]]*.?true/ && tl !~ /role[[:space:]]*=[[:space:]]*.?(presentation|none)/)
        bad("img-alt", tline, "<" tname "> has no alt attribute (use alt=\"\" if purely decorative)")
    } else if (lname == "label") {
      p = index(substr(lall, i + 1, 4000), "</label")
      nl++; ls[nl] = tstart; le[nl] = (p > 0 ? i + p : 0)
      v = attrval(tl, tag, "for"); if (v == "") v = attrval(tl, tag, "htmlfor")
      if (v != "") LF[tolower(v)] = 1
    } else if ((lname == "input" || lname == "select" || lname == "textarea") && tname == lname) {
      ty = tolower(attrval(tl, tag, "type"))
      if (ty == "hidden" || ty == "submit" || ty == "button" || ty == "reset" || ty == "image") continue
      seen("form-labels")
      if (spread || hasattr(tl, "aria-label") || hasattr(tl, "aria-labelledby") || hasattr(tl, "title")) continue
      wrapped = 0
      for (k = 1; k <= nl; k++) if (le[k] > 0 && tstart > ls[k] && tstart < le[k]) wrapped = 1
      if (wrapped) continue
      id = attrval(tl, tag, "id")
      if (substr(id, 1, 1) == "{") continue
      nin++; iln[nin] = tline; iid[nin] = tolower(id); itag[nin] = tname
    } else if ((lname == "button" && (tname == "button" || tname == "Button")) || (lname == "a" && tname == "a")) {
      if (lname == "a" && !hasattr(tl, "href")) continue
      if (spread || hasattr(tl, "aria-label") || hasattr(tl, "aria-labelledby") || hasattr(tl, "title")) { seen("icon-buttons"); continue }
      if (selfclose) inner = ""
      else {
        p = index(substr(lall, i + 1, 1500), "</" lname)
        if (p == 0) continue
        inner = substr(all, i + 1, p - 1)
      }
      seen("icon-buttons")
      il = tolower(inner)
      if (il ~ /alt[[:space:]]*=[[:space:]]*.[^"']/ || il ~ /<title>/ || il ~ /aria-label/ ) continue
      if (inner ~ /[{]/) continue
      gsub(/<[^>]*>/, "", inner); gsub(/&nbsp;/, "", inner); gsub(/[[:space:]]/, "", inner)
      if (inner == "") bad("icon-buttons", tline, "<" tname "> has no text and no aria-label (icon-only)")
    } else if (lname == "html") {
      seen("html-lang"); sawhtml = tline
      if (!hasattr(tl, "lang") && !spread) bad("html-lang", tline, "<html> has no lang attribute")
    } else if (lname == "meta") {
      if (tl ~ /name[[:space:]]*=[[:space:]]*.?viewport/) sawvp = 1
    } else if ((lname == "div" || lname == "span") && tname == lname) {
      if (tl ~ /[[:space:]](onclick|@click[[:alnum:].]*|v-on:click[[:alnum:].]*|on:click[[:alnum:]|]*|[(]click[)]|x-on:click[[:alnum:].]*)[[:space:]]*=/) {
        seen("clickable")
        if (spread) continue
        miss = ""
        if (!hasattr(tl, "role")) miss = miss "role, "
        if (!hasattr(tl, "tabindex")) miss = miss "tabIndex, "
        if (tl !~ /(onkeydown|onkeyup|onkeypress|@keydown|@keyup|@keypress|on:keydown|on:keyup|[(]keydown|[(]keyup|v-on:key|@key)/) miss = miss "keyboard handler, "
        if (miss != "") bad("clickable", tline, "<" tname "> has a click handler but no " substr(miss, 1, length(miss) - 2) " (not keyboard/screen-reader operable; use <button>)")
      }
    }
  }
  for (k = 1; k <= nin; k++) {
    if (iid[k] != "" && (iid[k] in LF)) continue
    bad("form-labels", iln[k], "<" itag[k] "> has no <label> wrapping it, no matching for/id, and no aria-label" (iid[k] != "" ? " (id=" iid[k] " has no <label for>)" : ""))
  }
  if (sawhtml) {
    seen("viewport")
    if (!sawvp && VPREQ == 1) bad("viewport", sawhtml, "no <meta name=viewport> in this HTML entrypoint: phones render it as a shrunken desktop page")
  }
}
AWK

# ---- awk: CSS rule parser for outline removal / focus replacement -----------
cat > "$TMP/css.awk" <<'AWK'
END {
  n = length(all); line = 1; inb = 0; cur = ""; block = ""
  for (i = 1; i <= n; i++) {
    c = substr(all, i, 1)
    if (c == "\n") line++
    if (c == "{") { if (inb) selt = block; else selt = cur; cur = ""; block = ""; inb = 1; bline = line; continue }
    if (c == "}") {
      if (inb) {
        tb = tolower(block); ts = tolower(selt)
        hasrepl = (tb ~ /box-shadow|border|background|text-decoration|ring|outline[[:space:]]*:[[:space:]]*[^;]*(solid|dashed|auto|[1-9][0-9]*px)/)
        if (tb ~ /outline(-style)?[[:space:]]*:[[:space:]]*(none|0)([^.[:alnum:]]|$)/ || tb ~ /outline-width[[:space:]]*:[[:space:]]*0/) {
          print "S|focus"
          gsub(/[[:space:]]+/, " ", selt); sub(/^ /, "", selt)
          if (!(ts ~ /:focus/ && hasrepl)) print "B|focus|" F ":" bline "|'" substr(selt, 1, 60) "' removes the focus outline and adds no replacement focus style"
        } else if (ts ~ /:focus/ && tb ~ /box-shadow|border|outline[[:space:]]*:[[:space:]]*[^;]*(solid|dashed|auto|[1-9][0-9]*px)|ring/) {
          print "R|" F ":" bline
        }
      }
      inb = 0; cur = ""; block = ""; continue
    }
    if (inb) block = block c; else cur = cur c
  }
}
{ all = all $0 "\n" }
AWK

if [ "$NM" -eq 0 ] && [ "$NC" -eq 0 ]; then
  for id in img-alt form-labels icon-buttons html-lang viewport zoom focus clickable fixed-width; do
    out SKIP "a11y-$id" "no HTML/JSX/TSX/Vue/Svelte/template/CSS files found"
  done
  out SKIP a11y-tap-targets "tap-target size is not statically knowable: run axe/Lighthouse (scripts/a11y-browser.mjs)"
  exit 0
fi

# does any file in the project declare a viewport meta?
VPANY=$(scan "$TMP/markup" 'name=.?viewport|viewport[[:space:]]*[:=]|export const viewport|generateViewport' | head -1)
: > "$TMP/res"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  sz=$(wc -c < "$f" | tr -d ' ')
  [ "${sz:-0}" -gt 300000 ] && continue
  vpreq=0
  case "$f" in
    *.html|*.htm) vpreq=1;;
    *layout.tsx|*layout.jsx|*layout.js) vpreq=0;;
    *) [ -z "$VPANY" ] && vpreq=1;;
  esac
  awk -v F="$f" -v VPREQ="$vpreq" -f "$TMP/tags.awk" "$f" >> "$TMP/res" 2>/dev/null
done < "$TMP/markup"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  sz=$(wc -c < "$f" | tr -d ' ')
  [ "${sz:-0}" -gt 300000 ] && continue
  awk -v F="$f" -f "$TMP/css.awk" "$f" >> "$TMP/res" 2>/dev/null
done < "$TMP/css"

# report <id> <what-was-checked> : uses S| and B| lines
report() {
  local id="$1" what="$2" nseen nbad
  nseen=$(grep -c "^S|$id\$" "$TMP/res")
  nbad=$(grep -c "^B|$id|" "$TMP/res")
  if [ "$nbad" -gt 0 ]; then
    grep "^B|$id|" "$TMP/res" | head -6 | awk -F'|' -v id="a11y-$id" '{ printf "WARN|%s|%s at %s [heuristic]\n", id, $4, $3 }'
    [ "$nbad" -gt 6 ] && out WARN "a11y-$id" "... and $((nbad-6)) more of the same"
  elif [ "$nseen" -gt 0 ]; then
    out PASS "a11y-$id" "$nseen $what checked, none flagged (static heuristic)"
  else
    out SKIP "a11y-$id" "no $what found in $NM markup file(s)"
  fi
}
report img-alt "<img> tags"
report form-labels "form controls"
report icon-buttons "buttons/links"
report html-lang "<html> tags"
report viewport "HTML entrypoints"
report clickable "click handlers on div/span"

# zoom blocking
cat "$TMP/markup" "$TMP/jscand" "$TMP/tsl" > "$TMP/zl"
h=$(scan "$TMP/zl" 'user-scalable[[:space:]]*=[[:space:]]*.?(no|0)|userScalable[[:space:]]*:[[:space:]]*false|maximum-scale[[:space:]]*=[[:space:]]*.?1([.]0+)?([^0-9.]|$)|maximumScale[[:space:]]*:[[:space:]]*1([^0-9.]|$)')
if [ -n "$h" ]; then
  out WARN a11y-zoom "pinch-zoom is blocked at $(printf '%s\n' "$h" | cite): users with low vision cannot enlarge the page"
elif [ "$NM" -gt 0 ]; then
  out PASS a11y-zoom "no user-scalable=no / maximum-scale=1 found in $NM markup file(s)"
else
  out SKIP a11y-zoom "no markup files"
fi

# focus outline
if [ "$NC" -gt 0 ] || [ "$NM" -gt 0 ]; then
  report focus "CSS rules removing outline"
  # tailwind / inline outline removal
  tw=$(scan "$TMP/markup" 'outline-none|outline:[[:space:]]*.?(none|0)' | grep -v -i -E 'focus|ring|shadow|border' | head -20)
  if [ -n "$tw" ]; then
    out WARN a11y-focus "outline removed inline/utility with no focus ring on the same line at $(printf '%s\n' "$tw" | cite) [heuristic]"
  fi
fi

# fixed pixel widths with no responsive rules anywhere
: > "$TMP/wl"; cat "$TMP/markup" "$TMP/css" | sort -u > "$TMP/wl"
fw=$(scan "$TMP/wl" '(^|[^[:alnum:]-])(min-)?width[[:space:]]*:[[:space:]]*(6[0-9][0-9]|[7-9][0-9][0-9]|[1-9][0-9][0-9][0-9]+)px|w-[[][6-9][0-9][0-9]px[]]|w-[[][1-9][0-9][0-9][0-9]+px[]]')
if [ -n "$fw" ]; then
  resp=$(scan "$TMP/wl" '@media|@container|(^|[^[:alnum:]])(sm|md|lg|xl|2xl)[:][[:alnum:]-]|useMediaQuery|matchMedia|(xs|sm|md|lg|xl)=[{]' | head -1)
  if [ -z "$resp" ]; then
    out WARN a11y-fixed-width "fixed width >= 600px at $(printf '%s\n' "$fw" | cite) and no media queries/breakpoints anywhere: likely overflows on a 375px phone [heuristic]"
  else
    out PASS a11y-fixed-width "fixed widths >= 600px at $(printf '%s\n' "$fw" | cite), but the project has responsive rules ($(printf '%s' "$resp" | cut -d: -f1,2)); verify they cover these containers"
  fi
else
  out PASS a11y-fixed-width "no fixed pixel widths >= 600px found (min-width/width; max-width is fine)"
fi

out SKIP a11y-tap-targets "tap-target size (44px) and colour contrast are not statically knowable: run axe/Lighthouse in a browser, e.g. node scripts/a11y-browser.mjs <url> at 375px width"
exit 0
