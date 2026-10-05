#!/usr/bin/env bash
# mogger-eval.sh - paid model evals for mogger's own agents and skill descriptions.
#
# Tests, with facts, the claim "Haiku-tier agents are good enough" (and that the
# Sonnet-tier agents need Sonnet), and hillclimbs ONE skill description at a time.
# Design source: Anthropic, "Automating eval design and hillclimbing with Claude"
# (Lance Martin, 2026-09-28). Every engine rule below cites it.
#
# USAGE
#   mogger-eval.sh estimate [--suite routing|triggers|all] [--repeats N]      NO model calls
#   mogger-eval.sh consent --budget USD | --revoke
#   mogger-eval.sh run [--suite S] [--budget USD] [--repeats N] [--background]
#   mogger-eval.sh status
#   mogger-eval.sh report
#   mogger-eval.sh hillclimb --skill NAME [--rounds N] [--repeats N] [--budget USD]
#   mogger-eval.sh apply <proposal-id> [--yes] [--target PATH] [--force]
#   mogger-eval.sh validate                 (checks tasks/graders/fixtures; free)
#   mogger-eval.sh ab estimate|plan|status|report|validate [--set base|hard|long] [--suite build|safety|all]   (free)
#   mogger-eval.sh ab run [--set base|hard|long] [--budget USD] [--model M] [--repeats N] [--tasks a,b] [--jobs N] [--background]
#     Does installing mogger change cost and correctness? Header of scripts/eval/ab.py; docs checked below.
# Extra options: --jobs N (parallel runs, default 3), --agents a,b, --skills a,b,
#   --no-effort-grid (haiku/sonnet at the agent's own effort only), --min-gain F,
#   --force (hillclimb past the noise/headroom stop).
#
# STATE (in the project, .claude/state/evals/): consent.json {budget_usd, ts, note},
#   last.json, report.html (static, no network), report.md, run.log, running.pid,
#   proposals/<id>.json|.diff, runs/<run>/<task>.jsonl (full stream-json transcripts).
#
# ENGINE RULES (article section -> where)
#  1 Tasks mirror production: evals/fixtures/* mini-repos; tasks in evals/tasks/*.json
#    (locate a definition, distil a big file, run tests and report, write a function to
#    spec, VERIFIED/REFUTED/UNVERIFIABLE with seeded truths and UNVERIFIABLE traps).
#  2 Programmatic graders first (scripts/eval/graders.py). Every task has a why_hard
#    note; cases were chosen because a human judged them hard, not because a model failed.
#  3 Each task runs on haiku and sonnet, at the agent's pinned effort and at default
#    effort, through headless `claude -p` (scripts/eval/runner.py).
#  4 Repeats (default 3): mean, run-to-run variance, 95% Wilson CI.
#  5 Seeded, stable 70/30 train/held-out split. The hillclimber reads train only;
#    a patch is kept only if train AND held-out do not regress and train improves
#    beyond noise; train up + held-out flat is reverted as overfitting; patches may not
#    contain >= 20 chars copied from any task input (scripts/eval/hillclimb.py).
#  6 Diagnostics: grader run twice, plumbing (timeout/API error/truncated/empty)
#    counted apart from wrong answers, headroom warning at >= 95%, noise check before
#    hillclimbing, stall reflection after 2 stalled rounds (bucket failures, no edit).
#  7 No leaked state: each trial runs in a fresh temp copy of the fixture with a
#    one-commit history; answer keys live in evals/tasks, never in a fixture.
#  8 Plain-words RECOMMENDATION with the numbers; a gap inside the CI is called noise.
#
# HEADLESS FLAGS - what was checked against the docs (https://code.claude.com/docs/en/headless,
#   /cli-reference, /sub-agents, /agent-sdk/typescript, /agent-sdk/cost-tracking; read 2026-09-29
#   and `claude --help` of v2.1.284):
#   VERIFIED: -p, --output-format stream-json (needs --verbose), --model, --effort
#     (low|medium|high|xhigh|max), --agents '<json>' (fields description, prompt, tools[],
#     model), --agent NAME, --tools, --allowedTools, --permission-mode dontAsk,
#     --max-turns, --max-budget-usd, --plugin-dir, --no-session-persistence, --settings.
#     Final stream line = {"type":"result"} with is_error, subtype (error_max_turns |
#     error_max_budget_usd | error_during_execution | success), result, num_turns,
#     stop_reason, total_cost_usd (client-side estimate), usage, modelUsage.
#   ASSUMED (not documented, unproven against a live API): a skill call shows up as an
#     assistant tool_use block named "Skill" with input.skill (name may be
#     "mogger:mogger-x" or "mogger-x"; both accepted); `--agent` honours the model/tools
#     from --agents plus --model/--effort given explicitly; the --settings permissions.deny
#     path syntax used to hide evals/ from the agent is best effort.
#
# A/B BENCHMARK (`ab`; scripts/eval/ab.py, tasks and fixtures in evals/ab/): plain Claude Code vs the same
#   plus this plugin, same model/effort/prompt/fixture copy/turn limit. Cost in USD is the CLI's client-side
#   estimate. A claim of "more" or "less" per successful task is made only when the 95% CI excludes zero.
#   VERIFIED (same docs, read 2026-10-02, CLI v2.1.287 --help): --include-hook-events, --permission-mode
#     acceptEdits, --allowedTools/--disallowedTools, --setting-sources, --strict-mcp-config, --plugin-dir,
#     --max-turns, --max-budget-usd, result-event usage/duration_ms/num_turns, init-event plugins[] and
#     claude_code_version, hook_started/hook_response events (hook_event, hook_name), env
#     CLAUDE_CODE_DISABLE_AUTO_MEMORY and CLAUDE_CODE_DISABLE_CLAUDE_MDS.
#     https://code.claude.com/docs/en/headless  /cli-reference  /plugins/create  /env-vars  /agent-sdk/typescript
#   ASSUMED, NOT PROVEN (needs one paid run to confirm): plugin hooks fire under acceptEdits; --setting-sources
#     project keeps the user's plugins and hooks out; hook events name the script in a '.../scripts/NAME.sh'
#     string. The report warns when arm B shows no hook events, or arm A shows any. --bare is not used (it
#     skips hooks and needs an API key). acceptEdits is not a sandbox: trials run model-chosen python3 and
#     grep commands in a temp folder as the current user.
#   LONG SET (`--set long`; scripts/eval/ablong*.py, evals/ab/tasks-long.json): suite build = 3 projects, 3 scripted
#     user messages each in ONE conversation (--session-id, then --resume; session persistence on); suite safety =
#     6 sandboxed irreversible-damage scenarios (temp tree, HOME inside it, PATH shims that refuse targets outside
#     it, local fakes for remote/db/prod/mail). --build-repeats/--safety-repeats; default 2 and 1. Header of ablong.py.
#
# Overridable: MOGGER_CLAUDE_BIN (the claude binary; tests use a stub),
#   MOGGER_EVAL_PLUGIN_ROOT, MOGGER_EVAL_DIR, MOGGER_EVAL_STATE_DIR, MOGGER_EVAL_PRICING,
#   MOGGER_EVAL_TRIGGER_MODEL (default sonnet), MOGGER_EVAL_PROPOSER_MODEL (default sonnet),
#   MOGGER_EVAL_TIMEOUT / _TRIGGER_TIMEOUT, MOGGER_EVAL_TRIAL_CAP_USD, MOGGER_EVAL_EXTRA_ARGS
#   (for example --bare), MOGGER_EVAL_SEED.
# Dollar figures are ESTIMATES (token counts x templates/pricing.json), never a bill.
# Needs python3 (real, not the Windows Store stub). No network access of its own.

