import {expect, test} from 'claude-code/testing'

import {actionFrom, buildSummary, chainNeighbours, splitTasks, conceptFields, engramDate, parseDate, isChainSummary} from './summary'
import type {ChainNode, ChainTask} from './summary'

const A = `---
created: 2026-08-04
---
# Project X

## Actions
- [ ] Draft proposal @Alice (deadline: 2026-09-01)
- [x] Book room
- [ ] Ask around @Team (deadline: 2027-01-04)

## Open questions
- Who decides?
- Is this fine?
`

const B = `---
created: 2026-10-07
---
# Follow-up

## Discussion
free text

## Actions
- [ ] No owner no deadline

## Open questions
- What is in scope?

## Other
- not a question either
`

function node(file: string, title: string, content: string, synapses: Record<string, string[]> = {}): ChainNode {
    return {file, title, content, synapses, concepts: {participants: ['Bob', 'Ann'], tags: ['planning']}, dateFormats: {filename: 'YYYY-MM-DD', date: 'YYYY-MM-DD'}}
}

// What `mia tasks` answers for A and B, by engram.
const TASKS: ChainTask[] = [
    {engram: '2026-08-04_a.md', text: 'Draft proposal @Alice (deadline: 2026-09-01)', done: false},
    {engram: '2026-08-04_a.md', text: 'Ask around @Team (deadline: 2027-01-04)', done: false},
    {engram: '2026-08-04_a.md', text: 'Book room', done: true},
    {engram: '2026-10-07_b.md', text: 'No owner no deadline', done: false},
    {engram: 'elsewhere.md', text: 'Not in the chain', done: false},
]

test('parseDate reads the brain\'s own format', () => {
    expect(parseDate('2026-08-04_x.md', 'YYYY-MM-DD')).toBe('2026-08-04')
    expect(parseDate('20260804_x.md', 'YYYYMMDD')).toBe('2026-08-04')
    expect(parseDate('04.08.26_x.md', 'DD.MM.YY')).toBe('2026-08-04')
    expect(parseDate('x.md', 'YYYY-MM-DD')).toBe('')
    expect(parseDate('2026_x.md', 'YYYY')).toBe('')
})

test('engramDate prefers filename, falls back to created', () => {
    expect(engramDate('20260804_x.md', A, {filename: 'YYYYMMDD', date: 'YYYY-MM-DD'})).toBe('2026-08-04')
    expect(engramDate('x.md', '---\ncreated: 04.08.2026\n---', {filename: 'YYYY-MM-DD', date: 'DD.MM.YYYY'})).toBe('2026-08-04')
    expect(engramDate('2026-08-04_x.md', A)).toBe('2026-08-04')
    expect(engramDate('x.md', A)).toBe('2026-08-04')
    expect(engramDate('x.md', '# none')).toBe('')
})

test('chainNeighbours flattens every field and dedupes', () => {
    expect(chainNeighbours({up: ['a.md'], down: ['b.md', 'a.md'], side: ['c.md']})).toEqual(['a.md', 'b.md', 'c.md'])
    expect(chainNeighbours(undefined)).toEqual([])
})

test('actionFrom keeps a task\'s text as written', () => {
    expect(actionFrom(TASKS[0]!, 'A', '2026-08-04')).toEqual({
        text: 'Draft proposal @Alice (deadline: 2026-09-01)', done: false, file: '2026-08-04_a.md', title: 'A', date: '2026-08-04',
    })
})

test('conceptFields keeps list fields and drops the atlas keys', () => {
    expect(conceptFields({title: 'T', synapses: {}, links: ['x.md'], hash: 'h', tags: ['a'], participants: []}))
        .toEqual({tags: ['a'], participants: []})
})

test('buildSummary orders the engrams and keeps the chain\'s tasks in that order', () => {
    const s = buildSummary(
        'work',
        'b.md',
        [node('2026-10-07_b.md', 'B', B, {up: ['2026-08-04_a.md']}), node('2026-08-04_a.md', 'A', A, {down: ['2026-10-07_b.md']})],
        TASKS,
        ['gone.md'],
        'now',
    )
    expect(s.timeline.map(t => t.file)).toEqual(['2026-08-04_a.md', '2026-10-07_b.md'])
    expect(s.timeline[1]!.ups).toBe(1)
    expect(s.first).toBe('2026-08-04')
    expect(s.last).toBe('2026-10-07')
    expect(s.open.map(a => a.text)).toEqual([
        'Draft proposal @Alice (deadline: 2026-09-01)',
        'Ask around @Team (deadline: 2027-01-04)',
        'No owner no deadline',
    ])
    expect(s.done.map(a => a.text)).toEqual(['Book room'])
    expect(s.concepts).toEqual([{name: 'participants', values: ['Ann', 'Bob']}, {name: 'tags', values: ['planning']}])
    expect(s.missing).toEqual(['gone.md'])
    expect(isChainSummary(s)).toBe(true)
})

test('isChainSummary rejects other shapes', () => {
    expect(isChainSummary(null)).toBe(false)
    expect(isChainSummary({v: 1, brain: 'b', seed: 's', timeline: [], open: [], done: []})).toBe(false)
})

test('splitTasks splits open from done, order kept', () => {
    const task = (text: string, done: boolean) => ({text, done, file: 'f.md', title: 'T', date: ''})
    const {open, done} = splitTasks([task('b', false), task('d', true), task('a', false)])
    expect(open.map(a => a.text)).toEqual(['b', 'a'])
    expect(done.map(a => a.text)).toEqual(['d'])
})
