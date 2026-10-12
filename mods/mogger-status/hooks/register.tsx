import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { MoggerSummary } from '../types'
import { ORANGE, TICK_MS, chadRows, headline, moodOf, toastText } from './chad'
import { LOG_PATH, ageText, newBlocks, newestTs, parseLog, statusText, summarize, voiceOn } from './log'

const summaryAtom = atom({ plugin: 'mogger', key: 'summary' } as const, null as MoggerSummary | null)
const isHidden = atom({ plugin: 'mogger', key: 'isHidden' } as const, false)
const sinceAtom = atom({ plugin: 'mogger', key: 'since' } as const, 0)

const voiceAtom = atom({ plugin: 'mogger', key: 'voice' } as const, true)
const frameAtom = atom({ plugin: 'mogger', key: 'frame' } as const, 0)

const QUIET_MS = 60_000
const POLL_MS = 2000

// newest event time already seen (seconds); -1 until the first read, so
// old blocks from earlier sessions never toast.
let seenTs = -1

async function refresh($: EngineInterface): Promise<void> {
  let text = ''
  try {
    text = await $.fs.read(LOG_PATH)
  } catch {
    // no log yet: show nothing
    $.ui.status(undefined)
    await update($, summaryAtom, () => null)
    return
  }
  const events = parseLog(text)
  let since = await read($, sinceAtom)
  if (since === 0) {
    since = await $.clock.now()
    await update($, sinceAtom, () => since)
  }
  const s = summarize(events, since)
  const voice = voiceOn(events)
  await update($, voiceAtom, () => voice)
  if (seenTs >= 0) {
    for (const b of newBlocks(events, seenTs)) {
      $.ui.toast(toastText(b.msg, voice, b.ts))
    }
  }
  seenTs = newestTs(events)
  await update($, summaryAtom, () => s)
  $.ui.status(statusText(s))
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await refresh($)
    $.clock.every(POLL_MS, () => refresh($))
    // motion: ticks only change the picture while the chad moves or blinks
    $.clock.every(TICK_MS, async () => {
      const now = await $.clock.now()
      const s = await read($, summaryAtom)
      const mood = moodOf(s?.last?.kind, s?.last ? now - s.last.ts * 1000 : Infinity)
      const frame = Math.floor(now / TICK_MS)
      const want = mood === 'idle' ? (frame % 24 === 0 ? 24 : 1) : frame
      if (want !== (await read($, frameAtom))) await update($, frameAtom, () => want)
    })
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    await refresh($)
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const s = await read($, summaryAtom)
    if (e.props.hasSurvey || s === null || (await read($, isHidden))) {
      return next(e)
    }
    const { Box, Button, Text } = $.ui.resolve(e)
    const now = await $.clock.now()
    const last = s.last
    const isQuiet = last === null || now - last.ts * 1000 > QUIET_MS
    const color = last === null ? undefined : last.kind === 'block' ? 'red' : last.kind === 'warn' ? 'yellow' : 'green'
    const line =
      last === null
        ? `${statusText(s)}. Nothing to report yet.`
        : `${statusText(s)}. Last: ${last.msg} (${ageText(now, last.ts)})`

    const frame = await read($, frameAtom)
    const voice = await read($, voiceAtom)
    const mood = moodOf(last?.kind, last ? now - last.ts * 1000 : Infinity)
    const rows = chadRows(mood, frame)
    const seed = mood === 'idle' ? Math.floor((await read($, sinceAtom)) / 1000) : s.fired

    return (
      <Box alignItems="center">
        <Box flexDirection="column" marginRight={2}>
          {rows.map((r, i) => (
            <Box key={`c${i}`}>
              {r.map((s, j) => (
                <Text key={`c${i}-${j}`} color={s.color} backgroundColor={s.bg}>
                  {s.text}
                </Text>
              ))}
            </Box>
          ))}
        </Box>
        <Box flexDirection="column">
          <Text bold color={ORANGE}>
            {headline(mood, s.fired, s.blocked, voice, last ?? undefined, seed)}
          </Text>
          <Text dimColor={isQuiet} color={isQuiet ? undefined : color}>
            {line}{' '}
          </Text>
          <Button key="hide" label="Hide" onPress={() => update($, isHidden, () => true)} />
        </Box>
      </Box>
    )
  })
}
