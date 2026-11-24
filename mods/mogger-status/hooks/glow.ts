// The glow: a slow pulse on a thin line over the prompt. Pure helpers: no timers, no engine calls.
// The tick comes from register.tsx. One full pulse is PERIOD ticks (about 8 seconds).
import type { Mood } from './voice'
import { ORANGE } from './voice'

export const GLOW_TICK_MS = 700
export const PERIOD = 12
const BASE = '#3a2a1e' // the dim end of the pulse: near the background, a hint of warm

const MOOD_COLOR: Record<Mood, string> = { idle: ORANGE, ok: '#3ddc84', warn: '#ffd23f', block: '#ff4d4d' }

// 0..1, a smooth swell: 0 at frame 0, 1 half a period later
export function level(frame: number): number {
  return (1 - Math.cos((2 * Math.PI * (frame % PERIOD)) / PERIOD)) / 2
}

const channel = (hex: string, i: number): number => parseInt(hex.slice(1 + i * 2, 3 + i * 2), 16)

// a colour part-way from `from` to `to`, as #rrggbb
export function mix(from: string, to: string, t: number): string {
  const c = [0, 1, 2].map(i => Math.round(channel(from, i) + (channel(to, i) - channel(from, i)) * t))
  return `#${c.map(v => v.toString(16).padStart(2, '0')).join('')}`
}

// the pulse colour for this frame: dim to the mood's colour and back
export function glowColor(mood: Mood, frame: number): string {
  return mix(BASE, MOOD_COLOR[mood], 0.15 + 0.85 * level(frame))
}

// the terminal cannot blur, so the pulse is a thin rule in that colour
export function rule(columns: number): string {
  return '─'.repeat(Math.max(1, Math.min(columns, 200)))
}