SELF="${BASH_SOURCE[0]:-$0}"
HERE="$(cd "$(dirname "$SELF")" && pwd)"
PY_CLI="$HERE/eval/cli.py"

if ! command -v python3 >/dev/null 2>&1 || ! python3 -c '1' >/dev/null 2>&1; then
  echo "mogger-eval needs python3 (a real one; the Windows Store stub does not count). Install python3 and try again." >&2
  exit 2
fi
export PYTHONDONTWRITEBYTECODE=1

STATE="${MOGGER_EVAL_STATE_DIR:-$PWD/.claude/state/evals}"
cmd="${1:-}"

bg=0
args=()
for a in "$@"; do
  if [ "$a" = "--background" ]; then bg=1; else args[${#args[@]}]="$a"; fi
done

pid_alive() {  # pid_alive <file>
  local p
  [ -f "$1" ] || return 1
  p=$(tr -dc '0-9' < "$1")
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

is_run=0
RS="$STATE"
case "$cmd" in
  run|hillclimb) is_run=1 ;;
  ab) RS="$STATE/ab"; [ "${2:-}" = "run" ] && is_run=1 ;;
esac

case "$is_run" in
  1)
    if [ "${MOGGER_EVAL_BG:-}" != "1" ] && pid_alive "$RS/running.pid"; then
      echo "An eval run is already going (pid $(tr -dc '0-9' < "$RS/running.pid")). See: mogger-eval.sh status" >&2
      exit 2
    fi
    if [ "$bg" = "1" ]; then
      # refuse synchronously, before detaching, when there is no consent and no --budget
      has_budget=0
      for a in "${args[@]}"; do
        case "$a" in --budget|--budget=*) has_budget=1 ;; esac
      done
      if [ "$has_budget" = "0" ] && [ ! -f "$STATE/consent.json" ]; then
        exec python3 "$PY_CLI" "${args[@]}"   # prints the refusal and exits 2
      fi
      mkdir -p "$RS"
      MOGGER_EVAL_BG=1 nohup bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$RS/running.pid" bash "$SELF" "${args[@]}" \
        >> "$RS/run.log" 2>&1 < /dev/null &
      started=$!
      n=0
      while [ ! -s "$RS/running.pid" ] && [ "$n" -lt 30 ]; do sleep 0.1; n=$((n+1)); done
      echo "Started in the background (pid $started). Log: $RS/run.log"
      echo "Check with: mogger-eval.sh status. Read results with: mogger-eval.sh report"
      exit 0
    fi
    python3 "$PY_CLI" "${args[@]}"
    rc=$?
    if [ "${MOGGER_EVAL_BG:-}" = "1" ]; then rm -f "$RS/running.pid"; fi
    exit $rc
    ;;
esac

case "$cmd" in
  ""|-h|--help|help)
    sed -n '2,22p' "$SELF" | sed 's/^# \{0,1\}//'
    [ -z "$cmd" ] && exit 2
    exit 0
    ;;
  *)
    exec python3 "$PY_CLI" "${args[@]}"
    ;;
esac
