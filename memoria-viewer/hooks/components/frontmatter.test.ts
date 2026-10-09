import { expect, test } from 'claude-code/testing'

import { shownValues } from './frontmatter'

test('a concept is shown by its display name, an undeclared one as written', () => {
  expect(shownValues({
    name: 'tags', kind: 'concept', list: true, values: ['java', 'loose'],
    concepts: [{ text: 'java', key: 'java', display_name: 'Java' }, { text: 'loose' }],
  })).toEqual([{ label: 'Java', concept: 'java' }, { label: 'loose', concept: 'loose' }])
})

test('a single value field is one value, empty is none', () => {
  expect(shownValues({ name: 'created', kind: 'value', list: false, values: '2026-09-23' })).toEqual([{ label: '2026-09-23' }])
  expect(shownValues({ name: 'created', kind: 'value', list: false, values: '' })).toEqual([])
})

test('a list value field is its values', () => {
  expect(shownValues({ name: 'aliases', kind: 'value', list: true, values: ['PX'] })).toEqual([{ label: 'PX' }])
})
