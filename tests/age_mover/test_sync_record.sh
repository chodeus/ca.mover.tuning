#!/bin/bash
# The sync record: the real decideMoveActions syncs a kept file whose copy the record lacks, whatever its date, and the real
# processTheMoves notes each copy and move it verified.
. "$(dirname "$0")/lib.sh"

# before every case's lastCacheSync, so the date rule alone syncs none of the files given it; nanoseconds as a real file has
OLD="2020-01-01 00:00:00.123456789"
MARK=1767323045

# plan [share/path]...: decideMoveActions on these /mnt/cache rows of share sh, which keeps them and syncs from MARK; RULES,
# TIME (each file's list time), LISTM (0: the share lists ctimes) and SHARESYNC (its own Synchronize) override the defaults
plan() {
    local p m s n i y
    FILTERED_FILELIST=$T/filtered HELD_FILELIST=$T/held overrideFlag=0
    : >"$HELD_FILELIST"
    {
        echo 'PRIMARYSTORAGENAME|SECONDARYSTORAGENAME|SHARENAME|SHAREUSECACHE|MODIFYTIME|PRIMARYSIZETHRESH|POOLUSED|FILESIZE|SPARSENESS|NBLINKS|INODE|FILETYPE|FILEPATH'
        for p; do
            read -r m s n i < <(stat -c '%Y %s %h %i' "/mnt/cache/$p")
            m=${TIME:-$m}
            y=f
            [ ! -d "/mnt/cache/$p" ] || y=d
            printf 'cache|user0|sh|yes|%s|0|0|%s|0|%s|%s|%s|/mnt/cache/%s\n' "$m" "$s" "$n" "$i" "$y" "$p"
        done
    } >"$FILTERED_FILELIST"
    SHARE_PLAN_RULES=${RULES:-"sh|1|0|0|0|0"} SHARE_SYNC_SETTINGS="${SHARESYNC:-$SYNCHRONIZECACHE}|$MARK|${LISTM:-1}|sh"$'\n'
    decideMoveActions >/dev/null 2>"$T/plan.err"
    check "decideMoveActions wrote nothing on stderr" "" "$(cat "$T/plan.err")"
}
# actions <expected>: each row's action and path, as the planner wrote them
actions() {
    check "the planner's actions" "$1" "$(awk -F'|' 'NR > 1 { p = $15; for (i = 16; i <= NF; i++) p = p "|" $i; print $11 ": " p }' "$MOVER_ACTIONLIST")"
}
old() { local p; for p; do touch -d "$OLD" "/mnt/cache/$p"; done; }
# copy_of <share/path>...: a copy on /mnt/user0 as rsync --archive leaves one
copy_of() { local p; for p; do mkdir -p "/mnt/user0/${p%/*}" && cp -a "/mnt/cache/$p" "/mnt/user0/$p"; done; }
# line_of <share/path>: the record line of its copy on /mnt/user0 as stat sees it now
line_of() { printf '%s|user0/%s\n' "$(stat -c '%s|%.9Y|%.9Z' "/mnt/user0/$1")" "$1"; }
# recorded <key>...: exactly these keys in the record
recorded() {
    check "the record holds exactly${*:+ $*}" "$( (($#)) && printf '%s\n' "$@" | LC_ALL=C sort)" \
        "$(sed -E "s/$SYNC_RECORD_KEY//" "$SYNC_RECORD" 2>/dev/null | LC_ALL=C sort)"
}

begin "a file renamed after its sync is synced under its new name" synchronizeCache yes
mk cache sh/r/new.txt
old sh/r/new.txt
mkdir -p /mnt/user0/sh/r "$T/record"
cp -a /mnt/cache/sh/r/new.txt /mnt/user0/sh/r/old.txt
line_of sh/r/old.txt >"$SYNC_RECORD"
plan sh/r/new.txt
actions "sync unrecorded from primary: sh/r/new.txt"
run_moves
cache_is sh sh/r sh/r/new.txt
array_is sh sh/r sh/r/new.txt sh/r/old.txt
recorded user0/sh/r/new.txt user0/sh/r/old.txt
check "the new name's line is its copy" "$(line_of sh/r/new.txt)" "$(grep -F '|user0/sh/r/new.txt' "$SYNC_RECORD")"
counter MOVEDFILES 1
counter SYNCFAILED 0

