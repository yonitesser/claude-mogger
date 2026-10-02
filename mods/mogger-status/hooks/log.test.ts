import { expect, test } from 'claude-code/testing'

import { ageText, newBlocks, newestTs, parseLog, statusText, summarize } from './log'

const LOG = [
  '1700000000\tinfo\tmogger is on for this session',
  '1700000010\tblock\tblocked a secret in config.js',
  '1700000020\tok\tformatted app.ts',
  'garbage line',
  '1700000030\twarn\tmore tests fail after the last edit',
  '1700000040\tblock\tblocked git push',
  '',
].join('\n')

test('parseLog keeps good lines and skips bad ones', async () => {
  const ev = parseLog(LOG)
  expect(ev.length).toBe(5)
  expect(ev[1]?.kind).toBe('block')
  expect(ev[1]?.msg).toBe('blocked a secret in config.js')
  expect(parseLog('').length).toBe(0)
})

test('summarize counts guards and blocks, not info lines', async () => {
  const s = summarize(parseLog(LOG), 0)
  expect(s.fired).toBe(4)
  expect(s.blocked).toBe(2)
  expect(s.last?.msg).toBe('blocked git push')
  expect(statusText(s)).toBe('mogger: 4 guards fired, 2 blocked')
})

test('summarize only counts events since the session began', async () => {
  const s = summarize(parseLog(LOG), 1700000025 * 1000)
  expect(s.fired).toBe(2)
  expect(s.blocked).toBe(1)
})

test('newBlocks returns only newer blocks', async () => {
  const ev = parseLog(LOG)
  expect(newBlocks(ev, 1700000010).length).toBe(1)
  expect(newBlocks(ev, newestTs(ev)).length).toBe(0)
})

test('ageText is short', async () => {
  expect(ageText(1700000030 * 1000, 1700000000)).toBe('30s ago')
  expect(ageText(1700000300 * 1000, 1700000000)).toBe('5m ago')
})
