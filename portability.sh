#!/usr/bin/env bash
# portability.sh — refuse the GNU-only constructs that do not exist in a
# BSD userland, which is what macOS ships.
#
# This gate exists because of a real defect: `sed -n 's/…",\?$/\1/p'` used
# `\?`, a GNU extension in a basic regular expression. GNU sed matched it,
# BSD sed never did, and so every command that resolved a version remotely
# answered `Version '26' not found` on a Mac while vibe itself worked. The
# class is invisible on Linux by construction, so only a check can catch it.
#
# usage: portability.sh [FILE…]   (default: nvm.sh beside this script)
# exit:  0 nothing GNU-only found; 1 findings, one per line with its reason
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES=("$@"); [ "${#FILES[@]}" -gt 0 ] || FILES=("$HERE/nvm.sh")
findings=0

# Each row: <extended regexp>\t<what is wrong, and the portable form>.
# The regexps are deliberately narrow: a mention inside a comment is still
# a finding, because a comment is where the next person copies from.
while IFS=$'\t' read -r pattern reason; do
    [ -n "$pattern" ] || continue
    case "$pattern" in \#*) continue ;; esac
    for file in "${FILES[@]}"; do
        while IFS=: read -r line text; do
            [ -n "$line" ] || continue
            printf '%s:%s: %s\n' "${file##*/}" "$line" "$reason" >&2
            printf '    %s\n' "$(printf '%s' "$text" | sed 's/^[[:space:]]*//')" >&2
            findings=$((findings + 1))
        done < <(grep -nE "$pattern" "$file" 2>/dev/null || true)
    done
done <<'ROWS'
sed[^|]*\\\?	`\?` is a GNU extension in a BRE; BSD sed never matches it. Use `\{0,1\}`, or a negated class as the neighbouring readers do.
sed[^|]*\\\+	`\+` is a GNU extension in a BRE; BSD sed never matches it. Use `\{1,\}` or `xx*`.
sed[^|]*\\\|	`\|` is a GNU extension in a BRE; BSD sed never matches it. Write two expressions, or use `-E` with `|`.
sed -i	`sed -i` takes a mandatory suffix on BSD. Write to a temporary file and `mv` it.
grep -P	`grep -P` is GNU-only. Use `grep -E`, or awk.
sort -V	`sort -V` is GNU-only. Sort with awk, or ask vibe for the order.
readlink -f	`readlink -f` is GNU-only. Use a `cd … && pwd` subshell.
date -d	`date -d` is GNU-only; BSD date takes `-v`/`-f`. Avoid date arithmetic.
head -n -[0-9]	`head -n -N` is GNU-only. Count the lines, or use awk/sed.
tail -n \+[0-9]+[^0-9]	`tail -n +N` is portable, but verify; prefer awk `NR>=N`.
(sed|grep)[^|]*\\[sw]	`\s` / `\w` are GNU extensions. Use `[[:space:]]` / `[[:alnum:]_]`.
(asort|asorti|gensub|systime|strftime|toupper\(\$0\)[^)]*,)	a gawk-only function; BSD awk has none of these. Use POSIX awk only.
echo -e	`echo -e` is not portable. Use `printf`.
\bseq \	`seq` is absent on some BSDs. Use a `while` loop.
mktemp -p	`mktemp -p` is GNU-only. Use `mktemp "${TMPDIR:-/tmp}/x.XXXXXX"`.
ROWS

if [ "$findings" -gt 0 ]; then
    printf 'portability.sh: %d GNU-only construct(s) — this file is sourced on macOS too\n' "$findings" >&2
    exit 1
fi
printf 'portability.sh: %s — no GNU-only constructs\n' "$(for f in "${FILES[@]}"; do printf '%s ' "${f##*/}"; done)"
