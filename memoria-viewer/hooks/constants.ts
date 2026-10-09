export const PICK = 'memoria-pick'
export const VIEW = 'memoria-view'
export const OWN_PLUGIN = 'memoria-viewer'

// Keeps one huge engram from eating the render budget (100000 characters).
export const BODY_LIMIT = 9500
export const MAX_HISTORY = 50

// `EngramBody` keys heading i as `${BODY_KEY}-h-${i}`.
export const BODY_KEY = 'body'

// A literal: it must match the `McpToolInputs` key and the `tool.call` matcher exactly.
export const TOOL_SHORT = 'show_engram'
export const SHOW_TOOL = 'mcp__memoria-viewer__show_engram' as const
