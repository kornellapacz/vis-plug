local M = {}

-- the plugins configurations set in visrc.lua
local conf = {}

-- the required plugins are stored here
M.plugins = {}

-- E.g. '~/.config/vis/plugins'
local get_default_plugins_path = function()
	local visrc, err = package.searchpath('visrc', package.path)
	if err then return nil end
	local visrc_path = visrc:match('(.*/)')
	return visrc_path ..'plugins'
end

-- the path where we store plugins on disk
local plugin_path = nil

-- set custom path
M.set_path = function(path)
	plugin_path = path
	package.path = package.path .. ';' .. path .. '/?.lua'
	package.path = package.path .. ';' .. path .. '/?/init.lua'
end

-- set default path
M.set_path(get_default_plugins_path())

-- table used by the :plug-commands command
local commands = {
	[':plug-ls'] = 'list plugins',
	[':plug-install'] = 'install plugins in conf (using git clone)',
	[':plug-update'] = 'update plugins in conf (using git pull)',
	[':plug-rm {name}'] = 'remove plugin by name (see plug-list for name)',
	[':plug-clean'] = 'delete all plugins in conf',
	[':plug-outdated'] = 'check if repos are up-to-date',
	[':plug-commands'] = 'list commands (this!)',
}

-- concat a table to a string, effectivly
local concat = function(iterable, func)
	local arr = {}
	for key, val in pairs(iterable) do
		table.insert(arr, func(key, val))
	end
	return table.concat(arr, '\n')
end

-- execute a command and return result string
local execute = function(command)
	local handle = io.popen(command)
	local result = handle:read("*a")
	handle:close()
	return result
end

-- check if file exists
local file_exists = function (path)
	local file = io.open(path)
	if not file then return false end
	file:close()
	return true
end

-- get folder name, used as name for plugin
-- E.g. https://github.com/erf/{vis-highlight}.git -> vis-highlight
local get_name_from_url = function(url)
	return string.match(url, '^.*/([^$.]+)')
end

-- E.g. '~/.config/vis/plugins/vis-highlight'
local get_plugin_path = function(name)
	return plugin_path .. '/' .. name
end

-- remove protocol from url to make it shorter for output
local get_short_url = function(url)
	return url:match('^.+://(.*)')
end

-- return true if has the protocol part of the url
-- '{https://}github.com/erf/vis-cursors.git'
local is_full_url = function(url)
	return url:find('^.+://') ~= nil
end

-- given a github short hand url, return the full url
-- E.g. 'erf/vis-cursors' -> 'https://github.com/erf/vis-cursors.git'
local get_full_url = function(url)
	if is_full_url(url) then
		return url
	end
	return string.gsub(url, '.+', 'https://github.com/%1')
end

-- iterate the plugins conf and call an operation per plugin
local for_each_plugin = function (op, args)
	for url, val in pairs(conf) do
		local file, alias, branch, commit
		if type(val) == 'table' then
			file   = val['file']   or val[1]
			alias  = val['alias']  or val[2]
			branch = val['branch'] or val[3]
			commit = val['commit'] or val[4]
		else
			file   = val
		end
		local full_url = get_full_url(url)
 		local name = get_name_from_url(url)
		if name then
			local path = get_plugin_path(name)
			op(full_url, name, path, file, alias, branch, commit, args)
		end
	end
end

local checkout = function(path, branch, commit)
	if commit then
		os.execute('git -C ' .. path .. ' checkout --quiet ' .. commit)
	elseif branch then
		os.execute('git -C ' .. path .. ' checkout --quiet ' .. branch)
	else
		os.execute('git -C ' .. path .. ' checkout --quiet master')
	end
end

local plug_install = function(url, name, path, file, alias, branch, commit, args)
	local short_url = get_short_url(url)
	local silent = args
	if file_exists(path) then
		checkout(path, branch, commit)
		if not silent then
			vis:message(name .. ' (' .. short_url .. ') already installed')
		end
	else
		local cmd = 'git -C ' .. plugin_path .. ' clone ' .. url .. ' --quiet 2> /dev/null'
		os.execute(cmd)
		checkout(path, branch, commit)
		if not silent then
			vis:message(name .. ' (' .. short_url .. ') installed')
		end
	end
	vis:redraw()
