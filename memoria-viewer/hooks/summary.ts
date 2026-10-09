import type {ActionItem, ChainSummary, QuestionGroup, TimelineRow} from '../types'
import {splitFrontmatter, stripSynapses} from './parse'

export type ChainNode = {
    file: string
    title: string
    synapses: Record<string, string[]>
    concepts: Record<string, string[]>
    content: string
    dateFormats: { filename: string; date: string }
}

export type ChainTask = { engram: string; text: string; done: boolean }

const ATLAS_KEYS = new Set(['title', 'synapses', 'links', 'error', 'modified', 'hash'])

/** An atlas entry's concept fields: its list keys other than `ATLAS_KEYS`. */
export function conceptFields(entry: Record<string, unknown>): Record<string, string[]> {
    const out: Record<string, string[]> = {}
    for (const [name, value] of Object.entries(entry)) {
        if (ATLAS_KEYS.has(name) || !Array.isArray(value)) continue
        out[name] = value.filter((v): v is string => typeof v === 'string')
    }
    return out
}

/** The date `text` starts with, in memoria's `format` tokens, as `YYYY-MM-DD`; '' if none. */
export function parseDate(text: string, format: string): string {
    const parts: string[] = []
    const pattern = format.replace(/YYYY|YY|MM|DD|HH|mm|ss|[.*+?^${}()|[\]\\]/g, token => {
        if (token.length === 1) return '\\' + token
        parts.push(token)
        return token === 'YYYY' ? '(\\d{4})' : '(\\d{2})'
    })
    const m = new RegExp('^' + pattern).exec(text)
    if (!m) return ''
    const get = (token: string) => (parts.includes(token) ? m[parts.indexOf(token) + 1] : undefined)
    const year = get('YYYY') ?? (get('YY') ? '20' + get('YY') : undefined)
    const month = get('MM')
    const day = get('DD')
    return year && month && day ? `${year}-${month}-${day}` : ''
}
const DEADLINE_RE = /\(\s*deadline:\s*(\d{4}-\d{2}-\d{2})\s*\)/i

const DEFAULT_FORMATS = {filename: 'YYYY-MM-DD', date: 'YYYY-MM-DD'}

/** The filename's date, else `created`'s, else ''. */
export function engramDate(file: string, content: string, formats = DEFAULT_FORMATS): string {
    const fromFile = parseDate(file, formats.filename)
    if (fromFile) return fromFile
    const {front} = splitFrontmatter(content)
    const created = /^created:\s*["']?([^"'\n]*)/m.exec(front)
    return created ? parseDate(created[1]!.trim(), formats.date) : ''
}

export function chainNeighbours(synapses: Record<string, string[]> | undefined): string[] {
    const seen = new Set<string>()
    for (const targets of Object.values(synapses ?? {})) {
        for (const t of targets) seen.add(t)
    }
    return [...seen]
}

/** Reads the optional `@Owner` and `(deadline: YYYY-MM-DD)` off a task's text. */
export function actionFrom(task: ChainTask, title: string, date: string): ActionItem {
    let text = task.text

    let deadline: string | undefined
    const d = DEADLINE_RE.exec(text)
    if (d) {
        deadline = d[1]
        text = (text.slice(0, d.index) + text.slice(d.index + d[0].length)).trim()
    }

    let owner: string | undefined
    const at = text.lastIndexOf(' @')
    if (at !== -1) {
        owner = text.slice(at + 2).trim()
        text = text.slice(0, at).trim()
    }

    return {
        text,
        done: task.done,
        file: task.engram,
        title,
        date,
        ...(owner ? {owner} : {}),
        ...(deadline ? {deadline} : {}),
    }
}

export function parseOpenQuestions(content: string): string[] {
    const {body} = splitFrontmatter(content)
    const out: string[] = []
    let inside = false
    for (const line of stripSynapses(body).split('\n')) {
        if (/^#{1,2}\s/.test(line)) {
            inside = /^##\s+open questions\s*$/i.test(line)
            continue
        }
        if (!inside) continue
        const m = /^\s*[-*]\s+(?!\[[ xX]\])(.*\S)\s*$/.exec(line)
        if (m) out.push(m[1]!)
    }
    return out
}

function byDeadline(a: ActionItem, b: ActionItem): number {
    if (a.deadline && b.deadline) return a.deadline.localeCompare(b.deadline)
    if (a.deadline) return -1
    if (b.deadline) return 1
    return a.date.localeCompare(b.date)
}

function union(lists: readonly (readonly string[])[]): string[] {
    return [...new Set(lists.flat())].sort((a, b) => a.localeCompare(b))
}

/** `tasks` are the whole brain's; only the chain's are kept. */
export function buildSummary(
    brain: string,
    seed: string,
    nodes: readonly ChainNode[],
    tasks: readonly ChainTask[],
    missing: readonly string[],
    today: string,
    builtAt: string,
): ChainSummary {
    const withMeta = nodes.map(n => {
        const date = engramDate(n.file, n.content, n.dateFormats)
        const actions = tasks.filter(t => t.engram === n.file).map(t => actionFrom(t, n.title, date))
        return {n, date, actions, questions: parseOpenQuestions(n.content)}
    })
    withMeta.sort((a, b) => {
        if (!a.date !== !b.date) return a.date ? -1 : 1
        return a.date.localeCompare(b.date) || a.n.file.localeCompare(b.n.file)
    })

    const timeline: TimelineRow[] = withMeta.map(({n, date, actions}) => ({
        file: n.file,
        title: n.title,
        date,
        open: actions.filter(a => !a.done).length,
        done: actions.filter(a => a.done).length,
        ups: n.synapses.up?.length ?? 0,
    }))

    const all = withMeta.flatMap(m => m.actions)
    const open = all.filter(a => !a.done).map(a => ({...a, overdue: !!a.deadline && a.deadline < today}))
    open.sort(byDeadline)
    const done = all.filter(a => a.done)

    const questions: QuestionGroup[] = withMeta
        .filter(m => m.questions.length > 0)
        .map(m => ({file: m.n.file, title: m.n.title, date: m.date, items: m.questions}))
        .reverse()

    const dates = timeline.map(t => t.date).filter(Boolean)
    return {
        v: 2,
        brain,
        seed,
        timeline,
        open,
        done,
        questions,
        concepts: [...new Set(nodes.flatMap(n => Object.keys(n.concepts)))]
            .sort((a, b) => a.localeCompare(b))
            .map(name => ({name, values: union(nodes.map(n => n.concepts[name] ?? []))}))
            .filter(field => field.values.length > 0),
        missing: [...missing],
        first: dates[0] ?? '',
        last: dates[dates.length - 1] ?? '',
        builtAt,
    }
}

/** Reload guard: state an older build wrote is discarded. */
export function isChainSummary(value: unknown): value is ChainSummary {
    if (typeof value !== 'object' || value === null) return false
    const v = value as Record<string, unknown>
    return (
        v.v === 2 &&
        typeof v.brain === 'string' &&
        typeof v.seed === 'string' &&
        Array.isArray(v.concepts) &&
        Array.isArray(v.timeline) &&
        Array.isArray(v.open) &&
        Array.isArray(v.done) &&
        Array.isArray(v.questions)
    )
}
