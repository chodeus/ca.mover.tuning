#!/bin/bash
# The sync record: the real processTheMoves notes each copy and move it verified, and the next load, or the end of the run,
# applies the notes to the record.
. "$(dirname "$0")/lib.sh"

MARK=1767323045

# plan [share/path]...: decideMoveActions on these files and folders of /mnt/cache, rows of share sh, which keeps them and
# syncs with lastCacheSync at MARK
plan() {
    local p m s n i y
    FILTERED_FILELIST=$T/filtered HELD_FILELIST=$T/held overrideFlag=0
    : >"$HELD_FILELIST"
    {
        echo 'PRIMARYSTORAGENAME|SECONDARYSTORAGENAME|SHARENAME|SHAREUSECACHE|MODIFYTIME|PRIMARYSIZETHRESH|POOLUSED|FILESIZE|SPARSENESS|NBLINKS|INODE|FILETYPE|FILEPATH'
        for p; do
            read -r m s n i < <(stat -c '%Y %s %h %i' "/mnt/cache/$p")
            y=f
            [ ! -d "/mnt/cache/$p" ] || y=d
            printf 'cache|user0|sh|yes|%s|0|0|%s|0|%s|%s|%s|/mnt/cache/%s\n' "$m" "$s" "$n" "$i" "$y" "$p"
        done
    } >"$FILTERED_FILELIST"
    SHARE_PLAN_RULES="sh|1|0|0|0|0" SHARE_SYNC_SETTINGS="$SYNCHRONIZECACHE|$MARK|sh"$'\n'
    decideMoveActions >/dev/null 2>"$T/plan.err"
    check "decideMoveActions wrote nothing on stderr" "" "$(cat "$T/plan.err")"
}
# actions <expected>: each row's action and path, as the planner wrote them
actions() {
    check "the planner's actions" "$1" "$(awk -F'|' 'NR > 1 { p = $15; for (i = 16; i <= NF; i++) p = p "|" $i; print $11 ": " p }' "$MOVER_ACTIONLIST")"
}
# recorded <key>...: exactly these keys in the record
recorded() {
    check "the record holds exactly${*:+ $*}" "$( (($#)) && printf '%s\n' "$@" | LC_ALL=C sort)" \
        "$(sed -E "s/$SYNC_RECORD_KEY//" "$SYNC_RECORD" 2>/dev/null | LC_ALL=C sort)"
}

begin "a file changed since the last sync replaces its copy, as before, and is recorded" synchronizeCache yes
mk cache sh/d.txt
mkdir -p /mnt/user0/sh
printf 'older\n' >/mnt/user0/sh/d.txt
plan sh/d.txt
actions "sync from primary: sh/d.txt"
run_moves
check "the copy has the new content" x "$(cat /mnt/user0/sh/d.txt)"
recorded user0/sh/d.txt

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

begin "a record that cannot be read or updated: the run records nothing" synchronizeCache yes
mk cache sh/v.txt
# a file where the record's folder must be
: >"$T/record"
plan sh/v.txt
log_has "Warning: cannot read or update the sync record \"$SYNC_RECORD\": this run records nothing"
actions "sync from primary: sh/v.txt"
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

begin "a synced folder is not recorded" synchronizeCache yes
mkdir -p /mnt/cache/sh/e "$T/record"
row 'sync from primary' d sh/e | list
SYNC_RECORD_OK=yes
run_moves
array_is sh sh/e
recorded

begin "a verified move off the secondary or unattended storage drops the key of the copy it took" synchronizeCache yes
mk disk1 sh/p.txt
mk other sh/u.txt
mkdir -p "$T/record"
printf '%s\n' '2|1.0|1.0|user0/sh/p.txt' '2|1.0|1.0|other/sh/u.txt' '2|1.0|1.0|user0/sh/keep.txt' >"$SYNC_RECORD"
{ row 'move from secondary' f sh/p.txt; row 'move unattended to primary' f sh/u.txt; } | list
SYNC_RECORD_OK=yes
run_moves
cache_is sh sh/p.txt sh/u.txt
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

finish
