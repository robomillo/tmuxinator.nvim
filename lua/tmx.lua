local Job = require('plenary.job')
local sqlite = require('sqlite.db')
local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local opt_map = {}
local favourites = {}
G = {}

G.db = sqlite.new(vim.fn.stdpath("config") .. "/tmx_db.db", { keep_open = true })
G.db:with_open(function()
  G.db:create("projects",
    { ensure = true,
      name = {
        "text",
        required = true,
        unique = true,
        primary = true,
      },
      access_count = {
        "number", default = 0
      },
      is_favourite = {
        "integer", default = 0
      }
    }
  )
end
)

function G:get()
  return G.db:with_open(
    function(db)
      local statement = "SELECT name, is_favourite FROM projects ORDER BY is_favourite DESC, access_count DESC, name;"
      local table = db:eval(statement)
      return table
    end
  )
end

function G:insert(project_name)
  G.db:with_open(
    function(db)
      local statement = "INSERT OR IGNORE INTO projects(name) VALUES (?);"
      db:eval(statement, project_name)
    end
  )
end

function G:toggle_favourite(project_name)
  G.db:with_open(
    function(db)
      local statement = "UPDATE projects SET is_favourite = CASE WHEN is_favourite = 1 THEN 0 ELSE 1 END WHERE name = ?;"
      db:eval(statement, project_name)
    end
  )
end

function G:increment_access_count(project_name)
  G.db:with_open(
    function(db)
      local statement = "UPDATE projects SET access_count = access_count + 1 WHERE name = ?"
      db:eval(statement, project_name)
    end
  )
end

local function opt_len()
  local count = 0
  for _ in pairs(opt_map) do count = count + 1 end
  return count
end

local function get_longest_opt()
  local sorted = {}
  for _, v in pairs(opt_map) do
    table.insert(sorted, v)
  end
  table.sort(sorted, function(a, b) return #a < #b end)
  return sorted[1]
end

local function create_initial_float()
  G.base_win_height = vim.api.nvim_win_get_height(G.base_win)
  G.base_win_width = vim.api.nvim_win_get_width(G.base_win)
  local width = string.len(get_longest_opt()) + 20
  local height = 10
  local opts = {
    relative = 'editor',
    row = height,
    col = math.floor(G.base_win_width * 0.5) - width,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded"
  }
  G.tmx_buf = vim.api.nvim_create_buf(true, true)
  G.tmx_win = vim.api.nvim_open_win(G.tmx_buf, true, opts)
  vim.api.nvim_win_set_option(G.tmx_win, "cursorline", true)
end

local function center(win, str)
  local width = vim.api.nvim_win_get_width(win)
  local shift = math.floor(width / 2) - math.floor(string.len(str) / 2)
  local left_and_center = string.rep(' ', shift) .. str
  return left_and_center .. string.rep(' ', width - string.len(left_and_center))
end

local function set_options_in_win()
  -- set favourite highlight group
  vim.api.nvim_set_hl(0, "favourite", { underline = true, bg = "#24283b", fg = "#e0af68" })

  -- center content
  local content = {}
  for k, v in pairs(opt_map) do
    table.insert(content, center(G.tmx_win, v))
  end
  -- set content
  vim.api.nvim_buf_set_lines(G.tmx_buf, 0, -1, false, content)
  local i = 0
  for k, v in ipairs(opt_map) do
    if favourites[k] ~= nil then
      vim.api.nvim_buf_add_highlight(G.tmx_buf, -1, "favourite", i, 0, -1)
    end
    i = i + 1
  end
  -- register command on buffer to process selection
  vim.api.nvim_buf_set_keymap(G.tmx_buf, 'i', '<Esc>',
    "<C-c>:q<CR>",
    { noremap = true })
  vim.api.nvim_buf_set_keymap(G.tmx_buf, 'n', '<Esc>',
    ":q<CR>",
    { noremap = true })
  vim.api.nvim_buf_set_keymap(G.tmx_buf, 'n', '<CR>',
    "<cmd>lua require('tmx').opt_selected()<CR>",
    { noremap = true })

  vim.api.nvim_buf_set_keymap(G.tmx_buf, 'n', '<leader>f',
    "<cmd>lua require('tmx').toggle_favourite()<CR>",
    { noremap = true })
end

local function switch_session()
  print("Switching to: " .. G.selected)
  Job:new({
    command = "/usr/local/bin/tmuxinator",
    args = { "start", G.selected },
  }):sync() -- or start()
  -- vim.api.nvim_win_close(G.tmx_win, 1)
end

local function opt_selected()
  G:increment_access_count(G.selected)
  switch_session()
end

local function parse_and_insert_new(raw_options)
  for idx, line in ipairs(raw_options) do
    for project in string.gmatch(line, "[^%s]+") do
      G:insert(project)
    end
  end
end

local function get_and_insert_new()
  Job:new({
    command = "/usr/local/bin/tmuxinator",
    args = { "list" },
    on_exit = function(j, return_val)
      local raw_options = j:result()
      table.remove(raw_options, 1)
      parse_and_insert_new(raw_options)
    end,
  }):sync() -- or start()
end

local function get_and_set_sorted_options()
  opt_map = {}
  favourites = {}
  local results = G:get()
  for idx, row in ipairs(results) do
    table.insert(opt_map, idx, row.name)
    if row.is_favourite == 1 then
      table.insert(favourites, row.name)
    end
  end
end

local function toggle_favourite()
  local selection = action_state.get_selected_entry()
  G.selected = selection[1]
  G:toggle_favourite(G.selected)
  get_and_set_sorted_options()
end

local function highlight_favourite(entry)

  return entry
end

local function tmx()
  get_and_insert_new()
  get_and_set_sorted_options()

  local find = function(opts)
    opts = opts or {}
    pickers.new(opts, {
      prompt_title = "colors",
      finder = finders.new_table {
        results = opt_map,
        entry_maker = function(entry)
          return {
            value = entry,
            display = highlight_favourite(entry),
            ordinal = entry,
          }
        end
      },
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        map('i', '<leader>f', toggle_favourite)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          G.selected = selection[1]
          opt_selected()
        end)
        return true
      end,
    }):find()
  end

  -- to execute the function
  find(require("telescope.themes").get_dropdown {})
  -- G.original_buf = vim.api.nvim_get_current_buf()
  -- G.base_win = vim.api.nvim_get_current_win()
  -- create_initial_float()
  -- set_options_in_win()
end

local function setup()
  vim.api.nvim_set_keymap('n', '<leader>a',
    "<cmd>lua require('tmx').tmx()<CR>",
    { noremap = true })

end

return {
  tmx = tmx,
  opt_selected = opt_selected,
  toggle_favourite = toggle_favourite,
  setup = setup,
}
