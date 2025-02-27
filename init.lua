local M = {}

-- the required plugins are stored here
M.plugins = {}

-- the plugins configurations set in visrc.lua
local plugins_conf = {}

-- the dir where we store plugins on disk
local plugins_path = nil

-- we store commands in an array of tables {name, func, desc}
local commands = {}

-- set custom path and add it first to package.path for require
M.set_path = function(path)
	plugins_path = path
	package.path = path .. '/?.lua;' .. path .. '/?/init.lua;' .. package.path
end

-- e.g. /Users/user/.cache/vis-plug
local get_default_cache_path = function()
	local HOME = os.getenv('HOME')
	local XDG_CACHE_HOME = os.getenv('XDG_CACHE_HOME')
	local CACHE_DIR = XDG_CACHE_HOME or (HOME .. '/.cache')
	return CACHE_DIR .. '/vis-plug'
end

-- set default install path for plugins
M.set_path(get_default_cache_path())

-- execute a command and return result string
local execute = function(command)
	local file = io.popen(command)
	local result = file:read("*a")
	result = result:gsub('(.-)%s*$', '%1') -- strip trailing spaces
	local success, message, code = file:close()
	return result, success, message, code
end

-- check if file exists
local file_exists = function (path)
	local file = io.open(path)
	if not file then return false end
	file:close()
	return true
end

-- use repo folder as plugin name
-- E.g. https://github.com/erf/{vis-highlight}.git -> vis-highlight
local get_name_from_url = function(url)
	return url:match('^.*/([^.]+)')
end

local get_folder = function(theme)
	if theme then
		return '/themes'
	else
		return '/plugins'
	end
end

-- E.g. '~/.cache/vis-plug/plugins/'
local get_base_path = function(theme)
	return plugins_path .. get_folder(theme)
end

-- '{http[s]://github.com}/erf/vis-cursors.git'
local is_github_url = function(url)
	return url:find('^http[s]?://github.com.+') ~= nil
end

-- return true if has the protocol part of the url
-- '{https://}github.com/erf/vis-cursors.git'
local is_host_url = function(url)
	return url:find('^.+://') ~= nil
end

-- return true if has the protocol part of the url
-- '{github.com/}erf/vis-cursors.git'
local is_no_host_url = function(url)
	return url:find('^%w+%.%w+[^/]') ~= nil
end

-- [user@]server:project.git
local is_short_ssh_url = function(url)
	return url:find('^.+@.+:.+')
end

-- remove protocol from url to make it shorter for output
local get_short_url = function(url)
	if is_github_url(url) then
		return url:match('^.+://.-/(.*)')
	elseif is_host_url(url) then
		return url:match('^.+://(.*)')
	elseif is_short_ssh_url(url) then
		return url -- TODO shorten?
	else
		return url
	end
end

-- given a github short hand url, return the full url
-- E.g. 'erf/vis-cursors' -> 'https://github.com/erf/vis-cursors.git'
local get_full_url = function(url)
	if is_host_url(url) then
		return url
	elseif is_no_host_url(url) then
		return 'https://' .. url
	elseif is_short_ssh_url(url) then
		return url
	else
		return 'https://github.com/' .. url
	end
end

-- find the plug in conf by name, used by plug-rm
local get_plug_by_name = function(name)
	if name == nil then
		return nil
	end
	for _, plug in ipairs(plugins_conf) do
		if plug.name == name then
			return plug
		end
	end
end

-- iterate the plugins conf and call an operation per plugin
local for_each_plugin = function (func, args)
	for _, plug in ipairs(plugins_conf) do
		func(plug, args)
	end
end

-- prepare the plug configuration
local plug_prepare = function(plug, args)
	plug.file = plug.file or 'init'
	plug.url  = get_full_url(plug.url)
 	plug.name = get_name_from_url(plug.url)
	plug.path = get_base_path(plug.theme) .. '/' .. plug.name
end

