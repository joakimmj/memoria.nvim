import type {FrontmatterField, TaskList, TaskMode} from '../../types'
import type {ViewElements} from '../utils/elements'
import REDOX from '../redox'
import Divider from './divider'
import FieldRows from './fields'
import type {ShownValue} from './fields'
import Source from './source'
import Tasks from './tasks'

export type FrontmatterProps = {
    elements: Pick<ViewElements, 'Box' | 'Text' | 'Button'>
    brain: string
    file: string
    fields: FrontmatterField[]
    tasks: TaskList
    taskMode: TaskMode | null
    onCycleTasks: (next: TaskMode) => void
    width: number
    onOpenConcept: (key: string, label: string) => void
    onCopyPath: () => void
}

/** A concept by its display name; an undeclared one as written, which is also how the atlas keys it. */
export function shownValues(field: FrontmatterField): ShownValue[] {
    if (field.concepts) return field.concepts.map(c => ({label: c.display_name ?? c.text, concept: c.key ?? c.text}))
    const values = Array.isArray(field.values) ? field.values : field.values ? [field.values] : []
    return values.map(label => ({label}))
}

export default function Frontmatter({elements, brain, file, fields, tasks, taskMode, onCycleTasks, width, onOpenConcept, onCopyPath}: FrontmatterProps) {
    const {Box} = elements
    const shown = fields.map(field => ({name: field.name, values: shownValues(field)})).filter(f => f.values.length > 0)
    return (
        <Box flexDirection="column" borderStyle="round" borderColor={REDOX.amber} paddingX={1}>
            <Source elements={elements} brain={brain} file={file} width={width} onCopyPath={onCopyPath}/>
            <Divider elements={elements} width={width} color={REDOX.amber}/>
            <Tasks
                elements={elements}
                tasks={tasks}
                width={width}
                mode={taskMode}
                defaultMode="closed"
                onCycle={onCycleTasks}
            />
            <FieldRows elements={elements} rows={shown} width={width} color={REDOX.amber} onOpenConcept={onOpenConcept}/>
        </Box>
    )
}
