import {rank} from '../filter'
import type {PickerCandidate} from '../../types'

/** Exact filename (".md" optional), else the picker's top ranked match. */
export function resolveEngram(candidates: PickerCandidate[], query: string): PickerCandidate | undefined {
    const exact = candidates.find(c => c.file === query || c.file === `${query}.md`)
    return exact ?? rank(candidates, query, 1)[0]
}
