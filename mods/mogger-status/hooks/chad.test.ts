import { expect, test } from 'claude-code/testing'

import { chadRows, headline, moodOf } from './chad'

test('chad moves only after a guard fires', () => {
  expect(moodOf('block', 1000)).toBe('block')
  expect(moodOf('block', 9000)).toBe('idle')
  expect(moodOf(undefined, 0)).toBe('idle')
  expect(chadRows('idle', 1)).toEqual(chadRows('idle', 2))
  expect(chadRows('block', 1)).not.toEqual(chadRows('block', 2))
})

test('chad blinks when idle and glows red on a block', () => {
  expect(chadRows('idle', 24)[1]?.text).toContain('─')
  expect(chadRows('idle', 1)[1]?.text).toContain('◉')
  expect(chadRows('block', 1)[1]?.color).toBe('red')
  expect(headline('block', 3, 1)).toContain('stopped')
})
