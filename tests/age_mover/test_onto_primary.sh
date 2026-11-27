#!/bin/bash
# A move with rsync, or a sync, onto the primary copies the file to a temporary name there, then links it to each name:
# what lands, what a different file written there meanwhile keeps, and what a failure or a stop leaves.
. "$(dirname "$0")/lib.sh"

# standin <command> <code>: the command runs the code, then the real command; start removes it. The run is a subshell
# of this script, so it would keep a command this script found before
standin() {
    printf '#!/bin/bash\n%s\nexec %q "$@"\n' "$2" "$(PATH=${PATH#"$T/bin:"} command -v "$1")" >"$T/bin/$1"
    chmod 755 "$T/bin/$1"
    hash -r
}
start() {
    rm -f "$T/bin/ln" "$T/bin/mktemp" "$T/bin/stat" "$T/bin/rm" "$T/copied"
    hash -r
    begin "$@"
}

start "a different file written on the primary during the transfer is kept, for a move and a sync"
mk disk1 sh/p/f.txt sh/p/g.txt
mkdir -p /mnt/cache/sh/p
{ row 'move from secondary' f sh/p/f.txt; row 'sync from secondary' f sh/p/g.txt; } | list
# before each copy of a file, a different one at its name on the primary
standin rsync 's=${@: -2:1}; r=/mnt/cache/${s#/mnt/*/}; [ ! -f "$s" ] || [ -e "$r" ] || printf "newer edit\n" >"$r"'
run_moves
check "the primary's files keep their content" "newer edit newer edit" "$(cat /mnt/cache/sh/p/f.txt /mnt/cache/sh/p/g.txt | paste -sd' ')"
cache_is sh sh/p sh/p/f.txt sh/p/g.txt
holds disk1 sh sh/p sh/p/f.txt sh/p/g.txt
log_has 'Left where it is: "/mnt/disk1/sh/p/f.txt" differs from the file already at "/mnt/cache/sh/p/f.txt", which the share shows; remove the copy you do not want'
log_has 'Left where it is: "/mnt/disk1/sh/p/g.txt" differs from the file already at "/mnt/cache/sh/p/g.txt"'
counter PRIMARYCONFLICTFILES 2
counter MOVEDFILES 0
counter NOTMOVEDFILES 0
counter REMAINING_ARRAY_FILES 0

start "a staged file's sync, after a move left for a different file during its transfer, still syncs" synchronizeCache yes
mk other sh/x/f.txt sh/y/f.txt
mkdir -p /mnt/cache/sh/y
{ row 'move unattended to primary' f sh/x/f.txt; row 'sync unattended to secondary' f sh/x/f.txt; row 'move unattended to primary' f sh/y/f.txt; } | list
standin rsync 's=${@: -2:1}; [ "$s" != /mnt/other/sh/y/f.txt ] || [ -e /mnt/cache/sh/y/f.txt ] || printf "newer edit\n" >/mnt/cache/sh/y/f.txt'
run_moves
cache_is sh sh/x sh/x/f.txt sh/y sh/y/f.txt
array_is sh sh/x sh/x/f.txt
log_count 1 'Left where it is:'
counter PRIMARYCONFLICTFILES 1
counter MOVEDFILES 1

start "a copy of the same file written on the primary during the transfer lets the move finish"
mk disk1 sh/p/f.txt
mkdir -p /mnt/cache/sh/p
row 'move from secondary' f sh/p/f.txt | list
standin rsync 's=${@: -2:1}; [ "$s" != /mnt/disk1/sh/p/f.txt ] || [ -e /mnt/cache/sh/p/f.txt ] || cp -a "$s" /mnt/cache/sh/p/f.txt'
run_moves
cache_is sh sh/p sh/p/f.txt
holds disk1 sh sh/p
log_lacks 'Left where it is'
counter MOVEDFILES 1
counter PRIMARYCONFLICTFILES 0