end

local plug_update = function(url, name, path, file, alias, branch, commit, args)
	if file_exists(path) then
		checkout(path, branch, commit)
		local local_hash = execute('git -C ' .. path .. ' rev-parse HEAD')
		local remote_hash = execute('git ls-remote ' .. url .. ' HEAD | cut -f1')
		if local_hash ~= remote_hash then
			os.execute('git -C ' .. path .. ' pull')
			vis:message(name .. ' UPDATED')
		else
			vis:message(name .. ' is up-to-date')
		end
	else
		vis:message(name .. ' is NOT installed')
	end
	vis:redraw()
end

local plug_require = function(url, name, path, file, alias, branch, commit, args)
	if not file_exists(path) then
		return
	end
	local plugin = require(name .. '/' .. file)
	if alias then
		M.plugins[alias] = plugin
	end
end

local plug_count = function()
	local count = 0
	for _ in pairs(conf) do
		count = count + 1
	end
	return count
end

local plug_diff = function(url, name, path, file, alias, branch, commit, args)
	local short_url = get_short_url(url)
	if not file_exists(path) then
		vis:message(name .. ' (' .. short_url .. ') is NOT installed')
		vis:redraw()
		return
	end
	local local_hash = execute('git -C ' .. path .. ' rev-parse HEAD')
	local remote_hash = execute('git ls-remote ' .. url .. ' HEAD | cut -f1')
	if local_hash == remote_hash then
		vis:message(name .. ' (' .. short_url .. ') is up-to-date')
	else
		vis:message(name .. ' (' .. short_url .. ') needs UPDATE')
	end
	vis:redraw()
end

local plug_list = function(url, name, path, file, alias, branch, commit, args)
	local short_url = get_short_url(url)
	if file_exists(path) then
		vis:message(name .. ' (' .. short_url .. ')')
	else
		vis:message(name .. ' (' .. short_url .. ') is NOT installed')
	end
	vis:redraw()
end

local install_plugins = function(silent)
	if not file_exists(plugin_path) then
		os.execute('mkdir -p ' .. plugin_path)
	end
	for_each_plugin(plug_install, silent)
end

local plug_delete = function(url, name, path, file)
	if file_exists(path) then
		os.execute('rm -rf ' .. path)
		vis:message(name .. ' (' .. path .. ') deleted')
	else
		vis:message(name .. ' (' .. path .. ') is not there')
	end
end

vis:command_register('plug-install', function(argv, force, win, selection, range)
	vis:message('installing..')
	vis:redraw()
	install_plugins(false)
	vis:redraw()
	return true
end)

vis:command_register('plug-rm', function(argv, force, win, selection, range)
	local name = argv[1]
	if name then
		vis:message('deleting ' .. name)
		plug_delete(nil, name, get_plugin_path(name))
	else
		vis:message('Error: missing name')
	end
	vis:redraw()
	return true
end)

vis:command_register('plug-clean', function(argv, force, win, selection, range)
	vis:message('cleaning..')
	vis:redraw()
	for_each_plugin(plug_delete)
	vis:redraw()
	return true
end)

vis:command_register('plug-update', function(argv, force, win, selection, range)
	vis:message('updating..')
	vis:redraw()
	for_each_plugin(plug_update)
	vis:redraw()
	return true
end)

vis:command_register('plug-ls', function(argv, force, win, selection, range)
	vis:message('plugins (' .. plug_count() .. ')')
	vis:redraw()
	for_each_plugin(plug_list)
	vis:redraw()
	return true
end)

vis:command_register('plug-outdated', function(argv, force, win, selection, range)
	vis:message('checking if up-to-date..')
	vis:redraw()
	for_each_plugin(plug_diff)
	vis:redraw()
	return true
end)

vis:command_register('plug-commands', function(argv, force, win, selection, range)
	vis:message('vis-plug commands')
	vis:redraw()
	local str = concat(commands, function(command, desc)
		return command .. ' - ' .. desc
	end)
	vis:message(str)
	vis:redraw()
	return true
end)

-- install, checkout and require plugins
M.init = function(plugins, install_on_init)
	conf = plugins or {}
	if install_on_init then
		install_plugins(true)
	end
	for_each_plugin(plug_require)
	return M
end

return M