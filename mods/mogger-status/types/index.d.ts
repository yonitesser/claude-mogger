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
      guards: { name: string; kind: string; state: string; source: 'file' | 'default'; options: string[] }[]
      note: string
      minute: number
      bar: { robot: boolean; detail: boolean }
    }
  }
}
