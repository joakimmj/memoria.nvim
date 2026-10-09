import type { EngramResponse } from './mia'
import type { EngramView, FrontmatterField, PendingChange, PickerState, TaskCounts } from '../types'

export function splitFrontmatter(content: string): { front: string; body: string } {
  const lines = content.split('\n')
  if (lines[0] !== '---') return { front: '', body: content }
  const closeIdx = lines.indexOf('---', 1)
  if (closeIdx === -1) return { front: '', body: content }
  return { front: lines.slice(1, closeIdx).join('\n'), body: lines.slice(closeIdx + 1).join('\n') }
}

export function stripSynapses(body: string): string {
  const open = '<!-- SYNAPSES -->'
  const close = '<!-- /SYNAPSES -->'
  const start = body.indexOf(open)
  if (start === -1) return body
  const end = body.indexOf(close, start)
  if (end === -1) return body
  return body.slice(0, start) + body.slice(end + close.length)
}

export function buildView(
  resp: EngramResponse,
  titleIndex: Record<string, string>,
  fields: FrontmatterField[],
  tasks: TaskCounts,
): EngramView {
  const { body: afterFront } = splitFrontmatter(resp.content)
  const body = stripSynapses(afterFront)

  return {
    v: 2,
    brain: resp.brain,
    file: resp.file,
    title: resp.entry.title,
    fields,
    tasks,
    entry: resp.entry,
    titleIndex,
    body: body.trim(),
  }
}

/** Reload guard: state an older build wrote is discarded. */
export function isEngramView(value: unknown): value is EngramView {
  if (typeof value !== 'object' || value === null) return false
  const v = value as Record<string, unknown>
  return (
    v.v === 2 &&
    typeof v.brain === 'string' &&
    typeof v.file === 'string' &&
    Array.isArray(v.fields) &&
    typeof v.tasks === 'object' && v.tasks !== null &&
    typeof v.entry === 'object' && v.entry !== null &&
    typeof v.titleIndex === 'object' && v.titleIndex !== null &&
    typeof v.body === 'string'
  )
}

export function isPendingChange(value: unknown): value is PendingChange {
  if (typeof value !== 'object' || value === null) return false
  const v = value as Record<string, unknown>
  return (
    v.v === 1 &&
    typeof v.brain === 'string' &&
    typeof v.file === 'string' &&
    typeof v.title === 'string' &&
    typeof v.count === 'number'
  )
}

/** A `touch` on an engram not shown: the same one bumps `count`, another replaces it. */
export function nextPending(
  prior: PendingChange | null,
  hit: { brain: string; file: string; title: string },
): PendingChange {
  if (prior && prior.brain === hit.brain && prior.file === hit.file) {
    return { ...prior, title: hit.title, count: prior.count + 1 }
  }
  return { v: 1, brain: hit.brain, file: hit.file, title: hit.title, count: 1 }
}

export function isPickerState(value: unknown): value is PickerState {
  if (typeof value !== 'object' || value === null) return false
  const v = value as Record<string, unknown>
  return v.v === 1 && (v.stage === 'brain' || v.stage === 'engram') && Array.isArray(v.brains) && Array.isArray(v.engrams)
}
