import { expect, test } from 'claude-code/testing'

import { decode } from './mia'

test('decodes a happy envelope', () => {
  const r = decode(0, '{"ok":true,"result":{"a":1}}\n', '')
  expect(r).toEqual({ ok: true, result: { a: 1 } })
})

test('decodes an {ok:false} envelope at exit 1', () => {
  const r = decode(1, '{"ok":false,"error":"boom"}\n', '')
  expect(r).toEqual({ ok: false, error: 'boom' })
})

test('reads the LAST non-empty stdout line, ignoring nvim startup chatter', () => {
  const stdout = 'some debug line from -l startup\nanother stray line\n{"ok":true,"result":{"brains":[]}}\n'
  const r = decode(0, stdout, '')
  expect(r).toEqual({ ok: true, result: { brains: [] } })
})

test('empty stdout falls back to stderr for the error text', () => {
  const r = decode(127, '', "env: 'nvim': No such file or directory\n")
  expect(r.ok).toBe(false)
  if (!r.ok) expect(r.error).toBe("env: 'nvim': No such file or directory")
})

test('empty stdout AND empty stderr still produces a clean error, never throws', () => {
  const r = decode(124, '', '')
  expect(r.ok).toBe(false)
  if (!r.ok) expect(r.error).toContain('124')
})

test('non-JSON stdout (as --help prints) decodes to a clean error, never throws', () => {
  const r = decode(0, 'Usage: mia <command> [options]\n\nCommands:\n  brains  Every registered brain\n', '')
  expect(r.ok).toBe(false)
  if (!r.ok) expect(r.error).toContain('non-JSON')
})

test('an envelope missing a boolean "ok" is treated as non-JSON, not crashed on', () => {
  const r = decode(0, '{"result":{}}\n', '')
  expect(r.ok).toBe(false)
})

test('{"ok":true} with no "result" decodes result to undefined, not an error', () => {
  const r = decode(0, '{"ok":true}\n', '')
  expect(r).toEqual({ ok: true, result: undefined })
})
