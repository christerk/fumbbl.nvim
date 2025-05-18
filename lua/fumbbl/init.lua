local Job = require("plenary.job")
local Popup = require("plenary.popup")

local Win_id
local fumbbl = {}

local dev_root = "S:"

local start_time

local function close_menu()
	vim.api.nvim_win_close(Win_id, true)
end

function string.starts(String, Start)
	return string.sub(String, 1, string.len(Start)) == Start
end

local function node()
	return "node"
end

local function display_time(prefix)
	local elapsed_time = os.clock() - start_time
	print(prefix .. ". Elapsed: " .. string.format("%.2f", elapsed_time) .. " seconds.")
end

local function execute_command(command, result_callback, ...)
	local callback_args = ...

	local job = Job:new({
		command = "cmd",
		args = { "/C", command },
		cwd = vim.fn.getcwd(),
		env = {},
		borderchars = { " " },
		on_exit = function(j, return_val)
			local result = j:result()

			vim.schedule(function()
				result_callback(result, callback_args)
			end)
		end,
	})

	return job:sync()
end

local function ignore_response(response) end

local function display_response(response)
	if response == nil or #response == 0 then
		return
	end

	Win_id = Popup.create(response, {})
	local bufnr = vim.api.nvim_win_get_buf(Win_id)
	local closeCmd = function()
		close_menu()
	end
	vim.keymap.set({ "n", "i" }, "q", closeCmd, { buffer = bufnr, silent = false })
	vim.keymap.set({ "n", "i" }, "<escape>", closeCmd, { buffer = bufnr, silent = false })
	vim.keymap.set({ "n", "i" }, "<enter>", closeCmd, { buffer = bufnr, silent = false })
end

local function copyfile(src, dst)
	local cmd = "copy /Y " .. src:gsub("/", "\\") .. " " .. dst:gsub("/", "\\")

	execute_command(cmd, ignore_response)
end

local function deploy(relative_path)
	local project_path = vim.fn.getcwd()
	local deploy_path = dev_root

	print("Deploying: " .. relative_path)
	copyfile(vim.fs.joinpath(project_path, relative_path), vim.fs.joinpath(deploy_path, relative_path))
end

local function sync_manifest(response)
	deploy("rev-manifest.json")
	display_time("Manifest updated")
end

local function gulp(type, file_path)
	local cmd = node() .. " node_modules/gulp/bin/gulp.js " .. type .. " --file=" .. file_path

	print("Gulp command: " .. cmd)
	execute_command(cmd, sync_manifest)
end

local function is_ts_app(file)
	return file.folder == "src/pages"
end

local function include_as_dep(name, key)
	if string.starts(name, "./node_modules") then
		return false
	end
	if not string.starts(name, "./") then
		return false
	end

	if string.find(name, ".vue?vue", 1, true) then
		return false
	end

	if name == "./" .. key then
		return false
	end

	return true
end