start "a sync from the secondary keeps the source, and copies no file already on the primary"
mk disk1 sh/p/f.txt sh/p/g.txt
mkdir -p /mnt/cache/sh/p
cp -a /mnt/disk1/sh/p/g.txt /mnt/cache/sh/p/g.txt
{ row 'sync from secondary' f sh/p/f.txt; row 'sync from secondary' f sh/p/g.txt; } | list
standin rsync "printf '%s\n' \"\${@: -2:1}\" >>'$T/copied'"
run_moves
cache_is sh sh/p sh/p/f.txt sh/p/g.txt
holds disk1 sh sh/p sh/p/f.txt sh/p/g.txt
check "only f.txt was copied" /mnt/disk1/sh/p/f.txt "$(grep -x '/mnt/disk1/sh/p/[fg].txt' "$T/copied")"
counter MOVEDFILES 2
counter SYNCFAILED 0

start "a group left for a different file during its transfer counts a name gone meanwhile as gone, and keeps its linked name"
mk disk1 sh/p/a.txt
for n in b c; do ln /mnt/disk1/sh/p/a.txt "/mnt/disk1/sh/p/$n.txt"; done
mkdir -p /mnt/cache/sh/p
for n in a b c; do row 'move from secondary' f "sh/p/$n.txt"; done | list
standin rsync 's=${@: -2:1}; [ ! -f "$s" ] || { printf "newer edit\n" >/mnt/cache/sh/p/a.txt; rm -f /mnt/disk1/sh/p/c.txt; }'
run_moves
check "the primary's file keeps its content" "newer edit" "$(cat /mnt/cache/sh/p/a.txt)"
cache_is sh sh/p sh/p/a.txt sh/p/b.txt
holds disk1 sh sh/p sh/p/a.txt sh/p/b.txt
log_count 1 'Left where it is:'
counter PRIMARYCONFLICTFILES 2
counter VANISHEDFILES 1
counter MOVEDFILES 0

start "a name gone from the source during the copy is not brought back on the primary"
mk disk1 sh/p/a.txt
for n in b c; do ln /mnt/disk1/sh/p/a.txt "/mnt/disk1/sh/p/$n.txt"; done
for n in a b c; do row 'move from secondary' f "sh/p/$n.txt"; done | list
after_first_rsync 'rm /mnt/disk1/sh/p/c.txt'
run_moves
cache_is sh sh/p sh/p/a.txt sh/p/b.txt
holds disk1 sh sh/p
counter MOVEDFILES 2
counter VANISHEDFILES 1
counter NOTMOVEDFILES 0

start "a group whose first name goes before its copy is copied from the next"
mk disk1 sh/p/a.txt
ln /mnt/disk1/sh/p/a.txt /mnt/disk1/sh/p/b.txt
{ row 'move from secondary' f sh/p/a.txt; row 'move from secondary' f sh/p/b.txt; } | list
standin rsync 's=${@: -2:1}; [ "$s" != /mnt/disk1/sh/p/a.txt ] || rm -f "$s"'
run_moves
cache_is sh sh/p sh/p/b.txt
holds disk1 sh sh/p
counter MOVEDFILES 1
counter VANISHEDFILES 1
counter NOTMOVEDFILES 0

start "a synced file gone before its copy counts as gone, not as a failed sync"
mk disk1 sh/p/f.txt
row 'sync from secondary' f sh/p/f.txt | list
standin rsync 's=${@: -2:1}; [ ! -f "$s" ] || rm -f "$s"'
run_moves
cache_is sh sh/p
log_has 'Gone from the source before its turn: "/mnt/disk1/sh/p/f.txt"'
counter VANISHEDFILES 1
counter NOTMOVEDFILES 0
counter SYNCFAILED 0

start "a hardlink group from the secondary lands as one file on the primary"
mk disk1 sh/p/a.txt
mkdir -p /mnt/disk1/sh/q
ln /mnt/disk1/sh/p/a.txt /mnt/disk1/sh/q/b.txt
{ row 'move from secondary' f sh/p/a.txt; row 'move from secondary' f sh/q/b.txt; } | list
run_moves
cache_is sh sh/p sh/p/a.txt sh/q sh/q/b.txt
holds disk1 sh sh/p sh/q
check "both names are one file of 2 links" "2 2 one file" \
    "$(stat -c %h /mnt/cache/sh/p/a.txt /mnt/cache/sh/q/b.txt | paste -sd' ') $([ /mnt/cache/sh/p/a.txt -ef /mnt/cache/sh/q/b.txt ] && echo one file)"