begin "a copy already on the secondary storage is recorded and left as it is" synchronizeCache yes
mk cache 'sh/a|b c.txt'
old 'sh/a|b c.txt'
copy_of 'sh/a|b c.txt'
before=$(stat -c '%i %.9Z' '/mnt/user0/sh/a|b c.txt')
plan 'sh/a|b c.txt'
actions "sync unrecorded from primary: sh/a|b c.txt"
run_moves
check "the copy is the same file, unchanged" "$before" "$(stat -c '%i %.9Z' '/mnt/user0/sh/a|b c.txt')"
check "the record is its line" "$(line_of 'sh/a|b c.txt')" "$(cat "$SYNC_RECORD")"

begin "a different file already in its place is left as it is" synchronizeCache yes
mk cache sh/c.txt
old sh/c.txt
mkdir -p /mnt/user0/sh
printf 'other\n' >/mnt/user0/sh/c.txt
plan sh/c.txt
actions "sync unrecorded from primary: sh/c.txt"
run_moves
check "the file in its place keeps its content" other "$(cat /mnt/user0/sh/c.txt)"
recorded
log_has 'Not synchronized, a different file is already at "/mnt/user0/sh/c.txt": move one of the two aside to synchronize it'
log_lacks 'Synchronizing'
counter SYNCCONFLICTFILES 1
counter NOTMOVEDFILES 0
counter SYNCFAILED 0
counter REMAINING_CACHE_FILES 0

begin "the log lists the first names left for a different file in their place, then how many more" synchronizeCache yes
mk cache sh/l/1.txt sh/l/2.txt sh/l/3.txt
old sh/l/1.txt sh/l/2.txt sh/l/3.txt
mkdir -p /mnt/user0/sh/l
for n in 1 2 3; do printf 'other\n' >/mnt/user0/sh/l/$n.txt; done
plan sh/l/1.txt sh/l/2.txt sh/l/3.txt
DIFFER_LIST_MAX=2 run_moves
log_count 2 'Not synchronized, a different file is already at'
log_has 'Also left for a different file already in their place: 1 more names, not listed'
counter SYNCCONFLICTFILES 3
# the next run, with two of them
fresh synchronizeCache yes
plan sh/l/1.txt sh/l/2.txt
DIFFER_LIST_MAX=2 run_moves
log_count 2 'Not synchronized, a different file is already at'
log_lacks 'Also left for'

begin "a recorded file not changed since the last sync stays as it is" synchronizeCache yes
mk cache sh/k.txt
old sh/k.txt
copy_of sh/k.txt
mkdir -p "$T/record"
line_of sh/k.txt >"$SYNC_RECORD"
plan sh/k.txt
actions "keep on primary: sh/k.txt"

begin "a file replaced under a recorded name by one with an older date replaces its copy" synchronizeCache yes
mk cache sh/v/s.txt sh/v/t.txt
copy_of sh/v/s.txt sh/v/t.txt
# s.txt differs from its copy in size only, t.txt in mtime only
touch -d "$OLD" /mnt/user0/sh/v/s.txt
touch -d 2019-01-01 /mnt/user0/sh/v/t.txt
mkdir -p "$T/record"
{ line_of sh/v/s.txt; line_of sh/v/t.txt; } >"$SYNC_RECORD"
printf 'a longer file\n' >/mnt/cache/sh/v/s.txt
printf 'y\n' >/mnt/cache/sh/v/t.txt
old sh/v/s.txt sh/v/t.txt
plan sh/v/s.txt sh/v/t.txt
actions "sync from primary: sh/v/s.txt
sync from primary: sh/v/t.txt"
run_moves
check "the copies hold the new content" "a longer file y" "$(cat /mnt/user0/sh/v/s.txt /mnt/user0/sh/v/t.txt | paste -sd' ')"
check "the record holds the new copies" "$( (line_of sh/v/s.txt; line_of sh/v/t.txt) | LC_ALL=C sort)" "$(LC_ALL=C sort "$SYNC_RECORD")"

