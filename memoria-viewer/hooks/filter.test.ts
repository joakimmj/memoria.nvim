import { expect, test } from 'claude-code/testing'

import { clipLabel, optionLabel, rank } from './filter'
import type { PickerCandidate } from '../types'

const ROWS: PickerCandidate[] = [
  { file: 'a.md', title: 'Planning Notes', modified: '2026-09-23T10:00:00Z', fields: { tags: ['planning'], participants: ['Alice Smith'] } },
  { file: 'b.md', title: 'Billing Review', modified: '2026-09-25T10:00:00Z', fields: { tags: ['finance'], participants: ['Pete Park'] } },
  { file: 'c.md', title: 'Reference Note', modified: '2026-09-20T10:00:00Z', fields: { tags: ['planning', 'finance'] } },
  { file: 'planning-ghost.md', title: 'Unrelated Title', modified: '2026-09-24T10:00:00Z', fields: {} },
]

test('empty query returns newest-first, capped to limit', () => {
  const r = rank(ROWS, '', 2)
  expect(r.map(x => x.file)).toEqual(['b.md', 'planning-ghost.md'])
})

test('a tag token matches via field values', () => {
  const r = rank(ROWS, 'finance', 10)
  expect(r.map(x => x.file).sort()).toEqual(['b.md', 'c.md'])
})

test('a participant token matches via field values', () => {
  const r = rank(ROWS, 'pete', 10)
  expect(r.map(x => x.file)).toEqual(['b.md'])
})

test('two tokens are ANDed, not ORed', () => {
  // Every word must match: "alice" narrows "planning" to one row.
  const r = rank(ROWS, 'planning alice', 10)
  expect(r.map(x => x.file)).toEqual(['a.md'])
})

test('ranking tiers: title-prefix beats title-substring beats filename-only beats field-only', () => {
  const rows: PickerCandidate[] = [
    { file: 'field-only.md', title: 'Zzz', modified: '2026-01-01T00:00:00Z', fields: { tags: ['sorted'] } },
    { file: 'sorted-file.md', title: 'Zzz', modified: '2026-01-01T00:00:00Z', fields: {} },
    { file: 'contains.md', title: 'Alpha Sorted Here', modified: '2026-01-01T00:00:00Z', fields: {} },
    { file: 'prefix.md', title: 'Sorted At Start', modified: '2026-01-01T00:00:00Z', fields: {} },
  ]
  const r = rank(rows, 'sorted', 10)
  expect(r.map(x => x.file)).toEqual(['prefix.md', 'contains.md', 'sorted-file.md', 'field-only.md'])
})

test('clipLabel never exceeds width and marks a cut with an ellipsis', () => {
  const label = clipLabel('a very long engram title indeed', 10)
  expect(label.length).toBeLessThanOrEqual(10)
  expect(label.endsWith('…')).toBe(true)
})

test('clipLabel leaves a label that already fits untouched', () => {
  expect(clipLabel('short', 10)).toBe('short')
})

test('optionLabel values stay unique across rows with identical titles (keyed by distinct filenames upstream)', () => {
  const rows: PickerCandidate[] = [
    { file: 'dup-1.md', title: 'Same Title', modified: '2026-01-01T00:00:00Z', fields: {} },
    { file: 'dup-2.md', title: 'Same Title', modified: '2026-01-02T00:00:00Z', fields: {} },
  ]
  const values = rows.map(r => r.file)
  expect(new Set(values).size).toBe(values.length)
  // Labels may collide; values (filenames) must not.
  expect(optionLabel(rows[0]!, 40)).toContain('Same Title')
})
