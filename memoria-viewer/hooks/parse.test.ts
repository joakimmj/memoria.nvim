import { expect, test } from 'claude-code/testing'

import { buildView, isEngramView, isPendingChange, isPickerState, nextPending } from './parse'
import type { EngramResponse } from './mia'
import type { FrontmatterField } from '../types'

const FIELDS: FrontmatterField[] = [{ name: 'tags', kind: 'concept', list: true, values: ['java'], concepts: [{ text: 'java' }] }]
const TASKS = { open: 1, done: 2 }

// Synthetic fixtures in three brain shapes: with a SYNAPSES block, with value
// fields only, and with neither.

const MEETINGS_RESPONSE: EngramResponse = {
  brain: 'meetings',
  file: '2026-09-23_access_bundles.md',
  path: '/brains/meetings/2026-09-23_access_bundles.md',
  entry: {
    title: 'Access Bundles',
    synapses: { down: ['2026-09-30_followup.md', '2026-10-01_ghost.md'], up: [] },
    links: ['2026-01-01_something.md'],
    modified: '2026-09-23T10:00:00Z',
    hash: 'abc123',
    tags: ['access_bundles', 'access'],
    participants: ['Camilla Ramsland', 'Kristin Normann'],
  },
  backlinks: [],
  content: `---
participants: [Camilla Ramsland, Kristin Normann]
tags: [access_bundles, access]
created: 2026-09-23
---
<!-- SYNAPSES -->
- **down:** [2026-09-30_followup](2026-09-30_followup.md)
- **up:**
***
<!-- /SYNAPSES -->

# Access Bundles

Bundles med tilganger som gis avhengig av rolle.
`,
}

const MEETINGS_TITLE_INDEX = { '2026-09-30_followup.md': 'Followup Meeting' }

test('meetings-shaped: fields/tasks/entry/titleIndex passed through, SYNAPSES block stripped, lead heading kept', () => {
  const v = buildView(MEETINGS_RESPONSE, MEETINGS_TITLE_INDEX, FIELDS, TASKS)
  expect(v.title).toBe('Access Bundles')
  expect(v.fields).toBe(FIELDS)
  expect(v.tasks).toBe(TASKS)
  expect(v.entry).toBe(MEETINGS_RESPONSE.entry)
  expect(v.titleIndex).toBe(MEETINGS_TITLE_INDEX)
  expect(v.body).toContain('Bundles med tilganger')
  expect(v.body).not.toContain('SYNAPSES')
  expect(v.body).toContain('# Access Bundles')
})

const PRESENTATIONS_RESPONSE: EngramResponse = {
  brain: 'presentations',
  file: 'q3_review.md',
  path: '/brains/presentations/q3_review.md',
  entry: {
    title: 'Q3 Review',
    synapses: {},
    links: [],
    modified: '2026-07-01T00:00:00Z',
    hash: 'def456',
  },
  backlinks: [],
  content: `---
header_left: Q3 Review
header_center: Finance
---

# Q3 Review
`,
}

test('presentations-shaped: frontmatter is left out of the body', () => {
  const v = buildView(PRESENTATIONS_RESPONSE, {}, [], { open: 0, done: 0 })
  expect(v.body).not.toContain('header_left')
  expect(v.entry).toBe(PRESENTATIONS_RESPONSE.entry)
  expect(v.body).toContain('# Q3 Review')
})

const COMPENDIUM_RESPONSE: EngramResponse = {
  brain: 'compendium',
  file: 'concept_topic.md',
  path: '/brains/compendium/concept_topic.md',
  entry: {
    title: 'Concept Topic',
    synapses: {},
    links: [],
    modified: '2026-05-01T00:00:00Z',
    hash: 'ghi789',
    tags: ['architecture'],
  },
  backlinks: [],
  content: `---
tags: [architecture]
---

# Concept Topic

Some concept description.
`,
}

test('compendium-shaped: no SYNAPSES block, no participants field, no date-prefix assumption', () => {
  const v = buildView(COMPENDIUM_RESPONSE, {}, [], { open: 0, done: 0 })
  expect(v.body).not.toContain('SYNAPSES')
  expect(v.body).toContain('Some concept description')
})

test('entry.title (the pane chrome/tab title) is independent of the body\'s own leading heading, which is kept as-is', () => {
  const resp: EngramResponse = {
    brain: 'b',
    file: 't.md',
    path: '/brains/b/t.md',
    entry: { title: 'Correct Title', synapses: {}, links: [], modified: 'x', hash: 'y' },
    backlinks: [],
    content: '---\ntags: []\n---\n\n# Wrong Heading\n\nBody text.\n',
  }
  const v = buildView(resp, {}, [], { open: 0, done: 0 })
  expect(v.title).toBe('Correct Title')
  expect(v.body).toContain('# Wrong Heading')
})

test('isEngramView rejects a shape tagged for a different version', () => {
  expect(isEngramView({ v: 1, brain: 'b', file: 'f', front: '', entry: {}, titleIndex: {}, body: '' })).toBe(false)
  expect(isEngramView({ v: 2, brain: 'b', file: 'f', fields: [], tasks: { open: 0, done: 0 }, entry: {}, titleIndex: {}, body: '' })).toBe(true)
})

test('isPickerState accepts a well-formed state and rejects a mistagged one', () => {
  expect(isPickerState({ v: 1, stage: 'brain', brains: [], engrams: [], filter: '' })).toBe(true)
  expect(isPickerState({ v: 2, stage: 'brain', brains: [], engrams: [], filter: '' })).toBe(false)
})

test('isPendingChange accepts a well-formed hint and rejects a mistagged or partial one', () => {
  expect(isPendingChange({ v: 1, brain: 'b', file: 'f.md', title: 'T', count: 1 })).toBe(true)
  expect(isPendingChange({ v: 2, brain: 'b', file: 'f.md', title: 'T', count: 1 })).toBe(false)
  expect(isPendingChange({ v: 1, brain: 'b', file: 'f.md', title: 'T' })).toBe(false)
  expect(isPendingChange(null)).toBe(false)
})

test('nextPending starts at 1, bumps the same engram, and replaces a different one', () => {
  const hit = { brain: 'meetings', file: 'a.md', title: 'A' }
  const first = nextPending(null, hit)
  expect(first).toEqual({ v: 1, ...hit, count: 1 })
  const again = nextPending(first, { ...hit, title: 'A2' })
  expect(again.count).toBe(2)
  expect(again.title).toBe('A2')
  const other = nextPending(again, { brain: 'meetings', file: 'b.md', title: 'B' })
  expect(other).toEqual({ v: 1, brain: 'meetings', file: 'b.md', title: 'B', count: 1 })
  expect(nextPending(again, { ...hit, brain: 'other' }).count).toBe(1)
})
