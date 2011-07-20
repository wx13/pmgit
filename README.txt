======================
pmgit (Poor Man's GIT)
======================

pmgit is a small bash script for mimicking some of the functionality of 
git.  It is very slow, has poor error checking, implements only a very 
small subset of what git does; but it is about a thousand times smaller 
in size.


Usage
=====

The code is written, not as a bash script, but as a collection of bash 
functions.  To "install", simply run

	source pmgit.sh

which will load the functions into memory.  To make this permanent, add 
the above line to .bash_profile or .bashrc.

The following commands are implemented:

pmgit init
	Same as git.

pmgit add [files]
	Same as git.

pmgit add -p files
	Same as git, but: must list files to add, and uses editdiff to let 
	you edit the patches.

pmgit rm files
	Same as git.

pmgit commit message
	Same as git, but only accepts messages on the command line (and 
	without the -m flag).

pmgit diff  [reference1] [reference2]
	Pretty much same as git.  References can be:
	1. Left out: first one will be working copy, second will be index.
	   Unless "--cached" specified: then first is index and second is 
	   HEAD.
	2. HEAD, HEAD^, HEAD^^, ..., HEAD~3, etc.
	3. A branch name.
	4. A tag.
	5. The start of a commit hash.

pmgit status
	Same as git.

pmgit log
	Same as git.

pmgit checkout [reference]
	Pretty much same as git, except does not reset the index.

pmgit reset-index
	same as "git reset --mixed HEAD"

pmgit tag
	same as git.

pmgit branch
	same as git.

pmgit branch name.
	same as "git checkout -b name"

pmgit graph
	shows a lousy "graph" view of repo structure

pmgit cherrypick reference
	same as git

Noticeably absent are merge and rebase, because these are both just 
sequential applications of cherrypick.

Also absent is the clone command, which can be replaced with 'cp' and 
'pmgit checkout'.  For example to clone repo1 to repo2:

	mkidr repo2
	cp -rl repo1/.pmgit repo2/.pmgit
	cd repo2
	pmgit checkout master
	pmgit reset-index

The commands diff and cherrypick allow for remote repositories. To add a 
remote, enter

	pmgit remote add <name> <path to .pmgit>

To remove

	rm .pmgit/remotes/<name>

Then diff and cherrypick can be run like this

	pmgit diff myremote:HEAD
	pmgit diff 3be421a6 myremote:HEAD^^
	pmgit cherrypick myremote:tag_1

Repository structure
====================

To keep things simple, and user script-able, pmgit does not use the same 
repository structure as git.  It looks like this:

	$ ls .pmgit/
	BRANCH  HEAD  branches  index  junk  objects  tags

BRANCH
	stores the name of the current branch.

HEAD
	stores the hash of the current commit.

branches/<name>
	stores the hash of the head of branch <name>

index/
	stores the current state of the index directory structure

junk/
	contains temporary files

tags/
	just like branches, but for tags

objects/blobs/<hash>
	contains a single file, in its original form.  <hash> is the sha1sum 
	of it contents

objects/commits/<hash>
	contains a commit, like this:

	| Wed Jun 29 11:27:10 PDT 2011
	| tree cdb5026b82027f9f05c7d24d5ac320670488cb9d
	| message 118fb38d9ca028c5e44be7681df5d61be1de541f
	| parent f42664e7d89c596d8e29e4e4a9461de3635a50cc

objects/messages/
	contains commit messages

objects/tress/
	contains trees like this:

	| ./file1.txt f78b65dfc4a48be402585a0b7adbe16226085eb5
	| ./file2.txt ee9e51458f4642f48efe956962058245ee7127b1
	| ./file3.txt 31db9994df40cb599f6436beb46ff4d9c2249e24