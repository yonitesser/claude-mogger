#!/usr/bin/env bash
# Tests for the grounding layer. Run: bash tests/grounding.test.sh
# Feeds check-references.sh the JSON Claude Code would send after an Edit/Write
# and asserts the exit code. 0 = allow, 2 = block (unresolved reference).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
PASS=0; FAIL=0

if ! command -v python3 >/dev/null 2>&1 || ! python3 -c '1' >/dev/null 2>&1; then
  echo "python3 not available: check-references.sh fails open; nothing to test"; exit 0
fi

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
cd "$SANDBOX"

expect() {  # expect <exit_code> <file> <description> [env assignment]
  local want="$1" file="$2" desc="$3" envv="${4:-X=1}" got
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$SANDBOX/$file" \
    | env "$envv" bash "$H/check-references.sh" >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$want" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$desc"
  else FAIL=$((FAIL+1)); printf '  FAIL %s (want %s, got %s)\n' "$desc" "$want" "$got"; fi
}
w() {  # w <path> <content> — write a file, creating dirs
  mkdir -p "$(dirname "$SANDBOX/$1")"; printf '%s\n' "$2" > "$SANDBOX/$1"
}

# ---- JS/TS project
w package.json '{"name":"demo","dependencies":{"express":"^4","@scope/pkg":"1"},"devDependencies":{"vitest":"1","@types/lodash":"4"}}'
w src/a.ts 'export const a = 1'
w src/util/index.ts 'export const u = 1'
w src/comp.tsx 'export default 1'
w src/data.json '{}'
w src/esm.js 'export const e = 1'
w src/style.css 'a{}'
w src/lib/thing.ts 'export {}'

echo "== relative resolution (JS/TS)"
w src/t1.ts "import { a } from './a'"
expect 0 src/t1.ts "resolves ./a to a.ts"
w src/t2.ts "import { x } from './missing'"
expect 2 src/t2.ts "flags ./missing"
w src/t3.ts "import { u } from './util'"
expect 0 src/t3.ts "resolves directory index.ts"
w src/t4.ts "import C from './comp'"
expect 0 src/t4.ts "resolves .tsx"
w src/t5.ts "import d from './data.json'"
expect 0 src/t5.ts "resolves explicit .json"
w src/t6.ts "import { e } from './esm.js'"
expect 0 src/t6.ts "explicit .js extension"
w src/t7.ts "import { a } from './a.js'"
expect 0 src/t7.ts "TS ESM style ./a.js resolves to a.ts"
w src/lib/t8.ts "import { a } from '../a'"
expect 0 src/lib/t8.ts "resolves ../a"
w src/lib/t9.ts "import { a } from '../nope'"
expect 2 src/lib/t9.ts "flags ../nope"
w src/t10.js "const a = require('./a')"
expect 0 src/t10.js "require ./a resolves"
w src/t11.js "const a = require('./ghost')"
expect 2 src/t11.js "require ./ghost flagged"
w src/t12.ts "import './style.css'"
expect 0 src/t12.ts "existing asset side-effect import"
w src/t13.ts "import './nothere.css'"
expect 0 src/t13.ts "missing asset (non-code ext) fails open"
w src/t14.ts "export * from './ghost'"
expect 2 src/t14.ts "export-from flagged"
w src/t15.ts "import { a } from './a'
import { b } from './b_missing'"
expect 2 src/t15.ts "one bad among good flagged"
w src/t16.ts "import type { T } from './ghost'"
expect 2 src/t16.ts "type-only relative import still must resolve"

