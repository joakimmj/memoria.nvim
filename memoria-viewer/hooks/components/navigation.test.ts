import { expect, test } from 'claude-code/testing'

import { buildRows } from './navigation'

const SYNAPSES = { down: ['2026-09-30_followup.md', '2026-10-01_ghost.md'], up: [] }
const TITLE_INDEX = { '2026-09-30_followup.md': 'Followup Meeting' }

test('down+up synapse rows ordered up-then-down, not insertion order', () => {
  const rows = buildRows(SYNAPSES, TITLE_INDEX)
  expect(rows.map(r => r.field)).toEqual(['up', 'down'])
})

test('an empty synapse array ("up": []) keeps a zero-target row rather than being dropped', () => {
  const rows = buildRows(SYNAPSES, TITLE_INDEX)
  const up = rows.find(r => r.field === 'up')!
  expect(up.targets).toEqual([])
})

test('a synapse target absent from the title index is marked not-exists, titled by its filename stem', () => {
  const rows = buildRows(SYNAPSES, TITLE_INDEX)
  const down = rows.find(r => r.field === 'down')!
  expect(down.targets).toEqual([
    { file: '2026-09-30_followup.md', title: 'Followup Meeting', exists: true },
    { file: '2026-10-01_ghost.md', title: '2026-10-01_ghost', exists: false },
  ])
})

test('keys outside up/down sort alphabetically after them', () => {
  const rows = buildRows({ related: ['a.md'], down: ['b.md'], up: ['c.md'] }, {})
  expect(rows.map(r => r.field)).toEqual(['up', 'down', 'related'])
})

test('no synapses (brain disables them) draws zero rows', () => {
  expect(buildRows({}, {})).toEqual([])
})
