#!/usr/bin/env luajit

local ffi = require("ffi")
ffi.cdef[[
int access(const char *pathname, int mode);
]]

--{{{ DEFAULT CONFIG
-- Some sensible default config, color scheme is solarized light
CONF = {
	verbose = true,
	sorting = "last_modified",
	max_posts_on_index = 10,
	fg_color     = "#657b83",	--> base00 (regular)
	fg_color_hi  = "#586e75",	--> base01 (emphasized)
	fg_color_sec = "#93a1a1",	--> base1 (secondary)
	bg_color     = "#fdf6e3",	--> base3
	bg_color_alt = "#eee8d5",	--> base2
	link_color   = "#859900",	--> green
	link_color2  = "#d33682",	--> magenta
	link_color3  = "#6c71c4",	--> violet
	h1_color     = "#2aa198",	--> cyan
	h2_color     = "#2aa198",	--> cyan
	h3_color     = "#586e75",	--> base01 (emphasized)
	padding = { top="20px", right="20%", bottom="40px", left="20%" },
	blog_title = "default lenie blog-title",
	clean_html = false,
}


--[[ Global state table, all fields are false until initialized.
STATE = {
	www_path = false,
	repo_path = false,
}
--]]
--}}}


--{{{ UTIL FUNCTIONS
-- Replacement for dofile that respects the environment of the caller function rather than
-- executing in the global environment. It will read and execute a lua file in the environment
-- of the parent function.
-- Here this is used to first set the environment of the function "read_rc()" to the global
-- table "CONF" and then call importfile() with the path to the rc.lua. importfile() will read
-- all the variables defined in that rc.lua and store them in the environment of it's parent
-- function, which has previously been set to the table CONF. This effectively populates or
-- overwrites entries in CONF with values defined in rc.lua.
function importfile(fname)
	local f,e = loadfile(fname)
	if not f then error(e, 2) end
	setfenv(f, getfenv(2))
	return f()
end


-- Check file or directory permission using standard C-lib function ACCESS(2) via LuaJITs ffi
-- library. Returns 0 when file exists or permission is granted, -1 otherwise.
function access(fname, mode)
	assert(fname and type(fname) == "string")
	if not mode then mode = 0			-- test for existence
	elseif mode == "r" then mode = 4		-- test for read permission
	elseif mode == "w" then mode = 2		-- test for write permission
	elseif mode == "x" then mode = 1		-- test for execute permission
	end

	return ffi.C.access(fname, mode)
end


function file_exists(fname) if access(fname) == 0 then return true else return false end end
function installed(pname)
	local path = os.getenv("PATH")
	for dir in string.gmatch(path, "[^:]+") do
		local fpath = string.format("%s/%s", dir, pname)
		if access(fpath) == 0 then return true end
	end
	return false
end


-- Get sha1 of most recent commit from the blogs git repository
function get_revision()
	local fd = io.popen("git log -1 | grep commit | awk '{ print $2 }'")
	local rev = fd:read("*a")
	fd:close()
	return rev
end


-- In the src directory there is a file "rev" that stores the sha1 of the commit associated with
-- the current state of the blog. Note that this is not necessarily the commit that is checked
-- out in the src directory; it refers to the generated HTML files and indicates whether the
-- blog - as seen by the web server - is out of sync with the blogs repository.
-- This function does the comparison and returns true if the blog is in sync with the repo.
function up_to_date(srcdir)
	local fd = io.open(srcdir.."/rev", 'r')
	if fd then
		local checked_out = fd:read("*l")
		fd:close()
		if get_revision() == checked_out then return true end
	end
	return false
end


-- Read the runtime config and return a table with the configuration state. If there is no rc
-- file, return default values. This function is sandboxed in its own environment for security
-- reasons and it expects the table for that environment as second argument. The runtime config
-- will be stored in that table.
function read_rc(srcdir, rc)
	-- Setting up the environment of the sandbox
	local print, sprintf = print, string.format
	local file_exists, importfile = file_exists, importfile
	setfenv(1, rc)

	local fname = srcdir.."/rc.lua"
	if file_exists(fname) then importfile(fname)
	else print( sprintf("WARNING: No rc.lua in %q, using default config", srcdir) )
	end
end
--}}}


