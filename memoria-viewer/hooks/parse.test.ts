import { expect, test } from 'claude-code/testing'

import { buildView, isEngramView, isPendingChange, isPickerState, nextPending } from './parse'
import type { EngramResponse } from './mia'
import type { FrontmatterField, TaskList } from '../types'

const FIELDS: FrontmatterField[] = [{ name: 'tags', kind: 'concept', list: true, values: ['java'], concepts: [{ text: 'java' }] }]
const NO_TASKS: TaskList = { open: [], done: [] }
const TASKS: TaskList = {
  open: [{ text: 'a', done: false, file: 'f.md', title: 'T', date: '' }],
  done: [],
}

// Synthetic fixtures in three brain shapes: with a SYNAPSES block, with value
// fields only, and with neither.

const MEETINGS_RESPONSE: EngramResponse = {
  brain: 'work',
  file: '2026-09-23_planning_notes.md',
  path: '/brains/work/2026-09-23_planning_notes.md',
  entry: {
    title: 'Planning Notes',
    synapses: { down: ['2026-09-30_followup.md', '2026-10-01_ghost.md'], up: [] },
    links: ['2026-01-01_something.md'],
    modified: '2026-09-23T10:00:00Z',
    hash: 'abc123',
    tags: ['planning_notes', 'planning'],
    participants: ['Alice Smith', 'Pete Park'],
  },
  backlinks: [],
  content: `---
participants: [Alice Smith, Pete Park]
tags: [planning_notes, planning]
created: 2026-09-23
---
<!-- SYNAPSES -->
- **down:** [2026-09-30_followup](2026-09-30_followup.md)
- **up:**
***
<!-- /SYNAPSES -->

# Planning Notes

Notes on what to plan and when.
`,
}

const MEETINGS_TITLE_INDEX = { '2026-09-30_followup.md': 'Followup Meeting' }

test('work-shaped: fields/tasks/entry/titleIndex passed through, SYNAPSES block stripped, lead heading kept', () => {
  const v = buildView(MEETINGS_RESPONSE, MEETINGS_TITLE_INDEX, FIELDS, TASKS)
  expect(v.title).toBe('Planning Notes')
  expect(v.fields).toBe(FIELDS)
  expect(v.tasks).toBe(TASKS)
  expect(v.entry).toBe(MEETINGS_RESPONSE.entry)
  expect(v.titleIndex).toBe(MEETINGS_TITLE_INDEX)
  expect(v.body).toContain('Notes on what to plan')
  expect(v.body).not.toContain('SYNAPSES')
  expect(v.body).toContain('# Planning Notes')
})

const PRESENTATIONS_RESPONSE: EngramResponse = {
  brain: 'slides',
  file: 'year_review.md',
  path: '/brains/slides/year_review.md',
  entry: {
    title: 'Year Review',
    synapses: {},
    links: [],
    modified: '2026-07-01T00:00:00Z',
    hash: 'def456',
  },
  backlinks: [],
  content: `---
header_left: Year Review
header_center: Overview
---

# Year Review
`,
}

test('slides-shaped: frontmatter is left out of the body', () => {
  const v = buildView(PRESENTATIONS_RESPONSE, {}, [], NO_TASKS)
  expect(v.body).not.toContain('header_left')
  expect(v.entry).toBe(PRESENTATIONS_RESPONSE.entry)
  expect(v.body).toContain('# Year Review')
})

const COMPENDIUM_RESPONSE: EngramResponse = {
  brain: 'reference',
  file: 'concept_topic.md',
  path: '/brains/reference/concept_topic.md',
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

test('reference-shaped: no SYNAPSES block, no participants field, no date-prefix assumption', () => {
  const v = buildView(COMPENDIUM_RESPONSE, {}, [], NO_TASKS)
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
  const v = buildView(resp, {}, [], NO_TASKS)
  expect(v.title).toBe('Correct Title')
  expect(v.body).toContain('# Wrong Heading')
})

test('isEngramView rejects a shape tagged for a different version', () => {
  expect(isEngramView({ v: 1, brain: 'b', file: 'f', front: '', entry: {}, titleIndex: {}, body: '' })).toBe(false)
  expect(isEngramView({ v: 2, brain: 'b', file: 'f', fields: [], tasks: { open: 0, done: 0 }, entry: {}, titleIndex: {}, body: '' })).toBe(false)
  expect(isEngramView({ v: 4, brain: 'b', file: 'f', path: '/b/f', fields: [], tasks: { open: [], done: [] }, entry: {}, titleIndex: {}, body: '' })).toBe(true)
  expect(isEngramView({ v: 4, brain: 'b', file: 'f', path: '/b/f', fields: [], tasks: { open: 0, done: 0 }, entry: {}, titleIndex: {}, body: '' })).toBe(false)
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
  const hit = { brain: 'work', file: 'a.md', title: 'A' }
  const first = nextPending(null, hit)
  expect(first).toEqual({ v: 1, ...hit, count: 1 })
  const again = nextPending(first, { ...hit, title: 'A2' })
  expect(again.count).toBe(2)
  expect(again.title).toBe('A2')
  const other = nextPending(again, { brain: 'work', file: 'b.md', title: 'B' })
  expect(other).toEqual({ v: 1, brain: 'work', file: 'b.md', title: 'B', count: 1 })
  expect(nextPending(again, { ...hit, brain: 'other' }).count).toBe(1)
})
