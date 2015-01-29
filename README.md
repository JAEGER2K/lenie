lenie
=====
*lenie* is a very simple, secure, revision controlled weblog service with a tiny memory
footprint and intimate relationship to the unix philosophy.

*lenie* is named after Lenie Clarke.

**Note**: Skip to the section *Installation* if you don't care for the background and just want
to get things going.

The Rant (aka motivation)
--------
The driving motivation behind the development of *lenie* was my frustration with available
blogging solutions, almost all of which seem to assume that the web browser is a good tool for
writing longer text (an assumption I disagree with). Additionally, most blogging packages also
are overly complex for my taste. When I look at all the ref-links and scripts that my browser
is faced with when trying to load a page from tumblr, blogger, medium and so on, my immediate
reaction is to close the tab and try not to think about all the tracking that is going
on at the cost of performance; all the security nightmares that lurk in the shadows of the
gigantic and probaly unmaintainable code bases delivering the data; all the wasted bytes
transferred unencrypted just to end up infront of closed doors because I am running
requestpolicy and noscript; and finally the few bytes of text that I actually wanted to read but
shan't because they are displayed above and behind half-loaded images because the CSS is being
delivered from the other side of the world.


The Idea
--------
*lenie* is a bit different in that no web browser is required to update or communicate with the
blog. You write the blog posts in your favourite text editor, locally on your computer.  The
syntax used is the very simple [markdown](http://en.wikipedia.org/wiki/Markdown), that is
easy to read and write.
All configuration of the blog, as it appears to the readers in their web browser, is done
entirely in one text file, that you also write/edit in your favourite text editor, locally on
your computer. That includes everything from colour scheme to the blogs title.

All text files are stored inside a directory on your hard drive. One folder with everything in
it. The folder is a git repository configured to push to a remote on which *lenie* is running.

The workflow for writing on the blog looks like this:

1. Write or edit text file in your favourite editor.
2. $ git commit
3. $ git push

A few milliseconds later on the remote end:

1. Upon receiving data a git-hook is triggered that starts *lenie*
2. *lenie* reads the text files from the git-repository
3. *lenie* generates static HTML/CSS from your text files, based on your configuration
4. *lenie* writes the generated HTML/CSS to a directory which is observed by a webserver and
will henceforth be served to visitors of your blog.


Simple, secure, revision controlled, tiny memory footprint, unix philosophy...
---------
Note that *light weight* is not included. That is not because *lenie* is fat, but because that
term seems to have become marketing slang with a diffuse meaning and I don't intend to convince
anyone to use *lenie* when it's not the right tool for their needs. Thusly I wish to elaborate
the buzzword extravaganza from the description truthfully.

**Simple** is not the same as **easy**. *lenie* provides an extremely simple workflow for the
regular tasks of the author of the blog. One that has been refined by programmers for years, but
can be very useful in non-programming environments as well. Simple means that the idea behind it
is not complicated and the interaction involves only what is necessary to accomplish the task.

This ties into the **UNIX philosophy**: One program does one thing and does it well. Combining
multiple such programs allows you to solve vastly different tasks without writing huge programs
from scratch for everything.

*lenie* out-sources much of the work to git, which stores all the information we could ever want
in each commit while providing a lot of features useful for blogging. A small list of things git
gives us for free:

* Securely communicate with the server via SSH when adding content to the blog
* Sign everything you commit to the blog with with your GPG-key
* Inherent backup of the entire blog (at least one copy on your local HDD and the web server),
accesible at any time, even when offline
* It's revision based, allowing you to roll back the blog to the state of May 4th with one
command, if you want
* A comprehensive history of all changes ever done to the blog and, if multiple people are
authoring it, who authored which change
* The ability to annotate any edits you make on old posts
* A lot more things that haven't come to mind yet but will emerge when someone thinks of it,
possibly without even requiring any additional code from *lenie*

**Secure** doesn't just refer to the encrypted communication via *SSH* but also to the increased
availability of the data. If the disk of the server crashes the entire content of the blog is
still in the git repository on your local drive and vice versa if something happens to your
local drive.

Not just the current state of your blog is backed up that way, thanks to the nature of *git* the
entire history of your blog, including every edit you ever made, is also backed up in the repo,
something programmers refer to as **revision control**.

Finally, *lenie* is written in Lua and run in LuaJIT, a very performant JIT-compiler for a very
compact language. *lenie* runs only **once** for every time you push changes to your blog-repo
and doesn't occupy a single byte of RAM the entire rest of the time. It is not required for
*lenie* to do any work when the website is requested by a visitor as nothing is generated
dynamically. I think we can consider **0 bytes in RAM** as a **tiny memory footprint**.


Behind the Scenes
-----------------
*lenie* itself only needs to be installed on the machine hosting the web server, where she is
triggered by a githook whenever the blogs git repository receives a commit. The changes are
checked out into a directory and *lenie* runs through the files, parsing all markdown files and
consulting the config file before outputting static HTML into the directory observed by the
web server of your choice.

The choice to generate HTML and CSS code statically is deliberate, as there are no databases
involved and the blog maintained by *lenie* is as simple a web site as a blog should be in my
humble opinion. The result is an extremely fast loading site that is restricted only by the
[capabilities of HTML and CSS](http://www.csszengarden.com/).

The HTML generation is implemented rather naively right now, but will be optimized eventually to
only generate what is affected by the changes made in the last commit. With the potential to
cache segments of generated HTML code between updates even lively sites with a long history and
hundreds of thousands of entries might be updated statically within a few milliseconds.

*lenie* itself is written in Lua 5.1 and runs with the extremely fast JIT-compiler
[LuaJIT](http://luajit.org/). Lua generally handles string manipulation with grace and LuaJIT
performs so well that it is frequently used in game programming where execution times of less
than 16 milliseconds have to be met every frame. So yeah, don't worry about the performance of
generating the static HTML sites, which only ever happens when you push updates to the blog
anyway.


Installation
------------
###On the server side...
... *lenie* needs to be installed in a folder included in the install path such
as /usr/bin or /usr/local/bin. You then call

    $ lenie init <new repo> <HTML destination>

Where **new repo** is a path to the blog repository you want to create and **HTML destination**
is the path to the directory where *lenie* is supposed to store the generated HTML code.

The path to the new repo must be a folder that doesn't already exist, however the parent
directory should exist. If you want your repository in */home/myuser/myblog*, then
*/home/myuser* must exist and you must have permission to write there, but the directory
*/home/myuser/myblog* should not exist already.

The path to the HTML destination must exist already and you need to have write permission there
as well. While it is not necessary for *lenie* to work, you probably also want your webserver
to read from that very directory. Examples would be */data/www* or */srv/www*.

**NOTE** that you should not point two lenie-blogs to the same www directory as they *will*
overwrite each others HTML files.

### On the client side...
... you simply clone a git repository from a remote where *lenie* has been set up. If the remote
is at */home/myuser/myblog* on *myserver.net* to which you have ssh access and you are on your
local computer at *~/blogs/*, then the command would be:

    $ git clone myuser@myserver.net:myblog/git mybloglocal

This will create the repository in *~/blogs/mybloglocal* and right now this will be an empty
repository. You add a markdown text-file, via *git add*, commit that addition to the repository
via *git commit* and send it to the remote via *git push*.

### Useful optional things
First of all, you might want to edit the user name under which your posts are published by
[defining the user.name](http://git-scm.com/book/en/v2/Getting-Started-First-Time-Git-Setup) in
your local git repository.

Configuration of the blog is done by adding a file called *rc.lua* to your repository. An
example of this file is distributed with *lenie*s source code
[under /doc/rc.lua](https://github.com/lamarpavel/lenie/blob/master/doc/rc.lua).

The default header of your blog can be replaced by adding a file called *preamble.md* to your
repository. It's just another markdown file, like any of your blog posts, but you probably want
to use it to add a title, subtitle, intro text and/or links to listing.html and index.html. This
stuff will appear at the top of all pages of your blog. And example file is distributed with
*lenie*s source code [under /doc/preamble.md](https://raw.githubusercontent.com/lamarpavel/lenie/master/doc/preamble.md).


Detailed setup info
-------------------
The basic setup on the client side (where the author writes) requires the following tools:

1. A text editor
2. git (either run in a terminal or one of te GUIs out there)

Optionally but very recommended:

3. ssh for securely connecting to the remote
4. gnupg for signing new posts and verifying the integrity of old posts

On the server side there needs to be the following additional software installed:

1. The basic suite of unix tools such as ls, grep, awk, etc
2. A web server of your choice (nginx, lighttpd, apache, etc)
3. markdown (currently the reference implementation *markdown.pl*)
4. *lenie*

The user under which git is run on the server needs to have permission to write in the directory
observed by the web server (eg. /data/www).


Configuring the Blog
--------------------
As mentioned before all configuration is done in a single text file that you edit locally and
add to the repository. This file needs to be called **rc.lua**, a documented example is provided
with *lenie* and should present no challenge to anyone who can read and write (you don't need to
be a programmer). If **rc.lua** does not exist in the repo, *lenie* will use a possibly ugly
default configuration.


State of development
--------------------
*lenie* is not entirely ready for prime time yet, but development has advanced to beta stage.
Most work so far has been laying out the concept and architecture, reading manpages and brushing
up my HTML/CSS and implementing the very basic core features.

The following is a list of core features implemented in the beta of *lenie*:

* ~~Automated setup of the server repository via *$ lenie init <blog dir> <web server dir>*,
much like *$ git init*~~
* ~~Configuration of number of posts displayed on the index~~
* ~~More configuration options for CSS appearance~~
* ~~Generation of pages dedicated to single posts~~
* ~~Headers for posts displaying date of publishing, last modification, author~~
* ~~Ordering posts by configurable criteria~~

And this is a list of planned work during the beta:

* Add option to use a custom CSS style commited to the repository instead of the generated one
* Efficiency: Currently *lenie* is pretty damn fast but has only been tested with small blogs of
a limited post-count. In order for that speed to scale for blogs with 1000+ posts *lenie* needs
to learn to selectively generate only those pages affected by affected the current commit. Once
that is done *lenies* scalability is determined by *git*, which is proven to scale way beyond
the amount of text a single person can write in their lifetime.
* Host an example blog (duh, I already have written the development documentation as blog, it
only needs to be hosted)
* Something something test cases
* Consider replacing the default *markdown* with one of the many alternatives to provide
additional features for formatting and ease of use (eg. images embedded in the text)
* ~~delete HTML pages that are no longer needed~~
* Find, document and eliminate all bugs

Feature additions for *lenie* after a stable release:

* *$ lenie init* should provide the option to write the default config to file and add it to the
new repository
* A smart concept for signing posts with your GPG-Key
* Some assembly of stats about the blog, probably on a dedicated page
* Support for directory hierarchies in the blog-repository (recursively scan for markdown files)
* When removing posts some links from other posts to the removed pages may become invalid,
think about a solution and whether it makes sense to try to solve this
