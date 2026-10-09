export type MemoriaArgs = {
    /** Known flags before any `--`, as typed (`-r` stays `-r`). */
    flags: ReadonlySet<string>
    /** Brain, then the engram query's words. */
    words: readonly string[]
    unknown: readonly string[]
}

export const KNOWN_FLAGS: ReadonlySet<string> = new Set(['--reload', '-r', '--close', '--summary', '-s'])

/** `/memoria`'s args into flags and words; `--` ends flags. */
export function parseMemoriaArgs(raw: string): MemoriaArgs {
    const flags = new Set<string>()
    const words: string[] = []
    const unknown: string[] = []
    let literal = false
    for (const token of raw.split(/\s+/)) {
        if (!token) continue
        if (!literal && token === '--') {
            literal = true
        } else if (!literal && token.startsWith('-')) {
            if (KNOWN_FLAGS.has(token)) flags.add(token)
            else unknown.push(token)
        } else {
            words.push(token)
        }
    }
    return {flags, words, unknown}
}