begin "with a share's own ctime setting on, a recorded copy of the same size stays as it is" synchronizeCache yes
mk cache sh/k.txt
old sh/k.txt
copy_of sh/k.txt
mkdir -p "$T/record"
line_of sh/k.txt >"$SYNC_RECORD"
LISTM=0 TIME=$(date -d 2021-01-01 +%s) plan sh/k.txt
actions "keep on primary: sh/k.txt"

begin "with only the global ctime setting on, a share listing mtimes still compares its recorded copy's mtime" synchronizeCache yes
mk cache sh/k.txt
old sh/k.txt
copy_of sh/k.txt
mkdir -p "$T/record"
line_of sh/k.txt >"$SYNC_RECORD"
CTIME=yes TIME=$(date -d 2021-01-01 +%s) plan sh/k.txt
actions "sync from primary: sh/k.txt"

begin "a folder syncs by date only" synchronizeCache yes
mkdir -p /mnt/cache/sh/e
touch -d "$OLD" /mnt/cache/sh/e
plan sh/e
actions "keep on primary: sh/e"

begin "a file at the sync size limit syncs neither by date nor for want of a copy" synchronizeCache yes
mk cache sh/big.txt sh/new.txt
old sh/big.txt
RULES="sh|1|2|0|0|0" plan sh/big.txt sh/new.txt
actions "keep on primary: sh/big.txt
keep on primary: sh/new.txt"

begin "a file changed since the last sync replaces its copy, as before, and is recorded" synchronizeCache yes
mk cache sh/d.txt
mkdir -p /mnt/user0/sh
printf 'older\n' >/mnt/user0/sh/d.txt
plan sh/d.txt
actions "sync from primary: sh/d.txt"
run_moves
check "the copy has the new content" x "$(cat /mnt/user0/sh/d.txt)"
recorded user0/sh/d.txt

begin "a new hardlink to a recorded file syncs with it, and its copy joins the recorded one" synchronizeCache yes
mk cache sh/h/a.txt
old sh/h/a.txt
copy_of sh/h/a.txt
mkdir -p "$T/record"
line_of sh/h/a.txt >"$SYNC_RECORD"
ln /mnt/cache/sh/h/a.txt /mnt/cache/sh/h/b.txt
plan sh/h/a.txt sh/h/b.txt
actions "sync unrecorded from primary: sh/h/a.txt
sync unrecorded from primary: sh/h/b.txt"
run_moves
array_is sh sh/h sh/h/a.txt sh/h/b.txt
check "the copies are one file" "$(stat -c %i /mnt/user0/sh/h/a.txt)" "$(stat -c %i /mnt/user0/sh/h/b.txt)"
recorded user0/sh/h/a.txt user0/sh/h/b.txt
counter SYNCFAILED 0

begin "a hardlink group whose recorded name changed syncs whole, with one action" synchronizeCache yes
mk cache sh/j/a.txt
old sh/j/a.txt
copy_of sh/j/a.txt
mkdir -p "$T/record"
line_of sh/j/a.txt >"$SYNC_RECORD"
printf 'a longer file\n' >/mnt/cache/sh/j/a.txt
old sh/j/a.txt
ln /mnt/cache/sh/j/a.txt /mnt/cache/sh/j/b.txt
plan sh/j/a.txt sh/j/b.txt
actions "sync from primary: sh/j/a.txt
sync from primary: sh/j/b.txt"
run_moves
check "the copies are one file with the new content" "$(stat -c %i /mnt/user0/sh/j/a.txt) a longer file" "$(stat -c %i /mnt/user0/sh/j/b.txt) $(cat /mnt/user0/sh/j/b.txt)"
recorded user0/sh/j/a.txt user0/sh/j/b.txt
counter SYNCFAILED 0