-- checkout specific branch or commit
local checkout = function(plug)
	if plug.commit then
		os.execute('git -C ' .. plug.path .. ' checkout --quiet ' .. plug.commit)
	elseif plug.branch then
		os.execute('git -C ' .. plug.path .. ' checkout --quiet ' .. plug.branch)
	else
		-- ELSE do nothing; there is no default "master" branch or "origin"
		-- for reference:
		-- git rev-parse --abbrev-ref HEAD
		-- git symbolic-ref refs/remotes/origin/HEAD --short
	end
end

local plug_require = function(plug, args)
	if not file_exists(plug.path) then
		return
	end
	if not plug.theme then
		local name = 'plugins/' .. plug.name .. '/' .. plug.file
		local plugin = require(name)
		if plug.alias then
			M.plugins[plug.alias] = plugin
		end
	end
end

local plug_outdated = function(plug, args)
	local short_url = get_short_url(plug.url)
	if not file_exists(plug.path) then
		vis:message(plug.name .. ' (' .. short_url .. ') is not installed')
		vis:redraw()
		return
	end
	local local_hash = execute('git -C ' .. plug.path .. ' rev-parse HEAD')
	local remote_hash = execute('git ls-remote ' .. plug.url .. ' HEAD | cut -f1')
	if local_hash == remote_hash then
		vis:message(plug.name .. ' (' .. short_url .. ') is up-to-date')
	else
		vis:message(plug.name .. ' (' .. short_url .. ') needs update')
	end
	vis:redraw()
end

local plug_list = function(plug, args)
	local short_url = get_short_url(plug.url)
	if file_exists(plug.path) then
		vis:message(plug.name .. ' (' .. short_url .. ')')
	else
		vis:message(plug.name .. ' (' .. short_url .. ') is not installed')
	end
	vis:redraw()
end

local install_plugins = function(silent)

	-- create folders
	os.execute('mkdir -p ' .. plugins_path .. '/plugins')
	os.execute('mkdir -p ' .. plugins_path .. '/themes')

	-- collect urls + paths
	local urls = ''
	local installed = 0
	for _, plug in ipairs(plugins_conf) do
		if not file_exists(plug.path) then
			urls = urls .. ' ' .. get_base_path(plug.theme)  .. ' ' .. plug.url
			installed = installed + 1
		end
	end

	-- git clone in parallel using xargs
	if urls ~= '' then
		if not silent then
			vis:info('installing..')
			vis:redraw()
		end
		os.execute('echo' .. urls .. ' | xargs -n2 -P0 sh -c \'git -C $0 clone $1 --quiet 2> /dev/null\'')
	end

	-- checkout git repo
	for_each_plugin(checkout)

	-- print result
	if urls ~= '' then
		vis:info('' .. installed .. ' plugins installed')
	elseif not silent then
		vis:info('nothing to install')
	end
end

local update_plugins = function()

	-- collect paths (if exists and has changed?)
	local paths = ''
	local updated = 0
	for _, plug in ipairs(plugins_conf) do
		if file_exists(plug.path) then
			updated = updated + 1
			paths = paths .. ' ' .. plug.path
		end
	end

	-- git pull in parallel using xargs
	if paths ~= '' then
		vis:info('updating..')
		vis:redraw()
		os.execute('echo' .. paths .. ' | xargs -n1 -P0 -I{} git -C {} pull --quiet 2> /dev/null')
	end

	-- checkout git repo
	for_each_plugin(checkout)

	-- print result
	if paths ~= '' then
		vis:info('' .. updated .. ' plugins updated')
	else
		vis:info('nothing to update')
	end
end

-- require plugins (and optionally install and checkout)
M.init = function(plugins, install_on_init)
	plugins_conf = plugins or {}
	for_each_plugin(plug_prepare)
	if install_on_init then
		install_plugins(true)
	end
	for_each_plugin(plug_require)
	return M
end

local command_install = function(argv, force, win, selection, range)
	install_plugins(false)
	return true
end

local command_rm = function(argv, force, win, selection, range)
	local name = argv[1]
	local plug = get_plug_by_name(name)
	if plug then
		if file_exists(plug.path) then
			os.execute('rm -rf ' .. plug.path)
			vis:info(plug.name .. ' (' .. plug.path .. ') deleted')
		else
			vis:info(plug.name .. ' is not installed')
		end
	else
		vis:info('did not find plugin \'' .. name .. '\'')
	end
	return true
