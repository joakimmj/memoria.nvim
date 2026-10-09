import {expect, test} from 'claude-code/testing'

import {parseMemoriaArgs} from './args'

test('empty input has no flags, words or unknowns', () => {
    const a = parseMemoriaArgs('')
    expect(a.flags.size).toBe(0)
    expect(a.words).toEqual([])
    expect(a.unknown).toEqual([])
})

test('known flags are collected, words keep their order', () => {
    const a = parseMemoriaArgs('  meetings --reload   standup ')
    expect([...a.flags]).toEqual(['--reload'])
    expect(a.words).toEqual(['meetings', 'standup'])
})

test('short and close flags are recognised', () => {
    expect(parseMemoriaArgs('-r').flags.has('-r')).toBe(true)
    expect(parseMemoriaArgs('--close').flags.has('--close')).toBe(true)
})

test('summary flags are recognised', () => {
    expect(parseMemoriaArgs('--summary meetings').flags.has('--summary')).toBe(true)
    expect(parseMemoriaArgs('-s meetings').flags.has('-s')).toBe(true)
})

test('unknown flag-shaped tokens are reported, not treated as words', () => {
    const a = parseMemoriaArgs('--wat meetings')
    expect(a.unknown).toEqual(['--wat'])
    expect(a.words).toEqual(['meetings'])
})

test('`--` ends flag parsing', () => {
    const a = parseMemoriaArgs('meetings -- --reload -x')
    expect(a.flags.size).toBe(0)
    expect(a.unknown).toEqual([])
    expect(a.words).toEqual(['meetings', '--reload', '-x'])
})
