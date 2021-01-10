#!/bin/bash
set -e

cleanup() {
    trap - TERM INT EXIT
    if [[ -O "$FIFO" ]]; then
        rm -f "$FIFO" || :
    fi
    if [[ -O "$DIR" ]]; then
        rmdir "$DIR" || :
    fi
}
trap "cleanup" TERM INT EXIT

DIR=$(mktemp -d "/dev/shm/epipe-$$.XXXXXXXXXX")
FIFO="$DIR/fifo"

mkfifo -m 0600 "$DIR/fifo"

emacsclient -n --eval "(progn (require 'named-pipe) (named-pipe-pager \"$FIFO\"))" >/dev/null <&-

exec 1>"$FIFO"
cleanup # Cleanup early. Nobody needs the paths now...

# Read from stdin and:
# * remove backspaces
# * cleanup carriage returns
sed -e ':s; s#[^\x08]\x08##g; t s' -e 's#$##' -e 's#.*##'
