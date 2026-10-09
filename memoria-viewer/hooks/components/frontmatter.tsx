import type {FrontmatterField, TaskCounts} from '../../types'
import type {ViewElements} from '../utils/elements'
import REDOX from '../redox'
import FieldRows from './fields'
import type {ShownValue} from './fields'

export type FrontmatterProps = {
    elements: Pick<ViewElements, 'Box' | 'Text' | 'Button'>
    fields: FrontmatterField[]
    tasks: TaskCounts
    width: number
    onOpenConcept: (key: string, label: string) => void
}

/** A concept by its display name; an undeclared one as written, which is also how the atlas keys it. */
export function shownValues(field: FrontmatterField): ShownValue[] {
    if (field.concepts) return field.concepts.map(c => ({label: c.display_name ?? c.text, concept: c.key ?? c.text}))
    const values = Array.isArray(field.values) ? field.values : field.values ? [field.values] : []
    return values.map(label => ({label}))
}

export default function Frontmatter({elements, fields, tasks, width, onOpenConcept}: FrontmatterProps) {
    const {Box, Text} = elements
    const shown = fields.map(field => ({name: field.name, values: shownValues(field)})).filter(f => f.values.length > 0)
    if (shown.length === 0 && tasks.open + tasks.done === 0) return null
    return (
        <Box flexDirection="column" borderStyle="round" borderColor={REDOX.amber} paddingX={1}>
            {tasks.open + tasks.done > 0 && (
                <Text>
                    <Text bold color={REDOX.amber}>Tasks: </Text>
                    <Text color={REDOX.warn}>{tasks.open} open</Text>
                    <Text dimColor> · </Text>
                    <Text color={REDOX.hint}>{tasks.done} done</Text>
                </Text>
            )}
            <FieldRows elements={elements} rows={shown} width={width} color={REDOX.amber} onOpenConcept={onOpenConcept}/>
        </Box>
    )
}
