import type {ViewElements} from '../utils/elements'
import REDOX from '../redox'

export type FocusedProps = {elements: ViewElements; focused: boolean}

export default function Focused({elements, focused}: FocusedProps) {
    const {Text} = elements
    return (
        <Text>
            <Text color={focused ? REDOX.orange : REDOX.subtle}>{focused ? '● focused' : '○ unfocused'}</Text>
            {!focused && <Text color={REDOX.hint}> — ctrl+x tab or click to focus</Text>}
        </Text>
    )
}
