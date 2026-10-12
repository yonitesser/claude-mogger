// The mogger chad: a robot (pale head, glowing orange eyes, black armour, orange
// asterisk on the chest) drawn as pixel art in 6 rows of text. Each text row holds two
// pixel rows, stacked with half blocks (fg = top pixel, bg = bottom pixel), so the
// picture is 15 x 12 pixels. Pure helpers: no timers, no engine calls.
// The band above the prompt may be taller than this (see `maxRows` in the engine
// types: up to half the terminal in fullscreen); 5 rows is a design choice.
export type ChadMood = 'idle' | 'block' | 'warn' | 'ok'
export type ChadSeg = { text: string; color?: string; bg?: string }
export type ChadRow = ChadSeg[]

export const ORANGE = '#ff7a1a'
const HEAD = '#e6e6e6'
const SHADE = '#9a9a9a'
const ARMOR = '#2a2a2a'
const PLATE = '#b4b4b4'
const BLINK = '#555555'
// motion lasts this long after a guard fires, then the chad stands still
export const ACTIVE_MS = 4000
export const TICK_MS = 250

export function moodOf(kind: string | undefined, ageMs: number): ChadMood {
  if (kind === undefined || ageMs > ACTIVE_MS) return 'idle'
  return kind === 'block' ? 'block' : kind === 'warn' ? 'warn' : 'ok'
}

// 15 wide, 12 tall. H head, S head shade, E eye (set in a dark visor), K armour, G neck,
// P chest plate, O orange trim (headphones, armour), B asterisk pixel (drawn from PLUS or CROSS below), . empty
const PIXELS = [
  '....SHHKHHS....',
  '...KHHHKHHHK...',
  '..OKKEEKEEKKO..',
  '...KSHHHHHSK...',
  '....SHHHHHS....',
  '.....SHHHS.....',
  '......KGK......',
  'KKKKPPPPPPPKKKK',
  'KOKPPPBBBPPPKOK',
  'KOKPPPBBBPPPKOK',
  'KKKPPPBBBPPPKKK',
  'KKKKPPPPPPPKKKK',
]
// the asterisk on the 3 x 3 chest cells: a plus, or an x; the active chad alternates them
const PLUS = ['.B.', 'BBB', '.B.']
const CROSS = ['B.B', '.B.', 'B.B']

// frame: 0.. (counts ticks). Idle: eyes blink for one tick every 24 ticks
// (6s); the asterisk stays still. Active: the asterisk spins and eyes glow.
export function chadPixels(mood: ChadMood, frame: number): (string | null)[][] {
  const isActive = mood !== 'idle'
  const isBlink = !isActive && frame % 24 === 0
  const eye = isBlink ? BLINK : mood === 'block' ? 'red' : mood === 'warn' ? 'yellow' : ORANGE
  const star = isActive && frame % 2 === 1 ? CROSS : PLUS
  const palette: Record<string, string> = { H: HEAD, S: SHADE, E: eye, K: ARMOR, P: PLATE, G: SHADE, O: ORANGE }
  return PIXELS.map((row, y) =>
    [...row].map((c, x) => {
      if (c === 'B') return star[y - 8]?.[x - 6] === 'B' ? ORANGE : PLATE
      return palette[c] ?? null
    }),
  )
}

// Two pixel rows -> one text row; equal neighbours merge into one segment.
export function chadRows(mood: ChadMood, frame: number): ChadRow[] {
  const px = chadPixels(mood, frame)
  const rows: ChadRow[] = []
  for (let y = 0; y < px.length; y += 2) {
    const row: ChadRow = []
    for (let x = 0; x < (px[y] as (string | null)[]).length; x++) {
      const top = (px[y] as (string | null)[])[x] ?? null
      const bottom = (px[y + 1] as (string | null)[])[x] ?? null
      const seg: ChadSeg =
        top === null && bottom === null
          ? { text: ' ' }
          : top === bottom
            ? { text: '█', color: top as string }
            : bottom === null
              ? { text: '▀', color: top as string }
              : top === null
                ? { text: '▄', color: bottom }
                : { text: '▀', color: top, bg: bottom }
      const last = row[row.length - 1]
      if (last && last.color === seg.color && last.bg === seg.bg) last.text += seg.text
      else row.push(seg)
    }
    rows.push(row)
  }
  return rows
}

