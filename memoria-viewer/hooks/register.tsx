import type {EngineInterface, PaneOpenArgs, Register} from 'claude-code'
import {atom, read, update} from 'claude-code'

import {optionLabel, rank} from './filter'
import type {BrainRow, EngramResponse, EngramSummary, MiaResult} from './mia'
import {decode, FIND_MIA} from './mia'
import {buildView, isEngramView, isPendingChange, isPickerState, nextPending} from './parse'
import type {BrainChoice, EngramView, FrontmatterField, HistoryEntry, NavMode, PickerState, TaskCounts} from '../types'
import {BODY_KEY, MAX_HISTORY, PICK, SHOW_TOOL, VIEW} from './constants'
import {parseMemoriaArgs} from './args'
import {TOOL_SPEC} from './tool'
import {resolveEngram} from './utils/resolve'
import type {ViewElements} from './utils/elements'
import {clip} from './utils/clip'
import {buildCandidates} from './utils/candidates'
import REDOX from './redox'
import Header from './components/header'
import SummaryView from './components/summary'
import EngramBody from './utils/engram-body'
import {buildSummary, chainNeighbours, conceptFields, isChainSummary} from './summary'
import type {ChainNode, ChainTask} from './summary'


const view = atom({plugin: 'memoria-viewer', key: 'view'} as const, null)
const picker = atom({plugin: 'memoria-viewer', key: 'picker'} as const, null)
const history = atom({plugin: 'memoria-viewer', key: 'history'} as const, [])
// Pages `h` left, for `l`; a fresh navigation clears it.
const forward = atom({plugin: 'memoria-viewer', key: 'forward'} as const, [])
// A `show_engram` touch on an engram not shown: hinted, never switched to.
const pending = atom({plugin: 'memoria-viewer', key: 'pending'} as const, null)
// When set, VIEW draws the summary; `view` stays underneath for `s`/`h`.
const summary = atom({plugin: 'memoria-viewer', key: 'summary'} as const, null)
const showDone = atom({plugin: 'memoria-viewer', key: 'showDone'} as const, false)

const MAX_CHAIN = 40

// Every function that uses `$`, and every atom, must live in this file: the
// engine does not follow `$` across an import, and only scans atoms declared here.
// The `mia` option; empty when unset.
let configuredMia = ''
let miaBin: Promise<string> | undefined

/** The `mia` option (a leading `~/` expanded), else what Neovim finds, else `mia` on PATH. */
async function findMia($: EngineInterface): Promise<string> {
    if (configuredMia) {
        if (!configuredMia.startsWith('~/')) return configuredMia
        const home = await $.process.run(['sh', '-c', 'printf %s "$HOME"'], {timeoutMs: 5000}).catch(() => undefined)
        return home?.stdout ? home.stdout + configuredMia.slice(1) : configuredMia
    }
    const found = await $.process.run(FIND_MIA, {timeoutMs: 15000}).catch(() => undefined)
    const path = found?.stdout.trim().split('\n').pop()?.trim()
    return path || 'mia'
}

async function mia<T>($: EngineInterface, argv: readonly string[]): Promise<MiaResult<T>> {
    miaBin ??= findMia($)
    const bin = await miaBin
    try {
        const {exitCode, stdout, stderr} = await $.process.run([bin, ...argv], {timeoutMs: 15000})
        return decode<T>(exitCode, stdout, stderr)
    } catch (err) {
        return {
            ok: false,
            error:
                `could not run ${bin}: ${err instanceof Error ? err.message : String(err)}. ` +
                'Set the plugin option "mia" to the bin/mia in memoria.nvim, or put mia on PATH.',
        }
    }
}

function listBrains($: EngineInterface) {
    return mia<{ brains: BrainRow[] }>($, ['brains'])
}

function listEngrams($: EngineInterface, brain: string) {
    return mia<{ brain: string; engrams: EngramSummary[] }>($, ['engrams', '--brain', brain])
}

