local Job = require'plenary.job'
local Popup = require'plenary.popup'

local Win_id
local fumbbl = {}

local dev_root = "S:"

local function close_menu()
    vim.api.nvim_win_close(Win_id, true)
end

function string.starts(String,Start)
   return string.sub(String,1,string.len(Start))==Start
end


local function execute_command(command, result_callback)
    Job:new({
        command = 'cmd',
        args = { '/C',command },
        cwd = vim.fn.getcwd(),
        env = { },
        borderchars = { " " },
        on_exit = function(j, return_val)
            local result = j:result()

            vim.schedule(function()
                result_callback(result)
            end)

            vim.schedule(result_callback)
        end,
    }):sync()
end

local function ignore_response(response)
    return
end

local function display_response(response)
    if response == nil then
        return
    end

    Win_id = Popup.create(response, {})
    local bufnr = vim.api.nvim_win_get_buf(Win_id)
    local closeCmd = function() close_menu() end
    vim.keymap.set("n", "q", closeCmd, { buffer=bufnr, silent=false })
    vim.keymap.set("n", "<escape>", closeCmd, { buffer=bufnr, silent=false })
    vim.keymap.set("n", "<enter>", closeCmd, { buffer=bufnr, silent=false })
    vim.keymap.set("i", "q", closeCmd, { buffer=bufnr, silent=false })
    vim.keymap.set("i", "<escape>", closeCmd, { buffer=bufnr, silent=false })
    vim.keymap.set("i", "<enter>", closeCmd, { buffer=bufnr, silent=false })
end

local function copyfile(src, dst)
    local cmd = "copy /Y " .. src:gsub("/", "\\") .. " " .. dst:gsub("/", "\\")

    print ("Executing command: " .. cmd)

    execute_command(cmd, ignore_response)
end


local function deploy(relative_path)
    local project_path = vim.fn.getcwd()
    local deploy_path = dev_root

    copyfile(vim.fs.joinpath(project_path, relative_path), vim.fs.joinpath(deploy_path, relative_path))
end

local function gulp(type, file_path)
    local cmd = "node node_modules/gulp/bin/gulp.js " .. type .. " --file=" .. file_path

    execute_command(cmd, display_response)

end

local function handle_ts(file)
    print("Handle TS")

    -- Todo.. This is a bit of a pain, and more or less deprecated anyway..
end

local function handle_js(file)
    gulp("js", file.relative_path)

    deploy(file.relative_path)
    deploy(vim.fs.joinpath(file.folder, "min", file.basefilename .. "-min.js"))
    deploy("rev-manifest.json")
end

local function handle_less(file)
    gulp("less", file.relative_path)

    local css_folder = vim.fs.dirname(file.folder)
    local css_file_name = file.basefilename .. ".css"
    local relative_css_path = vim.fs.normalize(vim.fs.joinpath(css_folder, css_file_name))

    deploy(relative_css_path)
    deploy("rev-manifest.json")
end

local function handle_default(file)
    deploy(file.relative_path)
end

function fumbbl.build()
    local project_path = vim.fs.normalize(vim.fn.getcwd())
    local relative_file_path = vim.fs.normalize(vim.fn.expand("%"))
    local relative_file_folder = vim.fs.dirname(relative_file_path)
    local absolute_file_path = vim.fs.normalize(vim.fs.abspath(relative_file_path))
    local file_name_without_extension = vim.fs.basename(vim.fn.expand("%:r"))
    local file_extension = vim.bo.filetype

    -- Ignore files outside of project path
    if not string.starts(absolute_file_path, project_path) then
        print("File is not part of project")
        return
    end

    vim.cmd('write')

    local file = {
        folder = relative_file_folder,
        basefilename = file_name_without_extension,
        extension = file_extension,
        relative_path = relative_file_path
    }

    if file_extension == "ts" then handle_ts(file)
    elseif file_extension == "js" then handle_js(file)
    elseif file_extension == "less" then handle_less(file)
    elseif file_extension == "vue" then handle_ts(file)
    else handle_default(file)
    end

    --vim.api.nvim_command('write')
    --execute_command("dir", display_response)
end

vim.keymap.set("n", "<C-b>", function() require'fumbbl'.build() end)
vim.keymap.set("i", "<C-b>", function() require'fumbbl'.build() end)

return fumbbl

