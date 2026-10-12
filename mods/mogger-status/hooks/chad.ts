// The mogger chad (robot with orange eyes and an orange burst on the chest,
// from assets/mogger-banner.png) drawn in 3 rows of plain text. Pure helpers:
// no timers, no engine calls.
export type ChadMood = 'idle' | 'block' | 'warn' | 'ok'
export type ChadRow = { text: string; color?: string }

export const ORANGE = '#ff7a1a'
const BURST = ['✻', '✺', '✹', '✸']
// motion lasts this long after a guard fires, then the chad stands still
export const ACTIVE_MS = 4000
export const TICK_MS = 250

export function moodOf(kind: string | undefined, ageMs: number): ChadMood {
  if (kind === undefined || ageMs > ACTIVE_MS) return 'idle'
  return kind === 'block' ? 'block' : kind === 'warn' ? 'warn' : 'ok'
}

// frame: 0.. (counts ticks). Idle: eyes blink for one tick every 24 ticks
// (6s); the burst stays still. Active: the burst spins and eyes glow.
export function chadRows(mood: ChadMood, frame: number): ChadRow[] {
  const isActive = mood !== 'idle'
  const isBlink = !isActive && frame % 24 === 0
  const eye = isBlink ? '─' : '◉'
  const eyeColor = mood === 'block' ? 'red' : mood === 'warn' ? 'yellow' : ORANGE
  const burst = BURST[isActive ? frame % BURST.length : 0] as string
  return [
    { text: ' ▄███▄ ' },
    { text: `▐${eye} ${eye}▌`, color: eyeColor },
    { text: ` ▀${burst}${isActive ? '█' : '▄'}▀ `, color: ORANGE },
  ]
}

// voice=true: the chad's own lines (mogger's voice, see the "voice" toggle).
// voice=false: the plain wording. Same facts either way.
export function headline(mood: ChadMood, fired: number, blocked: number, voice = false): string {
  if (voice) {
    if (mood === 'block') return 'not on my watch'
    if (mood === 'warn') return 'eyes on this'
    if (mood === 'ok') return 'handled'
    return fired === 0 ? 'mogger: watching. always.' : `mogger: watching. ${blocked} stopped, ${fired - blocked} noted`
  }
  if (mood === 'block') return 'mogger just stopped something'
  if (mood === 'warn') return 'mogger flagged something'
  if (mood === 'ok') return 'mogger is on it'
  return fired === 0 ? 'mogger is watching' : `mogger is watching: ${fired} checks, ${blocked} blocked`
}

// toast text for a new block
export function toastText(msg: string, voice = false): string {
  return voice ? `Not on my watch: ${msg}` : `mogger ${msg}`
}