function readEngram($: EngineInterface, brain: string, file: string) {
    return mia<EngramResponse>($, ['engram', file, '--brain', brain])
}

function readFrontmatter($: EngineInterface, brain: string, file: string) {
    return mia<{ fields: FrontmatterField[] }>($, ['frontmatter', file, '--brain', brain])
}

function readTasks($: EngineInterface, brain: string, file: string) {
    return mia<{ tasks: { not_done?: unknown[]; done?: unknown[] } }>($, ['tasks', '--engram', file, '--brain', brain])
}

/** Fields and task counts; a failed read leaves that part empty. */
async function readExtras($: EngineInterface, brain: string, file: string): Promise<[FrontmatterField[], TaskCounts]> {
    const [front, tasks] = await Promise.all([readFrontmatter($, brain, file), readTasks($, brain, file)])
    return [
        front.ok ? front.result.fields : [],
        tasks.ok
            ? {open: tasks.result.tasks.not_done?.length ?? 0, done: tasks.result.tasks.done?.length ?? 0}
            : {open: 0, done: 0},
    ]
}

/** Walks every synapse from `seed`, a layer at a time, up to MAX_CHAIN; unreadable targets are `missing`. */
async function buildChain($: EngineInterface, brain: string, seed: string) {
    const nodes: ChainNode[] = []
    const missing: string[] = []
    const seen = new Set<string>([seed])
    let layer = [seed]

    while (layer.length > 0 && nodes.length < MAX_CHAIN) {
        const batch = layer.slice(0, MAX_CHAIN - nodes.length)
        const reads = await Promise.all(batch.map(file => readEngram($, brain, file)))
        const next: string[] = []
        reads.forEach((r, i) => {
            const file = batch[i]!
            if (!r.ok) {
                if (file !== seed) missing.push(file)
                return
            }
            const entry = r.result.entry
            const synapses = entry.synapses ?? {}
            nodes.push({
                file,
                title: entry.title,
                synapses,
                concepts: conceptFields(entry),
                content: r.result.content,
                dateFormats: {
                    filename: r.result.filename_date_format ?? 'YYYY-MM-DD',
                    date: r.result.date_format ?? 'YYYY-MM-DD',
                },
            })
            for (const n of chainNeighbours(synapses)) {
                if (!seen.has(n)) {
                    seen.add(n)
                    next.push(n)
                }
            }
        })
        layer = next
    }

    if (nodes.length === 0) return {ok: false as const, error: `could not read ${seed}`}

    const listed = await mia<{ tasks: Record<string, { engram: string; text: string }[]> }>($, ['tasks', '--brain', brain])
    const tasks: ChainTask[] = listed.ok
        ? (['not_done', 'done'] as const).flatMap(state =>
            (listed.result.tasks[state] ?? []).map(t => ({engram: t.engram, text: t.text, done: state === 'done'})),
        )
        : []

    const today = new Date().toISOString().slice(0, 10)
    return {
        ok: true as const,
        summary: buildSummary(brain, seed, nodes, tasks, missing, today, new Date().toISOString()),
    }
}

async function openSummary(
    $: EngineInterface,
    brain: string,
    file: string,
    opts: { focus?: boolean } = {},
): Promise<{ ok: true } | { ok: false; error: string }> {
    const current = await read($, view)
    if (!current || current.brain !== brain || current.file !== file) {
        const opened = await openEngram($, brain, file, 'new', opts)
        if (!opened.ok) return opened
    }
    const built = await buildChain($, brain, file)
    if (!built.ok) return built
    await update($, summary, () => built.summary)
    await update($, showDone, () => false)
    const title = (await read($, view))?.title ?? file
    const panes = await $.ui.panes()
    const wantFocus = opts.focus ?? panes.some(p => p.id === VIEW)
    await place($, {id: VIEW, title: `Σ ${title}`, ...(wantFocus ? {focus: true as const} : {})})
    await $.ui.scroll({in: VIEW, to: 'start'}).catch(() => undefined)
    return {ok: true}
}

