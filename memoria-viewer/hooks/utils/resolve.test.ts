import {expect, test} from 'claude-code/testing'

import type {PickerCandidate} from '../../types'
import {resolveEngram} from './resolve'

const c = (file: string, title: string): PickerCandidate => ({file, title, modified: '2026-01-01T00:00:00Z', fields: {}})

const CANDS = [
    c('2026-09-23_access_bundles.md', 'Access Bundles'),
    c('2026-09-30_followup.md', 'Followup'),
]

test('exact filename matches, with or without .md', () => {
    expect(resolveEngram(CANDS, '2026-09-30_followup.md')?.title).toBe('Followup')
    expect(resolveEngram(CANDS, '2026-09-30_followup')?.title).toBe('Followup')
})

test('falls back to the ranked top match', () => {
    expect(resolveEngram(CANDS, 'bundles')?.file).toBe('2026-09-23_access_bundles.md')
})

test('no candidates → undefined', () => {
    expect(resolveEngram([], 'anything')).toBeUndefined()
})