counter MOVEDFILES 2
counter MOVEDSIZE 2
if [ "${AGE_MOVER_DEBUG:-0}" = 2 ]; then
    dlog_has 'Rsync cmd: "rsync" "--archive" "--xattrs" "/mnt/disk1/sh/p/a.txt" "/mnt/cache/sh/p/.ca.mover.tuning.'
    dlog_lacks 'remove-source-files'
fi

start "a group with a name already on the primary links the missing name to it, as one file"
mk disk1 sh/p/a.txt
mkdir -p /mnt/disk1/sh/q /mnt/cache/sh/p
ln /mnt/disk1/sh/p/a.txt /mnt/disk1/sh/q/b.txt
cp -p /mnt/disk1/sh/p/a.txt /mnt/cache/sh/p/a.txt
{ row 'move from secondary' f sh/p/a.txt; row 'move from secondary' f sh/q/b.txt; } | list
run_moves
cache_is sh sh/p sh/p/a.txt sh/q sh/q/b.txt
holds disk1 sh sh/p sh/q
check "both names are one file of 2 links" "2 2 one file" \
    "$(stat -c %h /mnt/cache/sh/p/a.txt /mnt/cache/sh/q/b.txt | paste -sd' ') $([ /mnt/cache/sh/p/a.txt -ef /mnt/cache/sh/q/b.txt ] && echo one file)"
counter MOVEDFILES 2

start "a hardlink group whose folders on the primary are on two filesystems gets a copy on each"
mk disk1 sh/p/a.txt
mkdir -p /mnt/disk1/sh/q /mnt/cache/sh/q
ln /mnt/disk1/sh/p/a.txt /mnt/disk1/sh/q/b.txt
{ row 'move from secondary' f sh/p/a.txt; row 'move from secondary' f sh/q/b.txt; } | list
standin stat '[ "$*" != "-L -c %d -- /mnt/cache/sh/q" ] || { echo 4242; exit; }'
run_moves
cache_is sh sh/p sh/p/a.txt sh/q sh/q/b.txt
holds disk1 sh sh/p sh/q
check "each name is its own file of 1 link" "1 1 two files" \
    "$(stat -c %h /mnt/cache/sh/p/a.txt /mnt/cache/sh/q/b.txt | paste -sd' ') $([ /mnt/cache/sh/p/a.txt -ef /mnt/cache/sh/q/b.txt ] || echo two files)"
counter MOVEDFILES 2

start "a name changed on the source after its copy stays there"
mk disk1 sh/p/f.txt
row 'move from secondary' f sh/p/f.txt | list
after_first_rsync "printf 'more\n' >>/mnt/disk1/sh/p/f.txt"
run_moves
check "the source keeps the change" "x more" "$(paste -sd' ' /mnt/disk1/sh/p/f.txt)"
cache_is sh sh/p sh/p/f.txt
log_has 'Still on the source after the move: "/mnt/disk1/sh/p/f.txt"'
counter MOVEDFILES 0
counter NOTMOVEDFILES 1

start "the folders a move makes on the primary take the source's mode, owner and date"
mk disk1 sh/p/q/f.txt
chown 99:100 /mnt/disk1/sh/p /mnt/disk1/sh/p/q
chmod 750 /mnt/disk1/sh/p/q
touch -d 2020-01-01 /mnt/disk1/sh/p/q /mnt/disk1/sh/p
want=$(stat -c '%a %u:%g %Y' /mnt/disk1/sh/p /mnt/disk1/sh/p/q)
row 'move from secondary' f sh/p/q/f.txt | list
run_moves
cache_is sh sh/p sh/p/q sh/p/q/f.txt
check "the folders' mode, owner and date" "$want" "$(stat -c '%a %u:%g %Y' /mnt/cache/sh/p /mnt/cache/sh/p/q)"

start "a file on the primary at the place of a folder the move needs is kept"
mk disk1 sh/p/f.txt
mkdir -p /mnt/cache/sh
printf 'keep\n' >/mnt/cache/sh/p
row 'move from secondary' f sh/p/f.txt | list
run_moves
check "the primary's file keeps its content" keep "$(cat /mnt/cache/sh/p)"
holds disk1 sh sh/p sh/p/f.txt
log_has "mkdir: cannot create directory '/mnt/cache/sh/p': File exists"
log_has 'Did not arrive: "/mnt/disk1/sh/p/f.txt"'
counter NOTMOVEDFILES 1