async function refreshSummary($: EngineInterface, opts: { focus?: boolean } = {}): Promise<{ ok: true } | { ok: false; error: string }> {
    const current = await read($, summary)
    if (!current) return {ok: false, error: 'no summary open'}
    const built = await buildChain($, current.brain, current.seed)
    if (!built.ok) return built
    await update($, summary, () => built.summary)
    const title = (await read($, view))?.title ?? current.seed
    await place($, {id: VIEW, title: `Σ ${title}`, ...(opts.focus ? {focus: true as const} : {})})
    return {ok: true}
}

async function closeSummary($: EngineInterface): Promise<void> {
    await update($, summary, () => null)
    const v = await read($, view)
    await place($, {id: VIEW, title: v?.title ?? 'memoria', focus: true})
    await $.ui.scroll({in: VIEW, to: 'start'}).catch(() => undefined)
}

// Once per load.
let toastedNarrow = false

/** `$.ui.open`, toasting once when too narrow to place. */
async function place($: EngineInterface, args: PaneOpenArgs): Promise<void> {
    const opened = await $.ui.open(args)
    if (!opened.isPlaced && !toastedNarrow) {
        toastedNarrow = true
        $.ui.toast('memoria-viewer: widen the terminal, or run /memoria again')
    }
}

/** Inside VIEW (`inline`) or in its own PICK pane. */
async function placePicker($: EngineInterface, inline: boolean, title: string): Promise<void> {
    if (inline) {
        const v = await read($, view)
        await place($, {id: VIEW, title: v?.title ?? title, focus: true, closeOnEscape: true})
        return
    }
    await place($, {id: PICK, title, focus: true, closeOnEscape: true, rows: 20})
}

async function openBrainPicker($: EngineInterface, brains: BrainChoice[], inline = false): Promise<void> {
    const state: PickerState = {v: 1, stage: 'brain', brains, engrams: [], filter: '', ...(inline ? {inline: true as const} : {})}
    await update($, picker, () => state)
    await placePicker($, inline, 'memoria: pick a brain')
}

async function openEngramPicker(
    $: EngineInterface,
    brains: BrainChoice[],
    brainName: string,
    filter = '',
    inline = false,
): Promise<{ ok: true } | { ok: false; error: string }> {
    const listed = await listEngrams($, brainName)
    if (!listed.ok) return {ok: false, error: listed.error}

    const candidates = buildCandidates(listed.result.engrams)
    const state: PickerState = {
        v: 1, stage: 'engram', brains, brain: brainName, engrams: candidates, filter,
        ...(inline ? {inline: true as const} : {}),
    }
    await update($, picker, () => state)
    await placePicker($, inline, `memoria: ${brainName}`)
    return {ok: true}
}

/** The engrams naming a concept, picked from inside VIEW. */
async function openConceptPicker(
    $: EngineInterface,
    brainName: string,
    key: string,
    label: string,
): Promise<{ ok: true } | { ok: false; error: string }> {
    const listed = await mia<{ brain: string; engrams: EngramSummary[] }>($, ['engrams', '--brain', brainName, '--concept', key])
    if (!listed.ok) return {ok: false, error: listed.error}

    const state: PickerState = {
        v: 1, stage: 'engram', brains: [], brain: brainName, filter: '',
        engrams: buildCandidates(listed.result.engrams),
        inline: true as const,
        concept: {key, label},
    }
    await update($, picker, () => state)
    await placePicker($, true, `memoria: ${label}`)
    return {ok: true}
}

type PickerElements = Pick<Extract<ReturnType<EngineInterface['ui']['resolve']>, { Input: unknown }>, 'Box' | 'Text' | 'Input' | 'Select'>

