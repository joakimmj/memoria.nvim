export const PICK = 'memoria-pick'
export const VIEW = 'memoria-view'
export const OWN_PLUGIN = 'memoria-viewer'

// The host draws the first 100000 characters of a tree's texts; the body gets
// most of that and the rest is left for the header, fields, tasks and labels.
export const BODY_LIMIT = 90000
export const MAX_HISTORY = 50

// `EngramBody` keys heading i as `${BODY_KEY}-h-${i}`.
export const BODY_KEY = 'body'

// A literal: it must match the `McpToolInputs` key and the `tool.call` matcher exactly.
export const TOOL_SHORT = 'show_engram'
export const SHOW_TOOL = 'mcp__memoria-viewer__show_engram' as const
