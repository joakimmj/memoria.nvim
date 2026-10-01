-- The one slug: engram filenames and concept keys. Strict snake_case ASCII, so
-- it is safe as a filename, in a shell, a URL and after a `#` in prose.
local M = {}

-- Lowercase Latin letters to ASCII. Our own rather than iconv's //TRANSLIT,
-- whose output differs between C libraries. A letter not here is dropped.
-- stylua: ignore
local TRANSLITERATE = {
  ["à"] = "a", ["á"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["å"] = "a",
  ["ā"] = "a", ["ă"] = "a", ["ą"] = "a", ["æ"] = "ae",
  ["ç"] = "c", ["ć"] = "c", ["ĉ"] = "c", ["ċ"] = "c", ["č"] = "c",
  ["ď"] = "d", ["đ"] = "d", ["ð"] = "d",
  ["è"] = "e", ["é"] = "e", ["ê"] = "e", ["ë"] = "e", ["ē"] = "e", ["ĕ"] = "e",
  ["ė"] = "e", ["ę"] = "e", ["ě"] = "e",
  ["ĝ"] = "g", ["ğ"] = "g", ["ġ"] = "g", ["ģ"] = "g",
  ["ĥ"] = "h", ["ħ"] = "h",
  ["ì"] = "i", ["í"] = "i", ["î"] = "i", ["ï"] = "i", ["ĩ"] = "i", ["ī"] = "i",
  ["ĭ"] = "i", ["į"] = "i", ["ı"] = "i", ["ĳ"] = "ij",
  ["ĵ"] = "j", ["ķ"] = "k", ["ĸ"] = "k",
  ["ĺ"] = "l", ["ļ"] = "l", ["ľ"] = "l", ["ŀ"] = "l", ["ł"] = "l",
  ["ñ"] = "n", ["ń"] = "n", ["ņ"] = "n", ["ň"] = "n", ["ŉ"] = "n", ["ŋ"] = "n",
  ["ò"] = "o", ["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o", ["ø"] = "o",
  ["ō"] = "o", ["ŏ"] = "o", ["ő"] = "o", ["œ"] = "oe",
  ["ŕ"] = "r", ["ŗ"] = "r", ["ř"] = "r",
  ["ś"] = "s", ["ŝ"] = "s", ["ş"] = "s", ["š"] = "s", ["ß"] = "ss",
  ["ţ"] = "t", ["ť"] = "t", ["ŧ"] = "t", ["þ"] = "th",
  ["ù"] = "u", ["ú"] = "u", ["û"] = "u", ["ü"] = "u", ["ũ"] = "u", ["ū"] = "u",
  ["ŭ"] = "u", ["ů"] = "u", ["ű"] = "u", ["ų"] = "u",
  ["ŵ"] = "w", ["ý"] = "y", ["ÿ"] = "y", ["ŷ"] = "y",
  ["ź"] = "z", ["ż"] = "z", ["ž"] = "z",
}

--- Strict snake_case from any text: transliterated, lowercased, every run of
--- anything outside [a-z0-9] one "_", none at either end.
---@param text string e.g. "Ærlig Østers"
---@return string slug e.g. "aerlig_osters"; "" when nothing usable is left
function M.slugify(text)
  local ascii = vim.fn.tolower(vim.trim(text)):gsub("[\194-\244][\128-\191]*", function(char)
    return TRANSLITERATE[char] or " "
  end)
  return (ascii:gsub("[^a-z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

return M
