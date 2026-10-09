import type {Elements} from 'claude-code'

// Every surface has these four, typed alike, so the terminal's describe them all.
export type ViewElements = Pick<Elements['terminal'], 'Box' | 'Text' | 'Button' | 'Markdown'>
