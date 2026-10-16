import {BODY_LIMIT} from '../constants'

/** The head of an overlong body, cut at a line boundary, with a note of what is left out. */
export function clip(text: string): string {
    if (text.length <= BODY_LIMIT) return text
    const cut = text.lastIndexOf('\n', BODY_LIMIT)
    const head = text.slice(0, cut > 0 ? cut : BODY_LIMIT)
    return `${head}\n\n…${text.length - head.length} more characters not shown…`
}