start "a dangling link at the name on the primary is kept"
mk disk1 sh/p/f.txt
mkdir -p /mnt/cache/sh/p
ln -s /nowhere /mnt/cache/sh/p/f.txt
row 'move from secondary' f sh/p/f.txt | list
run_moves
check "the link still points where it did" /nowhere "$(readlink /mnt/cache/sh/p/f.txt)"
cache_is sh sh/p sh/p/f.txt
holds disk1 sh sh/p sh/p/f.txt
log_has 'Left where it is: "/mnt/disk1/sh/p/f.txt" differs from the file already at "/mnt/cache/sh/p/f.txt"'
counter PRIMARYCONFLICTFILES 1

start "folders whose mode, owner or date cannot be set leave the file moved, with the error counted"
mk disk1 sh/p/f.txt
row 'move from secondary' f sh/p/f.txt | list
standin rsync "case \"\$*\" in *--dirs*) echo 'rsync: [generator] rsync_xal_set: lsetxattr(\"/mnt/cache/sh/p\",\"user.k\") failed: Operation not supported (95)' >&2; exit 23 ;; esac"
run_moves
cache_is sh sh/p sh/p/f.txt
holds disk1 sh sh/p
log_has 'rsync: [generator] rsync_xal_set: lsetxattr("/mnt/cache/sh/p","user.k") failed: Operation not supported (95)'
counter MOVEDFILES 1
counter TOOLERRORFILES 1

start "a source that cannot be removed after its copy stays, with the error in the log"
mk disk1 sh/p/f.txt
row 'move from secondary' f sh/p/f.txt | list
standin rm "case \"\$*\" in */mnt/disk1/*) echo \"rm: cannot remove '/mnt/disk1/sh/p/f.txt': Read-only file system\" >&2; exit 1 ;; esac"
run_moves
cache_is sh sh/p sh/p/f.txt
holds disk1 sh sh/p sh/p/f.txt
log_has "rm: cannot remove '/mnt/disk1/sh/p/f.txt': Read-only file system"
log_has 'Still on the source after the move: "/mnt/disk1/sh/p/f.txt"'
counter MOVEDFILES 0
counter NOTMOVEDFILES 1

start "a temporary name that cannot be removed is in the log"
mk disk1 sh/p/f.txt
row 'move from secondary' f sh/p/f.txt | list
standin rm "case \"\$*\" in *.ca.mover.tuning.*) echo 'rm: cannot remove the temporary name: Read-only file system' >&2; exit 1 ;; esac"
run_moves
check "one temporary name is left" 1 "$(find /mnt/cache/sh/p -name '.ca.mover.tuning.*' | wc -l)"
log_has 'rm: cannot remove the temporary name: Read-only file system'
counter MOVEDFILES 1

# a sync goes to rsync with either tool; Unraid's move takes its own way, and its stand-in refuses to copy onto the source
for case in 'move from secondary|rsync' 'sync from secondary|rsync' 'sync from secondary|move' 'move from secondary|move'; do
    action=${case%|*} tool=${case#*|}
    start "a $action with $tool through a folder on the primary that is a link to the source leaves the file where it is" movefilesTool "$tool"
    mk disk1 sh/p/f.txt
    ln -s /mnt/disk1/sh /mnt/cache/sh
    row "$action" f sh/p/f.txt | list
    run_moves
    holds disk1 sh sh/p sh/p/f.txt
    check "the folder on the primary is still the link" /mnt/disk1/sh "$(readlink /mnt/cache/sh)"
    if [ "$case" = 'move from secondary|move' ]; then
        log_lacks 'which the mover does not follow'
        log_has 'Still on the source after the move: "/mnt/disk1/sh/p/f.txt"'
    else
        log_has 'Left where it is, as a folder on its way on the primary is a link, which the mover does not follow: "/mnt/disk1/sh/p/f.txt"'
    fi
    counter MOVEDFILES 0
done

# each step that fails leaves the file on the source, no temporary name on the primary, and its error in the log
for step in stat copy temp link; do
    start "a $step that fails leaves the file on the source"
    mk disk1 sh/p/f.txt
    row 'move from secondary' f sh/p/f.txt | list
    case $step in
    stat) err="stat: cannot statx '/mnt/cache/sh/p': Input/output error"
        standin stat "[ \"\$*\" != '-L -c %d -- /mnt/cache/sh/p' ] || { echo \"$err\" >&2; exit 1; }" ;;
    copy) err='rsync: [receiver] write failed: No space left on device (28)'
        standin rsync "case \"\$*\" in *.ca.mover.tuning.*) echo '$err' >&2; exit 11 ;; esac" ;;
    temp) err="mktemp: failed to create file via template '/mnt/cache/sh/p/.ca.mover.tuning.XXXXXX': Read-only file system"
        standin mktemp "case \"\$*\" in *.ca.mover.tuning.*) echo \"$err\" >&2; exit 1 ;; esac" ;;
    link) err="ln: failed to create hard link '/mnt/cache/sh/p/f.txt': Invalid cross-device link"
        standin ln "case \"\$*\" in *.ca.mover.tuning.*) echo \"$err\" >&2; exit 1 ;; esac" ;;
    esac
    run_moves
    holds disk1 sh sh/p sh/p/f.txt
    cache_is sh sh/p
    log_has "$err"
    log_has 'Did not arrive: "/mnt/disk1/sh/p/f.txt"'
    counter MOVEDFILES 0
    counter NOTMOVEDFILES 1
