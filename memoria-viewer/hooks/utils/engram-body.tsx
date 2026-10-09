import type {RenderElement} from 'claude-code'
import type {ViewElements} from './elements'
import {scanHeadings, headingColor} from './headings'

export type EngramBodyProps = {
    elements: Pick<ViewElements, 'Box' | 'Text' | 'Markdown'>
    text: string
    /** Heading `i` is keyed `${keyPrefix}-h-${i}`. */
    keyPrefix: string
}

/**
 * Markdown with headings drawn as colored `Text`. Each heading sits in a keyed
 * `Box`, since a key on `Text` is not a scroll target.
 */
export default function EngramBody({elements, text, keyPrefix}: EngramBodyProps) {
    const {Box, Text, Markdown} = elements
    const lines = text.split('\n')
    const headings = scanHeadings(text)
    const blocks: RenderElement[] = []
    let cursor = 0
    let chunkN = 0
    let spacerN = 0

    // `Markdown` trims its edge blank lines; put one back between blocks.
    const emit = (el: RenderElement) => {
        if (blocks.length > 0) blocks.push(<Text key={`${keyPrefix}-sp-${spacerN++}`}> </Text>)
        blocks.push(el)
    }

    headings.forEach((heading, i) => {
        const chunk = lines.slice(cursor, heading.line).join('\n')
        if (chunk.trim() !== '') emit(<Markdown key={`${keyPrefix}-md-${chunkN++}`} text={chunk}/>)
        emit(
            <Box key={`${keyPrefix}-h-${i}`}>
                <Text bold underline={heading.level === 1} color={headingColor(heading.level)}>
                    {heading.text}
                </Text>
            </Box>
        )
        cursor = heading.line + 1
    })
    const tail = lines.slice(cursor).join('\n')
    if (tail.trim() !== '') emit(<Markdown key={`${keyPrefix}-md-${chunkN++}`} text={tail}/>)

    return <Box flexDirection="column">{blocks}</Box>
}
