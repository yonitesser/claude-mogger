import { expect, test } from 'claude-code/testing'

import { chadRows, headline, moodOf, toastText } from './chad'

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

test('voice changes the words, not the facts', () => {
  expect(headline('block', 3, 1, true)).toBe('not on my watch')
  expect(headline('idle', 0, 0, true)).toBe('mogger: watching. always.')
  expect(headline('idle', 5, 2, true)).toContain('2 stopped')
  expect(headline('block', 3, 1, false)).toBe('mogger just stopped something')
  expect(toastText('blocked git push', true)).toBe('Not on my watch: blocked git push')
  expect(toastText('blocked git push')).toBe('mogger blocked git push')
})
