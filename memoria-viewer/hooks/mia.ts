// Declared in the type contract, which must be self-contained.
import type {AtlasEntry} from '../types'

// `bin/mia` on Neovim's runtimepath. `mia` already needs memoria loaded at startup.
export const FIND_MIA = [
    'nvim', '--headless',
    '+lua io.write(vim.api.nvim_get_runtime_file("bin/mia", false)[1] or "")',
    '+qa',
] as const

export type MiaResult<T> = { ok: true; result: T } | { ok: false; error: string }

function lastNonEmptyLine(text: string): string | undefined {
    const lines = text.split('\n')
    for (let i = lines.length - 1; i >= 0; i--) {
        const line = lines[i]!.trim()
        if (line) return line
    }
    return undefined
}

/** `mia`'s output as an envelope. Reads the last line: `nvim -l` may print before it. */
export function decode<T>(exitCode: number, stdout: string, stderr: string): MiaResult<T> {
    const line = lastNonEmptyLine(stdout)
    if (!line) {
        return {ok: false, error: lastNonEmptyLine(stderr) || `mia printed nothing (exit ${exitCode})`}
    }

    let parsed: unknown
    try {
        parsed = JSON.parse(line)
    } catch {
        return {ok: false, error: `mia printed non-JSON: ${line.slice(0, 200)}`}
    }

    if (typeof parsed !== 'object' || parsed === null || typeof (parsed as { ok?: unknown }).ok !== 'boolean') {
        return {ok: false, error: `mia printed non-JSON: ${line.slice(0, 200)}`}
    }

    const envelope = parsed as { ok: boolean; result?: unknown; error?: unknown }
    if (envelope.ok === false) {
        return {ok: false, error: String(envelope.error ?? 'unknown error')}
    }
    return {ok: true, result: envelope.result as T}
}


export type BrainRow = { name: string; location: string; exists: boolean }
export type EngramSummary = { file: string; title: string; modified: string; [field: string]: unknown }
export type {AtlasEntry}
export type EngramResponse = {
    brain: string;
    file: string;
    path: string;
    entry: AtlasEntry;
    backlinks: string[];
    content: string
    /** Absent from an older `mia`. */
    filename_date_format?: string
    /** `%date%`'s format, so `created`'s. Absent from an older `mia`. */
    date_format?: string
}
