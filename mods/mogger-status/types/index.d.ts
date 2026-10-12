export type MoggerEvent = { ts: number; kind: string; msg: string }
export type MoggerSummary = {
  fired: number
  blocked: number
  last: MoggerEvent | null
}

declare module 'claude-code' {
  interface PluginState {
    'mogger': {
      summary: MoggerSummary | null
      isHidden: boolean
      since: number
      frame: number
      voice: boolean
      panel: 'none' | 'guards' | 'bar'
      guards: { name: string; state: string; source: string; kind: string; allowed: string[] }[]
      bar: { robot: boolean; detail: boolean }
    }
  }
}
