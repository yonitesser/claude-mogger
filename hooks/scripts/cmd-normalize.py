#!/usr/bin/env python3
"""Turn a shell command line into plain simple commands, one per line.

Used by require-approval.sh so the approval gate sees what really runs:
  * splits on ; && || | & and newlines
  * unwraps `bash -c "..."`, `sh -c`, `eval`, `$(...)`, backticks, xargs
  * strips sudo/env/command/nohup/time/timeout/... prefixes and VAR=x
  * drops git global options (`git -C dir -c k=v push` -> `git push`)
  * drops heredoc bodies and comments
  * a quoted argument that contains spaces (a commit message, an echo text)
    becomes "..." so prose that merely MENTIONS a command is not a command
On a quote or paren it cannot parse, it also prints the raw lines (so the gate
errs towards blocking). Reads the command on stdin. Always exits 0.
"""
import re, sys

WRAP = {"sudo", "doas", "env", "command", "nohup", "time", "exec", "nice", "ionice",
        "stdbuf", "timeout", "setsid", "builtin", "caffeinate", "unbuffer"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish"}
GIT_OPT_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path",
               "--super-prefix", "--config-env"}
GIT_OPT_FLAG = {"--no-pager", "-p", "--paginate", "--bare", "--no-replace-objects",
                "--literal-pathspecs"}
WRAP_ARG = {"sudo": ("-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U", "-r", "-t"),
            "doas": ("-u", "-C"), "env": ("-u", "-C", "-S"), "nice": ("-n",),
            "ionice": ("-c", "-n", "-p"), "timeout": ("-s", "-k")}
MAX_DEPTH = 6
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def strip_heredocs(s):
    out, lines, i = [], s.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        tags = re.findall(r"<<-?\s*(?:'([^']+)'|\"([^\"]+)\"|\\?([A-Za-z_][A-Za-z0-9_]*))", line)
        i += 1
        for t in tags:
            tag = next(x for x in t if x)
            while i < len(lines) and lines[i].strip() != tag:
                i += 1
            i += 1
    return "\n".join(out)


def match_paren(s, i):
    """s[i] == '(' ; return the index of the matching ')' or -1."""
    depth, q = 0, None
    while i < len(s):
        c = s[i]
        if q:
            if c == q:
                q = None
            elif c == "\\" and q == '"':
                i += 1
        elif c in "'\"":
            q = c
        elif c == "\\":
            i += 1
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def tokenize(s, subs, bad):
    """-> list of commands; a command is a list of (text, is_prose)."""
    cmds, cur, tok, quoted, i, n = [], [], [], False, 0, len(s)

    def end_tok():
        nonlocal tok, quoted
        if tok or quoted:
            t = "".join(tok)
            cur.append((t, quoted and bool(re.search(r"\s", t))))
        tok, quoted = [], False

    def end_cmd():
        nonlocal cur
        end_tok()
        if cur:
            cmds.append(cur)
        cur = []

    while i < n:
        c = s[i]
        if c == "\\" and i + 1 < n:
            if s[i + 1] != "\n":
                tok.append(s[i + 1])
            i += 2
        elif c == "'":
            j = s.find("'", i + 1)
            if j < 0:
                bad.append(1); tok.append(s[i + 1:]); i = n
            else:
                tok.append(s[i + 1:j]); quoted = True; i = j + 1
        elif c == '"':
            j, buf = i + 1, []
            while j < n and s[j] != '"':
                if s[j] == "\\" and j + 1 < n:
                    buf.append(s[j + 1]); j += 2
                elif s[j] == "$" and s[j + 1:j + 2] == "(":
                    k = match_paren(s, j + 1)
                    if k < 0:
                        bad.append(1); buf.append(s[j]); j += 1
                    else:
                        subs.append(s[j + 2:k]); buf.append(" "); j = k + 1
                elif s[j] == "`":
                    k = s.find("`", j + 1)
                    if k < 0:
                        bad.append(1); j += 1
                    else:
                        subs.append(s[j + 1:k]); buf.append(" "); j = k + 1
                else:
                    buf.append(s[j]); j += 1
            if j >= n:
                bad.append(1)
            tok.append("".join(buf)); quoted = True; i = j + 1
        elif c == "$" and s[i + 1:i + 2] == "(":
            k = match_paren(s, i + 1)
            if k < 0:
                bad.append(1); tok.append(c); i += 1
            else:
                subs.append(s[i + 2:k]); i = k + 1
        elif c == "`":
            k = s.find("`", i + 1)
            if k < 0:
                bad.append(1); i += 1
            else:
                subs.append(s[i + 1:k]); i = k + 1
        elif c == "#" and not tok and not quoted:
            while i < n and s[i] != "\n":
                i += 1
        elif c in ";&|\n(){}":
            end_cmd(); i += 1
        elif c in " \t":
            end_tok(); i += 1
        else:
            tok.append(c); i += 1
    end_cmd()
    return cmds


def simple(tokens, emit, depth):
    """tokens: list of (text, prose). Unwrap prefixes and emit normalised lines."""
    t = list(tokens)
    for _ in range(12):
        while t and ASSIGN.match(t[0][0]):
            t.pop(0)
        if not t:
            return
        h = t[0][0].rsplit("/", 1)[-1]
        if h in WRAP:
            t.pop(0)
            while t and (t[0][0].startswith("-") or ASSIGN.match(t[0][0])
                         or (h == "timeout" and re.match(r"^[0-9.]+[smhd]?$", t[0][0]))):
                a = t.pop(0)[0]
                if a in WRAP_ARG.get(h, ()) and t:
                    t.pop(0)
            continue
        if h == "xargs":
            t.pop(0)
            while t and t[0][0].startswith("-"):
                t.pop(0)
            continue
        break
    if not t:
        return
    h = t[0][0].rsplit("/", 1)[-1]
    if h in SHELLS:
        for k in range(1, len(t)):
            if re.match(r"^-[A-Za-z]*c[A-Za-z]*$", t[k][0]) and k + 1 < len(t):
                walk(t[k + 1][0], emit, depth + 1)
                return
    if h == "eval":
        walk(" ".join(x[0] for x in t[1:]), emit, depth + 1)
        return
    if h == "git":
        k = 1
        while k < len(t):
            a = t[k][0]
            if a in GIT_OPT_ARG:
                k += 2
            elif (a.startswith("--") and "=" in a) or a in GIT_OPT_FLAG:
                k += 1
            else:
                break
        t = [("git", False)] + t[k:]
    emit(" ".join('"..."' if p else x for x, p in t))


def walk(s, emit, depth=0):
    if depth > MAX_DEPTH:
        emit(s.replace("\n", " "))
        return
    s = strip_heredocs(s)
    subs, bad = [], []
    for cmd in tokenize(s, subs, bad):
        simple(cmd, emit, depth)
    for sub in subs:
        walk(sub, emit, depth + 1)
    if bad:
        for line in s.split("\n"):
            if line.strip():
                emit(line.strip())


def main():
    raw = sys.stdin.read()
    out = []
    try:
        walk(raw, out.append)
    except Exception:
        out = [l for l in raw.split("\n") if l.strip()]
    seen = set()
    for line in out:
        if line and line not in seen:
            seen.add(line)
            print(line)


if __name__ == "__main__":
    main()
