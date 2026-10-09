import {expect, test} from 'claude-code/testing'

import {actionFrom, buildSummary, chainNeighbours, conceptFields, engramDate, parseDate, isChainSummary, parseOpenQuestions} from './summary'
import type {ChainNode, ChainTask} from './summary'

const A = `---
created: 2026-08-04
---
# Broker groups

## Actions
- [ ] Draft proposal @Dag Brede (deadline: 2026-09-01)
- [x] Book room
- [ ] Ping legal @Identity-teamet (deadline: 2027-01-04)

## Open questions
- Who owns roles?
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
- Scope of bundles?

## Other
- not a question either
`

function node(file: string, title: string, content: string, synapses: Record<string, string[]> = {}): ChainNode {
    return {file, title, content, synapses, concepts: {participants: ['Bob', 'Ann'], tags: ['access']}, dateFormats: {filename: 'YYYY-MM-DD', date: 'YYYY-MM-DD'}}
}

// What `mia tasks` answers for A and B, by engram.
const TASKS: ChainTask[] = [
    {engram: '2026-08-04_a.md', text: 'Draft proposal @Dag Brede (deadline: 2026-09-01)', done: false},
    {engram: '2026-08-04_a.md', text: 'Ping legal @Identity-teamet (deadline: 2027-01-04)', done: false},
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

test('actionFrom reads the optional owner and deadline off a task', () => {
    expect(actionFrom(TASKS[0]!, 'A', '2026-08-04')).toMatchObject({
        text: 'Draft proposal', owner: 'Dag Brede', deadline: '2026-09-01', done: false, file: '2026-08-04_a.md',
    })
    const plain = actionFrom(TASKS[2]!, 'A', '2026-08-04')
    expect(plain).toMatchObject({text: 'Book room', done: true})
    expect(plain.owner).toBeUndefined()
})

test('conceptFields keeps list fields and drops the atlas keys', () => {
    expect(conceptFields({title: 'T', synapses: {}, links: ['x.md'], hash: 'h', tags: ['a'], participants: []}))
        .toEqual({tags: ['a'], participants: []})
})

test('parseOpenQuestions stays inside its section', () => {
    expect(parseOpenQuestions(A)).toEqual(['Who owns roles?', 'Is this fine?'])
    expect(parseOpenQuestions(B)).toEqual(['Scope of bundles?'])
    expect(parseOpenQuestions('# nothing')).toEqual([])
})

test('buildSummary orders timeline, sorts open actions, flags overdue', () => {
    const s = buildSummary(
        'meetings',
        'b.md',
        [node('2026-10-07_b.md', 'B', B, {up: ['2026-08-04_a.md']}), node('2026-08-04_a.md', 'A', A, {down: ['2026-10-07_b.md']})],
        TASKS,
        ['gone.md'],
        '2026-10-09',
        'now',
    )
    expect(s.timeline.map(t => t.file)).toEqual(['2026-08-04_a.md', '2026-10-07_b.md'])
    expect(s.timeline[1]!.ups).toBe(1)
    expect(s.first).toBe('2026-08-04')
    expect(s.last).toBe('2026-10-07')
    expect(s.open.map(a => a.text)).toEqual(['Draft proposal', 'Ping legal', 'No owner no deadline'])
    expect(s.open[0]!.overdue).toBe(true)
    expect(s.open[1]!.overdue).toBe(false)
    expect(s.done.map(a => a.text)).toEqual(['Book room'])
    expect(s.questions.map(q => q.file)).toEqual(['2026-10-07_b.md', '2026-08-04_a.md'])
    expect(s.concepts).toEqual([{name: 'participants', values: ['Ann', 'Bob']}, {name: 'tags', values: ['access']}])
    expect(s.missing).toEqual(['gone.md'])
    expect(isChainSummary(s)).toBe(true)
})

test('isChainSummary rejects other shapes', () => {
    expect(isChainSummary(null)).toBe(false)
    expect(isChainSummary({v: 1, brain: 'b', seed: 's', timeline: [], open: [], done: [], questions: []})).toBe(false)
})
