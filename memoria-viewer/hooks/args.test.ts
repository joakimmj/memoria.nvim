import {expect, test} from 'claude-code/testing'

import {parseMemoriaArgs} from './args'

test('empty input has no flags, words or unknowns', () => {
    const a = parseMemoriaArgs('')
    expect(a.flags.size).toBe(0)
    expect(a.words).toEqual([])
    expect(a.unknown).toEqual([])
})

test('known flags are collected, words keep their order', () => {
    const a = parseMemoriaArgs('  work --reload   standup ')
    expect([...a.flags]).toEqual(['--reload'])
    expect(a.words).toEqual(['work', 'standup'])
})

test('short and close flags are recognised', () => {
    expect(parseMemoriaArgs('-r').flags.has('-r')).toBe(true)
    expect(parseMemoriaArgs('--close').flags.has('--close')).toBe(true)
})

test('summary flags are recognised', () => {
    expect(parseMemoriaArgs('--summary work').flags.has('--summary')).toBe(true)
    expect(parseMemoriaArgs('-s work').flags.has('-s')).toBe(true)
})

test('unknown flag-shaped tokens are reported, not treated as words', () => {
    const a = parseMemoriaArgs('--wat work')
    expect(a.unknown).toEqual(['--wat'])
    expect(a.words).toEqual(['work'])
})

test('`--` ends flag parsing', () => {
    const a = parseMemoriaArgs('work -- --reload -x')
    expect(a.flags.size).toBe(0)
    expect(a.unknown).toEqual([])
    expect(a.words).toEqual(['work', '--reload', '-x'])
})
