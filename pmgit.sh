# poor man's git (pmgit)
# See README.txt


# terminal color shorthands
RED=`echo -e '\033[31m'`
GREEN=`echo -e '\033[32m'`
BLUE=`echo -e '\033[36m'`
YELLOW=`echo -e '\033[33m'`
NORMAL=`echo -e '\033[0m'`


function pmgit_init
{
	if [ -e .pmgit ]
	then
		echo "Error: already a pmgit repo"
	else
		mkdir .pmgit
		dotpmgit=.pmgit
		mkdir -p ${dotpmgit}/index
		mkdir -p ${dotpmgit}/objects
		mkdir -p ${dotpmgit}/objects/blobs
		mkdir -p ${dotpmgit}/objects/trees
		mkdir -p ${dotpmgit}/objects/commits
		mkdir -p ${dotpmgit}/objects/messages
		mkdir -p ${dotpmgit}/junk
		mkdir -p ${dotpmgit}/tags
		mkdir -p ${dotpmgit}/branches
		mkdir -p ${dotpmgit}/config
		mkdir -p ${dotpmgit}/remotes
		touch ${dotpmgit}/HEAD
		touch ${dotpmgit}/branches/master
		touch ${dotpmgit}/BRANCH
		touch ${dotpmgit}/config/whoami
		echo "master" > ${dotpmgit}/BRANCH
		echo "$(whoami)@$(hostname)" > ${dotpmgit}/config/whoami
		echo "remember to set your name and email in .pmgit/config/whoami"
	fi
}



