import { expect, test } from 'claude-code/testing'

import { DEFAULT_BAR, nextState, parseGuards, readBar } from './panel'

const LIST = [
  'name | state | kind | allowed | ON does | ASK does | OFF does',
  'danger-guard | on (default) | safety | on,ask,off | blocks | asks | allows',
  'taint-guard | on (default) | safety | on,off | blocks | - | allows',
  'push-guard | ask (file) | safety | on,ask | blocks | asks | -',
  'hint-noisy-bash | on (default) | standard | on,off | hints | - | none',
  'smoke-gate | off (env) | optin | on,off | blocks | - | none',
  'garbage line',
].join('\n')

test('parseGuards reads the list and skips headers and junk', () => {
  const g = parseGuards(LIST)
  expect(g.length).toBe(5)
  expect(g[0]).toEqual({ name: 'danger-guard', state: 'on', source: 'default', kind: 'safety', allowed: ['on', 'ask', 'off'] })
  expect(parseGuards('')).toEqual([])
})

test('a press cycles on, ask, off but never takes a safety guard to off', () => {
  const g = parseGuards(LIST)
  expect(nextState(g[0]!)).toBe('ask') // safety, on -> ask
  expect(nextState({ ...g[0]!, state: 'ask' })).toBe('on') // safety: ask -> on, not off
  expect(nextState(g[1]!)).toBeNull() // safety with no ask: nothing a button may do
  expect(nextState(g[2]!)).toBe('on') // ask -> on
  expect(nextState(g[3]!)).toBe('off') // standard: on -> off
  expect(nextState({ ...g[3]!, state: 'off' })).toBe('on')
})

test('an env var wins, so the button is not offered', () => {
  expect(nextState(parseGuards(LIST)[4]!)).toBeNull()
})

test('bar options fall back to the defaults on anything odd', () => {
  expect(readBar(undefined)).toEqual(DEFAULT_BAR)
  expect(readBar('x')).toEqual(DEFAULT_BAR)
  expect(readBar(null)).toEqual(DEFAULT_BAR)
  expect(readBar({ robot: false })).toEqual({ robot: false, detail: true })
  expect(readBar({ robot: 'no', detail: 0 })).toEqual(DEFAULT_BAR)
})
