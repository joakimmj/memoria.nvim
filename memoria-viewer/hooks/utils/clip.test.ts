import {expect, test} from 'claude-code/testing'

import {BODY_LIMIT} from '../constants'
import {clip} from './clip'

test('a body within the limit is unchanged', () => {
    const text = 'x'.repeat(BODY_LIMIT)
    expect(clip(text)).toBe(text)
})

test('a long body keeps its head, cut at a line, and counts what is left out', () => {
    const line = 'y'.repeat(99)
    const text = Array.from({length: 2000}, () => line).join('\n')
    const out = clip(text)
    const [head, note] = out.split('\n\n…')
    expect(head.length).toBeLessThanOrEqual(BODY_LIMIT)
    expect(head.endsWith(line)).toBe(true)
    expect(text.startsWith(head)).toBe(true)
    expect(note).toBe(`${text.length - head.length} more characters not shown…`)
})

test('a long body with no newline is cut at the limit', () => {
    const text = 'z'.repeat(BODY_LIMIT + 500)
    expect(clip(text).startsWith('z'.repeat(BODY_LIMIT) + '\n\n…500 more')).toBe(true)
})
