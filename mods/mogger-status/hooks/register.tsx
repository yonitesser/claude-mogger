import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { MoggerSummary } from '../types'
import { LOG_PATH, ageText, newBlocks, newestTs, parseLog, statusText, summarize } from './log'

const summaryAtom = atom({ plugin: 'mogger-status', key: 'summary' } as const, null as MoggerSummary | null)
const isHidden = atom({ plugin: 'mogger-status', key: 'isHidden' } as const, false)
const sinceAtom = atom({ plugin: 'mogger-status', key: 'since' } as const, 0)

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
  if (seenTs >= 0) {
    for (const b of newBlocks(events, seenTs)) {
      $.ui.toast(`mogger ${b.msg}`)
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

    return (
      <Box>
        <Text dimColor={isQuiet} color={isQuiet ? undefined : color}>
          {line}{' '}
        </Text>
        <Button key="hide" label="Hide" onPress={() => update($, isHidden, () => true)} />
      </Box>
    )
  })
}
