import { expect, test } from 'claude-code/testing'

import { DEFAULT_BAR, isPickable, optionsOf, parseCatalog, parseConfig, readBar, rowOf, withPick } from './panel'

// the same columns as hooks/guards.tsv: name, variable, kind, on-value, default, ifON, ifOFF, states, ifASK
const TSV = [
  '# name\tENV_VAR\tkind\ton-value\tdefault\tif ON\tif OFF\tstates\tif ASK',
  'danger-guard\tMOGGER_DANGER_GUARD\tsafety\ton\ton\tblocks\tallows\ton,ask,off\tasks',
  'taint-guard\tMOGGER_TAINT\tsafety\ton\ton\tblocks\tallows',
  'push-guard\tMOGGER_PUSH_GUARD\tsafety\ton\ton\tblocks\t-\ton,ask\tasks',
  'hint-noisy-bash\tMOGGER_HINT\tstandard\ton\ton\thints\tnone',
  'smoke-gate\tMOGGER_REQUIRE_SMOKE\toptin\ton\toff\tblocks\tnone',
  'garbage',
].join('\n')

test('parseCatalog reads rows, skips comments and junk, defaults states to on and off', () => {
  const defs = parseCatalog(TSV)
  expect(defs.map(d => d.name)).toEqual(['danger-guard', 'taint-guard', 'push-guard', 'hint-noisy-bash', 'smoke-gate'])
  expect(defs[0]?.states).toEqual(['on', 'ask', 'off'])
  expect(defs[1]?.states).toEqual(['on', 'off'])
  expect(parseCatalog('')).toEqual([])
})

test('options: safety guards never offer off; others offer every state they allow', () => {
  const [danger, taint, push, hint] = parseCatalog(TSV)
  expect(optionsOf(danger!)).toEqual(['on', 'ask'])
  expect(optionsOf(taint!)).toEqual(['on']) // safety, on or off only: nothing to pick
  expect(optionsOf(push!)).toEqual(['on', 'ask'])
  expect(optionsOf(hint!)).toEqual(['on', 'off'])
})

test('rowOf: the file wins when the guard allows its value, else the default', () => {
  const defs = parseCatalog(TSV)
  expect(rowOf(defs[0]!, {})).toEqual({ name: 'danger-guard', kind: 'safety', state: 'on', source: 'default', options: ['on', 'ask'] })
  expect(rowOf(defs[0]!, { 'danger-guard': 'ask' }).state).toBe('ask')
  expect(rowOf(defs[2]!, { 'push-guard': 'off' }).state).toBe('on') // not allowed: ignored, as the script does
  expect(rowOf(defs[4]!, {}).state).toBe('off') // opt-in guard defaults to off
  expect(rowOf(defs[3]!, { 'hint-noisy-bash': 'ask' }).state).toBe('on') // bad value: default
})

test('only guards with a real choice are offered', () => {
  const rows = parseCatalog(TSV).map(d => rowOf(d, {}))
  expect(rows.filter(isPickable).map(r => r.name)).toEqual(['danger-guard', 'push-guard', 'hint-noisy-bash', 'smoke-gate'])
})

test('withPick builds the new file and keeps other keys', () => {
  const [danger, , , hint] = parseCatalog(TSV)
  const r = withPick('{"voice":"off"}', hint!, 'off')
  expect(r.ok).toBe(true)
  expect(r.ok && JSON.parse(r.text)).toEqual({ voice: 'off', 'hint-noisy-bash': 'off' })
  const fresh = withPick(null, danger!, 'ask')
  expect(fresh.ok && JSON.parse(fresh.text)).toEqual({ 'danger-guard': 'ask' })
})

test('a safety guard cannot go off from the bar, and a broken file is never overwritten', () => {
  const [danger, , , hint] = parseCatalog(TSV)
  expect(withPick(null, danger!, 'off').ok).toBe(false)
  expect(withPick(null, hint!, 'ask').ok).toBe(false) // not an allowed state
  const bad = withPick('{not json', hint!, 'off')
  expect(bad.ok).toBe(false)
  expect(parseConfig('[1,2]')).toBeNull()
  expect(parseConfig('')).toEqual({})
})

test('bar options fall back to the defaults on anything odd', () => {
  expect(readBar(undefined)).toEqual(DEFAULT_BAR)
  expect(readBar('x')).toEqual(DEFAULT_BAR)
  expect(readBar(null)).toEqual(DEFAULT_BAR)
  expect(readBar({ robot: false })).toEqual({ robot: false, detail: true })
  expect(readBar({ robot: 'no', detail: 0 })).toEqual(DEFAULT_BAR)
})
