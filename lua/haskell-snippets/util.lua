---@mod haskell-snippets.util

---@brief [[

---WARNING: This is not part of the public API.
---Breaking changes to this module will not be reflected in the semantic versioning of this plugin.

--- Utility functions
---@brief ]]
local util = {}

-- Lazy-load luasnip to allow testing pure functions without luasnip installed
local ls, sn, text, insert
local function ensure_luasnip()
  if not ls then
    ls = require('luasnip')
    sn = ls.snippet_node
    text = ls.text_node
    insert = ls.insert_node
  end
end

local function cur_buf_opt(name)
  ---@diagnostic disable-next-line
  return vim.api.nvim_buf_get_option(0, name)
end

function util.indent_str()
  if cur_buf_opt('expandtab') then
    local indent = cur_buf_opt('shiftwidth')
    if indent == 0 then
      indent = cur_buf_opt('tabstop')
    end
    return string.rep(' ', indent)
  end
  return '\t'
end

---@param mk_node function
---@param extra_indent boolean?
local function _indent_newline(mk_node, extra_indent, _, parent)
  extra_indent = extra_indent == nil or extra_indent
  local ok, pos = pcall(function()
    return parent:get_buf_position()
  end)
  local indent_count = (ok and pos and pos[2]) or 0
  local indent_str = string.rep(' ', indent_count) .. (extra_indent and util.indent_str() or '')
  return mk_node(indent_str)
end

function util.indent_newline_text(txt, extra_indent)
  ensure_luasnip()
  local function mk_node(indent_str)
    return sn(nil, { text { '', indent_str .. txt } })
  end
  return function(...)
    return _indent_newline(mk_node, extra_indent, ...)
  end
end

function util.indent_newline_insert(txt, extra_indent)
  ensure_luasnip()
  local function mk_node(indent_str)
    return sn(nil, {
      text { '', indent_str },
      insert(1, txt),
    })
  end
  return function(...)
    return _indent_newline(mk_node, extra_indent, ...)
  end
end

---@diagnostic disable-next-line: deprecated
local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients

---@return string|nil
function util.lsp_get_module_name()
  if #get_clients { bufnr = 0 } > 0 then
    for _, lens in pairs(vim.lsp.codelens.get(0)) do
      -- Strings to match taken from the module name plugin:
      -- https://github.com/haskell/haskell-language-server/blob/f0c16469046bd554828ea057b5e1f047ad02348e/plugins/hls-module-name-plugin/src/Ide/Plugin/ModuleName.hs#L129-L136
      local name_module_decl_absent = lens.command.title:match('module (.*) where')
      local name_module_decl_present = lens.command.title:match('Set module name to (.*)')
      local name = name_module_decl_absent or name_module_decl_present
      if name then
        return name
      end
    end
  end
end

--- Strip forall quantifier from a type signature.
--- e.g., "forall a b. a -> b -> c" becomes "a -> b -> c"
---@param signature string
---@return string stripped signature without forall
function util.strip_forall(signature)
  -- Match: forall <type vars separated by spaces> . <rest>
  -- Also handles: forall a. forall b. (nested foralls)
  local result = signature
  while true do
    local stripped = result:match('^%s*forall%s+[^.]+%.%s*(.+)$')
    if stripped then
      result = stripped
    else
      break
    end
  end
  return result
end

--- Strip type class constraints from a type signature.
--- e.g., "Show a => a -> String" becomes "a -> String"
--- e.g., "(Show a, Eq b) => a -> b -> Bool" becomes "a -> b -> Bool"
---@param signature string
---@return string stripped signature without constraints
function util.strip_constraints(signature)
  -- Match: <constraint(s)> => <rest>
  -- Handles both single constraints and tuple constraints
  local depth = 0
  local i = 1
  local len = #signature

  while i <= len do
    local char = signature:sub(i, i)

    if char == '(' or char == '[' or char == '{' then
      depth = depth + 1
    elseif char == ')' or char == ']' or char == '}' then
      depth = depth - 1
    elseif depth == 0 and signature:sub(i, i + 3) == ' => ' then
      -- Found constraint arrow at depth 0
      return signature:sub(i + 4):match('^%s*(.+)$') or ''
    end
    i = i + 1
  end

  return signature
end

--- Normalize a type signature by removing forall and constraints.
---@param signature string
---@return string normalized signature
function util.normalize_signature(signature)
  local result = util.strip_forall(signature)
  result = util.strip_constraints(result)
  return result
end

--- Parse a Haskell type signature into parameter types and return type.
--- Handles parenthesized types like `(Int -> Int)` as single units.
--- Automatically strips forall quantifiers and type class constraints.
---@param signature string e.g., "Int -> String -> Bool"
---@return string[] params e.g., {"Int", "String"}
---@return string return_type e.g., "Bool"
function util.parse_type_signature(signature)
  -- Normalize: strip forall and constraints first
  signature = util.normalize_signature(signature)
  local types = {}
  local current = ''
  local depth = 0
  local i = 1
  local len = #signature

  while i <= len do
    local char = signature:sub(i, i)

    if char == '(' or char == '[' or char == '{' then
      depth = depth + 1
      current = current .. char
      i = i + 1
    elseif char == ')' or char == ']' or char == '}' then
      depth = depth - 1
      current = current .. char
      i = i + 1
    elseif depth == 0 and signature:sub(i, i + 3) == ' -> ' then
      -- Found arrow at depth 0
      local trimmed = current:match('^%s*(.-)%s*$')
      if trimmed and #trimmed > 0 then
        table.insert(types, trimmed)
      end
      current = ''
      i = i + 4 -- Skip ' -> '
    else
      current = current .. char
      i = i + 1
    end
  end

  -- Add the last type (return type)
  local trimmed = current:match('^%s*(.-)%s*$')
  if trimmed and #trimmed > 0 then
    table.insert(types, trimmed)
  end

  if #types == 0 then
    return {}, ''
  elseif #types == 1 then
    return {}, types[1]
  else
    local return_type = table.remove(types)
    return types, return_type
  end