echo "== bare packages (JS/TS)"
w src/b1.ts "import express from 'express'"
expect 0 src/b1.ts "declared dependency"
w src/b2.ts "import x from 'left-padder'"
expect 2 src/b2.ts "undeclared package flagged"
w src/b3.ts "import fs from 'node:fs'"
expect 0 src/b3.ts "node:fs"
w src/b4.ts "import fs from 'fs'; import path from 'path'; import { join } from 'fs/promises'"
expect 0 src/b4.ts "node builtins incl. subpath"
w src/b5.ts "import p from '@scope/pkg/sub/deep'"
expect 0 src/b5.ts "scoped package with subpath"
w src/b6.ts "import p from '@other/pkg'"
expect 2 src/b6.ts "undeclared scoped package flagged"
w src/b7.ts "import _ from 'lodash'"
expect 0 src/b7.ts "@types/lodash counts as declared"
w src/b8.ts "import type { X } from 'some-types-only'"
expect 0 src/b8.ts "type-only bare import fails open"
w src/b9.ts "// import x from 'ghost-pkg'
/* import y from 'ghost-two' */
const a = 1"
expect 0 src/b9.ts "commented-out imports ignored"
w src/b10.ts "const s = \"require('ghost-pkg')\"; const t = 'import x from \"ghost\"'; const u = \`from 'ghost'\`"
expect 0 src/b10.ts "require/import inside strings ignored"
w src/b11.ts "const m = await import('ghost-pkg')"
expect 0 src/b11.ts "dynamic import ignored"
w src/b12.ts "const x = require(name)"
expect 0 src/b12.ts "non-literal require ignored"
w src/b13.ts "import x from '@/components/x'; import y from '~/y'; import z from '#internal/z'; import w from '\$lib/w'"
expect 0 src/b13.ts "@/ ~/ # \$ aliases ignored"
w src/b14.ts "import x from 'https://esm.sh/x'; import y from 'bun:test'; import z from 'virtual:foo'"
expect 0 src/b14.ts "URL/scheme specifiers ignored"
w src/b15.ts "const a = Array.from('abc'); const from = 'x'; foo.from('ghost')"
expect 0 src/b15.ts "'from' as a method/variable not an import"
w src/b16.ts "import {
  a,
  b,
} from 'ghost-multi'"
expect 2 src/b16.ts "multi-line named import flagged with correct parse"
w src/b17.ts "import x = require('ghost-eq')"
expect 2 src/b17.ts "import = require flagged"
w src/b18.ts "const re = /['\"]/g; import y from 'express'"
expect 0 src/b18.ts "regex literal with quotes does not desync"
w src/b19.ts "import 'ghost-side-effect'"
expect 2 src/b19.ts "side-effect bare import flagged"
w src/b20.ts "jest.mock('ghost-pkg'); const p = 'express'"
expect 0 src/b20.ts "jest.mock not treated as import"
w src/b21.d.ts "import x from 'ghost-decl'"
expect 0 src/b21.d.ts ".d.ts skipped for bare"

