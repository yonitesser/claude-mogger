import { expect, test } from 'claude-code/testing'

import { QUIPS, chadRows, chadSvg, headline, momentOf, moodOf, quip, toastText } from './chad'
import type { Moment } from './chad'

test('chad moves only after a guard fires', () => {
  expect(moodOf('block', 1000)).toBe('block')
  expect(moodOf('block', 9000)).toBe('idle')
  expect(moodOf(undefined, 0)).toBe('idle')
  expect(chadRows('idle', 1)).toEqual(chadRows('idle', 2))
  expect(chadRows('block', 1)).not.toEqual(chadRows('block', 2))
})

const textOf = (rows: ReturnType<typeof chadRows>): string[] => rows.map(r => r.map(s => s.text).join(''))
const eyeColors = (rows: ReturnType<typeof chadRows>): (string | undefined)[] => (rows[0] ?? []).map(s => s.color)

test('chad is a robot: 6 rows, 15 cells wide, no hat, orange eyes and chest', () => {
  const rows = chadRows('idle', 1)
  expect(rows.length).toBe(6)
  for (const t of textOf(rows)) expect([...t].length).toBe(15)
  // the top row is the head only: empty cells to the sides
  expect(textOf(rows)[0]?.startsWith('   ')).toBe(true)
  expect(JSON.stringify(rows)).toContain('#ff7a1a')
})

test('chad blinks when idle and glows red on a block', () => {
  expect(JSON.stringify(chadRows('idle', 24))).not.toBe(JSON.stringify(chadRows('idle', 1)))
  expect(JSON.stringify(chadRows('idle', 24))).toContain('#555555')
  expect(JSON.stringify(chadRows('idle', 1))).not.toContain('#555555')
  expect(JSON.stringify(chadRows('block', 1))).toContain('"red"')
  expect(JSON.stringify(chadRows('warn', 1))).toContain('"yellow"')
  expect(headline('block', 3, 1)).toContain('stopped')
})

test('every segment is a half or full block, or a space, and neighbours merge', () => {
  for (const r of chadRows('block', 3)) {
    for (const s of r) expect(/^[ ▀▄█]+$/.test(s.text)).toBe(true)
    for (let i = 1; i < r.length; i++) {
      expect(r[i - 1]?.color === r[i]?.color && r[i - 1]?.bg === r[i]?.bg).toBe(false)
    }
  }
  expect(eyeColors(chadRows('idle', 1)).length > 0).toBe(true)
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

test('chadSvg draws the same pixels as the text rows, as one picture', () => {
  const svg = chadSvg('idle', 1)
  expect(svg.startsWith('<svg')).toBe(true)
  expect(svg).toContain('viewBox="0 0 15 12"')
  expect(svg).toContain('#ff7a1a')
  expect(svg).not.toContain('#555555')
  expect(chadSvg('idle', 24)).toContain('#555555') // the blink
  expect(chadSvg('block', 1)).toContain('fill="red"')
  expect(chadSvg('idle', 1, 10)).toContain('width="150"')
})
