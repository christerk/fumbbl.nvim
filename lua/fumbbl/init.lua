
local Job = require'plenary.job'
local Popup = require'plenary.popup'

local Win_id
local fumbbl = {}

function fumbbl.build()
    Job:new({
        command = 'cmd',
        args = { '/C','dir' },
        cwd = vim.fn.getcwd(),
        env = { },
        borderchars = { " " },
        on_exit = function(j, return_val)
            local result = j:result()

            vim.schedule(function()
                vim.api.nvim_command('write')
                Win_id = Popup.create(result, {})
                local bufnr = vim.api.nvim_win_get_buf(Win_id)
                local closeCmd = "<cmd>lua CloseMenu()<CR>"
                vim.api.nvim_buf_set_keymap(bufnr, "n", "q", closeCmd, { silent=false })
                vim.api.nvim_buf_set_keymap(bufnr, "n", "<Escape>", closeCmd, { silent=false })
                vim.api.nvim_buf_set_keymap(bufnr, "n", "<Enter>", closeCmd, { silent=false })
                vim.api.nvim_buf_set_keymap(bufnr, "i", "q", closeCmd, { silent=false })
                vim.api.nvim_buf_set_keymap(bufnr, "i", "<Escape>", closeCmd, { silent=false })
                vim.api.nvim_buf_set_keymap(bufnr, "i", "<Enter>", closeCmd, { silent=false })
            end)
        end,
    }):sync() -- sync() or start
end

local function CloseMenu()
    vim.api.nvim_win_close(Win_id, true)
end

vim.keymap.set("n", "<C-b>", function() require'fumbbl'.build() end)
vim.keymap.set("i", "<C-b>", function() require'fumbbl'.build() end)

return fumbbl