begin "a hardlink group with a different file at one name is left whole, a name gone before its turn counted as gone" synchronizeCache yes
mk cache sh/g/a.txt
old sh/g/a.txt
copy_of sh/g/a.txt
mkdir -p "$T/record"
line_of sh/g/a.txt >"$SYNC_RECORD"
ln /mnt/cache/sh/g/a.txt /mnt/cache/sh/g/b.txt
ln /mnt/cache/sh/g/a.txt /mnt/cache/sh/g/c.txt
printf 'other\n' >/mnt/user0/sh/g/b.txt
plan sh/g/a.txt sh/g/b.txt sh/g/c.txt
rm /mnt/cache/sh/g/c.txt
run_moves
array_is sh sh/g sh/g/a.txt sh/g/b.txt
check "the file at the second name keeps its content" other "$(cat /mnt/user0/sh/g/b.txt)"
log_count 1 'Not synchronized, a different file is already at'
recorded user0/sh/g/a.txt
counter SYNCCONFLICTFILES 2
counter VANISHEDFILES 1
counter SYNCFAILED 0

begin "a verified move takes its name out of the record" synchronizeCache yes
mk cache sh/m.txt
mkdir -p "$T/record"
printf '%s\n' '2|1.0|1.0|user0/sh/m.txt' '2|1.0|1.0|user0/sh/kept.txt' >"$SYNC_RECORD"
SYNC_RECORD_OK=yes
row 'move from primary' f sh/m.txt | list
run_moves
array_is sh sh/m.txt
recorded user0/sh/kept.txt

begin "a file synced or moved to the secondary storage from unattended storage is recorded, or taken out" synchronizeCache yes
mk other sh/s.txt sh/o.txt
mkdir -p "$T/record"
printf '%s\n' '2|1.0|1.0|user0/sh/o.txt' >"$SYNC_RECORD"
SYNC_RECORD_OK=yes
# s.txt as the planner stages it: to the primary, then synced from there
{ row 'move unattended to primary' f sh/s.txt; row 'sync unattended to secondary' f sh/s.txt; row 'move unattended to secondary' f sh/o.txt; } | list
run_moves
cache_is sh sh/s.txt
array_is sh sh/o.txt sh/s.txt
recorded user0/sh/s.txt

begin "test mode records none of its own syncs" synchronizeCache yes testmode yes
mk cache sh/t.txt
plan sh/t.txt
actions "sync from primary: sh/t.txt"
run_moves
array_is
check "nothing written for the record" "" "$(ls -A "$T/record" 2>/dev/null)"

begin "a share that does not synchronize syncs no file the record lacks" synchronizeCache no
mk cache sh/n.txt
old sh/n.txt
plan sh/n.txt
actions "keep on primary: sh/n.txt"

begin "a share whose own Synchronize is on under a global off syncs a file the record lacks" synchronizeCache no
mk cache sh/n.txt
old sh/n.txt
SHARESYNC=yes plan sh/n.txt
actions "sync unrecorded from primary: sh/n.txt"

begin "a record that cannot be read or updated: the run syncs by date only and records nothing" synchronizeCache yes
mk cache sh/u.txt sh/v.txt
old sh/u.txt
# a file where the record's folder must be
: >"$T/record"
plan sh/u.txt sh/v.txt
log_has "Warning: cannot read or update the sync record \"$SYNC_RECORD\": this run syncs by date only, and records nothing"
actions "keep on primary: sh/u.txt
sync from primary: sh/v.txt"
run_moves
array_is sh sh/v.txt
log_lacks 'sync record'

begin "a record folder that is a link, or not the run's own, is never written through" synchronizeCache yes
mk cache sh/u.txt
rm -rf "$T/elsewhere"
mkdir "$T/elsewhere"
ln -s "$T/elsewhere" "$T/record"
plan sh/u.txt
log_has "Warning: cannot read or update the sync record \"$SYNC_RECORD\""
actions "sync from primary: sh/u.txt"
run_moves
array_is sh sh/u.txt
check "nothing written through the link" "" "$(ls -A "$T/elsewhere")"
rm "$T/record"
mkdir -m 700 "$T/record"
chown 4242 "$T/record"
plan sh/u.txt
log_has "Warning: cannot read or update the sync record \"$SYNC_RECORD\""
run_moves
check "nothing written in a folder that is not the run's own" "" "$(ls -A "$T/record")"

