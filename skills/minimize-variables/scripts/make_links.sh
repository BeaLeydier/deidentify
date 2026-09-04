#!/bin/bash
# make_links.sh <release folder> <dta list file> <link root> <python> <code folder> <master.do ...>
# find_used_variables splits its file lists on spaces, so build a space-free symlink tree
# (data/<name>.dta, do/<nnn>_<name>.do) that resolves to the release files. Only the do-files
# the master actually reaches (see reachable_dofiles.py) are linked; the unreachable ones are
# written to <link root>/unreachable_dofiles.txt for the reviewer. Read-only.
REL="$1"; LIST="$2"; L="$3"; PY="$4"; CODE="$5"; shift 5
rm -rf "$L"; mkdir -p "$L/data" "$L/do"
while IFS= read -r line; do
  rel="${line#*/}"
  ln -s "$REL/$rel" "$L/data/$(echo "$rel" | sed 's|/|__|g; s| |_|g')"
done < "$LIST"
"$PY" "$CODE/reachable_dofiles.py" "$REL" "$@" > "$L/reachable_dofiles.txt" 2> "$L/unreachable_dofiles.txt"
i=0
while IFS= read -r f; do
  i=$((i+1)); ln -s "$f" "$L/do/$(printf '%03d' $i)_$(basename "$f" | tr ' ' '_')"
done < "$L/reachable_dofiles.txt"
echo "linked $(ls "$L/data" | wc -l) datasets, $(ls "$L/do" | wc -l) reachable do-files; $(grep -c '^  ' "$L/unreachable_dofiles.txt") unreachable ignored"
