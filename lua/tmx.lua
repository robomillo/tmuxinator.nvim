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
  G.selected = selection.value
  G:toggle_favourite(G.selected)
  get_and_set_sorted_options()
end

local function highlight_favourite(entry)

  return entry
end

local function contains(t, value)
  for _, v in ipairs(t) do
    if value == v then
      return true
    end
  end
  return false
end

local function tmx()
  get_and_insert_new()
  get_and_set_sorted_options()
  vim.api.nvim_set_hl(0, "Fav", { underline = true, fg = "#e0af68" })

  local find = function(opts)
    opts = opts or {}
    pickers.new(opts, {
      prompt_title = "tmx",
      finder = finders.new_table {
        results = opt_map,
        entry_maker = function(entry)
          return {
            value = entry,
            display = function(ent)
              if contains(favourites, ent.value) then
                return "* " .. ent.value .. " *", { { { 0, 100 }, "Fav" } }
              else
                return ent.value
              end
            end,
            ordinal = entry
          }
        end
      },
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        map('i', '<leader>f', toggle_favourite)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          G.selected = selection.value
          opt_selected()
        end)
        return true
      end,
    }):find()
  end

  find(require("telescope.themes").get_dropdown {})

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
