import {clipLabel} from '../filter'
import type {ViewElements} from '../utils/elements'

/** `concept`: what `mia engrams --concept` looks the value up by. */
export type ShownValue = { label: string; concept?: string }

export type FieldRow = { name: string; values: ShownValue[] }

// Digits are taken by synapses and related engrams; letters either view binds are left out.
export const CONCEPT_KEYS = ['a', 'c', 'f', 'i', 'm', 'n', 'o', 'p', 't', 'u', 'v', 'w', 'x', 'y', 'z'] as const

export type FieldRowsProps = {
    elements: Pick<ViewElements, 'Box' | 'Text' | 'Button'>
    rows: FieldRow[]
    width: number
    color: string
    onOpenConcept: (concept: string, label: string) => void
}

/** `Name: value …` rows; a concept value is a Button opening the engrams naming it. */
export default function FieldRows({elements, rows, width, color, onOpenConcept}: FieldRowsProps) {
    const {Box, Text, Button} = elements
    let next = 0
    const label = (text: string) => clipLabel(text, Math.max(8, Math.floor(width / 2) - 6))
    return (
        <Box flexDirection="column">
            {rows.map(row => (
                <Box flexDirection="row" gap={1}>
                    <Text bold color={color}>{row.name[0]!.toUpperCase() + row.name.slice(1)}:</Text>
                    <Box flexDirection="row" flexWrap="wrap" columnGap={1} rowGap={0}>
                        {row.values.map(value => {
                            if (!value.concept) return <Text>{label(value.label)}</Text>
                            const hotkey = CONCEPT_KEYS[next++]
                            return (
                                <Button
                                    plain
                                    hotkey={hotkey}
                                    label={label(value.label)}
                                    onPress={() => onOpenConcept(value.concept!, value.label)}
                                />
                            )
                        })}
                    </Box>
                </Box>
            ))}
        </Box>
    )
}
