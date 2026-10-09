import {clipLabel} from '../filter'
import type {ViewElements} from '../utils/elements'
import REDOX from '../redox'

export type SourceProps = {
    elements: Pick<ViewElements, 'Box' | 'Text' | 'Button'>
    brain: string
    file: string
    width: number
    onCopyPath: () => void
}

/** `Brain: <brain> · <filename>`, styled as the summary's `Chain · …` heading, and the key that copies the engram's path. */
export default function Source({elements, brain, file, width, onCopyPath}: SourceProps) {
    const {Box, Text, Button} = elements
    return (
        <Box flexDirection="row" flexWrap="wrap" columnGap={1}>
            <Text bold color={REDOX.amber}>{clipLabel(`Brain: ${brain} · ${file}`, Math.max(8, width - 6))}</Text>
            <Text dimColor>(</Text>
            <Button plain hotkey="y" label="copy path" onPress={onCopyPath}/>
            <Text dimColor>)</Text>
        </Box>
    )
}
