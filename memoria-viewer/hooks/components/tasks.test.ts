import {expect, test} from 'claude-code/testing'

import {actionLine, nextMode} from './tasks'

test('nextMode cycles closed → open → all → closed', () => {
    expect(nextMode('closed')).toBe('open')
    expect(nextMode('open')).toBe('all')
    expect(nextMode('all')).toBe('closed')
})

test('actionLine is the mark and the text as written', () => {
    const base = {text: 'Ship', done: false, file: 'f.md', title: 'T', date: ''}
    expect(actionLine(base)).toBe('☐  Ship')
    expect(actionLine({...base, done: true, text: 'Ship @Alice (deadline: 2026-09-01)'})).toBe('☑  Ship @Alice (deadline: 2026-09-01)')
})
