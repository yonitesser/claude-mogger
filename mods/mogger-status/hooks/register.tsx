import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { MoggerSummary } from '../types'
import { ORANGE, TICK_MS, chadRows, chadSvg, headline, moodOf, toastText } from './chad'
import { DEFAULT_BAR, isPickable, parseCatalog, parseConfig, readBar, rowOf, withPick } from './panel'
import type { BarOptions, GuardRow } from './panel'
import { LOG_PATH, TESTS_PATH, ageText, newBlocks, newestTs, parseLog, statusText, summarize, testsOf, testsText, voiceOn } from './log'

const summaryAtom = atom({ plugin: 'mogger', key: 'summary' } as const, null as MoggerSummary | null)
const isHidden = atom({ plugin: 'mogger', key: 'isHidden' } as const, false)
const sinceAtom = atom({ plugin: 'mogger', key: 'since' } as const, 0)

const voiceAtom = atom({ plugin: 'mogger', key: 'voice' } as const, true)
const panelAtom = atom({ plugin: 'mogger', key: 'panel' } as const, 'none' as 'none' | 'guards' | 'bar')
const guardsAtom = atom({ plugin: 'mogger', key: 'guards' } as const, [] as GuardRow[])
const noteAtom = atom({ plugin: 'mogger', key: 'note' } as const, '')
const barAtom = atom({ plugin: 'mogger', key: 'bar' } as const, DEFAULT_BAR as BarOptions)
const frameAtom = atom({ plugin: 'mogger', key: 'frame' } as const, 0)
const testsAtom = atom({ plugin: 'mogger', key: 'tests' } as const, null as 'pass' | 'fail' | null)
const minuteAtom = atom({ plugin: 'mogger', key: 'minute' } as const, 0)

const QUIET_MS = 60_000
const POLL_MS = 2000
const CONFIG_PATH = '.claude/mogger.json'

// newest event time already seen (seconds); -1 until the first read, so
// old blocks from earlier sessions never toast.
let seenTs = -1
// Only the terminal draws the robot as text (half blocks); the desktop app, the editor and the phone
// get a picture. A picture does not need to blink, so those surfaces redraw less, and a button press
// is not lost to a redraw in the middle of the click.
let isTerminal = true