begin "a changes file that is empty or not a file leaves the record as it is" synchronizeCache yes
mkdir -p "$T/record"
printf '%s\n' '2|1.0|1.0|user0/sh/a.txt' '2|1.0|1.0|user0/sh/b.txt' >"$SYNC_RECORD"
: >"$SYNC_RECORD.changes"
plan
recorded user0/sh/a.txt user0/sh/b.txt
check "the empty changes file is gone" no "$([ -e "$SYNC_RECORD.changes" ] && echo yes || echo no)"
mkdir "$SYNC_RECORD.changes"
plan
log_has "Warning: cannot read or update the sync record \"$SYNC_RECORD\""
recorded user0/sh/a.txt user0/sh/b.txt

begin "the changes a stopped run left reach the record at the next run, the last line for a key winning" synchronizeCache yes
mkdir -p "$T/record"
printf '%s\n' '2|1.0|1.0|user0/sh/kept.txt' '2|1.0|1.0|user0/sh/moved.txt' '2|1.0|1.0|user0/sh/again.txt' >"$SYNC_RECORD"
printf '%s\n' '+2|2.0|2.0|user0/sh/new.txt' '-user0/sh/moved.txt' '+2|3.0|3.0|user0/sh/back.txt' '-user0/sh/back.txt' \
    '-user0/sh/again.txt' '+2|4.0|4.0|user0/sh/again.txt' >"$SYNC_RECORD.changes"
plan
check "the record" "$(printf '%s\n' '2|1.0|1.0|user0/sh/kept.txt' '2|2.0|2.0|user0/sh/new.txt' '2|4.0|4.0|user0/sh/again.txt' | LC_ALL=C sort)" \
    "$(LC_ALL=C sort "$SYNC_RECORD")"
check "the changes file is gone" no "$([ -e "$SYNC_RECORD.changes" ] && echo yes || echo no)"

begin "a file gone from the primary before its turn is counted as gone, not as a different file in its place" synchronizeCache yes
mk cache sh/w.txt
old sh/w.txt
mkdir -p /mnt/user0/sh
printf 'other\n' >/mnt/user0/sh/w.txt
plan sh/w.txt
rm /mnt/cache/sh/w.txt
run_moves
check "the file in its place keeps its content" other "$(cat /mnt/user0/sh/w.txt)"
log_lacks 'Not synchronized'
counter SYNCCONFLICTFILES 0
counter VANISHEDFILES 1

begin "a change that cannot be noted stops the notes for the rest of the run, and the syncs go on" synchronizeCache yes
mk cache sh/p/1.txt sh/p/2.txt
plan sh/p/1.txt sh/p/2.txt
# a folder where the changes file goes
mkdir -p "$SYNC_RECORD.changes"
run_moves
array_is sh sh/p sh/p/1.txt sh/p/2.txt
log_count 1 "Warning: cannot write to \"$SYNC_RECORD.changes\": this run records nothing more in the sync record"
check "no record" no "$([ -e "$SYNC_RECORD" ] && echo yes || echo no)"
counter SYNCFAILED 0

begin "a record the run cannot update keeps its changes, and the next run applies them" synchronizeCache yes
mk cache sh/q.txt
plan sh/q.txt
mkdir -p "$T/fake"
printf '#!/bin/sh\ncase "$1" in *sync.record.*) exit 1 ;; esac\nexec %q "$@"\n' "$(command -v mktemp)" >"$T/fake/mktemp"
chmod 755 "$T/fake/mktemp"
PATH=$T/fake:$PATH run_moves
log_has "Warning: cannot update the sync record \"$SYNC_RECORD\": the next run tries again"
check "no record yet" no "$([ -e "$SYNC_RECORD" ] && echo yes || echo no)"
plan
recorded user0/sh/q.txt

