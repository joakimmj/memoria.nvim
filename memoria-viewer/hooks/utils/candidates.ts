import type {EngramSummary} from '../mia'
import type {PickerCandidate} from '../../types'

/** `mia engrams` rows as picker candidates; list fields become filterable. */
export function buildCandidates(engrams: readonly EngramSummary[]): PickerCandidate[] {
    return engrams.map(e => {
        const {file, title, modified, ...rest} = e
        const fields: Record<string, string[]> = {}
        for (const [name, value] of Object.entries(rest)) {
            if (Array.isArray(value) && value.every(v => typeof v === 'string')) fields[name] = value as string[]
        }
        return {file, title, modified, fields}
    })
}
