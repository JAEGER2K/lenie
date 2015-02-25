#!/usr/bin/env luajit

require("discount")

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
	srcdir = false,				--> path to working dir with checked out files
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


-- Check file or directory permission using standard C-lib function ACCESS(2) via LuaJITs ffi
-- library. Returns 0 when file exists or permission is granted, -1 otherwise.
function access(fname, mode)
	assert(fname and type(fname) == "string")
	if not mode then mode = 0				-- test for existence
	elseif mode == "r" then mode = 4		-- test for read permission
	elseif mode == "w" then mode = 2		-- test for write permission
	elseif mode == "x" then mode = 1		-- test for execute permission
	end

	return ffi.C.access(fname, mode)
end


function abspath(p)
	assert(type(p) == "string")
	-- Translate relative paths to absolute paths
	if p:sub(1,1) ~= '/' and p:sub(1,2) ~= '~/' then
		p = string.format("%s/%s", os.getenv("PWD"), p)
	end
	return p
end

function file_exists(fname)
	if access(fname) == 0 then return true else return false end
end

function installed(pname)
	local path = os.getenv("PATH")
	for dir in string.gmatch(path, "[^:]+") do
		local fpath = string.format("%s/%s", dir, pname)
		if access(fpath) == 0 then
			return true, fpath
		end
	end
	return false
end


-- Get sha1 of most recent commit from the blogs git repository
function get_index_rev()
	local fd = io.popen("git log -1 | grep commit | awk '{ print $2 }'")
	local rev = fd:read("*a")
	fd:close()
	return rev
end

-- Get sha1 of currentlt checked out commit from the blogs working directory
function get_working_rev(srcdir)
	local fd = io.open(srcdir.."/rev", "r")
	if fd then
		local working_dir_rev = fd:read("*l")
		fd:close()
		return working_dir_rev
	end
	return false
end


-- In the src directory there is a file "rev" that stores the sha1 of the commit associated with
-- the current state of the blog. Note that this is not necessarily the commit that is checked
-- out in the src directory; it refers to the generated HTML files and indicates whether the
-- blog - as seen by the web server - is out of sync with the blogs repository.
-- This function does the comparison and returns true if the blog is in sync with the repo.
function up_to_date(srcdir)
	if get_index_rev() == get_working_rev(srcdir) then
		return true
	else
		return false
	end
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
function get_metainfo(fname)
	local info = {}
	-- Query the git repository for information on the first version of this file
	local fd = io.popen(string.format('git log --pretty="format:%%ct%%n%%cD%%n%%an" -- %q|tail -3', fname))
	info.T = fd:read('*l'):match('%d+')
	info.date = fd:read('*l'):match('[^%+]+')
	info.author = fd:read('*l')
	fd:close()
	-- Query the git repository for information on the newest version of this file
	fd = io.popen(string.format('git log -1 --pretty="format:%%ct%%n%%cD%%n%%an" -- %q', fname))
	info.t = fd:read('*l'):match('%d+')
	info.update = fd:read('*l'):match('[^%+]+')
	info.editor = fd:read('*l')
	info.fname = fname
	info.title = string.match(fname, '([^/]+)%.md$')	--> file name without suffix or path
	fd:close()
	return info
end


