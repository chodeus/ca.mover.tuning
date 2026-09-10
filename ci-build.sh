#!/bin/bash
# Fork test shim: adapts this repo's package layout to the chodeus-ops build contract
# (--version <v> --branch <b>, writes dist/<pkg>.txz and stamps the manifest). Not for upstream.
set -euo pipefail
version=""; branch=""
while [ $# -gt 0 ]; do case "$1" in --version) version="$2"; shift 2 ;; --branch) branch="$2"; shift 2 ;; *) shift ;; esac; done
[ -n "$version" ] || { echo "--version required"; exit 1; }
name=ca.mover.tuning; root=$(pwd); src="$root/source/$name"; plg="$root/plugins/$name.plg"; out="$root/dist"
mkdir -p "$out"; tmp=$(mktemp -d)
sed -i "s/^version=.*/version=\"$version\"/" "$src/usr/local/emhttp/plugins/$name/default.cfg"
(cd "$src" && find . -type f ! -iname pkg_build.sh -exec cp --parents -f -t "$tmp/" {} +)
(cd "$tmp" && find . -type d -exec chmod 755 {} + && find ./ | LC_COLLATE=C sort | sed '2,$s,^\./,,' | tar --no-recursion --owner=0 --group=0 -T - -cJf "$out/$name-$version-x86_64-1.txz")
md5=$(md5sum "$out/$name-$version-x86_64-1.txz" | cut -d' ' -f1)
sed -i -e "s|^<!ENTITY version   \".*\">|<!ENTITY version   \"$version\">|" -e "s|^<!ENTITY md5       \".*\">|<!ENTITY md5       \"$md5\">|" \
       -e 's|^<!ENTITY github    ".*">|<!ENTITY github    "chodeus/\&name;">|' \
       -e "s|^<!ENTITY branch    \".*\">|<!ENTITY branch    \"$branch\">|" \
       -e 's|<URL>https://github.com/&github;/raw/&branch;/archive/&name;-&version;-x86_64-1.txz</URL>|<URL>https://github.com/\&github;/releases/download/v\&version;/\&name;-\&version;-x86_64-1.txz</URL>|' "$plg"
grep -q '/releases/download/v&version;/' "$plg" || { echo "manifest URL rewrite failed"; exit 1; }
echo "built $out/$name-$version-x86_64-1.txz md5 $md5"
