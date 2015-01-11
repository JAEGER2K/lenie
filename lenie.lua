#!/usr/bin/luajit
-- TODO where to put the asserts? Needs consistent solution.


--{{{ DEFAULT CONFIG
-- Some sensible default config, color scheme is solarized light
CONF = {
	-- runtime execution flags
	initialized  = false,
	verbose = true,
	sorting = "last_modified",
	max_posts_on_index = 10,
	-- TODO add entry for PWD directory of git and lenie
	-- appearance
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
	padding = { top="0px", right="10%", bottom="100px", left="40%" },
	blog_title = "default blog title",
	blog_subtitle = "powered by lenie; free of js, php, java, flash",
}
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


function file_exists(fname)
	local fd = io.open(fname, 'r')
	if io.type(fd) ~= nil then fd:close() return true
	else return false
	end
end


function installed(pname)
	return file_exists("/usr/bin/"..pname)
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

	return true		-- completed succesfully
end


-- Set up and configure the bare repository to automatically create static HTML files for the
-- web server upon receiving blog pusts via git push
function prepare(srcdir)
	-- Make sure all programs required to run this script are installed
	local req_progs = {"markdown", "git", "grep", "awk"}
	for ix,prog in ipairs(req_progs) do
		if not installed(prog) then
			print(string.format("ERROR: The program %q is required but can't be found", prog))
			os.exit()
		end
	end

	-- Read runtime config from rc.lua, store it in the global table "conf" and set its
	-- "initialized" flag
	CONF.initialized = read_rc(srcdir, CONF)
	return true
end
--}}}


