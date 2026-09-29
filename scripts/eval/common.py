"""Shared helpers for the mogger eval engine: paths, plugin loading, fingerprint,
stable train/held-out split, statistics, pricing.

Design source: Anthropic, "Automating eval design and hillclimbing with Claude"
(Lance Martin, 2026-09-28). Rule numbers below refer to the engine rules in
scripts/mogger-eval.sh.

ESTIMATE NOTICE: every dollar figure that comes from this file is token counts
x templates/pricing.json (approximate published rates), never a bill.
"""
import glob
import hashlib
import json
import math
import os
import re
import sys
import time

SEED = os.environ.get("MOGGER_EVAL_SEED", "mogger-eval-v1")
TRAIN_FRACTION = 0.70


def plugin_root():
    env = os.environ.get("MOGGER_EVAL_PLUGIN_ROOT")
    if env:
        return os.path.abspath(env)
    return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def evals_dir():
    return os.path.abspath(os.environ.get("MOGGER_EVAL_DIR") or os.path.join(plugin_root(), "evals"))


def state_dir():
    env = os.environ.get("MOGGER_EVAL_STATE_DIR")
    if env:
        return os.path.abspath(env)
    return os.path.join(os.getcwd(), ".claude", "state", "evals")


def claude_bin():
    return os.environ.get("MOGGER_CLAUDE_BIN") or "claude"