end

local command_checkout = function(argv, force, win, selection, range)
	local name = argv[1]
	local branch_or_commit = argv[2]
	if name == nil or branch_or_commit == nil then
		vis:info('missing {name} or {branch|commit}')
		return
	end
	local plug = get_plug_by_name(name)
	if plug then
		plug.commit = branch_or_commit
		checkout(plug)
		vis:info('checked out \'' .. branch_or_commit .. '\'')
	else
		vis:info('did not find plugin \'' .. name .. '\'')
	end
	return true
end

local command_clean = function(argv, force, win, selection, range)
	local deleted = 0
	for _, plug in ipairs(plugins_conf) do
		if file_exists(plug.path) then
			os.execute('rm -rf ' .. plug.path)
			deleted = deleted + 1
		end
	end
	if deleted == 0 then
		vis:info('nothing to delete')
	else
		vis:info('' .. deleted .. ' packages deleted')
	end
	return true
end

local command_update = function(argv, force, win, selection, range)
	update_plugins()
	return true
end

-- look for vis-plug path in package.path because it is NOT necessarily in the
-- `plugins_path` but could rather have been required from some other path E.g.
-- the `visrc` config path
local look_for_vis_plug_path = function()
	local plug_path = package.searchpath('plugins/vis-plug', package.path)
	if plug_path ~= nil then
		return plug_path
	end
	return package.searchpath('vis-plug', package.path)
end

-- curl fetch vis-plug init.lua file
local fetch_latest_vis_plug = function(plug_path)
	local url = 'https://raw.githubusercontent.com/erf/vis-plug/master/init.lua'
	local command = 'curl -s -S -f -H  "Cache-Control: no-cache" ' .. url .. ' > ' .. plug_path
	return execute(command)
end

local command_upgrade = function(argv, force, win, selection, range)
	vis:info('upgrading..')
	vis:redraw()
	local plug_path = look_for_vis_plug_path()
	if plug_path == nil then
		vis:info('error: could not find vis-plug path')
		return
	end

	local result, success, message, code = fetch_latest_vis_plug(plug_path)
	if success then
		vis:info('upgrade OK - restart for latest vis-plug')
	else
		vis:info('upgrade failed with code: ' .. tostring(code))
	end
	return true
end

local command_ls = function(argv, force, win, selection, range)
	vis:message('plugins (' .. #plugins_conf .. ')')
	vis:redraw()
	for_each_plugin(plug_list)
	return true
end

local command_outdated = function(argv, force, win, selection, range)
	vis:message('up-to-date?')
	vis:redraw()
	for_each_plugin(plug_outdated)
	return true
end

local command_list_commands = function(argv, force, win, selection, range)
	local arr = {}
	table.insert(arr, 'vis-plug commands')
	for _, command in ipairs(commands) do
		table.insert(arr, ':' .. command.name .. ' - ' .. command.desc)
	end
	local str = table.concat(arr, '\n')
	vis:message(str)
	return true
end

commands = { {
		name = 'plug-list',
		desc = 'list plugins (in conf)',
		func = command_ls,
	}, {
		name = 'plug-install',
		desc = 'install plugins (clone)',
		func = command_install,
	}, {
		name = 'plug-update',
		desc = 'update plugins (pull)',
		func = command_update,
	}, {
		name = 'plug-outdated',
		desc = 'check if plugins are up-to-date',
		func = command_outdated,
	}, {
		name = 'plug-upgrade',
		desc = 'upgrade to latest vis-plug version',
		func = command_upgrade,
	}, {
		name = 'plug-remove',
		desc = 'delete plugin by {name} (:plug-ls for names)',
		func = command_rm,
	}, {
		name = 'plug-clean',
		desc = 'delete all plugins from disk (in conf)',
		func = command_clean,
	}, {
		name = 'plug-checkout',
		desc = 'checkout {name} {branch|commit}',
		func = command_checkout,
	}, {
		name = 'plug-commands',
		desc = 'list commands (these)',
		func = command_list_commands,
	},
}

-- initialize commands
for _, command in ipairs(commands) do
	vis:command_register(command.name, command.func, command.desc)
end

return M