--[[
function get_postindex(srcdir)
	if CONF.verbose then print("Sourcing relevant markdown files from "..srcdir) end
	local mdfiles = {}
	--local ls = io.popen(string.format("ls -t %q", srcdir))
	local ls = io.popen("git ls-files --full-name")
	for fname in ls:lines() do
		local mdfile = fname:match('^.+%.md$')
		if mdfile and mdfile ~= "preamble.md" and mdfile ~= "footer.md" then
			mdfiles[#mdfiles+1] = get_metainfo(mdfile)
		end
	end
	ls:close()
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


-- Convert received mardown files to HTML and return that in a table of strings
function gen_posts(srcdir, mdfiles, rc, _posts)
	for ix,p in ipairs(mdfiles) do
		if not _posts[p.title] then
			local t = {}
			t[#t+1] = '<div id="postinfo">'
			local nr = ix
			if string.find(rc.sorting, "last_") then nr = (#mdfiles-ix)+1 end
			local s1 = string.format('#%d <a href="%s.html">%s</a> by %s', nr, p.title, p.title, p.author)
			local update = ""
			if p.t ~= p.T then update = string.format(" (updated %s)", p.update) end
			local s2 = string.format('<span id="secondary">on %s%s</span>', p.date, update)
			t[#t+1] = string.format('%s %s', s1, s2)
			t[#t+1] = '</div><div id="post">'
			local fd = io.open(string.format('%s/%s', srcdir, p.fname))
			t[#t+1] = discount(fd:read('*a'))
			fd:close()
			t[#t+1] = '</div>'
			_posts[p.title] = table.concat(t)
		end
	end
end


function gen_index_html(srcdir, mdfiles, rc, _posts)
	-- Create an array containing only the subset from mdfiles that is relevant for index.html
	local subset = mdfiles
	if rc.max_posts_on_index == 0 then
		subset = {}
	elseif rc.max_posts_on_index > 0 and rc.max_posts_on_index < #mdfiles then
		local t = {}
		for ix=1, rc.max_posts_on_index do
			t[ix] = mdfiles[ix]
		end
		subset = t
	end

	-- Generate the posts; they will be stored in the table we pass as last argument
	if rc.max_posts_on_index ~= 0 then
		gen_posts(srcdir, subset, rc, _posts)
	end

	-- Create an array referencing the relevant subset from _posts
	local t = {}
	for _, p in ipairs(subset) do
		t[#t+1] = _posts[p.title]
	end
	return table.concat(t, "<br /><br />")
end


function gen_listing_html(mdfiles)
	local listing = {}
	for ix, post in ipairs(mdfiles) do
		local name = post.title
		listing[#listing+1] = string.format('#%d\t<a href="%s.html">%s</a>', ix, name, name)
	end
	return table.concat(listing, "<br />\n")
end
--]]


function get_post_index()
	local rc = CONF

	local post_index = {}
	local ls = io.popen("git ls-files --full-name")
	for fname in ls:lines() do
		local mdfile = fname:match('^.+%.md$')
		if mdfile and mdfile ~= "preamble.md" and mdfile ~= "footer.md" then
			if rc.verbose then print(string.format("querying meta info on %s/%s", rc.srcdir, mdfile)) end
			post_index[#post_index+1] = get_metainfo(mdfile)
		end
	end
	ls:close()

	-- Sort post index based on the configured sorting function
	local sortfunctions = {
		last_modified = function(a,b) return a.t > b.t end,
		first_modified = function(a,b) return a.t < b.t end,
		last_published = function(a,b) return a.T > b.T end,
		first_published = function(a,b) return a.T < b.T end,
	}
	table.sort(post_index, sortfunctions[rc.sorting])
	return post_index
end


function get_changed_files()
	local rc = CONF
	-- First, get a list of all files that changed between the commit currently active in the
	-- repository-index and the one represented by the generated HTML code
	local r = get_working_rev(rc.srcdir)
	local ls = io.popen(string.format("git diff-tree --no-commit-id --name-only HEAD..%s", r))
	-- This only gives us the file name but not the (sub)directory it is in, as a work-around we
	-- create a LUT "changed" to store all the file names sans suffix or path and then traverse
	-- "post_index" to find matches with meta.title.
	local changed = {}		-- LUT for changed file names
	local special = { ["preamble.md"]=1, ["footer.md"]=1, ["rc.lua"]=1 }
	for fname in ls:lines() do
		if special[fname] then
			changed.all = true
			break
		end
		local title = string.match(fname, '([^/]+)%.md$')
		if title then changed[title] = true end
	end
	ls:close()

	return changed
end

-- Receives the meta info of all markdown files as assembled by get_post_index() and returns a
-- list of all posts to be generated. The returned list is a table where the name of the post is
-- the key and the value is the index in the input array "post_index" where to find the meta
-- info of that post. So if there is a post with the name "hello" then you can find the meta
-- info to that post via post_index[post_list["hello"]]. Where "name" refers to the file name as
-- stored in the meta info since this will be a unique identifier.
function get_post_list(post_index)
	local post_list = {}

	local changed = get_changed_files()
	local j = math.min(CONF.max_posts_on_index, #post_index)

	if j < 0 or changed.all == true then		--> all posts need to be generated
		for i,meta in ipairs(post_index) do
			post_list[meta.fname] = i
		end
	else										--> only some of the posts need to be generated
		-- All posts needed to assemble index.html
		if j > 0 then
			for i=1, j do
				local meta = post_index[i]
				post_list[meta.fname] = i
			end
		end
		-- if j == 0 then index.html won't contain posts and none need to be added to post_list

		-- All changed files
		for i,meta in ipairs(post_index) do
			if changed[meta.title] then
				post_list[meta.fname] = i
			end
		end
	end

	return post_list
end


function gen_posts(post_index, post_list)
	local rc = CONF
	-- loop (funct)
	-- 		generate posts from a list
	-- 		sleep TODO sleep interval and duration in CONF and rc.lua
	local posts = {}
	for fname,ix in pairs(post_list) do
		meta = post_index[ix]

		local t = {}
		t[#t+1] = '<div id="postinfo">'
		local nr = ix
		if string.find(rc.sorting, "last_") then nr = (#post_index-ix)+1 end
		local s1 = string.format('#%d <a href="%s.html">%s</a> by %s', nr, meta.title, meta.title, meta.author)
		local update = ""
		if meta.t ~= meta.T then update = string.format(" (updated %s)", meta.update) end
		local s2 = string.format('<span id="secondary">on %s%s</span>', meta.date, update)
		t[#t+1] = string.format('%s %s', s1, s2)
		t[#t+1] = '</div><div id="post">'
		local fd = io.open(string.format('%s/%s', rc.srcdir, meta.fname))
		t[#t+1] = discount(fd:read('*a'))
		fd:close()
		t[#t+1] = '</div>'
		posts[fname] = table.concat(t)

		--[[ TODO implement sleep() and test if rc.sleep_interval is enabled
		if i % rc.sleep_interval == 0 then sleep(rc.sleep_duration) end
		]]
	end
	return posts
end


function gen_index_html(post_index, posts)
	local t = {}
	local j = math.min(#post_index, CONF.max_posts_on_index)
	if j < 0 then j = #post_index end
	for i,meta in ipairs(post_index) do
		if i > j then break end
		t[#t+1] = posts[meta.fname]
	end

	return table.concat(t, "\n<br /><br />")
end


function gen_listing_html(post_index)
	local listing = {}

	local t = {}
	for i,meta in ipairs(post_index) do
		local fname = string.match(meta.fname, '(.+)%.md$')		--> file path without .md suffix
		listing[#listing+1] = string.format('#%d\t<a href="%s.html">%s</a>', i, fname, meta.title)
	end
	return table.concat(t, "<br />\n")
end


function assemble_pages(post_index, post_list, fragments)
	local rc = CONF
	-- Generate the HTML for the preamble text, if there is a markdown file for it.
	local preamble = false
	if file_exists(rc.srcdir.."/preamble.md") then
		local fd = io.open(string.format('%s/preamble.md', rc.srcdir))
		preamble = discount(fd:read('*a'))
		fd:close()
	end
	-- Generate the HTML for the footer, if there is a markdown file in the working dir.
	local footer = false
	if file_exists(rc.srcdir.."/footer.md") then
		local fd = io.open(string.format('%s/footer.md', rc.srcdir))
		footer = discount(fd:read('*a'))
		fd:close()
	end

	-- Now surround the generated HTML page fragments with a proper head, body and footer and
	-- store the results in a table whose key-value pairs describe the file name (sans suffix)
	-- and corresponding content for the final HTML pages to be written.
	local final_pages = {}
	for fname,page in pairs(fragments) do
		--local meta = post_index[post_list[fname]]
		local title = fname:match('([^/]+)%.md$')	-- TODO better solution for entries without .md
		local html = {}
		-- Header
		html[#html+1] = '<!DOCTYPE html><html><link href="style.css" rel="stylesheet">'
		html[#html+1] = string.format('<head><title>%s - %s</title></head>', rc.blog_title, title)
		html[#html+1] = '<body>'
		if preamble then
			html[#html+1] = '<div id="preamble">'
			html[#html+1] = preamble
			html[#html+1] = '<hr></div>'
		end
		-- Post
		html[#html+1] = page
		-- Footer
		if footer then
			html[#html+1] = '<br /><hr>'
			html[#html+1] = footer
		end
		html[#html+1] = '</body></html>'
		final_pages[fname] = table.concat(html)
	end

	return final_pages
end


function gen_html()
	local rc = CONF
	assert(type(rc.srcdir) == "string")
	-- TODO Early out: Does anything need to be (re)generated? (func)

	-- A1: Array of tables with meta info on every markdown file that is a post
	-- L1: List of posts that need to be generated, file name as key, corresponding index of A1
	-- as value
	-- T1: Table of generated posts, file name as key, HTML-string as value

	-- get metainfo on all posts in a sorted array: A1
	local A1 = get_post_index()


	-- A1 -> L1
	-- create list of posts to be generated: L1 (func)
	local L1 = get_post_list(A1)


	-- A1,L1 -> T1
	-- create table to store generated HTML of posts: T1
	local T1 = gen_posts(A1, L1)


	-- A1,T1 -> string:index.html
	-- assemble index.html: look up post-names from the sorted meta-info array A1, the generated
	-- HTML for these posts will be in a table T1
	T1["index.md"] = gen_index_html(A1, T1)


	-- A1 -> string:listing.html
	-- assemble listing.html: All that is needed can be found in A1 (func)
	T1["listing.md"] = gen_listing_html(A1)


	-- create T2 to store all final HTML pages
	-- generate preamble and footer
	-- Generate final HTML files by concatenating the page fragments in T1 with preamble and
	-- footer and store it in T2
	local pages = assemble_pages(A1, L1, T1)


	-- return table T2 with file names as key and final HTML as value
	return pages
end


--[[
function gen_html(src, rc)
	assert(type(src) == "string", "first argument needs to be a string describing the path to the source directory")

	-- Create list with file names and meta data of all posts
	local mdfiles = get_postindex(src)

	-- The table "pages" stores the HTML-bodies of posts with the posts title as key. This is
	-- the exact set of HTML pages to be generated; for every entry one HTML page will be
	-- generated.
	local pages = {}

	-- Create the index.html and by doing so generate all the posts contained on it and store
	-- them in "pages".
	pages.index = gen_index_html(src, mdfiles, rc, pages)

	-- First, get a list of all files that changed between the commit currently active in the
	-- repository-index and the one represented by the generated HTML code
	local r = get_working_rev(src)
	local ls = io.popen(string.format("git diff-tree --no-commit-id --name-only HEAD..%s", r))
	if rc.verbose then print("Generating posts based on file changes since last commit") end
	-- Now generate pages for all posts that have been added/modified since the last commit but
	-- have not already been generated during gen_index_html().

	-- Find that specific subset of mdfiles and pass it to gen_posts()
	local new_mdfiles = {}
	for fname in ls:lines() do
		local title = fname:match('^(.+)%.md$')
		if title and title ~= "preamble" and title ~= "footer" then
			local str = title .. ": Already generated"
			if not pages[title] then
				str = title .. ": Generating"
				new_mdfiles[#new_mdfiles+1] = get_metainfo(fname)
			end
			print(str)
		end
	end
	ls:close()
	gen_posts(src, new_mdfiles, rc, pages)


	-- Additionally, add an entry for a page with a listing of all posts and links to them. This
	-- includes posts that are contained on index.html and those that are not.
	pages.listing = gen_listing_html(mdfiles)

	-- Generate the HTML for the preamble text, if there is a markdown file for it.
	local preamble = false
	if file_exists(src.."/preamble.md") then
		local fd = io.open(string.format('%s/preamble.md', src))
		preamble = discount(fd:read('*a'))
		fd:close()
	end

	-- Generate the HTML for the footer, if there is a markdown file in the working dir.
	local footer = false
	if file_exists(src.."/footer.md") then
		local fd = io.open(string.format('%s/footer.md', src))
		footer = discount(fd:read('*a'))
		fd:close()
	end


	-- Now surround the generated HTML page fragments with a proper head, body and footer and
	-- store the results in a table whose key-value pairs describe the file name (sans suffix)
	-- and corresponding content for the final HTML pages to be written.
	local final_pages = {}
	for title, page in pairs(pages) do
		local html = {}
		-- Header
		html[#html+1] = '<!DOCTYPE html><html><link href="style.css" rel="stylesheet">'
		html[#html+1] = string.format('<head><title>%s - %s</title></head>', rc.blog_title, title)
		html[#html+1] = '<body>'
		if preamble then
			html[#html+1] = '<div id="preamble">'
			html[#html+1] = preamble
			html[#html+1] = '<hr></div>'
		end
		-- Post
		html[#html+1] = page
		-- Footer
		if footer then
			html[#html+1] = '<br /><hr>'
			html[#html+1] = footer
		end
		html[#html+1] = '</body></html>'
		final_pages[title] = table.concat(html)
	end

	return final_pages
end
--]]


function read_css(repo_dir)
	local fpath = repo_dir .. "/style.css"
	if file_exists(fpath) then
		local fd = io.open(fpath, "r")
		if fd then
			local css = fd:read("*a")
			fd:close()
			return css
		end
	end
	return false
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

	local html_pages = gen_html(src, CONF)
	-- If a style.css is in the repository that is an explicit sign for lenie not to generate
	-- one from the config and simply use the manually added one.
	local style_css = read_css(src) or gen_css(CONF)

	-- Write HTML files
	for fname,page in pairs(html_pages) do
		local path = string.format("%s/%s", dst, fname:match('(.+)/.+$') or "")
		if not file_exists(path) then
			local fd = io.popen(string.format("mkdir -p %q", path))
			fd:close()
		end

		local title = fname:match('([^/]+)%.md$')
		local fpath = string.format("%s/%s.html", path, title)
		local fd = io.open(fpath, 'w')
		if fd then
			if CONF.verbose then print(string.format("Writing HTML to %s", fpath)) end
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
		else
			print(string.format("ERROR: Could not write to %s", fname))
		end
	end

	-- Update rev file to most recent commit hash
	do
		local fd = io.open(src.."/rev", 'w+')
		fd:write( get_index_rev() )
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
	-- Create bare repository in repo_path/.git
	assert( os.execute(string.format("git init --bare --shared %s/.git", repo_path)) == 0 )

	local lenie_found, lenie_path = installed("lenie")
	assert( lenie_found, "ERROR: 'lenie' not found in install path, did you install it as 'lenie.lua'?" )
	local h = {}
	h[#h+1] = "#!/usr/bin/env bash"
	h[#h+1] = "#"
	h[#h+1] = "# This hook is executed by git after receiving data that was pushed to this"
	h[#h+1] = "# repository. $GIT_DIR will point to ?/myblog/.git/ where it will find ./HEAD"
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

	local hook_path = string.format("%s/.git/hooks/post-receive", repo_path)
	local fd = assert( io.open(hook_path, 'w+'), string.format("ERROR: Unable to open %s for writing", hook_path))
	fd:write(hooksrc); fd:close()							-- write post-receive hook to file
	assert( os.execute("chmod +x " .. hook_path) == 0 )		-- make hook executable

	print("\nSetup completed. The blog repository has been created in " .. repo_path ..
	" and configured to save all generated HTML files to " .. www_path .. "\n")
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
	lshtml:close()
end
--}}}


--{{{ MAIN
function sanity_checks()
	-- Make sure all programs required to run this script are installed
	local req_progs = {"markdown", "git", "grep", "awk", "luajit", "lenie"}
	for ix,prog in ipairs(req_progs) do
		if not installed(prog) then
			print(string.format("ERROR: The program %q is required but can't be found", prog))
			return false
		end
	end
	-- Check that the installed Lua interpreter has the correct version
	local req_version = {major=2, minor=0}
	local fd = io.popen("luajit -v")
	local version = fd:read("*l")
	fd:close()
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
	if msg then print(msg,"\n") end
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
	if arg[1] and arg[2] and arg[3] then
		local cmd, path1, path2 = arg[1], abspath(arg[2]), abspath(arg[3])

		if cmd == "generate" or cmd == "gen" then
			return { "gen", path1, path2 }
		elseif cmd == "initialize" or cmd == "init" then
			return { "init", path1, path2 }
		end
	end

	print_usage("Incorrect user input")
	return false
end


function main()
	local input = parse_input()
	if not input then os.exit() end
	assert( sanity_checks(), "Sanity checks failed" )
	if input[1] == "init" then				--> lenie init
		print( init(input[2], input[3]) )
	else									--> lenie generate
		-- Read runtime config from rc.lua, store it in the global table "CONF"
		read_rc(input[2], CONF)
		local pwd = os.getenv("PWD")
		CONF.srcdir = pwd:match('(.+)%.git$') .. "src"
		-- Generate the html code from markdown files
		local result = generate(input[2], input[3])
		if CONF.verbose then print( result ) end
		if CONF.clean_html then clean_www(input[2], input[3]) end
	end
end


main()
--}}}