end

--- Parse a Haskell function type declaration line.
---@param line string e.g., "funcName :: Int -> String -> Bool"
---@return table|nil {name: string, params: string[], return_type: string}
function util.parse_function_line(line)
  local name, signature = line:match("^%s*([%w_']+)%s*::%s*(.+)$")
  if not name or not signature then
    return nil
  end
  local params, return_type = util.parse_type_signature(signature)
  return {
    name = name,
    params = params,
    return_type = return_type,
  }
end

--- Check if a line is a continuation of a type signature.
--- Continuation lines are indented and don't start a new declaration.
---@param line string
---@param allow_double_colon boolean? Allow :: on continuation (for name-only first line)
---@return boolean
function util.is_signature_continuation(line, allow_double_colon)
  -- Must be indented (starts with whitespace)
  if not line:match('^%s+') then
    return false
  end
  -- Must not be a new declaration (no ::) unless explicitly allowed
  if line:match('::') and not allow_double_colon then
    return false
  end
  -- Must not be a function definition (no = at start after trimming, unless inside parens)
  local trimmed = line:match('^%s*(.-)%s*$')
  -- Check for common non-continuation patterns
  if trimmed:match("^[%w_']+%s+[%w_']+%s*=") then
    return false -- function definition like "f x = ..."
  end
  if trimmed:match('^|') then
    return false -- guard
  end
  if trimmed:match('^where%s') or trimmed == 'where' then
    return false -- where clause
  end
  -- Likely a continuation if starts with -> or contains type-like content
  return true
end

--- Collect a potentially multiline type signature starting from a given row.
--- Supports two formats:
---   1. name :: Type -> Type (standard)
---   2. name\n  :: Type -> Type (name on separate line)
---@param start_row number 1-indexed row number
---@return string|nil full_signature The complete signature (joined)
---@return string|nil name The function name
function util.collect_multiline_signature(start_row)
  local line_count = vim.api.nvim_buf_line_count(0)

  if start_row > line_count then
    return nil, nil
  end

  local first_line = vim.api.nvim_buf_get_lines(0, start_row - 1, start_row, false)[1]
  if not first_line then
    return nil, nil
  end

  local name, signature_start, current_row

  -- Try format 1: "name :: signature" on same line
  name, signature_start = first_line:match("^%s*([%w_']+)%s*::%s*(.*)$")

  if name then
    -- Standard format: name and :: on same line
    current_row = start_row + 1
  else
    -- Try format 2: name alone, then ":: signature" on next indented line
    name = first_line:match("^%s*([%w_']+)%s*$")
    if not name then
      return nil, nil
    end

    -- Check if next line starts with ::
    if start_row >= line_count then
      return nil, nil
    end

    local second_line = vim.api.nvim_buf_get_lines(0, start_row, start_row + 1, false)[1]
    if not second_line then
      return nil, nil
    end

    -- Next line must be indented and start with ::
    signature_start = second_line:match('^%s+::%s*(.*)$')
    if not signature_start then
      return nil, nil
    end

    current_row = start_row + 2
  end

  -- Collect continuation lines
  local signature_parts = { signature_start }

  while current_row <= line_count do
    local next_line = vim.api.nvim_buf_get_lines(0, current_row - 1, current_row, false)[1]
    if not next_line or not util.is_signature_continuation(next_line) then
      break
    end
    -- Trim and add the continuation
    local trimmed = next_line:match('^%s*(.-)%s*$')
    table.insert(signature_parts, trimmed)
    current_row = current_row + 1
  end

  -- Join all parts with space (normalizing whitespace)
  local full_signature = table.concat(signature_parts, ' ')
  -- Clean up multiple spaces
  full_signature = full_signature:gsub('%s+', ' ')
  -- Trim leading/trailing whitespace
  full_signature = full_signature:match('^%s*(.-)%s*$')

  if not full_signature or full_signature == '' then
    return nil, nil
  end

  return full_signature, name
end

--- Get function context from the line below the cursor.
--- Supports multiline type signatures.
---@return table|nil {name: string, params: string[], return_type: string}
function util.get_function_context()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local line_count = vim.api.nvim_buf_line_count(0)

  if row >= line_count then
    return nil
  end

  -- Try to collect multiline signature starting from line below cursor
  local signature, name = util.collect_multiline_signature(row + 1)
  if not signature or not name then
    return nil
  end

  local params, return_type = util.parse_type_signature(signature)
  return {
    name = name,
    params = params,
    return_type = return_type,
  }
end

return util
