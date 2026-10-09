import {BODY_LIMIT} from '../constants'

/** Head and tail of an overlong body. */
export function clip(text: string): string {
    if (text.length <= BODY_LIMIT) return text
    const head = text.slice(0, 4000)
    const tail = text.slice(-4000)
    const elided = text.length - head.length - tail.length
    return `${head}\n\n…${elided} characters elided…\n\n${tail}`
}
