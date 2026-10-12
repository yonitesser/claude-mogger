// Pure helpers for the bar's buttons: read the guard list that
// scripts/mogger-config.sh prints, pick the next state for a press, and the
// bar options the user can switch. No engine calls here.
export type GuardRow = { name: string; state: string; source: string; kind: string; allowed: string[] }

// `mogger-config.sh list` prints: name | state (source) | kind | allowed | ON | ASK | OFF
export function parseGuards(text: string): GuardRow[] {
  const rows: GuardRow[] = []
  for (const line of text.split('\n')) {
    const p = line.split(' | ')
    if (p.length < 4 || p[0] === 'name') continue
    const m = /^(\w+) \((\w+)\)$/.exec((p[1] ?? '').trim())
    if (!m) continue
    rows.push({ name: (p[0] ?? '').trim(), state: m[1] as string, source: m[2] as string, kind: (p[2] ?? '').trim(), allowed: (p[3] ?? '').trim().split(',') })
  }
  return rows
}

// The next state a press sets, or null when the button must not offer a press:
//  - an env var wins over the file, so a press would change nothing;
//  - a safety guard never goes `off` from a button (that needs the warning and the
//    explicit yes in the mogger-config skill), so it only moves between on and ask.
export function nextState(g: GuardRow): string | null {
  if (g.source === 'env') return null
  const order = ['on', 'ask', 'off'].filter(s => g.allowed.includes(s) && !(g.kind === 'safety' && s === 'off'))
  if (order.length < 2) return null
  const i = order.indexOf(g.state)
  return order[(i + 1) % order.length] ?? null
}

export type BarOptions = { robot: boolean; detail: boolean }
export const DEFAULT_BAR: BarOptions = { robot: true, detail: true }

// Anything stored that is not a plain object of booleans falls back to the default.
export function readBar(v: unknown): BarOptions {
  const o = typeof v === 'object' && v !== null ? (v as Record<string, unknown>) : {}
  return { robot: o.robot !== false, detail: o.detail !== false }
}
