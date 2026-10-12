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
    plugin: 'mogger',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { hasSurvey: false, isWorking: false } as never,
  })
  const text = await ui.find({ type: 'Text', text: /formatted app.ts/ })
  expect(text).toBeDefined()
  // the robot is drawn too: half-block cells in the chad's colours
  expect(await ui.find({ type: 'Text', text: /[▀▄█]/ })).toBeDefined()
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
      plugin: 'mogger',
      surface: 'terminal',
      component: 'AbovePrompt',
      props: { hasSurvey: false, isWorking: false } as never,
    })
  } catch {
    isDrawn = false
  }
  expect(isDrawn).toBe(false)
})

const GUARD_LIST = [
  'name | state | kind | allowed | ON does | ASK does | OFF does',
  'danger-guard | on (default) | safety | on,ask,off | blocks | asks | allows',
  'hint-noisy-bash | on (default) | standard | on,off | hints | - | none',
].join('\n')

test('Guards button lists guards; pressing one runs the config script', async ($, on) => {
  mock.clock(on, { now: NOW })
  mock.store(on, {})
  const calls: string[][] = []
  on('ui.status', async () => ({ value: undefined }) as never)
  on('ui.toast', async () => ({ value: undefined }) as never)
  on('session.start', async () => ({ cwd: '/tmp' }) as never)
  on('fs.read', async () => ({ value: LOG }) as never)
  on('process.run', async (_$, e) => {
    calls.push([...(e as unknown as { argv: string[] }).argv])
    return { value: { exitCode: 0, stdout: GUARD_LIST, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } } as never
  })
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true } as never)
  const ui = await $.ui.mount({
    plugin: 'mogger',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { hasSurvey: false, isWorking: false } as never,
  })
  await ui.press({ key: 'guards' })
  expect(await ui.find({ type: 'Button', text: /hint-noisy-bash: on/ })).toBeDefined()
  await ui.press({ key: 'hint-noisy-bash' })
  const set = calls.find(c => c.includes('set'))
  expect(set?.slice(-3)).toEqual(['set', 'hint-noisy-bash', 'off'])
  // never --confirm: the bar cannot talk a safety guard off
  expect(calls.some(c => c.includes('--confirm'))).toBe(false)
  await ui.unmount()
})

test('Bar button hides the robot and the choice is stored', async ($, on) => {
  mock.clock(on, { now: NOW })
  mock.store(on, {})
  on('ui.status', async () => ({ value: undefined }) as never)
  on('ui.toast', async () => ({ value: undefined }) as never)
  on('session.start', async () => ({ cwd: '/tmp' }) as never)
  on('fs.read', async () => ({ value: LOG }) as never)
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true } as never)
  const ui = await $.ui.mount({
    plugin: 'mogger',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { hasSurvey: false, isWorking: false } as never,
  })
  await ui.press({ key: 'bar' })
  await ui.press({ key: 'opt-robot' })
  expect(await ui.find({ type: 'Text', text: /[▀▄█]/ })).toBeUndefined()
  await ui.unmount()
  // a new session reads the stored choice back: still no robot
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true } as never)
  const again = await $.ui.mount({
    plugin: 'mogger',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { hasSurvey: false, isWorking: false } as never,
  })
  expect(await again.find({ type: 'Text', text: /[▀▄█]/ })).toBeUndefined()
  expect(await again.find({ type: 'Text', text: /formatted app.ts/ })).toBeDefined()
  await again.unmount()
})

test('a failing config script shows a toast, not a crash', async ($, on) => {
  mock.clock(on, { now: NOW })
  mock.store(on, {})
  const toasts: string[] = []
  on('ui.status', async () => ({ value: undefined }) as never)
  on('ui.toast', async (_$, e) => (toasts.push(JSON.stringify(e)), { value: undefined }) as never)
  on('session.start', async () => ({ cwd: '/tmp' }) as never)
  on('fs.read', async () => ({ value: LOG }) as never)
  let n = 0
  on('process.run', async () => {
    n++
    // the list works; the set fails
    return { value: { exitCode: n === 1 ? 0 : 1, stdout: n === 1 ? GUARD_LIST : '', stderr: 'no', isStdoutTruncated: false, isStderrTruncated: false } } as never
  })
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true } as never)
  const ui = await $.ui.mount({
    plugin: 'mogger',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { hasSurvey: false, isWorking: false } as never,
  })
  await ui.press({ key: 'guards' })
  await ui.press({ key: 'hint-noisy-bash' })
  expect(toasts.join('').includes('could not set hint-noisy-bash')).toBe(true)
  await ui.unmount()
})
