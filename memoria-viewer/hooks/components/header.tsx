import type {EngramView, HistoryEntry} from '../../types'
import type {ViewElements} from '../utils/elements'
import REDOX from '../redox'
import Focused from './focused'
import Frontmatter from './frontmatter'
import Navigation from './navigation'
import type {NavigationProps} from './navigation'

export type HeaderProps = {
    elements: ViewElements
    v: EngramView
    width: number
    focused: boolean
    stack: readonly HistoryEntry[]
    fwdStack: readonly HistoryEntry[]
} & Pick<
    NavigationProps,
    | 'pending'
    | 'onOpenPending'
    | 'onPickBrain'
    | 'onPickEngram'
    | 'onBack'
    | 'onForward'
    | 'onReload'
    | 'onSummary'
    | 'onClose'
    | 'onOpenSynapse'
> & {
    onOpenConcept: (key: string, label: string) => void
}

export default function Header({
    elements,
    v,
    width,
    focused,
    stack,
    fwdStack,
    pending,
    onOpenPending,
    onPickBrain,
    onPickEngram,
    onBack,
    onForward,
    onReload,
    onSummary,
    onClose,
    onOpenSynapse,
    onOpenConcept,
}: HeaderProps) {
    const {Box, Text} = elements
    return (
        <Box flexDirection="column">
            <Focused elements={elements} focused={focused}/>
            {v.isGone && <Text color={REDOX.red}>This engram no longer exists.</Text>}
            <Navigation
                elements={elements}
                synapses={v.entry.synapses ?? {}}
                titleIndex={v.titleIndex}
                width={width}
                stack={stack}
                fwdStack={fwdStack}
                pending={pending}
                onOpenPending={onOpenPending}
                onPickBrain={onPickBrain}
                onPickEngram={onPickEngram}
                onBack={onBack}
                onForward={onForward}
                onReload={onReload}
                onSummary={onSummary}
                onClose={onClose}
                onOpenSynapse={onOpenSynapse}
            />
            <Frontmatter elements={elements} fields={v.fields} tasks={v.tasks} width={width} onOpenConcept={onOpenConcept}/>
        </Box>
    )
}
