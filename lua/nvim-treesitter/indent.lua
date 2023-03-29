local parsers = require "nvim-treesitter.parsers"
local queries = require "nvim-treesitter.query"
local tsutils = require "nvim-treesitter.ts_utils"
local ts = vim.treesitter

local M = {}

M.avoid_force_reparsing = {
  yaml = true,
}

M.comment_parsers = {
  comment = true,
  jsdoc = true,
  phpdoc = true,
}

---@param root TSNode
---@param lnum integer
---@return TSNode
local function get_first_node_at_line(root, lnum)
  local col = vim.fn.indent(lnum)
  return root:descendant_for_range(lnum - 1, col, lnum - 1, col)
end

---@param root TSNode
---@param lnum integer
---@return TSNode
local function get_last_node_at_line(root, lnum)
  local col = #vim.fn.getline(lnum) - 1
  return root:descendant_for_range(lnum - 1, col, lnum - 1, col)
end

---@param root TSNode
---@param lnum integer
---@return TSNode
local function get_node_at_line_col(root, lnum, col)
  return root:descendant_for_range(lnum - 1, col, lnum - 1, col)
end

---@param lnum integer
---@param root TSNode
---@param node TSNode
---@param q table of query captures
---@return TSNode
---@return integer|nil
local function get_node_at_previous_nonblank(lnum, root, node, q)
  local node = node
  local expand_initial_node_at ---@type integer|nil

  local debug_ws = false

  local skip_trailing_space = function(l, col)
      local line_trailing_space_trimmed, _ = string.sub(l, 1, col + 1):gsub("%s*$", "")
      return #line_trailing_space_trimmed - 1
  end
  local skip_leading_space = function(l, col)
      local line_leading_space_trimmed, _ = string.sub(l, 1, col + 1):gsub("^%s*", "")
      return #line_leading_space_trimmed
  end

  local cur_line = lnum - 1
  local line = vim.fn.getline(cur_line)
  local cur_col = #line - 1
  local search_limit = lnum
  while search_limit > 0 do
    -- trim trailing space (if comments aren't to eol)
    cur_col = skip_trailing_space(line, cur_col)

    if debug_ws then
      print("trimmed space", cur_line, cur_col,
            "|" .. line .. "|",
            "|" .. line:sub(cur_col + 1, cur_col + 1) .. "|")
    end

    if cur_col > 0 then
      node = get_node_at_line_col(root, cur_line, cur_col)
      
      if debug_ws then
        print("post trim node", cur_line, cur_col, node:type(), "|" .. line:sub(cur_col + 1, cur_col + 1) .. "|")
      end

      if node:type() == "comment" then
        -- there's a comment to skip over
        local comment_srow, comment_scol, _ = node:start()
        -- skip the comment
        cur_line = comment_srow + 1
        cur_col = comment_scol - 1
        line = vim.fn.getline(cur_line)

        if debug_ws then
          print("skip_comment", cur_line, cur_col, '|'..line..'|')
        end

        -- move past any spaces
        if cur_col > 0 then
          -- note intentional use of cur_col without 1-based adjustment
          cur_col = skip_trailing_space(line, cur_col)

          if debug_ws then
            print("skip ws", cur_line, cur_col)
          end
        end
      elseif q.indent["end"][node:id()] then
        -- Previous tree has ended, abort reverse search
        cur_line = lnum
        line = vim.fn.getline(line)
        cur_col = skip_leading_space(line, 0)

        if debug_ws then
          print("end found, aborting search", cur_line, cur_col, "|"..line.."|")
        end
      else
        expand_initial_node_at = cur_line
        break
      end
    end

    -- skip back lines as needed if empty line (just space)
    if cur_col < 0 then
      if cur_line == 1 then
        -- there are no more lines
        return get_first_node_at_line(root, lnum), expand_initial_node_at
      else
        -- go back a line
        cur_line = cur_line - 1
        line = vim.fn.getline(cur_line)
        cur_col = skip_trailing_space(line, #line - 1)

        if debug_ws then
          print("back a line", cur_line, cur_col, "|"..line.."|")
        end
      end
    end

    if cur_col > 0 then
      node = get_node_at_line_col(root, cur_line, cur_col)

      if debug_ws then
        print("new node", cur_line, cur_col, node:type())
      end
    end
    search_limit = search_limit - 1
  end

  return node, expand_initial_node_at
end

---@param bufnr integer
---@param node TSNode
---@param delimiter string
---@return TSNode|nil child
---@return boolean|nil is_end
local function find_delimiter(bufnr, node, delimiter)
  for child, _ in node:iter_children() do
    if child:type() == delimiter then
      local linenr = child:start()
      local line = vim.api.nvim_buf_get_lines(bufnr, linenr, linenr + 1, false)[1]
      local end_char = { child:end_() }
      local trimmed_after_delim, trimmed_before_delim
      local escaped_delimiter = delimiter:gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%1")
      trimmed_after_delim, _ = line:sub(end_char[2] + 1):gsub("[%s" .. escaped_delimiter .. "]*", "")
      trimmed_before_delim, _ = line:sub(1, end_char[2] - 1):gsub("[%s" .. escaped_delimiter .. "]*", "")
      return child, #trimmed_after_delim == 0, #trimmed_before_delim == 0
    end
  end
end

local get_indents = tsutils.memoize_by_buf_tick(function(bufnr, root, lang)
  local map = {
    indent = {
      auto = {},
      begin = {},
      ["end"] = {},
      dedent = {},
      branch = {},
      ignore = {},
      indent = {},
      align = {},
      zero = {},
    },
  }

  local function split(to_split)
    local t = {}
    for str in string.gmatch(to_split, "([^.]+)") do
      table.insert(t, str)
    end
    return t
  end

  for name, node, metadata in queries.iter_captures(bufnr, "indents", root, lang) do
    local path = split(name)
    -- node may contain a period so append directly.
    table.insert(path, node:id())
    queries.insert_to_path(map, path, metadata or {})
  end

  return map
end, {
  -- Memoize by bufnr and lang together.
  key = function(bufnr, root, lang)
    return tostring(bufnr) .. root:id() .. "_" .. lang
  end,
})

---@param lnum number (1-indexed)
function M.get_indent(lnum)
  local bufnr = vim.api.nvim_get_current_buf()
  local parser = parsers.get_parser(bufnr)
  if not parser or not lnum then
    return -1
  end

  local root_lang = parsers.get_buf_lang(bufnr)

  -- some languages like Python will actually have worse results when re-parsing at opened new line
  if not M.avoid_force_reparsing[root_lang] then
    -- Reparse in case we got triggered by ":h indentkeys"
    parser:parse()
  end

  -- Get language tree with smallest range around node that's not a comment parser
  local root, lang_tree ---@type TSNode, LanguageTree
  parser:for_each_tree(function(tstree, tree)
    if not tstree or M.comment_parsers[tree:lang()] then
      return
    end
    local local_root = tstree:root()
    if ts.is_in_node_range(local_root, lnum - 1, 0) then
      if not root or tsutils.node_length(root) >= tsutils.node_length(local_root) then
        root = local_root
        lang_tree = tree
      end
    end
  end)

  -- Not likely, but just in case...
  if not root then
    return 0
  end

  local q = get_indents(vim.api.nvim_get_current_buf(), root, lang_tree:lang())
  local line = vim.fn.getline(lnum)
  local is_empty_line = string.match(line, "^%s*$") ~= nil
  local node ---@type TSNode
  local expand_initial_node_at ---@type number|nil a line number (1-based) on which to allow nodes to be endless
  node = get_first_node_at_line(root, lnum)

  if is_empty_line then
    node, expand_initial_node_at = get_node_at_previous_nonblank(lnum, root, node, q)
  end

  local indent_size = vim.fn.shiftwidth()
  local indent = 0
  local _, _, root_start = root:start()
  if root_start ~= 0 then
    -- injected tree
    indent = vim.fn.indent(root:start() + 1)
  end

  -- tracks to ensure multiple indent levels are not applied for same line
  -- these are tri-state, -ve means was dedented, nil means not processed
  -- +ve means was indented
  local is_start_processed_by_row = {}
  local is_end_processed_by_row = {}

  if q.indent.zero[node:id()] then
    return 0
  end


  local process_indent = function(q, node, srow, erow, lnum, indent, debug,
                                  capture_key,
                                  default_include_start,
                                  default_include_body,
                                  default_include_end,
                                  default_include_after,
                                  increment,
                                  start_attached,
                                  additional_check)
    if q.indent[capture_key][node:id()] then
      local include_start = default_include_start
      local include_body = default_include_body
      local include_end = default_include_end
      local include_after = default_include_after
      if q.indent[capture_key][node:id()]["indent.start"] ~= nil then
        include_start = tonumber(q.indent[capture_key][node:id()]["indent.start"]) == 1
      end
      if q.indent[capture_key][node:id()]["indent.body"] ~= nil then
        include_body = tonumber(q.indent[capture_key][node:id()]["indent.body"]) == 1
      end
      if q.indent[capture_key][node:id()]["indent.end"] ~= nil then
        include_end = tonumber(q.indent[capture_key][node:id()]["indent.end"]) == 1
      end
      if q.indent[capture_key][node:id()]["indent.after"] ~= nil then
        include_after = tonumber(q.indent[capture_key][node:id()]["indent.after"]) == 1
      end
      local is_processed = is_start_processed_by_row[srow]
      if not start_attached then
        is_processed = is_end_processed_by_row[erow]
      end
      if debug then
        print(" considering "..capture_key,
          "ip:"..tostring(is_processed),
          "srow:"..(srow + 1),
          "erow:"..(erow + 1),
          "lnum:"..lnum,
          "st:"..tostring(lnum - 1 == srow).."("..tostring(include_start)..")",
          "bd:"..tostring(srow < lnum - 1 and lnum - 1 < erow).."("..tostring(include_body)..")",
          "ed:"..tostring(lnum - 1 == erow).."("..tostring(include_end)..")",
          "af:"..tostring(erow < lnum - 1).."("..tostring(include_after)..")",
          "ain:"..tostring(expand_initial_node_at),
          "ac:"..tostring(additional_check)
          )
      end
      if
        (
          ((is_processed ~= nil and (is_processed > 0) ~= (increment > 0))
           or is_processed == nil)
          and additional_check
          and (
              (include_start and lnum - 1 == srow)
           or (include_body and srow < lnum - 1 and lnum - 1 < erow)
           or (include_end and lnum - 1 == erow)
           or ((include_after or expand_initial_node_at == erow + 1) and erow < lnum - 1))
        )
      then
        --indent = math.max(indent - indent_size, 0)
        indent = indent + increment
        if start_attached then
          is_start_processed_by_row[srow] = increment
        else
          is_end_processed_by_row[erow] = increment
        end
        if debug then
          print(
            "  > processed",
            capture_key,
            lnum,
            "srow:"..(srow + 1),
            "erow:"..(erow + 1),
            "isp:"..tostring(is_start_processed_by_row[srow]),
            "iep:"..tostring(is_end_processed_by_row[erow]),
            " = "..indent
          )
        end
      end
    end
    return indent
  end

  local debug = false

  while node do
    -- do 'autoindent' if not marked as @indent
    if
      not q.indent.begin[node:id()]
      and not q.indent["end"][node:id()]
      and not q.indent.align[node:id()]
      and q.indent.auto[node:id()]
      and node:start() < lnum - 1
      and lnum - 1 <= node:end_()
    then
      -- print("BAIL")
      return -1
    end

    -- Do not indent if we are inside an @ignore block.
    -- If a node spans from L1,C1 to L2,C2, we know that lines where L1 < line <= L2 would
    -- have their indentations contained by the node.
    if
      not q.indent.begin[node:id()]
      and q.indent.ignore[node:id()]
      and node:start() < lnum - 1
      and lnum - 1 <= node:end_()
    then
      return 0
    end

    local srow, _, erow = node:range()

    local is_start_processed = false
    local is_end_processed = false

    if debug then
      --print("|"..line.."|")
      print(
        "A@"..lnum,
        node:type(),
        "srow:"..(srow + 1),
        "erow:"..(erow + 1),
        "isp:"..tostring(is_start_processed_by_row[srow]),
        "iep:"..tostring(is_end_processed_by_row[erow]),
        "end:"..tostring(q.indent["end"][node:id()] ~= nil),
        "brch:"..tostring(q.indent.branch[node:id()] ~= nil),
        "ddnt:"..tostring(q.indent.dedent[node:id()] ~= nil),
        "idnt:"..tostring(q.indent.begin[node:id()] ~= nil),
        "algn:"..tostring(q.indent.align[node:id()] ~= nil),
        " = "..indent
      )
    end

    -- conditions were
    --   q.indent["end"][node:id()]
    --   and (
    --     (not is_end_processed_by_row[erow] and erow <= lnum - 1)
    --   )
    indent = process_indent(q, node, srow, erow, lnum, indent, debug,
                   "end",
                   false, -- start
                   false, --body
                   true, -- end
                   true, --after
                   -indent_size,
                   false, -- attach start
                   true)

    -- conditions were
    --  ((not is_start_processed_by_row[srow] and q.indent.dedent[node:id()]
    --    and not q.indent.dedent[node:id()]["indent.after"]
    --    and srow < lnum - 1)
    --   or
    --    ((true or not is_end_processed_by_row[erow]) and q.indent.dedent[node:id()]
    --     and q.indent.dedent[node:id()]["indent.after"]
    --     and erow < lnum - 1))

    indent = process_indent(q, node, srow, erow, lnum, indent, debug,
              "dedent",
               false, -- start
               true, --body
               true, -- end
               true, --after
               -indent_size,
               true, -- attach start
               true)

    -- conditions were
    --   (not is_end_processed_by_row[erow] and q.indent.branch[node:id()] and srow <= lnum - 1 and erow >= lnum - 1)

    indent = process_indent(q, node, srow, erow, lnum, indent, debug,
           "branch",
           true, -- start
           true, --body
           true, -- end
           false, --after
           -indent_size,
           true, -- attach start
           true)

    local should_process = ((is_start_processed_by_row[srow] == nil) or (is_start_processed_by_row[srow] < 0))
    local is_in_err = false
    if should_process then
      local parent = node:parent()
      is_in_err = parent and parent:has_error()
    end

    -- conditions were
    --   should_process
    --   and ((
    --     q.indent.begin[node:id()]
    --     and ((srow ~= erow and srow < lnum - 1 and lnum -1 <= erow) or is_in_err or q.indent.begin[node:id()]["indent.immediate"])
    --     and ((srow < lnum - 1 and lnum -1 <= erow) or q.indent.begin[node:id()]["indent.start_at_same_line"])
    --   ) or (
    --     q.indent.indent[node:id()]
    --     and ((srow ~= erow and srow < lnum - 1) or is_in_err or q.indent.indent[node:id()]["indent.immediate"])
    --     and (srow < lnum - 1 or q.indent.indent[node:id()]["indent.start_at_same_line"])
    --   ))

    -- FIXME: avoid indents that indent dedent same line... unless error   
    indent = process_indent(q, node, srow, erow, lnum, indent, debug,
           "begin",
           false, -- start -- FIXME: include immediate
           true, --body
           true, -- end
           false, --after
           indent_size,
           true, -- attach start
           srow ~= erow or is_in_err or expand_initial_node_at == erow + 1)

    local align_node = node
    if is_in_err and not q.indent.align[align_node:id()] then
      -- only when the node is in error, promote the
      -- first child's aligned indent to the error node
      -- to work around ((ERROR "X" . (_)) @aligned_indent (#set! "delimeter" "AB"))
      -- matching for all X, instead set do
      -- (ERROR "X" @aligned_indent (#set! "delimeter" "AB") . (_))
      -- and we will fish it out here.
      for c in align_node:iter_children() do
        if q.indent.align[c:id()] then
          q.indent.align[align_node:id()] = q.indent.align[c:id()]
          break
        end
      end
      if debug then
        if align_node ~= node then
          print(" using new node for align", align_node:type())
        end
      end
    end

    -- do not indent for nodes that starts-and-ends on same line and starts on target line (lnum)
    if q.indent.align[align_node:id()] then
      if debug then
        print(" considering align",
          "ip:"..tostring(is_start_processed_by_row[srow]),
          "srow:"..(srow + 1),
          "erow:"..(erow + 1),
          "lnum:"..lnum,
          "st:"..tostring(lnum - 1 == srow),
          "bd:"..tostring(srow < lnum - 1 and lnum - 1 < erow),
          "ed:"..tostring(lnum - 1 == erow),
          "af:"..tostring(erow < lnum - 1),
          "c1:"..tostring(srow ~= erow or is_in_err),
          "c2:"..tostring(srow ~= lnum - 1)
          )
      end
      if (srow ~= erow or is_in_err) and (srow ~= lnum - 1) then
      --if should_process and q.indent.align[node:id()] and (srow ~= erow or is_in_err) and (srow ~= lnum - 1) then
        local metadata = q.indent.align[align_node:id()]
        local o_delim_node, o_is_last_in_line ---@type TSNode|nil, boolean|nil
        local c_delim_node, c_is_last_in_line, c_is_first_in_line ---@type TSNode|nil, boolean|nil, boolean|nil
        local indent_is_absolute = false
        if metadata["indent.open_delimiter"] then
          o_delim_node, o_is_last_in_line, _ = find_delimiter(bufnr, node, metadata["indent.open_delimiter"])
        else
          o_delim_node = node
        end
        if metadata["indent.close_delimiter"] then
          c_delim_node, c_is_last_in_line, c_is_first_in_line =
            find_delimiter(bufnr, node, metadata["indent.close_delimiter"])
        else
          c_delim_node = node
        end

        if o_delim_node then
          local o_srow, o_scol = o_delim_node:start()
          local c_srow = nil
          if c_delim_node then
            c_srow, _ = c_delim_node:start()
          end
          if o_is_last_in_line then
            -- hanging indent (previous line ended with starting delimiter)
            -- should be processed like indent
            if should_process then
              indent = indent + indent_size * 1
              if (true or c_is_last_in_line) then
                -- If current line is outside the range of a node marked with `@aligned_indent`
                -- Then its indent level shouldn't be affected by `@aligned_indent` node
                if c_srow and (c_srow < lnum - 1) then
                  indent = math.max(indent - indent_size, 0)
                end
              end
              if c_is_first_in_line then
                -- If current line is outside the range of a node marked with `@aligned_indent`
                -- Then its indent level shouldn't be affected by `@aligned_indent` node
                if c_srow and (c_srow <= lnum - 1 and metadata["indent.dedent_hanging_close"]) then
                  indent = math.max(indent - indent_size, 0)
                end
              end
            end
          else
            -- aligned indent
            if (true or c_is_last_in_line) and c_srow and o_srow ~= c_srow and c_srow < lnum - 1 then
              -- If current line is outside the range of a node marked with `@aligned_indent`
              -- Then its indent level shouldn't be affected by `@aligned_indent` node
              indent = math.max(indent - indent_size, 0)
            else
              indent = o_scol + (metadata["indent.increment"] or 1)
              indent_is_absolute = true
            end
          end
          -- deal with the final line
          local avoid_last_matching_next = false
          if c_srow and c_srow ~= o_srow and c_srow == lnum - 1 then
            -- delims end on current line, and are not open and closed same line.
            -- then this last line may need additional indent to avoid clashes
            -- with the next. `indent.avoid_last_matching_next` controls this behavior,
            -- for example this is needed for function parameters.
            avoid_last_matching_next = metadata["indent.avoid_last_matching_next"] or false
          end
          if avoid_last_matching_next then
            -- last line must be indented more in cases where
            -- it would be same indent as next line (we determine this as one
            -- width more than the open indent to avoid confusing with any
            -- hanging indents)
            if indent <= vim.fn.indent(o_srow + 1) + indent_size then
              indent = indent + indent_size * 1
            else
              indent = indent
            end
          end
          is_start_processed_by_row[srow] = indent_size

          if debug then
            print(
              "  > processed align",
              lnum,
              "srow:"..(srow + 1),
              "erow:"..(erow + 1),
              "isp:"..tostring(is_start_processed_by_row[srow]),
              "iep:"..tostring(is_end_processed_by_row[erow]),
              " = "..indent
            )
          end

          if indent_is_absolute then
            -- don't allow further indenting by parent nodes, this is an absolute position
            if debug then
              print("returning absolute =", indent)
            end
            return indent
          end
        end
      end
    end

    --is_end_processed_by_row[erow] = is_end_processed_by_row[erow] or is_end_processed
    --is_start_processed_by_row[srow] = is_start_processed_by_row[srow] or is_start_processed

    if debug then
      print(
        "B@"..lnum,
        node:type(),
        "srow:"..(srow + 1),
        "erow:"..(erow + 1),
        "isp:"..tostring(is_start_processed_by_row[srow]),
        "iep:"..tostring(is_end_processed_by_row[erow]),
        "end:"..tostring(q.indent["end"][node:id()] ~= nil),
        "brch:"..tostring(q.indent.branch[node:id()] ~= nil),
        "ddnt:"..tostring(q.indent.dedent[node:id()] ~= nil),
        "idnt:"..tostring(q.indent.begin[node:id()] ~= nil),
        "algn:"..tostring(q.indent.align[node:id()] ~= nil),
        " = "..indent
      )
    end

    node = node:parent()
  end

  if debug then
    print("returning", indent)
  end
  return math.max(indent, 0)
end

---@type table<integer, string>
local indent_funcs = {}

---@param bufnr integer
function M.attach(bufnr)
  indent_funcs[bufnr] = vim.bo.indentexpr
  vim.bo.indentexpr = "nvim_treesitter#indent()"
end

function M.detach(bufnr)
  vim.bo.indentexpr = indent_funcs[bufnr]
end

return M
