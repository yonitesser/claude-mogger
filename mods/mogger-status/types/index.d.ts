export type MoggerEvent = { ts: number; kind: string; msg: string }
export type MoggerSummary = {
  fired: number
  blocked: number
  last: MoggerEvent | null
}

declare module 'claude-code' {
  interface PluginState {
    'mogger-status': {
      summary: MoggerSummary | null
      isHidden: boolean
      since: number
    }
  }
}