function drawPicker($: EngineInterface, els: PickerElements, width: number, p: PickerState) {
    const {Box, Text, Input, Select} = els
    const hint = p.inline ? <Text dimColor>Esc: back to the engram</Text> : null

    if (p.stage === 'brain') {
        return (
            <Box flexDirection="column">
                {hint}
                <Select
                    key="brain"
                    autoFocus
                    options={p.brains.map(b => ({value: b.name, label: b.exists ? b.name : `${b.name} (missing)`}))}
                    onSelect={v => {
                        const chosen = p.brains.find(b => b.name === v)
                        if (!chosen) return
                        if (!chosen.exists) {
                            $.ui.toast(`memoria: brain "${chosen.name}" directory missing (${chosen.location}).`)
                            return
                        }
                        void openEngramPicker($, p.brains, chosen.name, '', p.inline === true)
                    }}
                />
            </Box>
        )
    }

    const matches = rank(p.engrams, p.filter, 15)

    return (
        <Box flexDirection="column">
            {hint}
            {p.concept && <Text bold>Engrams naming {p.concept.label}</Text>}
            <Input
                key="filter"
                autoFocus
                value={p.filter}
                submitLabel="open"
                placeholder="title, file, tag or person"
                onInput={v => {
                    void update($, picker, s => (s ? {...s, filter: v} : s))
                }}
                onSubmit={() => {
                    const top = matches[0]
                    if (top && p.brain) void openEngram($, p.brain, top.file, 'new')
                }}
            />
            <Text dimColor>
                {matches.length} of {p.engrams.length}
            </Text>
            {matches.length === 0 ? (
                <Text dimColor>no match</Text>
            ) : (
                <Select
                    key="list"
                    options={matches.map(m => ({value: m.file, label: optionLabel(m, Math.max(4, width - 6))}))}
                    onSelect={v => {
                        if (p.brain) void openEngram($, p.brain, v, 'new')
                    }}
                />
            )}
        </Box>
    )
}

async function openEngram(
    $: EngineInterface,
    brain: string,
    file: string,
    mode: NavMode,
    opts: { focus?: boolean } = {},
): Promise<{ ok: true } | { ok: false; error: string }> {
    const [resp, listed, [fields, tasks]] = await Promise.all([
        readEngram($, brain, file),
        listEngrams($, brain),
        readExtras($, brain, file),
    ])
    if (!resp.ok) return {ok: false, error: resp.error}

    const titleIndex: Record<string, string> = {}
    if (listed.ok) {
        for (const e of listed.result.engrams) titleIndex[e.file] = e.title
    }

    const built = buildView(resp.result, titleIndex, fields, tasks)

    // Push the page being left, unless it is the one being opened.
    const previous = await read($, view)
    if (previous && (previous.brain !== brain || previous.file !== file)) {
        const entry: HistoryEntry = {brain: previous.brain, file: previous.file}
        if (mode === 'back') {
            await update($, forward, f => [...f, entry].slice(-MAX_HISTORY))
        } else {
            await update($, history, h => [...h, entry].slice(-MAX_HISTORY))
            if (mode === 'new') await update($, forward, () => [])
        }
    }

    await update($, view, () => built)
    await update($, summary, () => null)
    // Opening the engram a hint points at answers it.
    await update($, pending, p => (p && p.brain === brain && p.file === file ? null : p))
    await update($, picker, () => null)

    // Close the picker first, so the keyboard does not stay with it.
    await $.ui.close({id: PICK}).catch(() => undefined)

    // `focus` is set anew on every open: keep it for presses inside VIEW, never
    // take it for the first open from the picker or a model-driven open.
    const panes = await $.ui.panes()
    const alreadyOpen = panes.some(p => p.id === VIEW)
    const wantFocus = opts.focus ?? alreadyOpen
    await place($, {id: VIEW, title: built.title, ...(wantFocus ? {focus: true as const} : {})})
    await $.ui.scroll({in: VIEW, to: 'start'}).catch(() => undefined)
    return {ok: true}
}