done

# the plugin's stop also signals the hook, which ignores it
for who in plugin run; do
    start "a stop ($who) before the copy onto the primary is linked leaves no temporary name there"
    mk disk1 sh/p/f.txt
    chown 99:100 /mnt/disk1/sh /mnt/disk1/sh/p
    chmod 755 /mnt/disk1/sh
    chmod 750 /mnt/disk1/sh/p
    row 'move from secondary' f sh/p/f.txt | list
    if [ "$who" = plugin ]; then after_first_rsync "trap '' TERM; $(stop_hook plugin)"; else after_first_rsync "$(stop_hook run)"; fi
    run_moves 'processTheMoves did not return'
    if [ "$who" = plugin ]; then
        for _ in $(seq 100); do grep -qs 'mover: stopped' "$T/stop.out" && break; sleep 0.1; done
        check "the plugin's stop ended" 1 "$(grep -cs 'mover: stopped' "$T/stop.out")"
        rm -f "$T/stop.out"
    fi
    holds disk1 sh sh/p sh/p/f.txt
    cache_is sh sh/p
    check "the folders it made have their source folder's mode and owner" "755 99:100 750 99:100" \
        "$(stat -c '%a %u:%g' /mnt/cache/sh /mnt/cache/sh/p | paste -sd' ')"
done

