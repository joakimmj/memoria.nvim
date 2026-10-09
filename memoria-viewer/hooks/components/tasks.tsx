import {clipLabel} from '../filter'
import type {ActionItem, TaskList, TaskMode} from '../../types'
import type {ViewElements} from '../utils/elements'
import REDOX from '../redox'

export type TasksProps = {
    elements: Pick<ViewElements, 'Box' | 'Text' | 'Button'>
    tasks: TaskList
    width: number
    /** The person's choice; null shows `defaultMode`. */
    mode: TaskMode | null
    defaultMode: TaskMode
    onCycle: (next: TaskMode) => void
    /** A second, dim line under each task naming where it came from. */
    source?: (a: ActionItem) => string
}

const ORDER: readonly TaskMode[] = ['closed', 'open', 'all']

const LABEL: Record<TaskMode, string> = {closed: 'show open', open: 'show all', all: 'hide'}

/** closed → open → all → closed. */
export function nextMode(mode: TaskMode): TaskMode {
    return ORDER[(ORDER.indexOf(mode) + 1) % ORDER.length]!
}

export function actionLine(a: ActionItem): string {
    return `${a.done ? '☑' : '☐'}  ${a.text}`
}

/** `Tasks: N open · M done (t: …)`, and the list the mode shows; nothing when there are no tasks. */
export default function Tasks({elements, tasks, width, mode, defaultMode, onCycle, source}: TasksProps) {
    const {Box, Text, Button} = elements
    if (tasks.open.length + tasks.done.length === 0) return null

    const shown = mode ?? defaultMode
    const inner = Math.max(8, width - 6)
    const row = (a: ActionItem, dim: boolean) => (
        <Box flexDirection="column">
            <Text dimColor={dim}>{clipLabel(actionLine(a), inner)}</Text>
            {source && <Text dimColor>{clipLabel(`   ← ${source(a)}`, inner)}</Text>}
        </Box>
    )

    return (
        <Box flexDirection="column">
            <Box flexDirection="row" flexWrap="wrap" columnGap={1}>
                <Text>
                    <Text bold color={REDOX.amber}>Tasks: </Text>
                    <Text color={REDOX.warn}>{tasks.open.length} open</Text>
                    <Text dimColor> · </Text>
                    <Text color={REDOX.hint}>{tasks.done.length} done</Text>
                </Text>
                <Text dimColor>(</Text>
                <Button plain hotkey="t" label={LABEL[shown]} onPress={() => onCycle(nextMode(shown))}/>
                <Text dimColor>)</Text>
            </Box>
            {shown !== 'closed' && tasks.open.length === 0 && <Text dimColor>no open tasks</Text>}
            {shown !== 'closed' && tasks.open.map(a => row(a, false))}
            {shown === 'all' && tasks.done.map(a => row(a, true))}
        </Box>
    )
}