local function update_deps(file, data)
	local deps = {}
	local key = file.relative_path

	for i, module in pairs(data["modules"]) do
		if module["modules"] then
			for j, inner_module in pairs(module["modules"]) do
				local name = inner_module["name"]
				if include_as_dep(name, key) then
					deps[#deps + 1] = string.sub(name, 3)
				end
			end
		else
			if include_as_dep(module["name"], key) then
				deps[#deps + 1] = string.sub(module["name"], 3)
			end
		end
	end

	local f = io.open("ts-deps.json", "r")
	local ts_deps = vim.json.decode(f:read("*a"))
	f:close()

	ts_deps[key] = deps

	local updated_deps = vim.json.encode(ts_deps)

	local wf = io.open("ts-deps.json", "w")
	wf:write(updated_deps)
	wf:close()
end

local function display_webpack_results(data)
	if #data["errors"] > 0 then
		local errors = {}

		local function log(str)
			errors[#errors + 1] = str
		end

		for k, err in pairs(#data["errors"]) do
			log("---------------")
			if err["file"] then
				log("-- File: " .. err["file"])
			end
			if err["message"] then
				log("-- Message --")
				log(err["message"])
			end
			if err["loc"] then
				log("-- Loc " .. error["loc"])
			end
			if err["stack"] then
				log("-- Stack --")
				log(err["stack"])
			end
			if err["details"] then
				log("-- Details --")
				log(err["details"])
			end
		end

		display_response(errors)
	end

	if #data["warnings"] > 0 then
		display_response(data["warnings"])
	end
end

local function handle_webpack_response(response, file)
	local json_string = table.concat(response, " ")

	local data = vim.json.decode(json_string)
	display_webpack_results(data)

	if is_ts_app(file) then
		update_deps(file, data)
	end

	local js_file = vim.fs.joinpath("dist", file.basefilename .. ".js")
	gulp("tsjs", js_file)
	deploy(js_file)

	display_time("Webpack complete")
end

local function webpack(file)
	local src = vim.fs.joinpath(file.folder, file.basefilename)
	local dst = file.basefilename .. ".js"

	local cmd = node()
		.. " node_modules/webpack/bin/webpack.js --json --entry ./"
		.. src
		.. " --output-path .\\dist --output-filename "
		.. dst
	print("Webpack command: " .. cmd)

	execute_command(cmd, handle_webpack_response, file)
end

local function get_ts_roots(file)
	local f = io.open("ts-deps.json", "r")
	local ts_deps = vim.json.decode(f:read("*a"))
	f:close()

	roots = {}
	for root, deps in pairs(ts_deps) do
		for _, v in pairs(deps) do
			if v == file.relative_path then
				roots[#roots + 1] = root
				break
			end
		end
	end

	return roots
end

local function file_from_path(path)
	local relative_file_folder = vim.fs.dirname(path)
	local file_name = string.sub(path, #relative_file_folder + 2)
	local file_name_without_extension = vim.fs.basename(file_name)
	local file_extension = string.sub(file_name, #file_name_without_extension + 1)

	local folder, base, ext = string.match(path, "(.*)/([^/]+)[.]([^.]*)$")

	local file = {
		folder = folder,
		basefilename = base,
		extension = ext,
		relative_path = path,
	}

	return file
end

local function handle_ts(file)
	if is_ts_app(file) then
		webpack(file)
	else
		local roots = get_ts_roots(file)
		for k, root in pairs(roots) do
			local root_file = file_from_path(root)
			print("Processing root: " .. root_file.relative_path)
			webpack(file_from_path(root))
		end
	end
end

local function handle_js(file)
	gulp("js", file.relative_path)

	deploy(file.relative_path)
	deploy(vim.fs.joinpath(file.folder, "min", file.basefilename .. "-min.js"))
end

local function handle_less(file)
	gulp("less", file.relative_path)

	local css_folder = vim.fs.dirname(file.folder)
	local css_file_name = file.basefilename .. ".css"
	local relative_css_path = vim.fs.normalize(vim.fs.joinpath(css_folder, css_file_name))

	deploy(relative_css_path)
end

local function handle_default(file)
	deploy(file.relative_path)
end

function fumbbl.build()
	start_time = os.clock()

	local project_path = vim.fs.normalize(vim.fn.getcwd())
	local relative_file_path = vim.fs.normalize(vim.fn.expand("%"))
	local relative_file_folder = vim.fs.dirname(relative_file_path)
	local absolute_file_path = vim.fs.normalize(vim.fs.abspath(relative_file_path))
	local file_name_without_extension = vim.fs.basename(vim.fn.expand("%:r"))
	local file_extension = vim.fn.expand("%:e")

	print(relative_file_path)
	-- Ignore files outside of project path
	if not string.starts(absolute_file_path, project_path) then
		print("File is not part of project")
		return
	end

	vim.cmd("write")

	local file = {
		folder = relative_file_folder,
		basefilename = file_name_without_extension,
		extension = file_extension,
		relative_path = relative_file_path,
	}

	if file_extension == "ts" then
		handle_ts(file)
	elseif file_extension == "js" then
		handle_js(file)
	elseif file_extension == "less" then
		handle_less(file)
	elseif file_extension == "vue" then
		handle_ts(file)
	else
		handle_default(file)
	end

	display_time("Build complete")
end

function fumbbl.deployDev()
	local cmd = node() .. "\\node node_modules\\vite\\bin\\vite build --outDir ../dist --mode dev"
	execute_command(cmd, display_response)
end

function fumbbl.deployLive()
	local cmd = vim.fn.exepath("node") .. "\\node node_modules\\vite\\bin\\vite build --outDir ../distlive --mode live"
	execute_command(cmd, display_response)
end

return fumbbl
