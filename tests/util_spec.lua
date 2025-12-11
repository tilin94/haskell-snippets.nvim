describe('util', function()
  local util = require('haskell-snippets.util')

  describe('strip_forall', function()
    it('strips simple forall', function()
      assert.equals('a -> a', util.strip_forall('forall a. a -> a'))
    end)

    it('strips forall with multiple type vars', function()
      assert.equals('a -> b -> c', util.strip_forall('forall a b c. a -> b -> c'))
    end)

    it('strips nested forall', function()
      assert.equals('a -> b', util.strip_forall('forall a. forall b. a -> b'))
    end)

    it('returns unchanged if no forall', function()
      assert.equals('Int -> Int', util.strip_forall('Int -> Int'))
    end)

    it('handles leading whitespace', function()
      assert.equals('a -> a', util.strip_forall('  forall a. a -> a'))
    end)
  end)

  describe('strip_constraints', function()
    it('strips simple constraint', function()
      assert.equals('a -> String', util.strip_constraints('Show a => a -> String'))
    end)

    it('strips tuple constraints', function()
      assert.equals('a -> b -> Bool', util.strip_constraints('(Show a, Eq b) => a -> b -> Bool'))
    end)

    it('returns unchanged if no constraint', function()
      assert.equals('Int -> Int', util.strip_constraints('Int -> Int'))
    end)

    it('handles constraint with parens in type', function()
      assert.equals('(a, b) -> c', util.strip_constraints('Show a => (a, b) -> c'))
    end)
  end)

  describe('is_signature_continuation', function()
    it('returns true for indented arrow line', function()
      assert.is_true(util.is_signature_continuation('  -> Int'))
    end)

    it('returns true for indented type', function()
      assert.is_true(util.is_signature_continuation('  Int'))
    end)

    it('returns false for non-indented line', function()
      assert.is_false(util.is_signature_continuation('-> Int'))
    end)

    it('returns false for new declaration', function()
      assert.is_false(util.is_signature_continuation('  f :: Int'))
    end)

    it('returns false for function definition', function()
      assert.is_false(util.is_signature_continuation('  f x = x'))
    end)

    it('returns false for guard', function()
      assert.is_false(util.is_signature_continuation('  | x > 0 = 1'))
    end)

    it('returns false for where clause', function()
      assert.is_false(util.is_signature_continuation('  where'))
    end)
  end)

  describe('parse_type_signature', function()
    it('parses simple signature', function()
      local params, ret = util.parse_type_signature('Int -> Int')
      assert.are.same({ 'Int' }, params)
      assert.equals('Int', ret)
    end)

    it('parses multi-param signature', function()
      local params, ret = util.parse_type_signature('Int -> String -> Bool')
      assert.are.same({ 'Int', 'String' }, params)
      assert.equals('Bool', ret)
    end)

    it('handles type applications', function()
      local params, ret = util.parse_type_signature('Maybe Int -> IO String')
      assert.are.same({ 'Maybe Int' }, params)
      assert.equals('IO String', ret)
    end)

    it('handles parenthesized function types', function()
      local params, ret = util.parse_type_signature('(Int -> Int) -> Int')
      assert.are.same({ '(Int -> Int)' }, params)
      assert.equals('Int', ret)
    end)

    it('handles nested parentheses', function()
      local params, ret = util.parse_type_signature('((a -> b) -> c) -> Maybe d -> IO ()')
      assert.are.same({ '((a -> b) -> c)', 'Maybe d' }, params)
      assert.equals('IO ()', ret)
    end)

    it('handles single type (no arrow)', function()
      local params, ret = util.parse_type_signature('Int')
      assert.are.same({}, params)
      assert.equals('Int', ret)
    end)

    it('handles constraints by stripping them', function()
      local params, ret = util.parse_type_signature('Show a => a -> String')
      assert.are.same({ 'a' }, params)
      assert.equals('String', ret)
    end)

    it('handles multiple constraints', function()
      local params, ret = util.parse_type_signature('(Show a, Eq b) => a -> b -> Bool')
      assert.are.same({ 'a', 'b' }, params)
      assert.equals('Bool', ret)
    end)

    it('handles forall quantifier', function()
      local params, ret = util.parse_type_signature('forall a. a -> a')
      assert.are.same({ 'a' }, params)
      assert.equals('a', ret)
    end)

    it('handles forall with multiple type variables', function()
      local params, ret = util.parse_type_signature('forall a b c. a -> b -> c')
      assert.are.same({ 'a', 'b' }, params)
      assert.equals('c', ret)
    end)

    it('handles forall with constraints', function()
      local params, ret = util.parse_type_signature('forall a. Show a => a -> String')
      assert.are.same({ 'a' }, params)
      assert.equals('String', ret)
    end)

    it('handles nested forall', function()
      local params, ret = util.parse_type_signature('forall a. forall b. a -> b -> (a, b)')
      assert.are.same({ 'a', 'b' }, params)
      assert.equals('(a, b)', ret)
    end)

    it('handles empty string', function()
      local params, ret = util.parse_type_signature('')
      assert.are.same({}, params)
      assert.equals('', ret)
    end)

    it('handles complex nested types', function()
      local params, ret = util.parse_type_signature('(a -> (b -> c)) -> d')
      assert.are.same({ '(a -> (b -> c))' }, params)
      assert.equals('d', ret)
    end)

    it('handles list types with arrows', function()
      local params, ret = util.parse_type_signature('[Int -> Int] -> Bool')
      assert.are.same({ '[Int -> Int]' }, params)
      assert.equals('Bool', ret)
    end)

    it('handles record types with arrows', function()
      local params, ret = util.parse_type_signature('{f :: Int -> Int} -> Bool')
      assert.are.same({ '{f :: Int -> Int}' }, params)
      assert.equals('Bool', ret)
    end)
  end)

  describe('parse_function_line', function()
    it('parses simple function declaration', function()
      local result = util.parse_function_line('f :: Int -> Int')
      assert.equals('f', result.name)
      assert.are.same({ 'Int' }, result.params)
      assert.equals('Int', result.return_type)
    end)

    it('parses function with multiple params', function()
      local result = util.parse_function_line('add :: Int -> Int -> Int')
      assert.equals('add', result.name)
      assert.are.same({ 'Int', 'Int' }, result.params)
      assert.equals('Int', result.return_type)
    end)

    it('parses function with underscores', function()
      local result = util.parse_function_line('my_func :: String -> Bool')
      assert.equals('my_func', result.name)
      assert.are.same({ 'String' }, result.params)
      assert.equals('Bool', result.return_type)
    end)

    it('parses function with primes', function()
      local result = util.parse_function_line("f' :: Int -> Int")
      assert.equals("f'", result.name)
      assert.are.same({ 'Int' }, result.params)
      assert.equals('Int', result.return_type)
    end)

    it('handles leading whitespace', function()
      local result = util.parse_function_line('  helper :: a -> b')
      assert.equals('helper', result.name)
      assert.are.same({ 'a' }, result.params)
      assert.equals('b', result.return_type)
    end)

    it('returns nil for non-signature lines', function()
      assert.is_nil(util.parse_function_line('f x = x + 1'))
      assert.is_nil(util.parse_function_line('-- comment'))
      assert.is_nil(util.parse_function_line(''))
      assert.is_nil(util.parse_function_line('module Foo where'))
    end)

    it('parses function with no params', function()
      local result = util.parse_function_line('constant :: Int')
      assert.equals('constant', result.name)
      assert.are.same({}, result.params)
      assert.equals('Int', result.return_type)
    end)
  end)

  describe('get_function_context', function()
    local function setup_buffer(lines)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_set_current_buf(buf)
      return buf
    end

    it('returns context from line below cursor', function()
      setup_buffer { '', 'add :: Int -> Int -> Int', 'add a b = a + b' }
      vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- cursor on line 1

      local context = util.get_function_context()
      assert.is_not_nil(context)
      assert.equals('add', context.name)
      assert.are.same({ 'Int', 'Int' }, context.params)
      assert.equals('Int', context.return_type)
    end)

    it('returns nil when cursor is on last line', function()
      setup_buffer { 'f :: Int -> Int', 'f x = x' }
      vim.api.nvim_win_set_cursor(0, { 2, 0 }) -- cursor on last line

      local context = util.get_function_context()
      assert.is_nil(context)
    end)

    it('returns nil when next line is not a signature', function()
      setup_buffer { '-- documentation', 'f x = x + 1' }
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local context = util.get_function_context()
      assert.is_nil(context)
    end)

    it('returns nil for empty buffer', function()
      setup_buffer { '' }
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local context = util.get_function_context()
      assert.is_nil(context)
    end)

    it('handles complex signatures', function()
      setup_buffer { '', 'transform :: (a -> b) -> [a] -> [b]' }
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local context = util.get_function_context()
      assert.is_not_nil(context)
      assert.equals('transform', context.name)
      assert.are.same({ '(a -> b)', '[a]' }, context.params)
      assert.equals('[b]', context.return_type)
    end)

    it('handles multiline signature', function()
      setup_buffer {
        '',
        'longFunction :: Int',
        '  -> String',
        '  -> Bool',
        'longFunction x y = x > 0',
      }
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local context = util.get_function_context()
      assert.is_not_nil(context)
      assert.equals('longFunction', context.name)
      assert.are.same({ 'Int', 'String' }, context.params)
      assert.equals('Bool', context.return_type)
    end)

    it('handles multiline signature with forall', function()
      setup_buffer {
        '',
        'polymorphic :: forall a b.',
        '  a -> b -> (a, b)',
        'polymorphic x y = (x, y)',
      }
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local context = util.get_function_context()
      assert.is_not_nil(context)
      assert.equals('polymorphic', context.name)
      assert.are.same({ 'a', 'b' }, context.params)
      assert.equals('(a, b)', context.return_type)
    end)

    it('handles multiline signature with constraints', function()
      setup_buffer {
        '',
        'showIt :: Show a =>',
        '  a -> String',
        'showIt = show',
      }
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local context = util.get_function_context()
      assert.is_not_nil(context)
      assert.equals('showIt', context.name)
      assert.are.same({ 'a' }, context.params)
      assert.equals('String', context.return_type)
    end)

    it('stops at function definition', function()
      setup_buffer {
        '',
        'f :: Int -> Int',
        'f x = x + 1',
        'g :: String',
      }
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local context = util.get_function_context()
      assert.is_not_nil(context)
      assert.equals('f', context.name)
      assert.are.same({ 'Int' }, context.params)
      assert.equals('Int', context.return_type)
    end)

    it('handles signature with forall and constraints', function()
      setup_buffer {
        '',
        'complicated :: forall a. Show a => a -> String',
      }
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local context = util.get_function_context()
      assert.is_not_nil(context)
      assert.equals('complicated', context.name)
      assert.are.same({ 'a' }, context.params)
      assert.equals('String', context.return_type)
    end)

    it('handles name on separate line from ::', function()
      setup_buffer {
        '',
        'fmap',
        '  :: (a -> b)',
        '  -> f a',
        '  -> f b',
        'fmap = undefined',
      }
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local context = util.get_function_context()
      assert.is_not_nil(context)
      assert.equals('fmap', context.name)
      assert.are.same({ '(a -> b)', 'f a' }, context.params)
      assert.equals('f b', context.return_type)
    end)

    it('handles name on separate line with forall', function()
      setup_buffer {
        '',
        'traverse',
        '  :: forall t f a b. (Traversable t, Applicative f)',
        '  => (a -> f b)',
        '  -> t a',
        '  -> f (t b)',
        'traverse = undefined',
      }
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local context = util.get_function_context()
      assert.is_not_nil(context)
      assert.equals('traverse', context.name)
      assert.are.same({ '(a -> f b)', 't a' }, context.params)
      assert.equals('f (t b)', context.return_type)
    end)

    it('returns nil for name alone without signature', function()
      setup_buffer {
        '',
        'someFunc',
        'someFunc = undefined',
      }
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local context = util.get_function_context()
      assert.is_nil(context)
    end)
  end)
end)
