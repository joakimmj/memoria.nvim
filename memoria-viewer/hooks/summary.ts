import type {ActionItem, ChainSummary, TaskList, TimelineRow} from '../types'
import {splitFrontmatter} from './parse'

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

/** A task as the views list it; its text is shown as written. */
export function actionFrom(task: ChainTask, title: string, date: string): ActionItem {
    return {text: task.text, done: task.done, file: task.engram, title, date}
}

function union(lists: readonly (readonly string[])[]): string[] {
    return [...new Set(lists.flat())].sort((a, b) => a.localeCompare(b))
}

/** Open and done, each in the order given. */
export function splitTasks(actions: readonly ActionItem[]): TaskList {
    return {open: actions.filter(a => !a.done), done: actions.filter(a => a.done)}
}

/** `tasks` are the whole brain's; only the chain's are kept. */
export function buildSummary(
    brain: string,
    seed: string,
    nodes: readonly ChainNode[],
    tasks: readonly ChainTask[],
    missing: readonly string[],
    builtAt: string,
): ChainSummary {
    const withMeta = nodes.map(n => {
        const date = engramDate(n.file, n.content, n.dateFormats)
        const actions = tasks.filter(t => t.engram === n.file).map(t => actionFrom(t, n.title, date))
        return {n, date, actions}
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

    const {open, done} = splitTasks(withMeta.flatMap(m => m.actions))

    const dates = timeline.map(t => t.date).filter(Boolean)
    return {
        v: 2,
        brain,
        seed,
        timeline,
        open,
        done,
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
        Array.isArray(v.done)
    )
}