async function goBack($: EngineInterface): Promise<void> {
    const stack = await read($, history)
    if (stack.length === 0) return
    const popped = stack[stack.length - 1]!
    await update($, history, h => h.slice(0, -1))
    const result = await openEngram($, popped.brain, popped.file, 'back')
    if (!result.ok) $.ui.toast(`memoria: ${result.error}`)
}

async function goForward($: EngineInterface): Promise<void> {
    const stack = await read($, forward)
    if (stack.length === 0) return
    const popped = stack[stack.length - 1]!
    await update($, forward, f => f.slice(0, -1))
    const result = await openEngram($, popped.brain, popped.file, 'forward')
    if (!result.ok) $.ui.toast(`memoria: ${result.error}`)
}

/** Re-reads the engram on screen and re-opens VIEW (opening it if closed). */
async function refreshCurrent(
    $: EngineInterface,
    opts: { focus?: boolean; scrollTo?: 'start' | 'end' } = {},
): Promise<{ ok: true; title: string } | { ok: false; error: string }> {
    const current = await read($, view)
    if (!current) return {ok: false, error: 'nothing open'}

    const resp = await readEngram($, current.brain, current.file)
    if (!resp.ok) {
        // Only `no engram` means the file is gone; a spawn failure or timeout does not.
        if (/\bno engram\b/.test(resp.error)) {
            await update($, view, v => (v ? {...v, isGone: true as const} : v))
        }
        return {ok: false, error: resp.error}
    }

    const [listed, [fields, tasks]] = await Promise.all([
        listEngrams($, current.brain),
        readExtras($, current.brain, current.file),
    ])
    const titleIndex: Record<string, string> = {}
    if (listed.ok) {
        for (const e of listed.result.engrams) titleIndex[e.file] = e.title
    }
    const built = buildView(resp.result, titleIndex, fields, tasks)
    await update($, view, () => built)

    await place($, {id: VIEW, title: built.title, ...(opts.focus ? {focus: true as const} : {})})
    if (opts.scrollTo) await $.ui.scroll({in: VIEW, to: opts.scrollTo}).catch(() => undefined)
    return {ok: true, title: built.title}
}