--{{{ PATH 1: GENERATING STATIC HTML
-- Create table with files that need to be generated, sorted by date of modification
function get_metainfo(fname)
	local info = {}
	-- Query the git repository for information on the first version of this file
	local fd = io.popen(string.format('git log --pretty="format:%%ct%%n%%cD%%n%%an" -- %q|tail -3', fname))
	info.T = fd:read('*l'):match('%d+')
	info.date = fd:read('*l'):match('[^%+]+')
	info.author = fd:read('*l')
	-- Query the git repository for information on the newest version of this file
	fd = io.popen(string.format('git log -1 --pretty="format:%%ct%%n%%cD%%n%%an" -- %q', fname))
	info.t = fd:read('*l'):match('%d+')
	info.update = fd:read('*l'):match('[^%+]+')
	info.editor = fd:read('*l')
	info.fname = fname
	info.title = string.match(fname, '(.+)%.md$')
	fd:close()
	return info
end


function gather_mdfiles(srcdir)
	if CONF.verbose then print("Sourcing markdown files from "..srcdir) end
	local mdfiles = {}
	for fname in io.popen('ls -t "' .. srcdir .. '"'):lines() do
		local mdfile = fname:match('^.+%.md$')
		if mdfile and mdfile ~= "preamble.md" then
			mdfiles[#mdfiles+1] = get_metainfo(mdfile)
		end
	end
	-- Sort mdfiles based on the unix timestamp of the commit in descending order (newest first)
	local sortfunctions = {
		last_modified = function(a,b) return a.t > b.t end,
		first_modified = function(a,b) return a.t < b.t end,
		last_published = function(a,b) return a.T > b.T end,
		first_published = function(a,b) return a.T < b.T end,
	}
	table.sort(mdfiles, sortfunctions[CONF.sorting])
	return mdfiles
end


function gen_html(src, mdfiles, rc)
	assert(type(src) == "string", "first argument needs to be a string describing the path to the source directory")
	assert(type(mdfiles) == "table", "second argument needs to be an array containing markdown files as strings")

	-- Convert markdown files to HTML and store each one as string in an array
	local posts, names = {}, {}
	for ix,post in ipairs(mdfiles) do
		local t = {}
		t[#t+1] = '<div id="postinfo">'
		local nr = ix
		if string.find(rc.sorting, "last_") then nr = (#mdfiles-ix)+1 end
		local s1 = string.format('#%d <a href="%s.html">%s</a> by %s', nr, post.title, post.title, post.author)
		local update = ""
		if post.t ~= post.T then update = string.format(" (updated %s)", post.update) end
		local s2 = string.format('<span id="secondary">on %s%s</span>', post.date, update)
		t[#t+1] = string.format('%s %s', s1, s2)
		t[#t+1] = '</div><div id="post">'
		t[#t+1] = io.popen(string.format('markdown --html4tags "%s/%s"', src, post.fname)):read('*a')
		posts[ix] = table.concat(t)
		names[ix] = post.title
	end
	local num_posts = #posts

	-- Generate the HTML for the preamble text, if there is a markdown file for it.
	local preamble = false
	if file_exists(src.."/preamble.md") then
		preamble = io.popen(string.format('markdown --html4tags "%s/preamble.md"', src)):read('*a')
	end

	-- Additionally, add an entry for a page with a listing of all posts and links to them. This
	-- includes posts that are contained on index.html and those that are not.
	do
		local listing = {}
		for ix,name in ipairs(names) do
			listing[#listing+1] = string.format('#%d\t<a href="%s.html">%s</a>', ix, name, name)
		end
		posts[#posts+1] = table.concat(listing, "<br />\n")
		names[#names+1] = "listing"
	end

	-- Additionally, add one entry for the index page, containing as many posts as specified in
	-- the configuration for "max_posts_on_index". A setting of 0 is valid and negative values
	-- disable the limit
	do
		local i = rc.max_posts_on_index		-- nr of posts included on index.html
		if i < 0 or i > num_posts then i = num_posts end
		posts[#posts+1] = table.concat(posts, "</div><br /><br />", 1, i)
		names[#names+1] = "index"
	end

	-- Now generate HTML pages with head, boody and footer for each entry in the above table
	-- Now surround the generated HTML with a proper head, body and footer and store the results
	-- in a table whose key-value pairs describe the file name (sans suffix) and corresponding
	-- content for the actualy HTML pages to be written.
	local pages = {}
	for i=1,#posts do
		local html = {}
		-- Header
		html[#html+1] = '<!DOCTYPE html><html><link href="style.css" rel="stylesheet">'
		html[#html+1] = string.format('<head><title>%s - %s</title></head>', rc.blog_title, names[i])
		html[#html+1] = '<body>'
		html[#html+1] = '<div id="preamble">'
		html[#html+1] = preamble or "<h1>create preamble.md to replace this default header</h>"
		html[#html+1] = '<hr></div>'
		-- Post
		html[#html+1] = posts[i]
		-- Footer
		html[#html+1] = '</body></html>'
		pages[names[i]] = table.concat(html)
	end

	return pages
end


function gen_css(rc)
	local css = {}
	local pad = rc.padding
	css[#css+1] = string.format("body {color:%s; background-color:%s; padding:%s %s %s %s;}",
							rc.fg_color, rc.bg_color, pad.top, pad.right, pad.bottom, pad.left)
	css[#css+1] = string.format("a:link {color:%s;}", rc.link_color)
	css[#css+1] = string.format("a:hover {color:%s; text-decoration:underline;}", rc.link_color2)
	css[#css+1] = string.format("a:active {color:%s;}", rc.link_color2)
	css[#css+1] = string.format("a:visited {color:%s;}", rc.link_color3)
	css[#css+1] = string.format("h1 {color:%s;}", rc.h1_color)
	css[#css+1] = string.format("h2 {color:%s;}", rc.h2_color)
	css[#css+1] = string.format("h3 {color:%s;}", rc.h3_color)
	css[#css+1] = string.format("hr {color:%s;}", rc.bg_color_alt)

	css[#css+1] = "#preamble {padding: 0 0 25px 0;}"
	css[#css+1] = "#post {padding: 0 0 0 0;}"
	css[#css+1] = string.format('#primary {color:%s;}', rc.fg_color_hi)
	css[#css+1] = string.format('#secondary {color:%s;}', rc.fg_color_sec)

	css[#css+1] = "#postinfo {"
	css[#css+1] = string.format("\tcolor:%s; background-color:%s; font-size:%dpx;",
								rc.fg_color_hi, rc.bg_color_alt, 15)
	css[#css+1] = "\tpadding:2px 4px 2px 4px;"
	css[#css+1] = "}"

	return table.concat(css, "\n")
end


-- Read all files in the specified source directory "src" and generate HTML code to be stored in
-- destination directory "dst"
function generate(src, dst)
	assert(access(src, "w") == 0, "insufficient permissions in repo directory")
	assert(access(dst, "w") == 0, "insufficient permissions in www directory")
	if up_to_date(src) then return "Blog already up to date" end

	local mdfiles = gather_mdfiles(src)
	--local index_html = gen_html(src, mdfiles, CONF)
	local html_pages = gen_html(src, mdfiles, CONF)
	local style_css = gen_css(CONF)

	-- Write HTML files
	for fname,page in pairs(html_pages) do
		local path = string.format("%s/%s.html", dst, fname)
		local fd = io.open(path, 'w')
		if fd then
			if CONF.verbose then print(string.format("Writing HTML to %s", path)) end
			fd:write(page)
			fd:close()
		end
	end

	-- Write CSS file
	do
		local fname = dst.."/style.css"
		if CONF.verbose then print(string.format("Writing CSS to %s", fname)) end
		local fd = io.open(fname, 'w')
		if fd then
			fd:write(style_css)
			fd:close()
		end
	end

	-- Update rev file to most recent commit hash
	do
		local fd = io.open(src.."/rev", 'w+')
		fd:write( get_revision() )
		fd:close()
	end

	return "Blog updated!"
end
--}}}


--{{{ PATH 2: INITIAL SETUP
-- Initialize the git repository for the server and configure it.
function init( repo_path, www_path )
	assert(access(repo_path) ~= 0, string.format("%s already exists", repo_path))
	local updir = string.match(repo_path, "(.*)/[^/]+")
	assert(access(updir, "w") == 0, string.format("insufficient permissions in %s", updir))
	assert(access(www_path, "w") == 0, "insufficient permissions in www directory")
	-- Create directory repo_path, repo_path/src
	assert( os.execute("mkdir " .. repo_path) == 0 )
	assert( os.execute("mkdir " .. string.format("%s/src", repo_path)) == 0 )
	-- Create bare repository in repo_path/git
	assert( os.execute(string.format("git init --bare --shared %s/git", repo_path)) == 0 )

	local lenie_path = "/usr/local/bin/lenie.lua"	-- TODO(beta) besser solution for this
	local h = {}
	h[#h+1] = "#!/usr/bin/env bash"
	h[#h+1] = "#"
	h[#h+1] = "# This hook is executed by git after receiving data that was pushed to this"
	h[#h+1] = "# repository. $GIT_DIR will point to ?/myblog/git/ where it will find ./HEAD"
	h[#h+1] = "# and ./refs/heads/master. As per the directory structure of lenie the source"
	h[#h+1] = "# files (*.md and rc.lua) are to be checked out to ?/myblog/src/, which is at"
	h[#h+1] = "# ../src/ relative to $GIT_DIR."
	h[#h+1] = "#"
	h[#h+1] = "# 1. Check out all the source files (markdown files etc) from this bare repo"
	h[#h+1] = "# into the src directory"
	h[#h+1] = 'SRCDIR="${GIT_DIR}/../src"'
	h[#h+1] = 'GIT_WORK_TREE="$SRCDIR" git checkout -f'
	h[#h+1] = "#"
	h[#h+1] = "# 2. Run lenie on the src directory and let her write the generated HTML and CSS"
	h[#h+1] = "# files to the directory the webserver is reading from."
	h[#h+1] = string.format('%s generate "$SRCDIR" %q\n', lenie_path, www_path )
	local hooksrc = table.concat(h, "\n")

	local hook_path = string.format("%s/git/hooks/post-receive", repo_path)
	local fd = assert( io.open(hook_path, 'w+'), string.format("ERROR: Unable to open %s for writing", hook_path))
	fd:write(hooksrc); fd:close()							-- write post-receive hook to file
	assert( os.execute("chmod +x " .. hook_path) == 0 )		-- make hook executable

	local hints = {
		"Don't forget to add the SSH keys of everyone who should be able to push to this blog"
		.. " to '$HOME/.ssh/authorized_keys'. See 'man ssh' for details.",
	}
	print("\nSetup completed. The blog repository has been created at " .. repo_path ..
	" and has been configured to save all generated HTML files to " .. www_path .. "\n")
	for ix,str in ipairs( hints ) do
		print( string.format("Hint:\n%s", str) )
	end
end
--}}}


--{{{ CLEAN-UP
function clean_www(repo_dir, www_dir)
	-- Get a list of all html files in the www_dir, remove the .html-suffix, compare the string
	-- against a list of special file names to be excluded from the test and then check if a
	-- corresponding markdown file exists at repo_path. If no such file exists, remove the html
	-- file with the corresponding name.
	local special = {index=true, listing=true}
	local lshtml = io.popen(string.format('ls %q | grep "\\.html$" | sed "s/.html//"', www_dir))
	for f in lshtml:lines() do
		if not special[f] and not file_exists(string.format('%s/%s.md', repo_dir, f)) then
			local rmpath = string.format('%s/%s.html', www_dir, f)
			os.execute(string.format('rm %q', rmpath))
			if CONF.verbose then print(string.format('Removed %q', rmpath)) end
		end
	end
end
--}}}


--{{{ MAIN
function sanity_checks()
	-- Make sure all programs required to run this script are installed
	local req_progs = {"markdown", "git", "grep", "awk", "luajit"}
	for ix,prog in ipairs(req_progs) do
		if not installed(prog) then
			print(string.format("ERROR: The program %q is required but can't be found", prog))
			return false
		end
	end
	-- Check that the installed Lua interpreter has the correct version
	local req_version = {major=2, minor=0}
	local version = io.popen("luajit -v"):read("*l")
	local major,minor,rev = version:match("(%d)%.(%d)%.(%d)")
	major, minor, rev = tonumber(major), tonumber(minor), tonumber(rev)

	if major ~= req_version.major or minor ~= req_version.minor then
		print(string.format("LuaJIT version missmatch; requires %d.%d.* but found %d.%d.%d",
							req_version.major, req_version.minor, major, minor, rev))
		return false
	end

	return true
end


function print_usage(msg)
	if msg then print(msg) end
	local usage = {
		[[lenie init <path of repo to be created> <path to write HTML files>]],
		[[lenie generate <path to src dir of repo> <path to dest dir>]],
	}
	for ix,str in ipairs(usage) do
		print(string.format("usage [%d]: %s", ix, str))
	end
end


-- Parse input arguments, check that the number or arguments is correct and the permissions of
-- the specified directories are sufficient.
function parse_input()
	local exec_path, arg1, arg2 = arg[1], arg[2], arg[3]
	if exec_path == "generate" or exec_path == "gen" then
		local repo_dir, www_dir = arg1, arg2
		if repo_dir and www_dir then
			exec_path = "gen"
		else
			print_usage("ERROR: 'lenie gen' requires two paths as arguments.")
			return false
		end
	elseif exec_path == "initialize" or exec_path == "init" then
		local repo_path, www_dir = arg1, arg2
		if repo_path and www_dir then
			exec_path = "init"
		else
			print_usage("ERROR: 'lenie init' requires two paths as arguments.")
			return false
		end
	else
		print_usage()
		return false
	end

	return {exec_path, arg1, arg2}
end


function main()
	local input = assert( parse_input(), "Input parsing failed" )
	assert( sanity_checks(), "Sanity checks failed" )
	if input[1] == "init" then				--> lenie init
		print( init(input[2], input[3]) )
	else									--> lenie generate
		-- Read runtime config from rc.lua, store it in the global table "CONF"
		read_rc(input[2], CONF)
		-- Generate the html code from markdown files
		local result = generate(input[2], input[3])
		if CONF.verbose then print( result ) end
		if CONF.clean_html then clean_www(input[2], input[3]) end
	end
end


main()
--}}}

