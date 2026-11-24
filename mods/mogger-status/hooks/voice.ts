// Voice and mood for the mogger bar: pools of smug one-liners, the headline and the toast text,
// and the mood a recent event gives the glow. Pure helpers: no timers, no engine calls.
export type Mood = 'idle' | 'block' | 'warn' | 'ok'
export const ORANGE = '#ff7a1a'
// the glow shows the mood for this long after a guard fires, then goes back to orange
export const ACTIVE_MS = 4000

export function moodOf(kind: string | undefined, ageMs: number): Mood {
  if (kind === undefined || ageMs > ACTIVE_MS) return 'idle'
  return kind === 'block' ? 'block' : kind === 'warn' ? 'warn' : 'ok'
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

// voice=true: the bar's own lines. voice=false: the plain wording. Same facts either way.
// seed picks the line: pass the count of events so far (changes with every event);
// for idle, pass the session start so the line is steady within a session.
export function headline(mood: Mood, fired: number, blocked: number, voice = false, last?: { kind: string; msg: string }, seed = fired): string {
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
