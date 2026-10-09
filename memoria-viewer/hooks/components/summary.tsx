import {clipLabel} from '../filter'
import type {ChainSummary, TaskMode} from '../../types'
import type {ViewElements} from '../utils/elements'
import REDOX from '../redox'
import Divider from './divider'
import FieldRows from './fields'
import Focused from './focused'
import Tasks from './tasks'

export type SummaryProps = {
    elements: ViewElements
    s: ChainSummary
    width: number
    focused: boolean
    taskMode: TaskMode | null
    canBack: boolean
    onBack: () => void
    onEngram: () => void
    onReload: () => void
    onClose: () => void
    onCycleTasks: (next: TaskMode) => void
    onOpen: (file: string) => void
    onOpenConcept: (concept: string, label: string) => void
}

export default function Summary({
    elements,
    s,
    width,
    focused,
    taskMode,
    canBack,
    onBack,
    onEngram,
    onReload,
    onClose,
    onCycleTasks,
    onOpen,
    onOpenConcept,
}: SummaryProps) {
    const {Box, Text, Button} = elements
    const inner = Math.max(8, width - 6)
    const range = s.first && s.last && s.first !== s.last ? `${s.first} → ${s.last}` : s.first
    // Related engrams get 1-9; tasks cite them as `[n]`.
    const hotkeys = new Map<string, string>()
    s.timeline.slice(0, 9).forEach((row, i) => hotkeys.set(row.file, String(i + 1)))
    const ref = (file: string): string => {
        const k = hotkeys.get(file)
        return k ? `[${k}] ` : ''
    }

    return (
        <Box flexDirection="column">
            <Focused elements={elements} focused={focused}/>
            <Box flexDirection="column" borderStyle="round" borderColor={REDOX.teal} paddingX={1}>
                <Box flexDirection="row" gap={1}>
                    <Button plain hotkey="h" dimColor={!canBack} label="←" onPress={onBack}/>
                    <Button plain hotkey="s" label="engram" onPress={onEngram}/>
                    <Button plain hotkey="r" label="reload" onPress={onReload}/>
                    <Button plain role="dismiss" hotkey="q" label="close" onPress={onClose}/>
                </Box>
            </Box>

            <Box flexDirection="column" borderStyle="round" borderColor={REDOX.amber} paddingX={1}>
                <Text bold color={REDOX.amber}>
                    Chain · {s.timeline.length} engram{s.timeline.length === 1 ? '' : 's'}{range ? ` · ${range}` : ''}
                </Text>
                <Divider elements={elements} width={width} color={REDOX.amber}/>
                {s.missing.length > 0 && (
                    <Text>
                        <Text bold color={REDOX.red}>Broken links: </Text>
                        <Text color={REDOX.red}>{clipLabel(s.missing.join(', '), Math.max(8, inner - 14))}</Text>
                    </Text>
                )}
                <FieldRows
                    elements={elements}
                    rows={s.concepts.map(field => ({
                        name: field.name,
                        values: field.values.map(value => ({label: value, concept: value})),
                    }))}
                    width={width}
                    color={REDOX.amber}
                    gap={1}
                    onOpenConcept={onOpenConcept}
                />

                <Box marginTop={1}>
                    <Text bold color={REDOX.amber}>Related engrams:</Text>
                </Box>
                {s.timeline.map(row => {
                    const mark = row.file === s.seed ? '● ' : row.ups > 1 ? '↳ ' : '  '
                    const tasks = row.open + row.done > 0 ? ` · ☐${row.open} ☑${row.done}` : ''
                    const label = `${mark}${row.date ? `${row.date}  ` : ''}${row.title}${tasks}`
                    return (
                        <Button
                            plain
                            hotkey={hotkeys.get(row.file)}
                            label={clipLabel(label, inner)}
                            onPress={() => onOpen(row.file)}
                        />
                    )
                })}

                {s.open.length + s.done.length > 0 && (
                    <Box marginTop={1}>
                        <Tasks
                            elements={elements}
                            tasks={{open: s.open, done: s.done}}
                            width={width}
                            mode={taskMode}
                            defaultMode="open"
                            onCycle={onCycleTasks}
                            source={a => `${ref(a.file)}${a.title}`}
                        />
                    </Box>
                )}
            </Box>
        </Box>
    )
}
