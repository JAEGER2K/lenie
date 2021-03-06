-- Do you want verbose output on what is happening when you push to your blog-repository and
-- the HTML is generated?
verbose = true

-- The sorting order of your blog posts. Choices currently are between two base modes that go
-- in both directions:
-- first_modified and last_modified sort based on the modification (or creation) date of a post
-- first_- and last_published sort based on the time of the first draft of a post appearing
sorting = "last_modified"

-- How many posts do you want to be displayed fully on the start page of your blog? Your choice
-- is between an obvious positive number, zero if you don't want any posts showing (which makes
-- sense for a blog mainly consisting of a header and a separate post listing) or a negative
-- number signalling "all". Which posts will be shown also depends on the sorting.
-- The remaining posts not shown on the start page will still be generated and you can directly
-- link to them by referring to the file name with the .md replaced by .html (eg. myfirstpost.md
-- can be linked to via [Some link title](myfirstpost.html) where the []() is the markdown-
-- syntax for hyperlinks.)
-- There will also be a page "listing.html" that simply lists and links to all posts on your
-- blog, adhering to your set sorting order.
max_posts_on_index = 10

-- The default colour scheme here is based on Solarized Light [1] as it is a generally very
-- pleasant theme but you are free to use any colours you want, including green-on-black
-- duochrome colors if you are stuck in 1999 or whatever.
-- The identifiers here should be self-explanatory, but I'll give you a rundown anyway:
-- fg_* is the text colour, *_hi is used for highlighted text and *_sec for content of secondary
-- importance. The background colour is determined by bg_color and there is bg_color_alt for
-- alternation (eg. the post info bar).
-- The three link colours are 1) regular, 2) hovered over and 3) visited.
-- h1, h2 and h3 denote the colours for headers generated by ===, --- and ### (see [2])
fg_color     = "#657b83"	--> base00 (regular)
fg_color_hi  = "#586e75"	--> base01 (emphasized)
fg_color_sec = "#93a1a1"	--> base1 (secondary)
bg_color     = "#fdf6e3"	--> base3
bg_color_alt = "#eee8d5"	--> base2
link_color   = "#859900"	--> green
link_color2  = "#d33682"	--> magenta
link_color3  = "#6c71c4"	--> violet
h1_color     = "#2aa198"	--> cyan
h2_color     = "#2aa198"	--> cyan
h3_color     = "#586e75"	--> base01 (emphasized)

-- For a bit of page layout configuration we have the padding, determining the position of the
-- posts on the weblog. The syntax here is that of a Lua table being defined using CSS notation
-- for the fields: 20px meaning 20 pixels and 20% meaning 20% of the browser width.
padding = { top="20px", right="20%", bottom="40px", left="20%" }

-- This is not the title that appears on your blog but that your browser will likely display as
-- tab and window name. Also search engines are looking for it.
blog_title = "default lenie blog-title"


-- [1] http://ethanschoonover.com/solarized
-- [2] https://en.wikipedia.org/wiki/Markdown