def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def read_json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def write_json(path, obj):
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    tmp = path + ".tmp%d" % os.getpid()
    with open(tmp, "w") as f:
        json.dump(obj, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


# ------------------------------------------------------------ plugin content
def split_frontmatter(text):
    """Return (frontmatter_text, dict, body). Line-based 'key: value' only."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return "", {}, text
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return "", {}, text
    fm_lines = lines[1:end]
    d = {}
    for ln in fm_lines:
        m = re.match(r"^([A-Za-z_-]+):[ \t]*(.*)$", ln)
        if m:
            d[m.group(1)] = m.group(2).strip()
    return "\n".join(fm_lines), d, "\n".join(lines[end + 1:])


def load_agents(root=None):
    root = root or plugin_root()
    out = {}
    for p in sorted(glob.glob(os.path.join(root, "agents", "*.md"))):
        text = open(p).read()
        _, fm, body = split_frontmatter(text)
        name = fm.get("name") or os.path.basename(p)[:-3]
        tools = [t.strip() for t in fm.get("tools", "").split(",") if t.strip()]
        out[name] = {"name": name, "description": fm.get("description", ""), "tools": tools,
                     "model": fm.get("model", ""), "effort": fm.get("effort", ""),
                     "body": body, "path": p}
    return out


def load_skills(root=None):
    root = root or plugin_root()
    out = {}
    for p in sorted(glob.glob(os.path.join(root, "skills", "*", "SKILL.md"))):
        text = open(p).read()
        fmt, fm, body = split_frontmatter(text)
        name = fm.get("name") or os.path.basename(os.path.dirname(p))
        out[name] = {"name": name, "description": fm.get("description", ""),
                     "frontmatter": fmt, "path": p, "text": text}
    return out


def fingerprint(root=None):
    """Hash of agents/*.md (whole files) + skills/*/SKILL.md frontmatter (which
    holds the descriptions). Body edits to a skill do not change it: only what
    decides routing and triggering does."""
    root = root or plugin_root()
    h = hashlib.sha256()
    for p in sorted(glob.glob(os.path.join(root, "agents", "*.md"))):
        h.update(("A:" + os.path.basename(p) + "\n").encode())
        h.update(open(p, "rb").read())
    for p in sorted(glob.glob(os.path.join(root, "skills", "*", "SKILL.md"))):
        fmt, _, _ = split_frontmatter(open(p).read())
        h.update(("S:" + os.path.basename(os.path.dirname(p)) + "\n").encode())
        h.update(fmt.encode())
    return h.hexdigest()[:16]


# ------------------------------------------------------------ split (rule 5)
def split_ids(items, seed=None, frac=TRAIN_FRACTION):
    """items: list of (id, stratum). Returns {id: 'train'|'heldout'}.
    Seeded, stable: rank inside each stratum by sha256(seed|id), first ~70% train.
    Each stratum with >= 2 members has at least one member on each side."""
    seed = SEED if seed is None else seed
    groups = {}
    for i, s in items:
        groups.setdefault(s, []).append(i)
    out = {}
    for s, ids in groups.items():
        ranked = sorted(ids, key=lambda x: hashlib.sha256((seed + "|" + x).encode()).hexdigest())
        n = len(ranked)
        k = int(frac * n + 0.5)
        if n >= 2:
            k = max(1, min(n - 1, k))
        for j, i in enumerate(ranked):
            out[i] = "train" if j < k else "heldout"
    return out


# ------------------------------------------------------------ statistics (rule 4)
def mean(xs):
    xs = list(xs)
    return sum(xs) / len(xs) if xs else 0.0


def sample_sd(xs):
    xs = list(xs)
    if len(xs) < 2:
        return 0.0
    m = mean(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1))


def wilson(k, n, z=1.96):
    """95% Wilson score interval for k successes in n trials."""
    if n <= 0:
        return (0.0, 1.0)
    p = float(k) / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def diff_ci(k1, n1, k2, n2):
    """Newcombe hybrid-score 95% CI for p2 - p1. Returns (diff, lo, hi)."""
    if n1 <= 0 or n2 <= 0:
        return (0.0, -1.0, 1.0)
    p1, p2 = float(k1) / n1, float(k2) / n2
    l1, u1 = wilson(k1, n1)
    l2, u2 = wilson(k2, n2)
    d = p2 - p1
    lo = d - math.sqrt((p2 - l2) ** 2 + (u1 - p1) ** 2)
    hi = d + math.sqrt((u2 - p2) ** 2 + (p1 - l1) ** 2)
    return (d, lo, hi)


def pct(x):
    return int(round(100.0 * x))


# ------------------------------------------------------------ pricing (ESTIMATE)
def pricing():
    path = os.environ.get("MOGGER_EVAL_PRICING") or os.path.join(plugin_root(), "templates", "pricing.json")
    d = read_json(path, None)
    if not d or "models" not in d:
        d = read_json(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "templates", "pricing.json"), None)
    if not d or "models" not in d:
        d = {"models": {"haiku": {"input_per_mtok": 1.0, "output_per_mtok": 5.0},
                        "sonnet": {"input_per_mtok": 2.0, "output_per_mtok": 10.0},
                        "opus": {"input_per_mtok": 4.0, "output_per_mtok": 20.0}}}
    return d


def tier_of(model):
    m = (model or "").lower()
    for t in ("haiku", "sonnet", "opus"):
        if t in m:
            return t
    return "sonnet"


def token_cost(tier, in_tok, out_tok):
    p = pricing()["models"].get(tier) or pricing()["models"]["sonnet"]
    return in_tok / 1e6 * p["input_per_mtok"] + out_tok / 1e6 * p["output_per_mtok"]


# Per-trial token and time ASSUMPTIONS for `estimate` (no model calls are made).
# Multi-turn agent runs re-send context every turn, so input is large.
EST = {
    "routing": {"in": 30000, "out": 1500, "secs": {"haiku": 40, "sonnet": 60}},
    "triggers": {"in": 16000, "out": 250, "secs": {"haiku": 10, "sonnet": 14}},
    "proposer": {"in": 6000, "out": 800, "secs": {"haiku": 20, "sonnet": 30}},
}


def est_trial(kind, tier):
    e = EST[kind]
    return token_cost(tier, e["in"], e["out"]), e["secs"].get(tier, 40)


def die(msg, code=2):
    sys.stderr.write(msg.rstrip("\n") + "\n")
    sys.exit(code)
