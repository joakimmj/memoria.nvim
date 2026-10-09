import type {ToolSpec} from 'claude-code'
import {TOOL_SHORT} from './constants'

/** The tool a model calls to show an engram. */
export const TOOL_SPEC: ToolSpec = {
    name: TOOL_SHORT,
    description:
        'Show a memoria engram in the docked viewer pane, or tell the pane that an engram it may ' +
        'be showing has just changed on disk. Display only: it never reads, writes, creates or ' +
        'edits a file, it only mirrors what is already on disk, so call it AFTER a write has ' +
        'landed, never instead of one. Use mode "open" once, when you start working on an engram, ' +
        'to put it on screen. Use mode "touch" (the default) after every later write to that ' +
        'engram: the pane reloads it if it is the one on screen, and otherwise leaves the reader ' +
        'where they are and raises a small hint instead. If the pane is closed it is reopened on that engram. Every outcome -- pane busy ' +
        'with another engram, no such brain or engram -- comes back as one line of text and ' +
        'nothing else happens; it never fails a task and never needs a retry.',
    inputSchema: {
        type: 'object',
        properties: {
            brain: {type: 'string', description: 'The memoria brain the engram lives in, e.g. "meetings" or "work".'},
            engram: {
                type: 'string',
                description:
                    'The engram filename, with its date prefix and ".md" and no directory part, e.g. ' +
                    '"2026-10-07_access_bundles.md". A bare title or keyword also resolves, by the same ' +
                    'ranking the /memoria picker filter box uses.',
            },
            mode: {
                type: 'string',
                enum: ['open', 'touch'],
                default: 'touch',
                description:
                    '"open" takes over the pane and shows this engram. "touch" reports that the file just ' +
                    'changed: the pane reloads it when it is the one on screen, and otherwise only hints. ' +
                    'Defaults to "touch", the one that never takes the pane away from the reader.',
            },
        },
        required: ['brain', 'engram'],
    },
}