# anything other than init, must find .pmgit
function pmgit_find_base
{
	if [ -z "$@" ]
	then
		echo "/.pmgit"
		return
	fi
	if [ -d ${1}/.pmgit ]
	then
		echo ${1}/.pmgit
	else
		i1=$(stat -c %i ${1})
		i2=$(stat -c %i /)
		if [ "${i1}" = "${i2}" ]
		then
			echo "/.pmgit"
		else
			echo $(pmgit_find_base ${1%/*})
		fi
	fi
}



# Compute the hash of a message string,
# and put it into a file with that hash as its name.
# Then return the hash value.
function pmgit_hash_message
{
	echo $@ > ${dotpmgit}/junk/message.txt
	hash=$(sha1sum ${dotpmgit}/junk/message.txt | awk '{print $1}')
	mv ${dotpmgit}/junk/message.txt ${dotpmgit}/objects/messages/${hash}
	echo ${hash}
}


# Construct a commit (a tree, a message, and a parent).
# Compute the hash, and put commit in file with that hash
# as its name.  Then return the hash value.
function pmgit_hash_commit
{
	tree_hash=$1
	msg_hash=$2
	parent_hash=$(cat ${dotpmgit}/HEAD)
	date > ${dotpmgit}/junk/commit.txt
	cat ${dotpmgit}/config/whoami >> ${dotpmgit}/junk/commit.txt
	echo "tree ${tree_hash}" >> ${dotpmgit}/junk/commit.txt
	echo "message ${msg_hash}" >> ${dotpmgit}/junk/commit.txt
	echo "parent ${parent_hash}" >> ${dotpmgit}/junk/commit.txt
	hash=$(sha1sum ${dotpmgit}/junk/commit.txt | awk '{print $1}')
	mv ${dotpmgit}/junk/commit.txt ${dotpmgit}/objects/commits/${hash}
	echo ${hash}
}



# take the tree in the index and:
# 1. hash each file
# 2. create tree object which is a text file containing
#     - file/directory structure
#     - hash of each file
# Then hash this, and put in right place.
function pmgit_hash_index_tree
{
	# store up tree structure in a file
	> ${dotpmgit}/junk/tree.txt
	cd ${dotpmgit}/index/
	for file in $(find -type f)
	do
		file_hash=$(sha1sum $file | awk '{print $1}')
		if [ ! -e ${dotpmgit}/objects/blobs/${file_hash} ]
		then
			cp $file ${dotpmgit}/objects/blobs/${file_hash}
			#chmod 444 ${dotpmgit}/objects/blobs/${file_hash}
		fi
		echo $file ${file_hash} >> ${dotpmgit}/junk/tree.txt
	done
	cd - &> /dev/null
	hash=$(sha1sum ${dotpmgit}/junk/tree.txt | awk '{print $1}')
	mv ${dotpmgit}/junk/tree.txt ${dotpmgit}/objects/trees/${hash}
	echo ${hash}
}




# copy files to index tree
function pmgit_add_to_index
{
	path=$(pwd)/$1
	repo=${dotpmgit%.pmgit}
	rpath=${path#${repo}}
	cd $repo
	rsync -rlRm --exclude=.pmgit $rpath ${dotpmgit}/index/
	cd - > /dev/null
}
# remove files from index tree
function pmgit_remove_from_index
{
	path=$(pwd)/$1
	file=$(basename -- $1)
	repo=${dotpmgit%.pmgit}
	rpath=${path#${repo}}
	cd $repo
	rm -ri ${dotpmgit}/index/${rpath}
	cd - > /dev/null
}
function pmgit_add_to_index_interactive
{
	path=$(pwd)/$1
	repo=${dotpmgit%.pmgit}
	rpath=${path#${repo}}
	cd $repo
	if [ ! -e ${dotpmgit}/index/$rpath ]
	then
		echo "Can't 'add -p' an untracked file."
		return;
	fi
	d=$(diff -q $rpath ${dotpmgit}/index/$rpath)
	if [ "$d" = "" ]
	then
		echo "No changes."
		return
	fi
	diff -u ${dotpmgit}/index/$rpath $rpath > ${dotpmgit}/junk/patch.txt
	editdiff ${dotpmgit}/junk/patch.txt
	patch ${dotpmgit}/index/${rpath} ${dotpmgit}/junk/patch.txt
	cd - > /dev/null
}




function pmgit_find_parent_commit
{
	commit_hash=$1
	num=$2
	if [ "$3" = "" ]
	then
		rdotpmgit=$dotpmgit
	else
		rdotpmgit=$3
	fi
	for i in $(seq 1 $num)
	do
		commit_hash=$(grep "parent" ${rdotpmgit}/objects/commits/${commit_hash} | awk '{print $2}')
	done
	echo $commit_hash
}



# given a branch/ref/partial hash,
# return the full hash
function pmgit_tell_me_the_commit_hash
{
	if [[ "$1" =~ ":" ]]
	then
		remote=${1%:*}
		rdotpmgit=$(head ${dotpmgit}/remotes/${remote})
		ref=${1#*:}
	else
		remote=""
		rdotpmgit=${dotpmgit}
		ref="$1"
	fi
	string=$ref
	if [ "${string:0:4}" = "HEAD" ]
	then
		head_hash=$(cat ${rdotpmgit}/HEAD)
		if [ "${string:4}" = "" ]
		then
			echo ${head_hash}
		elif [ "${string:4:1}" = "^" ]
		then
			nc=$(expr "${string:4}" : '\^*')
			echo $(pmgit_find_parent_commit ${head_hash} $nc $rdotpmgit)
		elif [ "${string:4:1}" = "~" ]
		then
			nc=${string:5}
			echo $(pmgit_find_parent_commit ${head_hash} $nc $rdotpmgit)
		else
			return
		fi
	else
		if [ -e ${rdotpmgit}/branches/${string} ]
		then
			cat ${rdotpmgit}/branches/${string}
		elif [ -e ${rdotpmgit}/tags/${string} ]
		then
			cat ${rdotpmgit}/tags/${string}
		else
			hash=$(find ${rdotpmgit}/objects/commits/ -name "${string}*" | awk '{print $1}')
			if [[ "$hash" =~ [0-9a-f]{40} ]]
			then
				echo $(basename $hash)
			else
				return
			fi
		fi
	fi
}



# 1. create temp dir (junk)
# 2. Get tree from commit
# 3. Loop over tree files:
#   a. mkdir -p on dirname
#   b. "cp filehash filename"
function pmgit_expand_to_dir
{
	if [[ "$1" =~ ":" ]]
	then
		remote=${1%:*}
		dotpm=$(head ${dotpmgit}/remotes/${remote})
		ref=${1#*:}
	else
		remote=""
		dotpm=${dotpmgit}
		ref="$1"
	fi
	commit_hash=$(pmgit_tell_me_the_commit_hash $1)
	if [ "$commit_hash" = "" ]
	then
		echo ""
		return
	fi
	tree_hash=$(grep tree ${dotpm}/objects/commits/${commit_hash} | awk '{print $2}')
	if [ -e ${dotpmgit}/junk/tree/${tree_hash} ]
	then
		echo ${dotpmgit}/junk/tree/${tree_hash}
		return
	fi
	mkdir -p ${dotpmgit}/junk/tree/${tree_hash}
	while read file hash
	do
		mkdir -p $(dirname ${dotpmgit}/junk/tree/${tree_hash}/${file})
		cp ${dotpm}/objects/blobs/${hash} ${dotpmgit}/junk/tree/${tree_hash}/${file}
	done < ${dotpm}/objects/trees/${tree_hash}
	echo ${dotpmgit}/junk/tree/${tree_hash}
}




# display a diff between two revisions
function pmgit_diff
{
	exclude="-x .pmgit"
	if [ "$1" = "--cached" ]
	then
		dir1=$(pmgit_expand_to_dir HEAD)
		dir2=${dotpmgit}/index/
		n1="HEAD"
		n2="index"
	elif [ "$#" = "0" ]
	then
		dir1=${dotpmgit}/index/
		dir2=${dotpmgit%.pmgit}
		n1="index"
		n2="working copy"
	elif [ "$#" = "1" ]
	then
		dir1=${dotpmgit%.pmgit}
		dir2=$(pmgit_expand_to_dir $1)
		n1="working copy"
		n2="$2"
	else
		dir1=$(pmgit_expand_to_dir $1)
		dir2=$(pmgit_expand_to_dir $2)
		n1="$1"
		n2="$2"
	fi
	cwd=$(pwd)
	cwd=${cwd//\//\\\/}
	if [ "$dir1" = "" -o "$dir2" = "" ]
	then
		echo "Bad reference."
		return
	fi
	d1=${dir1//\//\\\/}
	d2=${dir2//\//\\\/}
	diff -ur ${exclude} $dir1 $dir2 \
		| sed "s/^Only in ${d1}:/${RED}deleted:${NORMAL}/g" \
		| sed "s/^Only in ${d2}:/${GREEN}new:${NORMAL}/g" \
		| sed "s/${d1}/${n1}/" \
		| sed "s/${d2}/${n2}/" \
		| sed "s/^@@.*@@/$BLUE&$NORMAL/g" \
		| sed "s/^\+[^+].*/$GREEN&$NORMAL/g" \
		| sed "s/^\-[^-].*/$RED&$NORMAL/g" \
		| sed "s/^\+\+\+/$GREEN&$NORMAL/g" \
		| sed "s/^\-\-\-/$RED&$NORMAL/g" \
		| sed "s/$cwd//g" \
		| less -R
}


function pmgit_status
{
	repo=${dotpmgit%.pmgit}
	cd $repo
	dir1=$(pmgit_expand_to_dir HEAD)
	if [ ! "$dir1" = "" ]
	then
		echo "indexed, but not commited:"
		echo -n "$GREEN"
		diff -qr $dir1 .pmgit/index/ | grep "differ" | awk '{print "    modified: " $4}'
		diff -qr $dir1 .pmgit/index/ | grep "Only in $dir1" | awk '{print "    removed: " $4}'
		diff -qr $dir1 .pmgit/index/ | grep "Only in \.pmgit" | awk '{print "    new: " $4}'
		echo "$NORMAL"
	fi
	echo "not added to index:"
	echo -n "$RED"
	diff -qr -x .pmgit .pmgit/index/ ./ | grep "differ" | awk '{print "    modified: " $4}'
	diff -qr -x .pmgit .pmgit/index/ ./ | grep "Only in \.pmgit" | awk '{print "    removed: " $4}'
	echo "$NORMAL"
	echo "untracked files:"
	diff -qr -x .pmgit ${dotpmgit}/index/ ./ | grep "Only in \./" | awk '{print "    " $4}'
	cd - &> /dev/null
}



function pmgit_log
{
	commit_hash=$(pmgit_tell_me_the_commit_hash HEAD)
	while [ ! "${commit_hash}" = "" ]
	do
		echo -n "$YELLOW"
		echo -n "commit ${commit_hash}"
		echo "$NORMAL"
		head -2 ${dotpmgit}/objects/commits/${commit_hash}
		echo ""
		message_hash=$(grep message ${dotpmgit}/objects/commits/${commit_hash} | awk '{print $2}')
		cat ${dotpmgit}/objects/messages/${message_hash}
		echo ""
		commit_hash=$(grep parent ${dotpmgit}/objects/commits/${commit_hash} | awk '{print $2}')
	done | less -R
}


function pmgit_graph
{
	# first get a list of all commits, in topological order
	commits=()
	i=0
	for ref in ${dotpmgit}/HEAD ${dotpmgit}/branches/* $(find ${dotpmgit}/tags/ -type f)
	do
		i=$((i+1))
		commit_hash=$(cat $ref)
		while [ ! "${commit_hash}" = "" ]
		do
			commits[i]="${commits[i]} ${commit_hash}"
			commit_hash=$(grep parent ${dotpmgit}/objects/commits/${commit_hash} | awk '{print $2}')
		done
		#echo $ref" : "${commits[i]}
	done
	n=$i
	allcommits=$(
		for i in $(seq 1 $n)
		do
			echo ${commits[i]}
		done | \
 		awk '{
				wl = 40;
				b[NR] = split($0,c);
				++n;
				for(i=0;i<=b[NR];++i)
					a[NR,i] = c[i];
			}
			END{
				p="";
				for(j=1;j<=b[1];++j) p=(p " " a[1,j]);
				for(i=2;i<=n;++i)
				{
					kp=2;
					for(j=1;j<=b[i];++j)
					{
						k=index(p,a[i,j]);
						if(k!=0) kp = k;
						if(k==0)
						{
							p = (substr(p,1,kp+wl-1) " " a[i,j] substr(p,kp+wl,10000000))
							kp += wl+1;
						}
					}
				}
				print p
			}'
	)

	# now we have an array of commit strings (commits[])
	# and a string of total commits (allcommits)

	i=0
	# loop over HEAD, branches, & tags
	for commit in $allcommits
	do
		i=$((i+1))
		graph[i]="$commit "
	done
	n=$i
	i=0
	for ref in ${dotpmgit}/HEAD ${dotpmgit}/branches/* $(find ${dotpmgit}/tags/ -type f)
	do
		i=$((i+1))
		echo $i = $(basename $ref)
		j=0
		for commit in ${allcommits}
		do
			j=$((j+1))
			ans=$(expr match "${commits[i]}" ".*${commit}.*")
			if [ "$ans" != "0" ]
			then
				graph[j]=${graph[j]}'+'
			else
				graph[j]=${graph[j]}"-"
			fi
		done
	done
	for i in $(seq 1 $n)
	do
		echo ${graph[i]}
	done
}






function pmgit_checkout
{
	# check for dirty working copy
	status=$(pmgit_status | grep -e "    modified:" -e "    removed:" -e "    new:")
	if [ ! "$status" = "" ]
	then
		echo "Warning: dirty tree. Hit any key to continue."
		read ans
	fi
	# now do the checkout
	dir1=$(pmgit_expand_to_dir $1)
	if [ "$dir1" = "" ]
	then
		echo "Bad reference."
		return
	fi
	rsync -a ${dir1}/ ${dotpmgit%.pmgit}/
	new_head=$(pmgit_tell_me_the_commit_hash $1)
	if [ "$new_head" = "" ]
	then
		echo "Bad reference."
		return
	fi
	echo ${new_head} > ${dotpmgit}/HEAD
	if [ -f ${dotpmgit}/branches/$1 ]
	then
		echo $1 > ${dotpmgit}/BRANCH
	fi
}


function pmgit_reset_index
{
	dir1=$(pmgit_expand_to_dir HEAD)
	rm -rf ${dotpmgit}/index/
	mkdir ${dotpmgit}/index
	rsync -a ${dir1}/ ${dotpmgit}/index/
}



function pmgit_create_tag
{
	if [ "$1" = "" ]
	then
		echo "Empty tag."
		return
	fi
	if [ -e ${dotpmgit}/tags/$1 ]
	then
		echo "Tag $1 already exists"
		return
	fi
	pmgit_tell_me_the_commit_hash HEAD > ${dotpmgit}/tags/$1
}
function pmgit_create_branch
{
	if [ "$1" = "" ]
	then
		echo "Empty branch name."
		return
	fi
	if [ -e ${dotpmgit}/branches/$1 ]
	then
		echo "Branch $1 already exists"
		return
	fi
	pmgit_tell_me_the_commit_hash HEAD > ${dotpmgit}/branches/$1
	echo $1 > ${dotpmgit}/BRANCH
}
function pmgit_show_branches
{
	curb=$(cat ${dotpmgit}/BRANCH)
	for branch in ${dotpmgit}/branches/*
	do
		branch=$(basename $branch)
		if [ "$curb" = "$branch" ]
		then
			echo -n '* '
			echo -n "$GREEN"
			echo $branch "$NORMAL"
		else
			echo "  "$branch
		fi
	done
}



function pmgit_cherrypick
{
	conflicts=0
	# check if work directory is clean
	workdir=${dotpmgit%.pmgit}
	a1=$(diff -qr --exclude=.pmgit ${workdir} ${dotpmgit}/index | grep "Only in ${dotpmgit}/index" | wc -l)
	a2=$(diff -qr --exclude=.pmgit ${workdir} ${dotpmgit}/index | grep " differ$" | wc -l)
	if [ "$a1" != "0" -o "$a1" != "0" ]
	then
		echo "Working directory is dirty!"
		return;
	fi

	# is this a remote commit
	if [[ "$1" =~ ":" ]]
	then
		remote=${1%:*}
		rdotpmgit=$(head ${dotpmgit}/remotes/${remote})
		remote="${1%:*}:"
		ref=${1#*:}
	else
		remote=""
		rdotpmgit=${dotpmgit}
		ref="$1"
	fi

	# get the parent of the cherry
	cherry_commit_hash=$(pmgit_tell_me_the_commit_hash $1)
	if [[ ! "$cherry_commit_hash" =~ [0-9a-f]{40} ]]
	then
		echo "Bad reference."
		return
	fi
	parent_commit_hash=$(pmgit_find_parent_commit ${cherry_commit_hash} 1 $rdotpmgit)
	if [[ ! "$parent_commit_hash" =~ [0-9a-f]{40} ]]
	then
		echo "Cherry commit has no parent. Aborting."
		return
	fi

	# expand all three commits, so we can diff & merge
	head_dir=$(pmgit_expand_to_dir HEAD)
	cherry_dir=$(pmgit_expand_to_dir ${remote}${cherry_commit_hash})
	parent_dir=$(pmgit_expand_to_dir ${remote}${parent_commit_hash})

	# check if index clean
	a1=$(diff -qr ${dotpmgit}/index ${head_dir} | grep "Only in" | wc -l)
	a2=$(diff -qr ${dotpmgit}/index ${head_dir} | grep " differ$" | wc -l)
	if [ "$a1" != "0" -o "$a1" != "0" ]
	then
		echo "Index contains uncommitted chages!"
		return;
	fi

	# look for new files
	new_files=$(diff -qr ${parent_dir} ${cherry_dir} | grep "Only in ${cherry_dir}" | awk '{sub(":","",$3); print $3 "/" $4}')
	for file in ${new_files}
	do
		filename=${file#${cherry_dir}/}
		if [ -e ${workdir}/$filename ]
		then
			merge -q ${workdir}/$filename ${workdir}/$filename ${file}
			conflicts=$((conflicts+$?))
		else
			cd ${cherry_dir}
			cp --parents ${filename} ${workdir}/
			cd - &> /dev/null
		fi
	done
	# look for deleted files
	del_files=$(diff -qr ${parent_dir} ${cherry_dir} | grep "Only in ${parent_dir}" | awk '{sub(":","",$3); print $3 "/" $4}')
	for file in ${del_files}
	do
		filename=${file#${parent_dir}/}
		if [ -e ${workdir}/$filename ]
		then
			ans=$(diff -q ${workdir}/${filename} ${parent_dir}/${filename} | wc -l)
			if [ "$ans" = "0" ]
			then
				rm ${workdir}/${filename}
			else
				echo "File ${filename} deleted in commit, but modified in working copy."
				echo "Leaving file alone; manually delete if desired."
			fi
		fi
	done
	# look for modified files
	mod_files=$(diff -qr ${parent_dir} ${cherry_dir} | grep " differ$" | awk '{print $2}')
	for file in ${mod_files}
	do
		filename=${file#${parent_dir}}
		if [ -e ${workdir}/${filename} ]
		then
			merge ${workdir}/${filename} ${parent_dir}/${filename} ${cherry_dir}/${filename}
			conflicts=$((conflicts+$?))
		else
			cd ${cherry_dir}
			cp --parents ${filename} ${workdir}/
			cd - &> /dev/null
		fi
	done


	if [ "$conflicts" != "0" ]
	then
		echo "There were conflicts. Fix them and then commit the changes."
	else
		echo "No conflicts.  Don't forget to add & commit the changes."
	fi

	# tell user which files to add/rm
	echo "To add:"
	if [ "$del_files" != "" ]
	then
		df=${del_files//${parent_dir}//}
		echo "  pmgit rm ${df#//}"
	fi
	if [ "${new_files}${modfiles}" != "" ]
	then
		af="${new_files//${cherry_dir}//} ${mod_files//${parent_dir}//}"
		echo "  pmgit add ${af#//}"
	fi

	echo "Message is:"
	msghash=$(grep "message" ${rdotpmgit}/objects/commits/${cherry_commit_hash} | awk '{print $2}')
	path=$rdotpmgit
	cat ${rdotpmgit}/objects/messages/${msghash}
}




function pmgit_remote
{
	if [ "$1" == "" ]
	then
		ls ${dotpmgit}/remotes/
		return
	fi
	if [ "$1" == "add" ]
	then
		path=$(cd $3; pwd)
		echo "$path" > ${dotpmgit}/remotes/$2
		return
	fi
	echo "Unknown option to remote."
}




# main function
function pmgit
{

	command=$1
	shift

	# if init, don't need to check for repo
	if [ "$command" = "init" ]; then
		pmgit_init
		return
	fi

	# find and export the .pmgit dir
	dotpmgit=$(pmgit_find_base $(pwd))
	if [ ! -d ${dotpmgit} ]
	then
		echo "Error: not a pmgit repository!"
		return
	fi
	export dotpmgit

	case $command in
		add)
			if [ "$1" = "-p" ]
			then
				shift
				for file in $@
				do
					if [ -f $file ]
					then
						pmgit_add_to_index_interactive $file
					else
						echo "File $file does not exist or is not a file. Skipping."
					fi
				done
			else
				for file in $@
				do
					if [ -e $file ]
					then
						pmgit_add_to_index $file
					else
						echo "$file does not exist."
					fi
				done
			fi
			;;
		rm)
			for file in $@
			do
				pmgit_remove_from_index $file
			done
			;;
		commit)
			if [ -z "$@" ]
			then
				echo "Warning: empty commit message."
				echo "Press any key to continue."
				read a
			fi
			message_hash=$(pmgit_hash_message $@)
			tree_hash=$(pmgit_hash_index_tree)
			# check for changes
			head_commit_hash=$(pmgit_tell_me_the_commit_hash HEAD)
			head_tree_hash=$(grep "tree" ${dotpmgit}/objects/commits/${head_commit_hash} | awk '{print $2}')
			if [ "$tree_hash" = "$head_tree_hash" ]
			then
				echo "No changes to commit."
			else
				commit_hash=$(pmgit_hash_commit $tree_hash $message_hash)
				echo ${commit_hash} > ${dotpmgit}/HEAD
				branch=$(cat ${dotpmgit}/BRANCH)
				if [ -f ${dotpmgit}/branches/${branch} ]
				then
					echo ${commit_hash} > ${dotpmgit}/branches/${branch}
				fi
			fi
			;;
		diff)
			pmgit_diff $@
			;;
		status)
			pmgit_status
			;;
		log)
			pmgit_log
			;;
		checkout)
			pmgit_checkout $@
			;;
		reset-index)
			pmgit_reset_index
			;;
		tag)
			pmgit_create_tag $1
			;;
		branch)
			if [ "$1" = "" ]
			then
				pmgit_show_branches
			else
				pmgit_create_branch $1
			fi
			;;
		graph)
			pmgit_graph
			;;
		cherrypick)
			pmgit_cherrypick $@
			;;
		remote)
			pmgit_remote $@
			;;
		*)
			echo "Unknown command."
			;;
	esac
}