echo "== config-driven fail-open (JS/TS)"
mkdir -p alias/src; w alias/package.json '{"dependencies":{}}'
w alias/tsconfig.json '{"compilerOptions":{"baseUrl":".","paths":{"utils/*":["src/utils/*"]}}}'
w alias/src/x.ts "import u from 'utils/thing'"
expect 0 alias/src/x.ts "tsconfig paths/baseUrl: bare import not flagged"
w alias/src/y.ts "import u from './nothere'"
expect 2 alias/src/y.ts "tsconfig alias project still flags broken relative"
mkdir -p mono/packages/app; w mono/package.json '{"workspaces":["packages/*"]}'
w mono/packages/app/package.json '{"name":"app"}'
w mono/packages/app/i.ts "import s from '@mono/shared'"
expect 0 mono/packages/app/i.ts "workspaces monorepo: bare import not flagged"
ISO=$(mktemp -d); trap 'rm -rf "$SANDBOX" "$ISO"' EXIT
printf "import s from 'whatever'\n" > "$ISO/i.ts"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$ISO/i.ts" | bash "$H/check-references.sh" >/dev/null 2>&1
if [ $? -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   no package.json: bare check skipped"; else FAIL=$((FAIL+1)); echo "  FAIL no package.json: bare check skipped"; fi
mkdir -p inst/node_modules/vendored; w inst/package.json '{}'
w inst/i.ts "import v from 'vendored'"
expect 0 inst/i.ts "package present in node_modules not flagged"
mkdir -p selfp; w selfp/package.json '{"name":"selfp"}'
w selfp/i.ts "import v from 'selfp'"
expect 0 selfp/i.ts "self-reference by package name"

echo "== controls"
w src/c1.ts "import x from './ghost'"
expect 0 src/c1.ts "MOGGER_CHECK_REFERENCES=off disables" MOGGER_CHECK_REFERENCES=off
w notes.md "import x from './ghost'"
expect 0 notes.md "non-code file ignored"
w conf.yaml "from: ./ghost"
expect 0 conf.yaml "yaml ignored"
expect 0 src/does-not-exist.ts "missing file fails open"
printf '{"tool_name":"Write","tool_input":{}}' | bash "$H/check-references.sh" >/dev/null 2>&1
if [ $? -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   no file_path fails open"; else FAIL=$((FAIL+1)); echo "  FAIL no file_path"; fi
mkdir -p node_modules/dep; w node_modules/dep/i.js "require('./ghost')"
expect 0 node_modules/dep/i.js "files inside node_modules skipped"

echo "== error message content"
w src/m1.ts "import a from './ghost-file'
import b from 'ghost-pkg'"
MSG=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$SANDBOX/src/m1.ts" | bash "$H/check-references.sh" 2>&1 >/dev/null)
for needle in "line 1" "./ghost-file" "line 2" "ghost-pkg" "package.json"; do
  if printf '%s' "$MSG" | grep -qF -- "$needle"; then PASS=$((PASS+1)); echo "  ok   message mentions: $needle"
  else FAIL=$((FAIL+1)); echo "  FAIL message missing: $needle"; fi
done

echo "== Python"
w requirements.txt 'requests==2.31
PyYAML>=6
python-dateutil
'
w app/__init__.py ''
w app/models.py 'X = 1'
w app/pkg/__init__.py ''
w app/p1.py 'from .models import X'
expect 0 app/p1.py "relative import resolves"
w app/p2.py 'from .ghost import X'
expect 2 app/p2.py "relative import of missing module flagged"
w app/p3.py 'from . import models'
expect 0 app/p3.py "from . import (package with __init__)"
w app/p4.py 'from .pkg import anything'
expect 0 app/p4.py "relative import of subpackage"
w app/pkg/p5.py 'from ..models import X'
expect 0 app/pkg/p5.py "parent-relative import resolves"
w app/pkg/p6.py 'from ..ghost import X'
expect 2 app/pkg/p6.py "parent-relative missing flagged"
w app/p7.py 'import os, sys, json
from collections import OrderedDict
import xml.etree.ElementTree as ET
from typing import TYPE_CHECKING'
expect 0 app/p7.py "stdlib modules"
w app/p8.py 'import requests
import yaml
from dateutil import parser'
expect 0 app/p8.py "declared deps incl. import-name aliases (yaml, dateutil)"
w app/p9.py 'import numpyy'
expect 2 app/p9.py "undeclared package flagged"
w app/p10.py 'from app.models import X
import app.pkg'
expect 0 app/p10.py "local absolute imports"
w app/p11.py 'try:
    import ujson
except ImportError:
    ujson = None'
expect 0 app/p11.py "try/except ImportError guarded import"
w app/p12.py '# import ghostpkg
s = "import ghostpkg"
def f():
    """import ghostpkg"""'
expect 0 app/p12.py "commented/string imports ignored"
w app/p13.py 'def broken(:'
expect 0 app/p13.py "syntax error fails open"
w app/p14.py 'from __future__ import annotations'
expect 0 app/p14.py "__future__"
printf 'import whatever\n' > "$ISO/i.py"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$ISO/i.py" | bash "$H/check-references.sh" >/dev/null 2>&1
if [ $? -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   no manifest anywhere: bare check skipped"; else FAIL=$((FAIL+1)); echo "  FAIL no manifest anywhere: bare check skipped"; fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
