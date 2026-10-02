import { expect, mock, test } from 'claude-code/testing'

const NOW = 1_700_000_100_000
const LOG = [
  '1700000100\tblock\tblocked a secret in config.js',
  '1700000105\tok\tformatted app.ts',
].join('\n')

test('band shows the last event when the log has lines', async ($, on) => {
  mock.clock(on, { now: NOW })
  on('ui.status', async () => ({ value: undefined }) as never)
  on('ui.toast', async () => ({ value: undefined }) as never)
  on('session.start', async () => ({ cwd: '/tmp' }) as never)
  on('fs.read', async () => ({ value: LOG }) as never)
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true } as never)
  const ui = await $.ui.mount({
    plugin: 'mogger-status',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { hasSurvey: false, isWorking: false } as never,
  })
  const text = await ui.find({ type: 'Text', text: /formatted app.ts/ })
  expect(text).toBeDefined()
  await ui.unmount()
})

test('band yields to the engine when there is no log', async ($, on) => {
  mock.clock(on, { now: NOW })
  on('ui.status', async () => ({ value: undefined }) as never)
  on('session.start', async () => ({ cwd: '/tmp' }) as never)
  on('fs.read', async () => {
    throw new Error('ENOENT')
  })
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true } as never)
  // nothing beneath the plugin draws the band, so a plugin that yields leaves
  // mount with no tree: it rejects, which is what "hidden" means here.
  let isDrawn = true
  try {
    await $.ui.mount({
      plugin: 'mogger-status',
      surface: 'terminal',
      component: 'AbovePrompt',
      props: { hasSurvey: false, isWorking: false } as never,
    })
  } catch {
    isDrawn = false
  }
  expect(isDrawn).toBe(false)
})
