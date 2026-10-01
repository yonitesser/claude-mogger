"""Plain-English report (text, markdown) and a static HTML page.

The HTML is one self-contained file: inline CSS, no scripts, no fonts, no images and no
network requests (article: "static files that open locally and load nothing from the
network"). Transcript links are relative paths to the saved stream-json files.
Short sentences, small words (STE).
"""
import html
import os

import common


def _pct(x):
    return "%d%%" % common.pct(x)


def _ci(v):
    return "CI %d-%d" % (common.pct(v["ci95"][0]), common.pct(v["ci95"][1]))


def lines(last):
    L = []
    L.append("mogger eval results (%s)" % last.get("ts", "?"))
    L.append("All dollar figures are ESTIMATES: token counts x published rates. They are not a bill.")
    if last.get("partial"):
        L.append("PARTIAL RESULTS: the run stopped at the budget. Some runs did not happen.")
    routing = (last.get("suites") or {}).get("routing")
    if routing:
        L.append("")
        L.append("Agent routing: does the cheap model do the job?")
        L.append("Overall the agents in their current setting passed %s of scored runs (%s, %d runs, about $%.2f)." % (
            _pct(routing["score"]), _ci(routing), routing["n"], routing.get("cost_usd", 0)))
        for name, a in sorted(routing.get("agents", {}).items()):
            L.append("- " + a["recommendation"])
            if a.get("effort_note"):
                L.append("  " + a["effort_note"])
            cells = ", ".join("%s %s (n=%d)" % (k, _pct(v["score"]), v["n"]) for k, v in sorted(a["candidates"].items()))
            L.append("  All settings: " + cells + ".")
    trig = (last.get("suites") or {}).get("triggers")
    if trig:
        L.append("")
        L.append("Skill triggering: does each skill fire when it should?")
        L.append("Overall %s right (%s, %d runs, about $%.2f)." % (_pct(trig["score"]), _ci(trig), trig["n"], trig.get("cost_usd", 0)))
        for name, v in sorted(trig.get("skills", {}).items(), key=lambda kv: kv[1]["score"])[:20]:
            rc = "n/a" if v.get("recall") is None else _pct(v["recall"])
            fr = "n/a" if v.get("false_rate") is None else _pct(v["false_rate"])
            L.append("- %s: %s right. Fires when it should: %s. Fires when it should not: %s." % (name, _pct(v["score"]), rc, fr))
    recs = last.get("recommendations") or []
    if recs:
        L.append("")
        L.append("What to do:")
        for r in recs:
            L.append("- " + r)
    if last.get("warnings"):
        L.append("")
        L.append("Warnings:")
        for w in last["warnings"]:
            L.append("- " + w)
    if not routing and not trig:
        L.append("No suite results in this run.")
    return L


def plain_text(last):
    return "\n".join(lines(last)) + "\n"


def markdown(last):
    out = ["# mogger eval report", ""]
    body = lines(last)
    out.append(body[1] if len(body) > 1 else "")
    out.append("")
    for ln in body[2:]:
        if ln and not ln.startswith(("-", " ")) and ln.endswith(("?", ":")):
            out.append("## " + ln.rstrip(":"))
        else:
            out.append(ln)
    out.append("")
    out.append("Run: %s. Fingerprint: %s." % (last.get("ts", "?"), last.get("fingerprint", "?")))
    return "\n".join(out) + "\n"


CSS = ("body{font:16px/1.5 system-ui,sans-serif;max-width:60rem;margin:0 auto;padding:1rem 16px;background:#fff;color:#1a1a1a}"
       "@media(prefers-color-scheme:dark){body{background:#151515;color:#e8e8e8}td,th{border-color:#444}}"
       "table{border-collapse:collapse;width:100%;margin:.5rem 0}td,th{border:1px solid #ccc;padding:.3rem .5rem;text-align:left}"
       ".warn{border-left:4px solid #c60;padding:.2rem .8rem;margin:.5rem 0}.note{opacity:.75}")


def page(last):
    e = html.escape
    o = ["<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
         "<title>mogger eval report</title><style>%s</style></head><body>" % CSS, "<h1>mogger eval report</h1>",
         "<p class=\"note\">Dollar figures are estimates (token counts x published rates), not a bill. Run %s. Fingerprint %s.</p>" % (
             e(str(last.get("ts", "?"))), e(str(last.get("fingerprint", "?"))))]
    if last.get("partial"):
        o.append("<p class=\"warn\"><strong>Partial results.</strong> The run stopped at the budget.</p>")
    routing = (last.get("suites") or {}).get("routing")
    if routing:
        o.append("<h2>Agent routing</h2><p>Current settings passed %s (%s, %d runs).</p>" % (_pct(routing["score"]), _ci(routing), routing["n"]))
        for name, a in sorted(routing.get("agents", {}).items()):
            o.append("<h3>%s</h3><p>%s</p>" % (e(name), e(a["recommendation"])))
            o.append("<table><tr><th>Setting</th><th>Score</th><th>95% CI</th><th>Scored runs</th><th>Plumbing</th><th>Run variance</th></tr>")
            for k, v in sorted(a["candidates"].items()):
                pl = ", ".join("%s %d" % (x, y) for x, y in sorted(v["plumbing"].items())) or "none"
                o.append("<tr><td>%s</td><td>%s</td><td>%d-%d</td><td>%d</td><td>%s</td><td>%.2f</td></tr>" % (
                    e(k), _pct(v["score"]), common.pct(v["ci95"][0]), common.pct(v["ci95"][1]), v["n"], e(pl), v["run_variance"]))
            o.append("</table>")
    trig = (last.get("suites") or {}).get("triggers")
    if trig:
        o.append("<h2>Skill triggering</h2><p>Overall %s right (%s, %d runs).</p>" % (_pct(trig["score"]), _ci(trig), trig["n"]))
        o.append("<table><tr><th>Skill</th><th>Right</th><th>Fires when it should</th><th>Fires when it should not</th><th>Train</th><th>Held-out</th></tr>")
        for name, v in sorted(trig.get("skills", {}).items(), key=lambda kv: kv[1]["score"]):
            rc = "n/a" if v.get("recall") is None else _pct(v["recall"])
            fr = "n/a" if v.get("false_rate") is None else _pct(v["false_rate"])
            o.append("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>" % (
                e(name), _pct(v["score"]), rc, fr, _pct(v["train"]["score"]), _pct(v["heldout"]["score"])))
        o.append("</table>")
    if last.get("recommendations"):
        o.append("<h2>What to do</h2><ul>%s</ul>" % "".join("<li>%s</li>" % e(r) for r in last["recommendations"]))
    if last.get("warnings"):
        o.append("<h2>Warnings</h2>%s" % "".join("<p class=\"warn\">%s</p>" % e(w) for w in last["warnings"]))
    tr = last.get("transcripts_dir")
    if tr:
        o.append("<p class=\"note\">Transcripts (stream-json, one file per run): %s</p>" % e(tr))
    o.append("</body></html>")
    return "\n".join(o) + "\n"


def write_reports(last, state):
    with open(os.path.join(state, "report.md"), "w") as f:
        f.write(markdown(last))
    with open(os.path.join(state, "report.html"), "w") as f:
        f.write(page(last))
