// Pure helpers for the bar's panels: read the guard catalog (hooks/guards.tsv),
// work out each guard's state from the switch file, build the new file text for a
// pick, and the bar options the user can switch. No engine calls, no commands:
// the mod reads and writes the same switch file the mogger:config script does.
export type GuardDef = { name: string; envVar: string; kind: string; onValue: string; dflt: string; states: string[] }
export type GuardRow = { name: string; kind: string; state: string; source: 'file' | 'default'; options: string[] }

// guards.tsv: name, variable, kind, on-value, default, ifON, ifOFF, states, ifASK; tab separated; # lines are comments.
export function parseCatalog(tsv: string): GuardDef[] {
  const defs: GuardDef[] = []
  for (const line of tsv.split('\n')) {
    if (line.startsWith('#')) continue
    const c = line.split('\t')
    if (c.length < 5 || !(c[0] ?? '').trim()) continue
    const states = (c[7] ?? '').trim() === '' ? ['on', 'off'] : (c[7] as string).trim().split(',')
    defs.push({ name: (c[0] as string).trim(), envVar: (c[1] ?? '').trim(), kind: (c[2] ?? '').trim(), onValue: (c[3] ?? '').trim(), dflt: (c[4] ?? '').trim(), states })
  }
  return defs
}

// What a pick may be. A safety guard never goes `off` from the bar (that needs the warning and
// the explicit yes in /mogger:config), so it only moves between on and ask.
export function optionsOf(d: GuardDef): string[] {
  return ['on', 'ask', 'off'].filter(s => d.states.includes(s) && !(d.kind === 'safety' && s === 'off'))
}

export function parseConfig(text: string | null): Record<string, unknown> | null {
  if (text === null || text.trim() === '') return {}
  try {
    const v: unknown = JSON.parse(text)
    return typeof v === 'object' && v !== null && !Array.isArray(v) ? (v as Record<string, unknown>) : null
  } catch {
    return null
  }
}

// What `mogger-config.sh list` shows with no MOGGER_* variable set: the file value when the guard allows
// it, else the default. A variable that is set still wins at run time; a mod cannot read variables by a
// computed name, so the panel says so in one line instead of marking each guard.
export function rowOf(d: GuardDef, cfg: Record<string, unknown>): GuardRow {
  const v = cfg[d.name]
  const fromFile = typeof v === 'string' && d.states.includes(v)
  return { name: d.name, kind: d.kind, state: fromFile ? (v as string) : d.dflt, source: fromFile ? 'file' : 'default', options: optionsOf(d) }
}

// A guard the bar may offer a choice for: there must be at least two states to pick from.
export function isPickable(g: GuardRow): boolean {
  return g.options.length >= 2
}

// The new switch-file text after a pick, or why not. A file that is not a JSON object is never overwritten.
export function withPick(cfgText: string | null, d: GuardDef, value: string): { ok: true; text: string } | { ok: false; reason: string } {
  if (!optionsOf(d).includes(value)) return { ok: false, reason: `${d.name} cannot be ${value} from the bar` }
  const cfg = parseConfig(cfgText)
  if (cfg === null) return { ok: false, reason: 'the switch file is not valid JSON; fix it by hand first' }
  return { ok: true, text: `${JSON.stringify({ ...cfg, [d.name]: value }, null, 2)}\n` }
}

export type BarOptions = { robot: boolean; detail: boolean }
export const DEFAULT_BAR: BarOptions = { robot: true, detail: true }

// Anything stored that is not a plain object of booleans falls back to the default.
export function readBar(v: unknown): BarOptions {
  const o = typeof v === 'object' && v !== null ? (v as Record<string, unknown>) : {}
  return { robot: o.robot !== false, detail: o.detail !== false }
}