export const register: Register = (on, options) => {
    configuredMia = typeof options.mia === 'string' ? options.mia.trim() : ''
    on('session.start', async ($, e, next) => {
        await $.command.register({
            name: 'memoria',
            description: 'Browse a memoria brain and walk its synapses',
            argumentHint: '[brain] [engram]',
        })

        const currentView = await read($, view)
        if (currentView && !isEngramView(currentView)) {
            await update($, view, () => null)
        }
        const currentPicker = await read($, picker)
        if (currentPicker && !isPickerState(currentPicker)) {
            await update($, picker, () => null)
        }
        const currentSummary = await read($, summary)
        if (currentSummary && !isChainSummary(currentSummary)) {
            await update($, summary, () => null)
        }
        const currentPending = await read($, pending)
        if (currentPending && !isPendingChange(currentPending)) {
            await update($, pending, () => null)
        }

        // The engine may sanitize the plugin name; `tool.call` matches SHOW_TOOL literally.
        const registered = await $.tool.register(TOOL_SPEC)
        if (registered.tool !== SHOW_TOOL) {
            $.ui.toast(`memoria-viewer: tool registered as ${registered.tool}, expected ${SHOW_TOOL}; update SHOW_TOOL`)
        }

        return next(e)
    })

    on('command.run', {command: 'memoria'}, async ($, e) => {
        const args = parseMemoriaArgs(e.args)
        if (args.unknown.length > 0) {
            return {text: `memoria: unknown flag ${args.unknown.join(', ')}. Flags: --reload (-r), --summary (-s), --close`}
        }
        const wantSummary = args.flags.has('--summary') || args.flags.has('-s')

        if (args.flags.has('--close')) {
            await $.ui.close({id: PICK}).catch(() => undefined)
            await $.ui.close({id: VIEW}).catch(() => undefined)
            return {text: 'memoria closed.'}
        }

        if (args.flags.has('--reload') || args.flags.has('-r')) {
            const current = await read($, view)
            if (!current) return {text: 'memoria: nothing open to reload.'}
            if (await read($, summary)) {
                const r = await refreshSummary($, {focus: true})
                return {text: r.ok ? 'memoria: summary reloaded' : `memoria: ${r.error}`}
            }
            const refreshed = await refreshCurrent($, {focus: true})
            return {text: refreshed.ok ? `memoria: reloaded ${refreshed.title}` : `memoria: ${refreshed.error}`}
        }

        if (wantSummary && args.words.length === 0) {
            const current = await read($, view)
            if (!current) return {text: 'memoria: nothing open to summarise — /memoria -s <brain> <engram>.'}
            const r = await openSummary($, current.brain, current.file, {focus: true})
            return {text: r.ok ? 'memoria: summary' : `memoria: ${r.error}`}
        }

        // Bare `/memoria` toggles; arguments navigate.
        if (args.words.length === 0) {
            const panes = await $.ui.panes()
            if (panes.some(p => p.id === PICK || p.id === VIEW)) {
                await $.ui.close({id: PICK}).catch(() => undefined)
                await $.ui.close({id: VIEW}).catch(() => undefined)
                return {text: 'memoria closed.'}
            }
        }

        const brainsResult = await listBrains($)
        if (!brainsResult.ok) return {text: `memoria: ${brainsResult.error}`}
        const brains: BrainChoice[] = brainsResult.result.brains

        const [brainArg, ...rest] = args.words
        if (!brainArg) {
            await openBrainPicker($, brains)
            return {text: 'memoria: pick a brain.'}
        }
        const engramQuery = rest.join(' ')

        const match = brains.find(b => b.name === brainArg)
        if (!match) {
            return {text: `memoria: no brain "${brainArg}". Brains: ${brains.map(b => b.name).join(', ')}`}
        }
        if (!match.exists) {
            return {text: `memoria: brain "${brainArg}" directory missing (${match.location}).`}
        }

        if (!engramQuery) {
            const opened = await openEngramPicker($, brains, match.name)
            if (!opened.ok) return {text: `memoria: ${opened.error}`}
            return {text: `memoria: pick an engram in ${match.name}.`}
        }

        const listed = await listEngrams($, match.name)
        if (!listed.ok) return {text: `memoria: ${listed.error}`}
        const candidates = buildCandidates(listed.result.engrams)
        const top = resolveEngram(candidates, engramQuery)

        if (top) {
            if (wantSummary) {
                const r = await openSummary($, match.name, top.file, {focus: true})
                return {text: r.ok ? `memoria: summary of ${top.title}` : `memoria: ${r.error}`}
            }
            const opened = await openEngram($, match.name, top.file, 'new')
            if (!opened.ok) return {text: `memoria: ${opened.error}`}
            return {text: `memoria: ${top.title}`}
        }

        const state: PickerState = {
            v: 1,
            stage: 'engram',
            brains,
            brain: match.name,
            engrams: candidates,
            filter: engramQuery
        }
        await update($, picker, () => state)
        await place($, {id: PICK, title: `memoria: ${match.name}`, focus: true, closeOnEscape: true, rows: 20})
        return {text: `memoria: no match for "${engramQuery}" in ${match.name} — narrowed the picker.`}
    })

    // Listed in the prompt, not behind ToolSearch, so a model can call it without a lookup.
    on('tool.describe', {tool: SHOW_TOOL}, async ($, e, next) => ({...(await next(e)), isDeferred: false}))

    // Display only: always answers one line, never denies or throws, so a model never retries.
    on('tool.call', {tool: SHOW_TOOL}, async ($, e) => {
        const reply = (line: string) => ({result: line})
        try {
            const mode = e.mode ?? 'touch'
            const brainsResult = await listBrains($)
            if (!brainsResult.ok) return reply(`viewer unavailable: ${brainsResult.error}`)
            const brain = brainsResult.result.brains.find(b => b.name === e.brain)
            if (!brain || !brain.exists) return reply(`viewer: no usable brain "${e.brain}"`)

            const listed = await listEngrams($, brain.name)
            if (!listed.ok) return reply(`viewer: ${listed.error}`)
            const hit = resolveEngram(buildCandidates(listed.result.engrams), String(e.engram))
            if (!hit) return reply(`viewer: no engram matching "${e.engram}"`)

            if (mode === 'open') {
                const opened = await openEngram($, brain.name, hit.file, 'new', {focus: false})
                return reply(opened.ok ? `viewer: opened ${hit.file}` : `viewer: ${opened.error}`)
            }

            // A touch with the pane closed reopens it, unfocused.
            const current = await read($, view)
            if (!current) {
                const opened = await openEngram($, brain.name, hit.file, 'new', {focus: false})
                return reply(opened.ok ? `viewer: opened ${hit.file}` : `viewer: ${opened.error}`)
            }

            // A write to an engram in the shown chain rebuilds the summary.
            const chain = await read($, summary)
            if (chain && chain.brain === brain.name && chain.timeline.some(t => t.file === hit.file)) {
                const r = await refreshSummary($, {focus: false})
                return reply(r.ok ? `viewer: refreshed summary (${hit.file} changed)` : `viewer: ${r.error}`)
            }

            if (current.brain === brain.name && current.file === hit.file) {
                const refreshed = await refreshCurrent($, {focus: false, scrollTo: 'end'})
                return reply(refreshed.ok ? `viewer: refreshed ${hit.file}` : `viewer: ${refreshed.error}`)
            }

            const prior = await read($, pending)
            const next = nextPending(prior, {brain: brain.name, file: hit.file, title: hit.title})
            await update($, pending, () => next)
            if (next.count === 1) $.ui.toast(`memoria: ${hit.title} changed (g to open)`)
            return reply(`viewer: ${hit.file} changed; pane is showing another engram`)
        } catch (err) {
            return reply(`viewer: ${err instanceof Error ? err.message : String(err)}`)
        }
    })

    on('ui.close', {id: PICK}, async ($, e, next) => {
        await update($, picker, () => null)
        return next(e)
    })

    on('ui.close', {id: VIEW}, async ($, e, next) => {
        if (e.origin.kind === 'person' && (await read($, picker))?.inline) {
            await update($, picker, () => null)
            // Esc gave the keyboard to the composer; take it back.
            const shown = await read($, view)
            await place($, {id: VIEW, title: shown?.title ?? 'memoria', focus: true})
            return {value: undefined}
        }
        await update($, picker, () => null)
        await update($, view, () => null)
        await update($, summary, () => null)
        await update($, history, () => [])
        await update($, forward, () => [])
        await update($, pending, () => null)
        return next(e)
    })

    on('ui.render', {component: 'Pane', requestId: PICK}, async ($, e) => {
        // Mobile has no Input/Select.
        if (e.surface === 'mobile') {
            const {Box, Text} = $.ui.resolve(e)
            return (
                <Box flexDirection="column">
                    <Text dimColor>memoria: picking isn't available on mobile yet.</Text>
                </Box>
            )
        }
        const {Box, Text, Input, Select} = $.ui.resolve(e)
        const p = await read($, picker)

        if (!p) {
            return (
                <Box flexDirection="column">
                    <Text dimColor>Nothing to pick — run /memoria.</Text>
                </Box>
            )
        }
        return drawPicker($, {Box, Text, Input, Select}, e.props.bodyColumns, p)
    })

    on('ui.render', {component: 'Pane', requestId: VIEW}, async ($, e) => {
        const {Box, Text, Button, Markdown} = $.ui.resolve(e)
        const elements: ViewElements = {Box, Text, Button, Markdown}
        const v: EngramView | null = await read($, view)
        const width = e.props.bodyColumns
        const stack = await read($, history)
        const fwdStack = await read($, forward)
        const hint = await read($, pending)
        const inlinePicker = await read($, picker)
        const chain = await read($, summary)
        const doneShown = await read($, showDone)

        if (inlinePicker?.inline && e.surface !== 'mobile') {
            const {Input, Select} = $.ui.resolve(e)
            return drawPicker($, {Box, Text, Input, Select}, width, inlinePicker)
        }

        if (!v) {
            return (
                <Box flexDirection="column">
                    <Text dimColor>Nothing open — run /memoria.</Text>
                </Box>
            )
        }

        if (chain && isChainSummary(chain)) {
            return (
                <SummaryView
                    elements={elements}
                    s={chain}
                    width={width}
                    focused={e.props.isFocused}
                    showDone={doneShown}
                    canBack
                    onBack={() => {
                        void closeSummary($)
                    }}
                    onEngram={() => {
                        void closeSummary($)
                    }}
                    onReload={() => {
                        void refreshSummary($, {focus: true}).then(r => {
                            if (!r.ok) $.ui.toast(`memoria: ${r.error}`)
                        })
                    }}
                    onClose={() => {
                        void $.ui.close({id: VIEW})
                    }}
                    onToggleDone={() => {
                        void update($, showDone, d => !d)
                    }}
                    onOpen={file => {
                        void openEngram($, chain.brain, file, 'new')
                    }}
                    onOpenConcept={(concept, label) => {
                        void openConceptPicker($, chain.brain, concept, label).then(r => {
                            if (!r.ok) $.ui.toast(`memoria: ${r.error}`)
                        })
                    }}
                />
            )
        }

        const focused = e.props.isFocused
        const content = clip(v.body)

        return (
            <Box flexDirection="column">
                <Header
                    elements={elements}
                    v={v}
                    width={width}
                    focused={focused}
                    stack={stack}
                    fwdStack={fwdStack}
                    pending={hint}
                    onOpenPending={() => {
                        if (hint) void openEngram($, hint.brain, hint.file, 'new')
                    }}
                    onPickBrain={() => {
                        void (async () => {
                            const r = await listBrains($)
                            if (!r.ok) return $.ui.toast(`memoria: ${r.error}`)
                            await openBrainPicker($, r.result.brains, true)
                        })()
                    }}
                    onPickEngram={() => {
                        void (async () => {
                            const r = await listBrains($)
                            if (!r.ok) return $.ui.toast(`memoria: ${r.error}`)
                            const opened = await openEngramPicker($, r.result.brains, v.brain, '', true)
                            if (!opened.ok) $.ui.toast(`memoria: ${opened.error}`)
                        })()
                    }}
                    onBack={() => {
                        void goBack($)
                    }}
                    onForward={() => {
                        void goForward($)
                    }}
                    onReload={() => {
                        void refreshCurrent($, {focus: true}).then(r => {
                            if (!r.ok) $.ui.toast(`memoria: ${r.error}`)
                        })
                    }}
                    onSummary={() => {
                        void openSummary($, v.brain, v.file, {focus: true}).then(r => {
                            if (!r.ok) $.ui.toast(`memoria: ${r.error}`)
                        })
                    }}
                    onClose={() => {
                        void $.ui.close({id: VIEW})
                    }}
                    onOpenSynapse={file => {
                        void openEngram($, v.brain, file, 'new')
                    }}
                    onOpenConcept={(key, label) => {
                        void openConceptPicker($, v.brain, key, label).then(r => {
                            if (!r.ok) $.ui.toast(`memoria: ${r.error}`)
                        })
                    }}
                />
                <Box flexDirection="column" borderStyle="round" borderColor={REDOX.orange} paddingX={1}>
                    <EngramBody elements={elements} text={content} keyPrefix={BODY_KEY}/>
                </Box>
            </Box>
        )
    })
}
