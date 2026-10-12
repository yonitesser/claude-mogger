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

// ---- panels: the guard list is read from guards.tsv and the switch file, no command is run ----
const CATALOG = [
  '# name\tENV_VAR\tkind\ton-value\tdefault\tif ON\tif OFF\tstates\tif ASK',
  'danger-guard\tMOGGER_DANGER_GUARD\tsafety\ton\ton\tblocks\tallows\ton,ask,off\tasks',
  'hint-noisy-bash\tMOGGER_HINT\tstandard\ton\ton\thints\tnone',
].join('\n')

type Setup = { surface?: 'terminal' | 'desktop'; config?: string | null; failCatalog?: boolean }

// answers fs.read by path (log, catalog, switch file) and records fs.write
async function setup($: any, on: any, o: Setup = {}) {
  mock.clock(on, { now: NOW })
  mock.store(on, {})
  const writes: { path: string; text: string }[] = []
  const toasts: string[] = []
  on('ui.status', async () => ({ value: undefined }) as never)
  on('ui.toast', async (_$: unknown, e: unknown) => (toasts.push(JSON.stringify(e)), { value: undefined }) as never)
  on('session.start', async () => ({ cwd: '/tmp' }) as never)
  on('fs.read', async (_$: unknown, e: { path: string }) => {
    if (e.path.endsWith('guards.tsv')) {
      if (o.failCatalog) throw new Error('ENOENT')
      return { value: CATALOG } as never
    }
    if (e.path.endsWith('mogger.json')) {
      if (o.config === null || o.config === undefined) throw new Error('ENOENT')
      return { value: o.config } as never
    }
    return { value: LOG } as never
  })
  on('fs.write', async (_$: unknown, e: { path: string; text: string }) => (writes.push({ path: e.path, text: e.text }), { value: undefined }) as never)
  const surface = o.surface ?? 'terminal'
  await $.session.start({ cwd: '/tmp', surface, isInteractive: true } as never)
  const ui = await $.ui.mount({ plugin: 'mogger', surface, component: 'AbovePrompt', props: { hasSurvey: false, isWorking: false } as never })
  return { ui, writes, toasts }
}

test('Guards opens a dropdown for each changeable guard, and a pick writes the switch file', async ($, on) => {
  const { ui, writes, toasts } = await setup($, on, { config: '{"voice":"off"}' })
  expect(await ui.find({ type: 'Select', key: 'sel-hint-noisy-bash' })).toBeUndefined() // closed until opened
  await ui.press({ key: 'guards' })
  expect(await ui.find({ type: 'Select', key: 'sel-danger-guard' })).toBeDefined()
  expect(await ui.find({ type: 'Select', key: 'sel-hint-noisy-bash' })).toBeDefined()
  await ui.select({ key: 'sel-hint-noisy-bash', value: 'off' })
  expect(writes.length).toBe(1)
  expect(writes[0]?.path.endsWith('.claude/mogger.json')).toBe(true)
  expect(JSON.parse(writes[0]?.text ?? '{}')).toEqual({ voice: 'off', 'hint-noisy-bash': 'off' })
  expect(toasts.join('').includes('hint-noisy-bash is now off')).toBe(true)
  await ui.unmount()
})

test('a safety guard offers on and ask only, never off', async ($, on) => {
  const { ui, writes } = await setup($, on)
  await ui.press({ key: 'guards' })
  const sel = await ui.find({ type: 'Select', key: 'sel-danger-guard' })
  expect(JSON.stringify(sel)).not.toContain('"off"')
  await ui.select({ key: 'sel-danger-guard', value: 'off' }) // even if asked directly
  expect(writes.length).toBe(0)
  await ui.unmount()
})

test('awkward: no catalog or a broken switch file shows a message, not an empty panel', async ($, on) => {
  const a = await setup($, on, { failCatalog: true })
  await a.ui.press({ key: 'guards' })
  expect(await a.ui.find({ type: 'Text', text: /Could not read the guard list/ })).toBeDefined()
  await a.ui.unmount()
})

test('awkward: a switch file that is not JSON is shown as a problem and never overwritten', async ($, on) => {
  const { ui, writes } = await setup($, on, { config: '{not json' })
  await ui.press({ key: 'guards' })
  expect(await ui.find({ type: 'Text', text: /not valid JSON/ })).toBeDefined()
  expect(writes.length).toBe(0)
  await ui.unmount()
})

test('Display explains itself and a pick hides the robot, kept for the next session', async ($, on) => {
  const { ui } = await setup($, on)
  await ui.press({ key: 'bar' })
  expect(await ui.find({ type: 'Text', text: /What this bar shows/ })).toBeDefined()
  await ui.select({ key: 'sel-robot', value: 'off' })
  expect(await ui.find({ type: 'Text', text: /[▀▄█]/ })).toBeUndefined()
  await ui.unmount()
  // a new session reads the stored choice back: still no robot, the text is there
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true } as never)
  const again = await $.ui.mount({ plugin: 'mogger', surface: 'terminal', component: 'AbovePrompt', props: { hasSurvey: false, isWorking: false } as never })
  expect(await again.find({ type: 'Text', text: /[▀▄█]/ })).toBeUndefined()
  expect(await again.find({ type: 'Text', text: /formatted app.ts/ })).toBeDefined()
  await again.unmount()
})

test('the desktop draws the robot as one picture, not rows of half blocks', async ($, on) => {
  const { ui } = await setup($, on, { surface: 'desktop' })
  expect(await ui.find({ type: 'Svg' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /[▀▄█]/ })).toBeUndefined()
  await ui.unmount()
})
