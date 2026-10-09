import type { PickerCandidate } from '../types'

/** A label that does not fit drops its Button or option, so clip it first. */
export function clipLabel(text: string, width: number): string {
  const w = Math.max(1, Math.floor(width))
  if (text.length <= w) return text
  if (w === 1) return '…'
  return text.slice(0, w - 1) + '…'
}

/** Title, then field values while they fit. */
export function optionLabel(row: PickerCandidate, width: number): string {
  const extras: string[] = []
  if (row.fields.tags?.length) extras.push('#' + row.fields.tags.join(' #'))
  if (row.fields.participants?.length) extras.push(row.fields.participants.join(', '))
  const suffix = extras.length > 0 ? '  — ' + extras.join(' · ') : ''
  return clipLabel(row.title + suffix, width)
}

/**
 * Every query word must appear in title, filename or a field value; ranked by
 * where the whole query matched (title prefix, title, filename, fields), then
 * newest. An empty query lists all, newest first.
 */
export function rank(rows: PickerCandidate[], query: string, limit = 15): PickerCandidate[] {
  const q = query.trim().toLowerCase()
  if (!q) {
    return [...rows].sort((a, b) => b.modified.localeCompare(a.modified)).slice(0, limit)
  }

  const tokens = q.split(/\s+/).filter(Boolean)
  const scored: { row: PickerCandidate; tier: number }[] = []

  for (const row of rows) {
    const title = row.title.toLowerCase()
    const file = row.file.toLowerCase()
    const fieldText = Object.values(row.fields).flat().join(' ').toLowerCase()
    const haystack = `${title} ${file} ${fieldText}`
    if (!tokens.every(t => haystack.includes(t))) continue

    let tier: number
    if (title.startsWith(q)) tier = 0
    else if (title.includes(q)) tier = 1
    else if (file.includes(q)) tier = 2
    else tier = 3

    scored.push({ row, tier })
  }

  scored.sort((a, b) => (a.tier !== b.tier ? a.tier - b.tier : b.row.modified.localeCompare(a.row.modified)))
  return scored.slice(0, limit).map(s => s.row)
}
