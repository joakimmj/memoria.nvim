import {clipLabel} from '../filter'
import type {ActionItem, ChainSummary} from '../../types'
import type {ViewElements} from '../utils/elements'
import REDOX from '../redox'
import FieldRows from './fields'
import Focused from './focused'

export type SummaryProps = {
    elements: ViewElements
    s: ChainSummary
    width: number
    focused: boolean
    showDone: boolean
    canBack: boolean
    onBack: () => void
    onEngram: () => void
    onReload: () => void
    onClose: () => void
    onToggleDone: () => void
    onOpen: (file: string) => void
    onOpenConcept: (concept: string, label: string) => void
}

function actionLine(a: ActionItem): string {
    const parts = [a.done ? '☑' : '☐', a.text]
    if (a.owner) parts.push(`@${a.owner}`)
    if (a.deadline) parts.push(a.deadline)
    return parts.join('  ')
}

export default function Summary({
    elements,
    s,
    width,
    focused,
    showDone,
    canBack,
    onBack,
    onEngram,
    onReload,
    onClose,
    onToggleDone,
    onOpen,
    onOpenConcept,
}: SummaryProps) {
    const {Box, Text, Button} = elements
    const inner = Math.max(8, width - 6)
    const range = s.first && s.last && s.first !== s.last ? `${s.first} → ${s.last}` : s.first
    // Related engrams get 1-9; tasks and questions cite them as `[n]`.
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
                    <Button plain hotkey="d" label={showDone ? 'hide done' : 'show done'} onPress={onToggleDone}/>
                    <Button plain hotkey="r" label="reload" onPress={onReload}/>
                    <Button plain role="dismiss" hotkey="q" label="close" onPress={onClose}/>
                </Box>
            </Box>

            {s.concepts.length > 0 && (
                <Box flexDirection="column" borderStyle="round" borderColor={REDOX.amber} paddingX={1}>
                    <FieldRows
                        elements={elements}
                        rows={s.concepts.map(field => ({
                            name: field.name,
                            values: field.values.map(value => ({label: value, concept: value})),
                        }))}
                        width={width}
                        color={REDOX.amber}
                        onOpenConcept={onOpenConcept}
                    />
                </Box>
            )}

            <Box flexDirection="column" borderStyle="round" borderColor={REDOX.orange} paddingX={1}>
                <Text bold color={REDOX.orange}>
                    Chain · {s.timeline.length} engram{s.timeline.length === 1 ? '' : 's'}{range ? ` · ${range}` : ''}
                </Text>
                {s.missing.length > 0 && (
                    <Text color={REDOX.red}>{clipLabel(`broken links: ${s.missing.join(', ')}`, inner)}</Text>
                )}

                <Box marginTop={1}>
                    <Text bold color={REDOX.teal}>Related engrams</Text>
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

                <Box marginTop={1}>
                    <Text bold color={REDOX.teal}>Tasks · {s.open.length} open</Text>
                </Box>
                {s.open.map(a => (
                    <Box flexDirection="column">
                        <Text color={a.overdue ? REDOX.red : undefined}>{clipLabel(actionLine(a), inner)}</Text>
                        <Text dimColor>{clipLabel(`   ← ${ref(a.file)}${a.title}`, inner)}</Text>
                    </Box>
                ))}
                {s.done.length > 0 && !showDone && <Text dimColor>done ({s.done.length}) — d to show</Text>}
                {showDone && s.done.map(a => (
                    <Box flexDirection="column">
                        <Text dimColor>{clipLabel(actionLine(a), inner)}</Text>
                        <Text dimColor>{clipLabel(`   ← ${ref(a.file)}${a.title}`, inner)}</Text>
                    </Box>
                ))}

                {s.questions.length > 0 && (
                    <Box marginTop={1}>
                        <Text bold color={REDOX.teal}>Open questions</Text>
                    </Box>
                )}
                {s.questions.map(q => (
                    <Box flexDirection="column">
                        <Text color={REDOX.amber}>{clipLabel(`${ref(q.file)}${q.date}  ${q.title}`, inner)}</Text>
                        {q.items.map(item => (
                            <Text>{clipLabel(`  • ${item}`, inner)}</Text>
                        ))}
                    </Box>
                ))}
            </Box>
        </Box>
    )
}