async function refresh($: EngineInterface): Promise<void> {
  let text = ''
  try {
    text = await $.fs.read(LOG_PATH)
  } catch {
    // no log yet: show nothing
    $.ui.status(undefined)
    if ((await read($, summaryAtom)) !== null) await update($, summaryAtom, () => null)
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
  if (voice !== (await read($, voiceAtom))) await update($, voiceAtom, () => voice)
  if (seenTs >= 0) {
    for (const b of newBlocks(events, seenTs)) {
      $.ui.toast(toastText(b.msg, voice, b.ts))
    }
  }
  seenTs = newestTs(events)
  // write only a changed summary: a redraw every poll could land between a button's press and release
  if (JSON.stringify(s) !== JSON.stringify(await read($, summaryAtom))) await update($, summaryAtom, () => s)
  let tests: 'pass' | 'fail' | null = null
  try {
    tests = testsOf(await $.fs.read(TESTS_PATH))
  } catch {
    // no test run yet: show nothing
  }
  if (tests !== (await read($, testsAtom))) await update($, testsAtom, () => tests)
  const minute = Math.floor((await $.clock.now()) / 60_000)
  if (minute !== (await read($, minuteAtom))) await update($, minuteAtom, () => minute) // keeps "(5m ago)" fresh
  $.ui.status(statusText(s))
}

// The guard panel reads the catalog and the switch file itself, and writes the same file the mogger:config
// script writes. No command is run, so it needs no jq and no shell.
async function readConfig($: EngineInterface): Promise<string | null> {
  try {
    return await $.fs.read(CONFIG_PATH)
  } catch {
    return null
  }
}

async function loadGuards($: EngineInterface): Promise<void> {
  try {
    const defs = parseCatalog(await $.fs.read(`${$.plugin.root}/hooks/guards.tsv`))
    const cfg = parseConfig(await readConfig($))
    if (cfg === null) {
      await update($, noteAtom, () => 'The switch file .claude/mogger.json is not valid JSON. Fix it by hand, then open Guards again.')
      await update($, guardsAtom, () => [])
      return
    }
    await update($, guardsAtom, () => defs.map(d => rowOf(d, cfg)).filter(isPickable))
    await update($, noteAtom, () => (defs.length === 0 ? 'The guard list is empty.' : ''))
  } catch (err) {
    await update($, guardsAtom, () => [])
    await update($, noteAtom, () => `Could not read the guard list: ${err instanceof Error ? err.message : String(err)}`)
  }
}

async function setGuard($: EngineInterface, name: string, to: string): Promise<void> {
  try {
    const d = parseCatalog(await $.fs.read(`${$.plugin.root}/hooks/guards.tsv`)).find(x => x.name === name)
    if (d === undefined) throw new Error(`unknown guard ${name}`)
    const r = withPick(await readConfig($), d, to)
    if (!r.ok) {
      $.ui.toast(`mogger: ${r.reason}`)
    } else {
      await $.fs.write(CONFIG_PATH, r.text)
      $.ui.toast(`mogger: ${name} is now ${to}`)
    }
  } catch (err) {
    $.ui.toast(`mogger: could not set ${name}: ${err instanceof Error ? err.message : String(err)}`)
  }
  await loadGuards($)
}

async function setBar($: EngineInterface, next: BarOptions): Promise<void> {
  await update($, barAtom, () => next)
  try {
    await $.store.set('mogger.bar', next)
  } catch {
    // not stored: the choice holds for this session only
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    isTerminal = e.surface === null || e.surface === 'terminal'
    try {
      const saved = await $.store.get('mogger.bar')
      await update($, barAtom, () => readBar(saved))
    } catch {
      // no stored choice: defaults
    }
    await refresh($)
    $.clock.every(POLL_MS, () => refresh($))
    // motion: ticks only change the picture while the chad moves or blinks
    $.clock.every(TICK_MS, async () => {
      const now = await $.clock.now()
      const s = await read($, summaryAtom)
      const mood = moodOf(s?.last?.kind, s?.last ? now - s.last.ts * 1000 : Infinity)
      const frame = Math.floor(now / TICK_MS)
      const want = mood === 'idle' ? (isTerminal && frame % 24 === 0 ? 24 : 1) : frame
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
    // Svg is drawn on the remote surfaces (desktop, editor, phone) and Select on all but the phone;
    // the terminal's table has no Svg and the phone's no Select
    const table = $.ui.resolve(e) as unknown as Record<string, any>
    const Svg = e.surface === 'terminal' ? undefined : table.Svg
    const Select = e.surface === 'mobile' ? undefined : table.Select
    const now = await $.clock.now()
    const last = s.last
    const isQuiet = last === null || now - last.ts * 1000 > QUIET_MS
    const color = last === null ? undefined : last.kind === 'block' ? 'red' : last.kind === 'warn' ? 'yellow' : 'green'
    const line =
      last === null
        ? `${statusText(s)}. Nothing to report yet.`
        : `${statusText(s)}. Last: ${last.msg} (${ageText(now, last.ts)})`

    const tests = await read($, testsAtom)
    const frame = await read($, frameAtom)
    const voice = await read($, voiceAtom)
    const mood = moodOf(last?.kind, last ? now - last.ts * 1000 : Infinity)
    const rows = chadRows(mood, frame)
    const seed = mood === 'idle' ? Math.floor((await read($, sinceAtom)) / 1000) : s.fired

    const bar = await read($, barAtom)
    const panel = await read($, panelAtom)
    const guards = await read($, guardsAtom)
    const note = await read($, noteAtom)
    const toggle = async (to: 'guards' | 'bar') => {
      const open = await read($, panelAtom)
      if (open === to) return update($, panelAtom, () => 'none' as const)
      if (to === 'guards') await loadGuards($)
      return update($, panelAtom, () => to)
    }
    const onOff = [{ value: 'on' }, { value: 'off' }]
    // a dropdown where the surface has one; the phone has none, so a button that flips the value
    const pick = (key: string, label: string, options: { value: string }[], value: string, onPick: (v: string) => unknown) =>
      Select ? (
        <Box key={`pick-${key}`} marginRight={2}>
          <Select key={`sel-${key}`} label={`${label}:`} options={options} value={value} onSelect={(v: string) => onPick(v)} />
        </Box>
      ) : (
        <Box key={`pick-${key}`} marginRight={2}>
          <Button
            key={`btn-${key}`}
            label={`${label}: ${value}`}
            onPress={() => onPick(options[(options.findIndex(o => o.value === value) + 1) % options.length]?.value ?? value)}
          />
        </Box>
      )

    return (
      <Box flexDirection="column">
        <Box alignItems="center">
          {bar.robot && (
            <Box flexDirection="column" marginRight={2}>
              {Svg ? (
                <Svg source={chadSvg(mood, frame)} alt="mogger, a robot with orange eyes" />
              ) : (
                rows.map((r, i) => (
                  <Box key={`c${i}`}>
                    {r.map((seg, j) => (
                      <Text key={`c${i}-${j}`} color={seg.color} backgroundColor={seg.bg}>
                        {seg.text}
                      </Text>
                    ))}
                  </Box>
                ))
              )}
            </Box>
          )}
          <Box flexDirection="column">
            <Text bold color={ORANGE}>
              {headline(mood, s.fired, s.blocked, voice, last ?? undefined, seed)}
            </Text>
            {bar.detail && (
              <Text dimColor={isQuiet} color={isQuiet ? undefined : color}>
                {line}{' '}
              </Text>
            )}
            {bar.detail && tests !== null && (
              <Text color={tests === 'fail' ? 'red' : 'green'}>{testsText(tests)} </Text>
            )}
            <Box>
              <Button key="guards" label={`⚙ Guards ${panel === 'guards' ? '▴' : '▾'}`} variant="primary" onPress={() => toggle('guards')} />
              <Text> </Text>
              <Button key="bar" label={`◐ Display ${panel === 'bar' ? '▴' : '▾'}`} variant="primary" onPress={() => toggle('bar')} />
              <Text> </Text>
              <Button key="hide" label="✕ Hide" onPress={() => update($, isHidden, () => true)} />
            </Box>
          </Box>
        </Box>
        {panel === 'bar' && (
          <Box flexDirection="column" marginTop={1}>
            <Text dimColor>What this bar shows (kept for next time):</Text>
            <Box flexWrap="wrap">
              {pick('robot', 'Robot', onOff, bar.robot ? 'on' : 'off', v => setBar($, { ...bar, robot: v === 'on' }))}
              {pick('detail', 'Detail line', onOff, bar.detail ? 'on' : 'off', v => setBar($, { ...bar, detail: v === 'on' }))}
            </Box>
          </Box>
        )}
        {panel === 'guards' && (
          <Box flexDirection="column" marginTop={1}>
            <Text dimColor>Pick on (block), ask (you decide each time) or off (allow) for each guard. Safety guards can only be on or ask here; to turn one off use /mogger:config. A MOGGER_* variable that is set still wins.</Text>
            {note !== '' && <Text color="red">{note}</Text>}
            <Box flexWrap="wrap">
              {guards.map(g =>
                pick(
                  g.name,
                  g.name,
                  g.options.map(value => ({ value })),
                  g.state,
                  v => setGuard($, g.name, v),
                ),
              )}
            </Box>
          </Box>
        )}
      </Box>
    )
  })
}
