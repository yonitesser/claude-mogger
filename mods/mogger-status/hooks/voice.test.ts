import { expect, test } from 'claude-code/testing'

import { QUIPS, headline, momentOf, moodOf, quip, toastText } from './voice'
import type { Moment } from './voice'

test('mood is set only just after a guard fires', () => {
  expect(moodOf('block', 1000)).toBe('block')
  expect(moodOf('block', 9000)).toBe('idle')
  expect(moodOf(undefined, 0)).toBe('idle')
  expect(moodOf('ok', 1)).toBe('ok')
})

test('voice changes the words, not the facts', () => {
  expect(headline('block', 3, 1, false)).toBe('mogger just stopped something')
  expect(headline('idle', 0, 0, false)).toBe('mogger is watching')
  expect(headline('block', 3, 1, true, { kind: 'block', msg: 'blocked git push' }, 0)).toBe(QUIPS.block[0])
  expect(toastText('blocked git push', false)).toBe('mogger blocked git push')
  // the facts stay in the toast, the quip comes after
  expect(toastText('blocked git push', true, 1)).toBe(`mogger blocked git push. ${QUIPS.block[1]}`)
  expect(headline('idle', 5, 2, true, undefined, 3)).toContain('2 stopped, 3 noted.')
})

test('every moment has a pool of 8 or more distinct lines', () => {
  for (const m of Object.keys(QUIPS) as Moment[]) {
    expect(QUIPS[m].length >= 8).toBe(true)
    expect(new Set(QUIPS[m]).size).toBe(QUIPS[m].length)
  }
})

test('rotation never repeats a line on the next event', () => {
  for (const m of Object.keys(QUIPS) as Moment[]) {
    for (let i = 0; i < 40; i++) expect(quip(m, i)).not.toBe(quip(m, i + 1))
  }
})

test('moments: tests passed and false done get their own pools', () => {
  expect(momentOf('ok', 'tests passed')).toBe('pass')
  expect(momentOf('ok', 'formatted a.ts')).toBe('ok')
  expect(momentOf('block', 'done claim after code edits (noproof)')).toBe('caught')
  expect(momentOf('block', 'blocked git push')).toBe('block')
  expect(momentOf('warn', 'x')).toBe('warn')
})

test('a quip never replaces or garbles a block reason', () => {
  for (const q of QUIPS.block) expect(q.length < 40).toBe(true)
})