--{{{ PATH 1: GENERATING STATIC HTML
-- Create table with files that need to be generated, sorted by date of modification
function get_metainfo(fname)
	local fd = io.popen(string.format('git log -1 --pretty="format:%%ct%%n%%cD%%n%%an" -- %q', fname))
	local info = {}
	info.t = fd:read('*l'):match('%d+')
	info.date = fd:read('*l'):match('[^%+]+')
	info.author = fd:read('*l')
	info.fname = fname
	info.title = string.match(fname, '(.+)%.md$')
	return info
end


function gather_mdfiles(srcdir)
	if CONF.verbose then print("Sourcing markdown files from "..srcdir) end
	local mdfiles = {}
	for fname in io.popen('ls -t "' .. srcdir .. '"'):lines() do
		local mdfile = fname:match('^.+%.md$')
		if mdfile then
			mdfiles[#mdfiles+1] = get_metainfo(mdfile)
		end
	end
	-- Sort mdfiles based on the unix timestamp of the commit in descending order (newest first)
	local sortfunctions = {
		last_modified = function(a,b) return a.t > b.t end,
		first_modified = function(a,b) return a.t < b.t end,
	}
	table.sort(mdfiles, sortfunctions[CONF.sorting])
	return mdfiles
end


function gen_html(src, mdfiles, rc)
	assert(rc.initialized, "Runtime config has to be initialized before generating HTML")
	assert(type(src) == "string", "first argument needs to be a string describing the path to the source directory")
	assert(type(mdfiles) == "table", "second argument needs to be an array containing markdown files as strings")

	-- Convert markdown files to HTML and store each one as string in an array
	local posts, names = {}, {}
	for ix,post in ipairs(mdfiles) do
		local t = {}
		t[#t+1] = '<div id="postinfo">'
		t[#t+1] = string.format(
			'#%d <a href="%s.html">%s</a> by %s <span id="secondary">on %s</span>',
			ix, post.title, post.title, post.author, post.date
			)
		t[#t+1] = '</div><div id="post">'
		t[#t+1] = io.popen(string.format('markdown --html4tags "%s/%s"', src, post.fname)):read('*a')
		posts[ix] = table.concat(t)
		names[ix] = post.title
	end

	-- Additionally, add one entry for the index page, containing as many posts as specified in
	-- the configuration for "max_posts_on_index"
	do
		local j = rc.max_posts_on_index
		if j < 0 then j = #posts end
		posts[#posts+1] = table.concat(posts, "</div><br /><br />", 1, j)
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
		html[#html+1] = string.format('<h1><a href="index.html">%s</a></h1>', rc.blog_title)
		html[#html+1] = string.format("<h2>%s</h2>", rc.blog_subtitle)
		html[#html+1] = '</div>'
		-- Post
		html[#html+1] = posts[i]
		-- Footer
		html[#html+1] = "</body></html>"
		pages[names[i]] = table.concat(html)
	end

	return pages
end


function gen_css(rc)
	assert(rc.initialized, "Runtime config has to be initialized before generating CSS")
	local css = {}
	local col,bg,pad = assert(rc.fg_color), assert(rc.bg_color), assert(rc.padding)
	css[#css+1] = string.format("body {color:%s; background-color:%s; padding:%s %s %s %s;}",
	col, bg, pad.top, pad.right, pad.bottom, pad.left)
	css[#css+1] = string.format("a {color:%s;}", rc.link_color or col)
	css[#css+1] = string.format("h1 {color:%s;}", rc.h1_color or col)
	css[#css+1] = string.format("h2 {color:%s;}", rc.h2_color or col)
	css[#css+1] = string.format("h3 {color:%s;}", rc.h3_color or col)
	css[#css+1] = string.format("hr {color:%s;}", rc.bg_color_alt or col)

	css[#css+1] = "#preamble {padding: 0 0 25px 0;}"
	css[#css+1] = "#post {padding: 0 0 0 0;}"
	css[#css+1] = string.format('#primary {color:%s;}', rc.fg_color_hi or col)
	css[#css+1] = string.format('#secondary {color:%s;}', rc.fg_color_sec or col)

	css[#css+1] = "#postinfo {"
	css[#css+1] = string.format("color:%s; background-color:%s;", rc.fg_color_hi or col, rc.bg_color_alt or bg)
	css[#css+1] = "padding:2px 4px 2px 4px;"
	css[#css+1] = "}"


	css[#css+1] = "\n"
	return table.concat(css, "\n")
end


-- Read all files in the specified source directory "src" and generate HTML code to be stored in
-- destination directory "dst"
function generate(src, dst)
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
	-- TODO create directory repo_path, repo_path/src
	-- TODO create bare repository in repo_path/git
	-- TODO add post-receive hook
	local hints = {
		[[Don't forget to add the SSH keys of everyone who should be able to push to this blog
		to '$HOME/.ssh/authorized_keys'. See man ssh for details.]],
		[[Make sure the permissions of the directory where the HTML pages should be written are
		set properly. The user calling "lenie generate" must have permission to write there and
		the webserver must have permission to read the files there.]],
	}
	print("Setup completed. The blog repository has been created at " .. repo_path ..
	" and has been configured to save all generated HTML files to " .. www_path)
	for ix,str in ipairs( hints ) do
		print("Hint " .. ix .. ": " .. str)
	end
end
--}}}


--{{{ MAIN
function print_usage()
	local usage = {
		[[lenie init <path of repo> <path to www dir observed by webserver>]],
		[[lenie generate <path to src dir> <path to dest dir>]],
	}
	for ix,str in ipairs(usage) do
		print("usage ["..ix.."]: " .. str)
	end
end

-- Parse input arguments
function main()
	if arg[1] == "generate" or arg[1] == "gen" then
		local srcdir, dstdir = arg[2], arg[3]
		if srcdir == nil or dstdir == nil then
			print("ERROR: Arguments missing.")
			print_usage()
			os.exit()
		end
		assert( prepare(srcdir), "Failure during preparation phase" )
		local result = generate(srcdir, dstdir)
		if CONF.verbose then print( result ) end
	elseif arg[1] == "initialize" or arg[1] == "init" then
		local repo_path, www_path = arg[2], arg[3]
		if not repo_path or not www_path then
			print("ERROR: Arguments missing.")
			print_usage()
			os.exit()
		end
		print("Sorry, this feature has not yet been fully implemented")
	else
		print_usage()
		os.exit()
	end
end
--}}}


main()
