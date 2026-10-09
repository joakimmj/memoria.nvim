import {clipLabel} from '../filter'
import type {HistoryEntry, PendingChange} from '../../types'
import type {ViewElements} from '../utils/elements'
import REDOX from '../redox'

export type SynapseTarget = { file: string; title: string; exists: boolean }
export type SynapseRow = { field: string; targets: SynapseTarget[] }

export type NavigationProps = {
    elements: ViewElements
    synapses: Record<string, string[]>
    /** Filename → title; a target missing here is broken. */
    titleIndex: Record<string, string>
    width: number
    stack: readonly HistoryEntry[]
    fwdStack: readonly HistoryEntry[]
    /** An engram that changed while another was shown. */
    pending: PendingChange | null
    onOpenPending: () => void
    onPickBrain: () => void
    onPickEngram: () => void
    onBack: () => void
    onStepDown: () => void
    onStepUp: () => void
    onForward: () => void
    onReload: () => void
    onSummary: () => void
    onClose: () => void
    onOpenSynapse: (file: string) => void
}

const SYNAPSE_ORDER = ['up', 'down']

function orderIndex(order: string[], name: string): number {
    const i = order.indexOf(name)
    return i === -1 ? order.length : i
}

function stem(file: string): string {
    return file.replace(/\.md$/, '')
}

/** `up` before `down`, then alphabetical; a target missing from `titleIndex` is shown by its stem, dimmed. */
export function buildRows(synapses: Record<string, string[]>, titleIndex: Record<string, string>): SynapseRow[] {
    const names = Object.keys(synapses).sort((a, b) => {
        const diff = orderIndex(SYNAPSE_ORDER, a) - orderIndex(SYNAPSE_ORDER, b)
        return diff !== 0 ? diff : a.localeCompare(b)
    })
    return names.map(field => ({
        field,
        targets: (synapses[field] ?? []).map(file => ({
            file,
            title: titleIndex[file] ?? stem(file),
            exists: file in titleIndex,
        })),
    }))
}

export default function Navigation({
    elements,
    synapses,
    titleIndex,
    width,
    stack,
    fwdStack,
    pending,
    onOpenPending,
    onPickBrain,
    onPickEngram,
    onBack,
    onStepDown,
    onStepUp,
    onForward,
    onReload,
    onSummary,
    onClose,
    onOpenSynapse,
}: NavigationProps) {
    const {Box, Text, Button} = elements
    const rows = buildRows(synapses, titleIndex).filter(row => row.targets.length > 0)

    let hotkeyNum = 1
    const nextHotkey = (): string | undefined => (hotkeyNum <= 9 ? String(hotkeyNum++) : undefined)

    return (
        <Box flexDirection="column" borderStyle="round" borderColor={REDOX.teal} paddingX={1}>
            <Box flexDirection="row" gap={1}>
                <Button plain hotkey="h" dimColor={stack.length === 0} label="←" onPress={onBack}/>
                <Button plain hotkey="j" label="↓" onPress={onStepDown}/>
                <Button plain hotkey="k" label="↑" onPress={onStepUp}/>
                <Button plain hotkey="l" dimColor={fwdStack.length === 0} label="→" onPress={onForward}/>
                <Button plain hotkey="b" label="brain" onPress={onPickBrain}/>
                <Button plain hotkey="e" label="engram" onPress={onPickEngram}/>
                <Button plain hotkey="s" label="summary" onPress={onSummary}/>
                <Button plain hotkey="r" label="reload" onPress={onReload}/>
                <Button plain role="dismiss" hotkey="q" label="close" onPress={onClose}/>
            </Box>
            {pending && (
                <Box flexDirection="row" gap={1}>
                    <Text color={REDOX.orange}>●</Text>
                    <Button
                        plain
                        hotkey="g"
                        label={`${clipLabel(pending.title, Math.max(8, width - 14))} changed${pending.count > 1 ? ` ×${pending.count}` : ''}`}
                        onPress={onOpenPending}
                    />
                </Box>
            )}
            {rows.length > 0 && (
                <Text color={REDOX.teal}>{'─'.repeat(Math.max(1, width - 4))}</Text>
            )}
            {rows.map(row => (
                <Box flexDirection="row">
                    <Text bold color={REDOX.teal}>{row.field[0]!.toUpperCase() + row.field.slice(1)}: </Text>
                    <Box flexDirection="row" flexWrap="wrap" columnGap={1} rowGap={0}>
                        {row.targets.length === 0 && <Text dimColor>—</Text>}
                        {row.targets.map(t => {
                            const hk = nextHotkey()
                            return (
                                <Button
                                    plain
                                    hotkey={hk}
                                    dimColor={!t.exists}
                                    label={clipLabel(t.title, Math.max(8, Math.floor(width / 2) - 6))}
                                    onPress={() => onOpenSynapse(t.file)}
                                />
                            )
                        })}
                    </Box>
                </Box>
            ))}
        </Box>
    )
}
