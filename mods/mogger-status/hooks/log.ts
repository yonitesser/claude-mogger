// Pure helpers for the mogger event log. One line per event:
//   <epoch seconds> TAB <kind> TAB <short message>
// Written by mogger_event in hooks/scripts/lib.sh. No secrets in the log.
import type { MoggerEvent, MoggerSummary } from '../types'

export const LOG_PATH = '.claude/state/mogger-events.log'

// kinds that count as "a guard fired". "info" lines (session start) do not.
const COUNTED = ['block', 'warn', 'ok']

export function parseLog(text: string): MoggerEvent[] {
  const events: MoggerEvent[] = []
  for (const line of text.split('\n')) {
    const parts = line.split('\t')
    if (parts.length < 3) continue
    const ts = Number(parts[0])
    if (!Number.isFinite(ts) || ts <= 0) continue
    const kind = parts[1] ?? ''
    if (kind === '') continue
    events.push({ ts, kind, msg: parts.slice(2).join(' ').slice(0, 120) })
  }
  return events
}

// sinceMs: only count events at or after this time (0 = all).
export function summarize(events: MoggerEvent[], sinceMs: number): MoggerSummary {
  const mine = events.filter(e => e.ts * 1000 >= sinceMs)
  const counted = mine.filter(e => COUNTED.includes(e.kind))
  return {
    fired: counted.length,
    blocked: counted.filter(e => e.kind === 'block').length,
    last: counted.length > 0 ? (counted[counted.length - 1] as MoggerEvent) : null,
  }
}

export function statusText(s: MoggerSummary): string {
  return `mogger: ${s.fired} guards fired, ${s.blocked} blocked`
}

export function newestTs(events: MoggerEvent[]): number {
  return events.reduce((m, e) => Math.max(m, e.ts), 0)
}

// Events to toast: blocks newer than lastTs.
export function newBlocks(events: MoggerEvent[], lastTs: number): MoggerEvent[] {
  return events.filter(e => e.kind === 'block' && e.ts > lastTs)
}

export function ageText(nowMs: number, ts: number): string {
  const s = Math.max(0, Math.round(nowMs / 1000 - ts))
  if (s < 60) return `${s}s ago`
  if (s < 3600) return `${Math.floor(s / 60)}m ago`
  return `${Math.floor(s / 3600)}h ago`
}

// Session start logs "voice on" or "voice off" (hooks/scripts/session-start.sh).
// The newest one wins. No line yet: voice is on, the default.
export function voiceOn(events: MoggerEvent[]): boolean {
  for (let i = events.length - 1; i >= 0; i--) {
    const e = events[i] as MoggerEvent
    if (e.kind === 'voice') return e.msg !== 'off'
  }
  return true
}

// The newest test run, from .claude/state/test-evidence.json (written by record-test-run.sh).
// Anything that is not a clear pass or fail shows nothing.
export const TESTS_PATH = '.claude/state/test-evidence.json'

export function testsOf(text: string | null): 'pass' | 'fail' | null {
  if (text === null) return null
  try {
    const v: unknown = JSON.parse(text)
    const st = typeof v === 'object' && v !== null ? (v as Record<string, unknown>).status : null
    return st === 'pass' || st === 'fail' ? st : null
  } catch {
    return null
  }
}

export function testsText(t: 'pass' | 'fail' | null): string {
  return t === null ? '' : `tests: ${t}`
}
