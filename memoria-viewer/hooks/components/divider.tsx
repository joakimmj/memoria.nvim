import type {ViewElements} from '../utils/elements'

export type DividerProps = {elements: Pick<ViewElements, 'Text'>; width: number; color: string}

/** A rule across a bordered, padded box. */
export default function Divider({elements, width, color}: DividerProps) {
    const {Text} = elements
    return <Text color={color}>{'─'.repeat(Math.max(1, width - 4))}</Text>
}
