remotename=`git remote -v | grep -E "origin.*push" | grep -oE ":([^ ]+)" | grep -oE "[^:]+"`
BINSTORE=$(dirname /media/lab/gitserve/gitbin-store/$remotename/blah) #using dirname with a fake file to clean up double slashes etc.

function addbin {
    [[ -d $BINSTORE ]] || mkdir -p $BINSTORE

    while [[ "x$1" != "x" ]];
    do
        src=$1 ; shift
        hash=`md5sum $src | cut -d" " -f1`
        # check whether the file is already a symlink to its hash in the binstore
        # i.e. there is nothing to reset
        [[ -L $src && "`readlink $src`" == "$BINSTORE/$hash" ]] && continue 

        echo "git-bin-add: adding $src with hash $hash to $BINSTORE"

        if [[ -e $BINSTORE/$hash && `stat -c%s $BINSTORE/$hash` != `stat -c%s $src` ]]; then
            echo "git-bin-add: SIGNATURE CONFLICT in $src!"
            echo "git-bin-add: $src  in store has size `stat -c%s $BINSTORE/$hash`, and your file has size `stat -c%s $src`"
            return
        elif [[ -e $BINSTORE/$hash && -h $src ]]; then
            echo "git-bin-add: nothing to do, $src is already in the binstore"
            #TODO: symlink it anyways. There might be multiple 'copies' of the same file in a git repo.
            return
        fi

        # BACKUP
        cp -f $src .tmp_$hash

        (cp -f $src $BINSTORE/$hash && rm -f $src && ln -s $BINSTORE/$hash $src && git add $src && rm -f .tmp_$hash) || (echo "git-bin-add: something went wrong when adding $src, reverting" && mv -f .tmp_$hash $src)
    done
}

function editbin {
    if [[ ! -d $BINSTORE ]];
    then
        echo "git-bin-edit: the binstore ($BINSTORE) doesn't exist. You probably haven't added any binaries to git-bin yet."
        return
    fi

    while [[ "x$1" != "x" ]];
    do
        src=$1 ; shift
        storefile=`readlink $src`
        [[ $? == 1 || "$(dirname $storefile)" != "$BINSTORE" ]] && continue #not a symlink
        tmpfile=.tmp_$(basename $storefile)

        cp $storefile $tmpfile && mv -f $tmpfile $src && echo "git-bin-edit: $src is now available for editing"
    done
}

function resetbin {
    if [[ ! -d $BINSTORE ]];
    then
        echo "git-bin-reset: the binstore ($BINSTORE) doesn't exist. You probably haven't added any binaries to git-bin yet."
        return
    fi

    while [[ "x$1" != "x" ]];
    do
        src=$1 ; shift
        hash=`md5sum $src | cut -d" " -f1`
     
        # check whether the file is already a symlink to its hash in the binstore
        # i.e. there is nothing to reset
        [[ -L $src && "`readlink $src`" == "$BINSTORE/$hash" ]] && continue 

        if [[ ! -e $BINSTORE/$hash ]];
        then
            # The hash is not in the binstore. this could be because the file was never tracked by
            # git-bin, or because the file content has changed (following a git-bin-edit).
            # We test to see if the file was in git-bin by seeing if git-status lists it as having
            # had a type change (i.e. going from a symlink to a regular file). This will be the
            # status even if the file has also had its contents changed. If this is not the case,
            # we should just ignore the file as it's probably not a git-bin file.
            git status $src | grep -E "typechange: $src\$" 2>&1 >/dev/null || continue
            
            #otherwise, the file has changed, so we should back it up!
            echo "git-bin-reset: $src has changed, saving a copy to /tmp/$src.$hash"
            cp -f $src /tmp/$src.$hash
        else
            # The has is in the binstore. We need to check for signature conflicts:
            if [[ `stat -c%s $BINSTORE/$hash` != `stat -c%s $src` ]]; then
                echo "git-bin-reset: SIGNATURE CONFLICT in $src!"
                echo "git-bin-reset: $src in store has size `stat -c%s $BINSTORE/$hash`, and your file has size `stat -c%s $src`"
                return
            fi
        fi
        # now we can just restore the file using git.
        echo "git-bin-reset: restoring $src to the git HEAD"
        rm -f $src && git checkout -- $src
    done
}

funcname=$1 ; shift

case $funcname in
    add|edit|reset) 
        if [[ "x$1" == "x" ]];
        then
            echo "git-bin: you must specify a file name to operate on!"
            exit 1
        fi
        eval ${funcname}bin $@
        ;;
    *) 
        echo "git-bin error: '$funcname' not a recognized command"
        echo "available commands are: add, edit, reset"
        ;;
esac
