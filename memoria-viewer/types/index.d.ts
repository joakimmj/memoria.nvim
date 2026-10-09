export type AtlasEntry = {
    title: string
    synapses: Record<string, string[]>
    links: string[]
    modified: string
    hash: string
    error?: string
    [field: string]: unknown
}

/** No `key` when undeclared. */
export type FieldConcept = { text: string; key?: string; display_name?: string }

export type FrontmatterField = {
    name: string
    kind: 'concept' | 'value'
    list: boolean
    concept_type?: string
    concept_form?: 'slug' | 'display_name'
    /** One string for `list = false`. */
    values: string | string[]
    concepts?: FieldConcept[]
}

export type EngramView = {
    /** Shape version, see the reload guards. */
    v: 4
    brain: string
    file: string
    /** Absolute, as the CLI answers it. */
    path: string
    title: string
    fields: FrontmatterField[]
    tasks: TaskList
    entry: AtlasEntry
    /** Filename → title. */
    titleIndex: Record<string, string>
    /** Without frontmatter and SYNAPSES block. */
    body: string
    /** The file is gone. */
    isGone?: true
}

export type HistoryEntry = { brain: string; file: string }

// Where the page being left goes: `history` ('new', 'forward') or `forward` ('back').
export type NavMode = 'new' | 'back' | 'forward'

export type BrainChoice = { name: string; exists: boolean; location: string }

export type PickerCandidate = {
    file: string
    title: string
    modified: string
    fields: Record<string, string[]>
}

export type PickerState = {
    v: 1
    stage: 'brain' | 'engram'
    brains: BrainChoice[]
    brain?: string
    engrams: PickerCandidate[]
    filter: string
    /** Drawn inside VIEW; Esc returns to the engram. */
    inline?: true
    /** Listing the engrams naming this concept. */
    concept?: { key: string; label: string }
}

export type PendingChange = {
    /** Shape version, see the reload guards. */
    v: 1
    brain: string
    file: string
    title: string
    count: number
}

export type ActionItem = {
    text: string
    done: boolean
    file: string
    title: string
    date: string
}

export type TaskList = { open: ActionItem[]; done: ActionItem[] }

/** `closed`: heading only; `open`: open tasks; `all`: open and done. */
export type TaskMode = 'closed' | 'open' | 'all'

export type TimelineRow = {
    file: string
    title: string
    date: string
    open: number
    done: number
    /** More than one marks a merge point. */
    ups: number
}

export type ChainSummary = {
    v: 2
    brain: string
    seed: string
    timeline: TimelineRow[]
    open: ActionItem[]
    done: ActionItem[]
    concepts: { name: string; values: string[] }[]
    /** Synapse targets not in the brain. */
    missing: string[]
    first: string
    last: string
    builtAt: string
}

declare module 'claude-code' {
    interface PluginState {
        'memoria-viewer': {
            summary: ChainSummary | null
            taskMode: TaskMode | null
            view: EngramView | null
            picker: PickerState | null
            history: HistoryEntry[]
            forward: HistoryEntry[]
            pending: PendingChange | null
        }
    }

    interface McpToolInputs {
        'mcp__memoria-viewer__show_engram': {
            brain: string
            engram: string
            mode?: 'open' | 'touch'
        }
    }
}