// Voice: pools of smug one-liners per moment. The pick is a plain rotation
// (index = seed mod pool size), so the same line never shows twice in a row and
// there are no model calls. The quip sits beside the facts, never in place of them.
export type Moment = 'block' | 'warn' | 'ok' | 'pass' | 'caught' | 'idle' | 'quiet'

export const QUIPS: Record<Moment, string[]> = {
  block: [
    'Not on my watch.',
    'Nice try.',
    'Denied. Warmly.',
    'That was adorable. No.',
    'Bold move. Blocked.',
    'Not today, chaos.',
    'Saved you from yourself.',
    'Hard pass.',
    'Tempting. Still no.',
    'I read the room. The room says no.',
  ],
  warn: [
    'Eyes on this.',
    'Noted. Judging quietly.',
    'Not a block. Yet.',
    'I raised an eyebrow.',
    'That smells off.',
    'Careful. I am watching.',
    'Filing that under suspicious.',
    'Worth a second look. I took it.',
  ],
  ok: [
    'Handled.',
    'Tidied. You are welcome.',
    'Quietly fixed.',
    'Done before you asked.',
    'Sorted.',
    'Routine.',
    'Easy.',
    'Already on it.',
  ],
  pass: [
    'Green. Obviously.',
    'Tests pass. Not surprised.',
    'Clean run.',
    'Zero failures. Naturally.',
    'Green across the board.',
    'That is how it is done.',
    'Passing. Smugly.',
    'Flawless. Again.',
  ],
  caught: [
    'Proof or it did not happen.',
    '"Done" is a claim. Show me.',
    'Nothing ran. Nice story though.',
    'Confidence is not evidence.',
    'Run it. Then we talk.',
    'Bold of you to say done.',
    'I need receipts.',
    'Trust, but verify. Mostly verify.',
  ],
  idle: [
    'mogger: watching. always.',
    'Quiet shift. I like it.',
    'Standing guard. Bring your worst.',
    'All clear. Suspiciously.',
    'Guarding. Smugly.',
    'Ready when you make a mistake.',
    'On duty, effortlessly.',
    'Nothing to stop yet. Give it time.',
  ],
  quiet: [
    'Back to watching.',
    'Calm again.',
    'Back to being bored.',
    'Still here. Still watching.',
    'Scoreboard so far:',
    'Standing guard again.',
    'Resuming smugness.',
    'Nothing else to stop. For now.',
  ],
}

// Which moment an event is. The log only has block|warn|ok, so a few messages
// that mogger writes itself pick the finer ones.
export function momentOf(kind: string, msg: string): Moment {
  if (kind === 'ok' && msg.startsWith('tests passed')) return 'pass'
  if (kind === 'block' && /^(done claim|stopped early|stopped with)/.test(msg)) return 'caught'
  return kind === 'block' ? 'block' : kind === 'warn' ? 'warn' : 'ok'
}

export function quip(moment: Moment, seed: number): string {
  const pool = QUIPS[moment]
  return pool[Math.abs(Math.trunc(seed)) % pool.length] as string
}

// voice=true: the chad's own lines. voice=false: the plain wording. Same facts either way.
// seed picks the line: pass the count of events so far (changes with every event);
// for idle, pass the session start so the line is steady within a session.
export function headline(mood: ChadMood, fired: number, blocked: number, voice = false, last?: { kind: string; msg: string }, seed = fired): string {
  if (voice) {
    if (mood !== 'idle' && last) return quip(momentOf(last.kind, last.msg), seed)
    return fired === 0 ? quip('idle', seed) : `${quip('quiet', seed)} ${blocked} stopped, ${fired - blocked} noted.`
  }
  if (mood === 'block') return 'mogger just stopped something'
  if (mood === 'warn') return 'mogger flagged something'
  if (mood === 'ok') return 'mogger is on it'
  return fired === 0 ? 'mogger is watching' : `mogger is watching: ${fired} checks, ${blocked} blocked`
}

// toast text for a new block: the facts first, the quip after
export function toastText(msg: string, voice = false, seed = 0): string {
  return voice ? `mogger ${msg}. ${quip(momentOf('block', msg), seed)}` : `mogger ${msg}`
}