begin "the next load removes a temporary record a stopped merge left, and keeps the changes" synchronizeCache yes
mkdir -p "$T/record"
printf 'x\n' >"$SYNC_RECORD.Ab12Cd"
printf '%s\n' '+2|1.0|1.0|user0/sh/c.txt' >"$SYNC_RECORD.changes"
plan
check "the stopped merge's temporary record is gone" no "$([ -e "$SYNC_RECORD.Ab12Cd" ] && echo yes || echo no)"
recorded user0/sh/c.txt

begin "a record path that is not a file is reported, never read as an empty record" synchronizeCache yes
mkdir -p -m 700 "$T/record" "$SYNC_RECORD"
plan
log_has "Warning: cannot read or update the sync record \"$SYNC_RECORD\""
counter SYNC_RECORD_OK no
check "nothing written into it" "" "$(ls -A "$SYNC_RECORD")"

begin "a record folder others can write to is never written through" synchronizeCache yes
mkdir -p "$T/record"
chmod 777 "$T/record"
plan
log_has "Warning: cannot read or update the sync record \"$SYNC_RECORD\""
counter SYNC_RECORD_OK no
check "nothing written into it" "" "$(ls -A "$T/record")"

begin "a synced folder is not recorded" synchronizeCache yes
mkdir -p /mnt/cache/sh/e "$T/record"
row 'sync from primary' d sh/e | list
SYNC_RECORD_OK=yes
run_moves
array_is sh sh/e
recorded

begin "a verified move drops the key of the copy it took and of the one it replaced" synchronizeCache yes
mk disk1 sh/p.txt
mk other sh/u.txt sh/v.txt
mkdir -p "$T/record"
printf '%s\n' '2|1.0|1.0|user0/sh/p.txt' '2|1.0|1.0|other/sh/u.txt' '2|1.0|1.0|other/sh/v.txt' '2|1.0|1.0|user0/sh/v.txt' \
    '2|1.0|1.0|user0/sh/keep.txt' >"$SYNC_RECORD"
{ row 'move from secondary' f sh/p.txt; row 'move unattended to primary' f sh/u.txt; row 'move unattended to secondary' f sh/v.txt; } | list
SYNC_RECORD_OK=yes
run_moves
cache_is sh sh/p.txt sh/u.txt
array_is sh sh/v.txt
recorded user0/sh/keep.txt

begin "a copy rsync reported an error for is not recorded, and a move it reported one for still drops its key" synchronizeCache yes
mk cache sh/e.txt sh/m.txt
rm -rf "$T/bin"
mkdir -p "$T/record" "$T/bin"
printf '%s\n' '2|1.0|1.0|user0/sh/m.txt' >"$SYNC_RECORD"
printf '#!/bin/bash\n/usr/bin/rsync "$@"\nexit 23\n' >"$T/bin/rsync"
chmod 755 "$T/bin/rsync"
{ row 'sync from primary' f sh/e.txt; row 'move from primary' f sh/m.txt; } | list
SYNC_RECORD_OK=yes
PATH="$T/bin:$PATH" run_moves
rm -rf "$T/bin"
array_is sh sh/e.txt sh/m.txt
recorded
counter TOOLERRORFILES 2
counter SYNCFAILED 1

begin "the free-space warning counts a dated sync's bytes, not those of a sync for want of a recorded copy"
mkdir -p /mnt/cache/sh
printf 'four\n' >/mnt/cache/sh/a.txt
row 'sync unrecorded from primary' f sh/a.txt | list
(array_disk_space() { echo "disk1 100 2"; } && warnMinimumFreeSpace >/dev/null)
log_lacks 'Minimum free space'
row 'sync from primary' f sh/a.txt | list
(array_disk_space() { echo "disk1 100 2"; } && warnMinimumFreeSpace >/dev/null)
log_has 'Warning: [sh] Minimum free space (not set) is below the largest file to move (5 B) and disk1 has 2 B free for 5 B'

finish
