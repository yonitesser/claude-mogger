import { expect, test } from 'claude-code/testing'

import { PERIOD, glowColor, level, mix, rule } from './glow'

test('the pulse swells and fades once per period', () => {
  expect(level(0)).toBe(0)
  expect(level(PERIOD / 2)).toBe(1)
  expect(level(PERIOD)).toBe(0)
  for (let f = 0; f < PERIOD * 2; f++) expect(level(f) >= 0 && level(f) <= 1).toBe(true)
})

test('colours mix to valid hex and the mood changes the bright end', () => {
  expect(mix('#000000', '#ffffff', 0.5)).toBe('#808080')
  for (let f = 0; f < PERIOD; f++) expect(glowColor('idle', f)).toMatch(/^#[0-9a-f]{6}$/)
  expect(glowColor('block', PERIOD / 2)).toBe('#ff4d4d')
  expect(glowColor('idle', PERIOD / 2)).toBe('#ff7a1a')
  expect(glowColor('idle', 0)).not.toBe(glowColor('idle', PERIOD / 2))
})

test('the rule is at least one cell and never huge', () => {
  expect(rule(0)).toBe('─')
  expect(rule(80).length).toBe(80)
  expect(rule(100000).length).toBe(200)
})