start "a stop right after the temporary name is made leaves none"
mk disk1 sh/p/f.txt
row 'move from secondary' f sh/p/f.txt | list
standin mktemp "n=\$($(PATH=${PATH#"$T/bin:"} command -v mktemp) \"\$@\") || exit
p=\$PPID; while [ \"\$(cut -d' ' -f4 /proc/\$p/stat)\" != $$ ]; do p=\$(cut -d' ' -f4 /proc/\$p/stat); done
kill -TERM \$p; echo \"\$n\"; exit"
run_moves 'processTheMoves did not return'
holds disk1 sh sh/p sh/p/f.txt
cache_is sh sh/p

for case in 'move from secondary|rsync' 'sync from secondary|rsync' 'sync from secondary|move'; do
    action=${case%|*} tool=${case#*|}
    start "a folder row, $action with $tool, keeps a file at its place on the primary, one at a folder's on its way, and a link there" movefilesTool "$tool"
    mkdir -p /mnt/disk1/sh/a/e /mnt/disk1/sh/b/e /mnt/disk1/sh/c/e /mnt/cache/sh/a
    printf 'keep\n' >/mnt/cache/sh/a/e
    printf 'keep\n' >/mnt/cache/sh/b
    ln -s /mnt/disk1/sh/c /mnt/cache/sh/c
    { row "$action" d sh/a/e; row "$action" d sh/b/e; row "$action" d sh/c/e; } | list
    run_moves
    check "the primary's files keep their content" "keep keep" "$(cat /mnt/cache/sh/a/e /mnt/cache/sh/b 2>&1 | paste -sd' ')"
    check "the link stays" /mnt/disk1/sh/c "$(readlink /mnt/cache/sh/c)"
    cache_is sh sh/a sh/a/e sh/b sh/c
    holds disk1 sh sh/a sh/a/e sh/b sh/b/e sh/c sh/c/e
    for f in a/e b/e c/e; do
        log_has "Left where it is, as the primary holds a file or a link at its place or that of a folder on its way: \"/mnt/disk1/sh/$f\""
    done
    dlog_lacks 'Rsync cmd'
done

# the planner's real find, on a temporary copy beside names close to its form: a shorter one, and a folder
planner() {
    mkdir -p "$T/shares"
    printf 'shareUseCache="yes"\nshareCachePool="cache"\n' >"$T/shares/sh.cfg"
    ( CFGPATH=$T/shares FILTERED_FILELIST=$T/filtered; createFilteredFilelist ) >/dev/null 2>&1
    check "the list's names" "$1" "$(awk -F'|' 'NR > 1 { print $13 }' "$T/filtered" | LC_ALL=C sort | paste -sd' ')"
    check "no list of temporary copies left" no "$([ -e "$T/filtered.stale" ] && echo yes || echo no)"
}
for mode in no yes; do
    does=removes
    [ "$mode" = no ] || does="in test mode names"
    start "the planner $does a temporary copy an earlier run left on the primary, and lists the rest" movingThreshold 0 freeingThreshold 0 testmode $mode
    mk cache sh/p/f.txt sh/p/.ca.mover.tuning.Ab12C
    printf 'part\n' >/mnt/cache/sh/p/.ca.mover.tuning.Ab12Cd
    mkdir /mnt/cache/sh/p/.ca.mover.tuning.Xy34Zw
    planner "/mnt/cache/sh/p/.ca.mover.tuning.Ab12C /mnt/cache/sh/p/.ca.mover.tuning.Xy34Zw /mnt/cache/sh/p/f.txt"
    if [ "$mode" = no ]; then
        cache_is sh sh/p sh/p/f.txt sh/p/.ca.mover.tuning.Ab12C sh/p/.ca.mover.tuning.Xy34Zw
        log_has 'Removed "/mnt/cache/sh/p/.ca.mover.tuning.Ab12Cd", a temporary copy an earlier run left'
    else
        cache_is sh sh/p sh/p/f.txt sh/p/.ca.mover.tuning.Ab12C sh/p/.ca.mover.tuning.Ab12Cd sh/p/.ca.mover.tuning.Xy34Zw
        log_has 'TEST MODE: Would remove "/mnt/cache/sh/p/.ca.mover.tuning.Ab12Cd", a temporary copy an earlier run left'
    fi
done

# last: the run's copy watcher outlives a stopped run here, as the test shell stands in for the run's pid. The stand-in's
# helper renames itself, or copyPids would hold it as the copy; its sleep must not hold logged's pipe open
start "a stop of the run alone while a pause holds its copy onto the primary ends the run at once"
mk disk1 sh/p/f.txt
row 'move from secondary' f sh/p/f.txt | list
standin rsync "case \"\$*\" in *.ca.mover.tuning.*) p=\$PPID
    while [ \"\$(cut -d' ' -f4 /proc/\$p/stat)\" != $$ ]; do p=\$(cut -d' ' -f4 /proc/\$p/stat); done
    echo $$ >'$PAUSEFILE'
    ( printf helper >/proc/self/comm; until grep -qF 'Paused: the copy waits for Resume' '$MOVER_LOG'; do sleep 0.1; done; kill -TERM \$p ) </dev/null >/dev/null 2>&1 &
    sleep 10 2>/dev/null ;; esac"
# lifts the pause, so a run that waits for its copy still ends
( sleep 15; rm -f "$PAUSEFILE" ) &
watchdog=$!
t0=$SECONDS
run_moves 'processTheMoves did not return'
check "the run ended within 6 s of its start" yes "$([ $((SECONDS - t0)) -le 6 ] && echo yes || echo no)"
kill "$watchdog" 2>/dev/null
wait "$watchdog" 2>/dev/null
rm -f "$PAUSEFILE"
holds disk1 sh sh/p sh/p/f.txt
cache_is sh sh/p

finish
