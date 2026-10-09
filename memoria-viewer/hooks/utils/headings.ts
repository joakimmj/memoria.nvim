import REDOX from '../redox'

export type HeadingLevel = 1 | 2 | 3 | 4 | 5 | 6

export type HeadingMatch = {
    level: HeadingLevel
    /** Without the `#` marker. */
    text: string
    /** Line index in `body.split('\n')`. */
    line: number
}

const HEADING = /^(#{1,6})\s+(.+)$/
const FENCE = /^(```|~~~)/

/** ATX headings, skipping fenced code. Its indexes are `EngramBody`'s heading keys. */
export function scanHeadings(body: string): HeadingMatch[] {
    const headings: HeadingMatch[] = []
    const lines = body.split('\n')
    let inFence = false
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i]!
        if (FENCE.test(line.trim())) {
            inFence = !inFence
            continue
        }
        if (inFence) continue
        const match = line.match(HEADING)
        if (match) headings.push({level: match[1]!.length as HeadingLevel, text: match[2]!.trim(), line: i})
    }
    return headings
}

/** redox.nvim's `@markup.heading.N` colors (level 1 also carries the underline). */
export function headingColor(level: HeadingLevel): string {
    switch (level) {
        case 1:
            return REDOX.orange
        case 2:
            return REDOX.rust
        case 3:
            return REDOX.teal
        case 4:
            return REDOX.amber
        case 5:
            return REDOX.cyan
        case 6:
            return REDOX.sea
    }
}
