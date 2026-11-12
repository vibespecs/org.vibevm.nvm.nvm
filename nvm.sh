#!/bin/sh
# nvm.sh — nvm, on vibe: nvm's command surface, and the state nvm owns.
#
#   . "$(vibe app describe org.vibevm.nvm/nvm --json | …)"/nvm.sh
#   nvm install 22.9.0
#   nvm use --lts
#
# It is sourced, exactly as nvm-sh's `nvm.sh` is, because `nvm use` changes
# the **current** shell: a program could not. Sourcing defines one public
# function, `nvm`, plus helpers in the reserved `__vibenvm_` namespace.
#
# **Every version is vibe's answer; the state nvm owns is this file's.** That
# division is the whole design, so it is written out rather than inferred:
#
#   vibe's, and never recomputed here — every version a spelling selects
#   (`vibe app env`, `vibe install -g --plan-only`), every install
#   (`vibe install -g`), every activation (`vibe app env`), the content of
#   every listing (`vibe app versions`), the slot's default (`vibe app use`),
#   the declared version file, the channels behind `lts` and `latest`, the
#   download cache and every digest. Nothing here parses a release index, a
#   `.nvmrc`, a channel or a semver range.
#
#   this file's, because the concept is nvm's and vibe has no counterpart to
#   read — the **alias store** under `<root>/alias` (nvm's own layout, byte
#   for byte), the **version categories** of `--only=` and `$NVM_ONLY` with
#   the `<root>/.lts-status` record they need, the **colour palette** of
#   `set-colors` and `$NVM_COLORS` and the rows this file paints with it, the
#   per-version **install locks** under `<root>/.cache/locks`, and nvm's
#   **npm prefix hygiene** (`$PREFIX`, `$NPM_CONFIG_PREFIX`, the four npmrc
#   levels). Each is a thing nvm's users have on disk and in their fingers;
#   none of them is a version decision, and none of them hides a gap in vibe
#   behind a shim nobody audits (PROP-075 `#VIBENVM`).
#
# The one alias nvm's users really have — `default` — is deliberately **not**
# in that store: it is the slot default, which is vibe's own fact, read and
# written through `vibe app use`. One source of truth, by construction.
#
# The surface it maps is PROP-075 `#VIBENVM-MAPPING`, and it maps all of it:
# this file carries no accepted gap, and every string, exit code and argument
# form below was taken from the pinned nvm-sh v0.41.0 rather than recalled.
#
# Sourcing arguments, nvm's own: `--no-use` (apply nothing now — the
# default here, since vibe's own PATH is already the user's) and `--install`
# (install the slot's runtime now, as nvm's installer does).

# ---------------------------------------------------------------- facts ---

# This package's own revision: the template revision of
# `org.vibevm.nvm/nvm`, bumped with every revision of this file. It is what
# `nvm --vibenvm-version` prints and what `nvm debug` reports, and it is
# never what `nvm --version` prints.
VIBENVM_REVISION='1.0.1'
# The nvm release whose surface this file carries, baked in as the fallback
# for the derivation in the plumbing below — which is what `nvm --version`
# actually prints, as nvm's own `--version` prints an nvm version.
NVM_COMPAT='0.41.0'
# The slot and the package the shim drives. One slot, by construction.
VIBENVM_SLOT='node'
VIBENVM_PACKAGE='org.vibevm.node/node'

# ------------------------------------------------------------- plumbing ---

__vibenvm_echo() { printf '%s\n' "$*"; }
__vibenvm_err() { printf '%s\n' "$*" >&2; }

# The nvm version this installation implements, for `nvm --version`. vibe
# names an installed application's directory after the installation key, so
# the file this shell is sourcing sits at
# `…/org.vibevm.nvm.nvm@<version>/nvm.sh` and the version is the `@` tail of
# its own directory. Nothing here decides that version: it reads the one vibe
# chose when it placed this file, which is why a new nvm version needs no
# edit here and only a `[template.versions]` row.
#
# Where the shell cannot say which file is being sourced — dash's `$0` is the
# shell's name and not the file's — the baked constant stands in, which is
# the whole reason there is one.
__vibenvm_derive_compat() {
    __vibenvm_self=''
    # `$BASH_SOURCE` is an array and only bash may subscript one, so the
    # subscript is written inside `eval`, where no other shell parses it.
    if [ -n "${BASH_VERSION-}" ]; then
        __vibenvm_self="$(eval 'printf "%s\n" "${BASH_SOURCE[0]-}"' 2>/dev/null)"
    fi
    [ -n "$__vibenvm_self" ] || __vibenvm_self="$0"
    case "$__vibenvm_self" in
        */*) __vibenvm_self="${__vibenvm_self%/*}" ;;
        *) return 1 ;;
    esac
    case "$__vibenvm_self" in
        *@*) __vibenvm_self="${__vibenvm_self##*@}" ;;
        *) return 1 ;;
    esac
    # A version, or the parse found something else and the fallback wins.
    case "$__vibenvm_self" in
        [0-9]*) ;;
        *) return 1 ;;
    esac
    case "$__vibenvm_self" in
        *[!0-9A-Za-z.+-]*) return 1 ;;
    esac
    __vibenvm_echo "$__vibenvm_self"
}

NVM_COMPAT="$(__vibenvm_derive_compat 2>/dev/null || __vibenvm_echo "$NVM_COMPAT")"

# The vibe binary, as any user has it: on PATH. A shim that guessed at an
# installation root would be guessing about the very thing vibe owns.
__vibenvm_vibe() {
    if command -v vibe >/dev/null 2>&1; then
        command vibe "$@"
        return $?
    fi
    __vibenvm_err 'vibenvm: `vibe` is not on PATH, and vibenvm is vibe'\''s own command surface'
    return 127
}

# nvm's version spellings, as a vibe requirement or channel. This is the
# one translation table the file carries, and it translates *spelling*
# only: what each requirement selects is vibe's decision, never ours.
#
#   v22.9.0 / 22.9.0  one release           -> `=22.9.0`
#   22.9              the newest of a minor -> `~22.9`
#   22                the newest of a major -> `22`
#   node/stable       the newest release    -> `latest`
#   lts, lts/*        the newest LTS        -> `lts`
#   lts/jod           the newest of a line  -> `lts/jod`
#   default           the slot's default    -> `=<that version>`
#
# Everything else is handed to vibe as written, so a vibe requirement a
# user already knows (`^22`, `>=20 <23`) works here too.
__vibenvm_requirement() {
    __vibenvm_req_value="$1"
    case "$__vibenvm_req_value" in
        v[0-9]*) __vibenvm_req_value="${__vibenvm_req_value#v}" ;;
    esac
    case "$__vibenvm_req_value" in
        node | stable | latest)
            __vibenvm_echo 'latest'
            return 0
            ;;
        default)
            # nvm's `default` is the version a new shell gets, and in vibe
            # that is the slot's default — not a channel, which is why
            # handing `default` to vibe as a requirement was wrong
            # (PROP-075 `#VIBENVM-MAPPING`: "`default` is the slot
            # default"). The version is read out of vibe's own answer and
            # resolved nowhere here.
            __vibenvm_req_default="$(__vibenvm_default_version)"
            if [ -z "$__vibenvm_req_default" ]; then
                __vibenvm_err "nvm: the \`$VIBENVM_SLOT\` slot has no default version; \`nvm install <version> --default\` sets one"
                return 3
            fi
            __vibenvm_echo "=$__vibenvm_req_default"
            return 0
            ;;
        lts | 'lts/*')
            __vibenvm_echo 'lts'
            return 0
            ;;
        lts/*)
            __vibenvm_echo "$__vibenvm_req_value"
            return 0
            ;;
        iojs | iojs-* | io.js)
            # `org.vibevm.node/node` carries no io.js version, so an io.js
            # spelling selects nothing. That is not a refusal: it is the same
            # answer nvm gives where no io.js is available, and the callers
            # turn it into `N/A` as they do for any other miss.
            return 3
            ;;
        '')
            return 1
            ;;
    esac
    # **A named user alias is a spelling too.** nvm resolves one here and
    # then resolves what it points at — `nvm_resolve_local_alias` follows
    # the chain and, unless the result is an **exactly** installed
    # version, hands it to `nvm_version` (nvm.sh 2143-2167). So an alias
    # naming a partial version selects what that partial selects: with
    # v22.9.0 installed, `nvm alias work 22` then `nvm use work` uses
    # v22.9.0, which is what real nvm v0.41.0 does and what this table
    # must do, or every verb that takes a version refuses a perfectly
    # good alias.
    #
    # The recursion terminates because `__vibenvm_resolve_alias` only
    # reads the store: what it returns is a version spelling, never
    # another alias name, so the second pass cannot reach this branch.
    if [ -f "$(__vibenvm_alias_path)/$__vibenvm_req_value" ]; then
        __vibenvm_req_alias="$(__vibenvm_resolve_alias "$__vibenvm_req_value" 2>/dev/null)"
        case "$__vibenvm_req_alias" in
            '' | '∞') ;;
            "$__vibenvm_req_value") ;;
            *)
                __vibenvm_requirement "$__vibenvm_req_alias"
                return $?
                ;;
        esac
    fi
    # A bare numeric pattern is nvm's prefix match, which is a semver
    # requirement with as many fields as the user typed.
    case "$__vibenvm_req_value" in
        *[!0-9.]*)
            __vibenvm_echo "$__vibenvm_req_value"
            return 0
            ;;
        *.*.*) __vibenvm_echo "=$__vibenvm_req_value" ;;
        *.*) __vibenvm_echo "~$__vibenvm_req_value" ;;
        *) __vibenvm_echo "$__vibenvm_req_value" ;;
    esac
}

# The version the slot's default names, by vibe's own answer: the `default`
# field of the slot's listing carries the installation key, and the version
# is that key's version half. `--installed` makes the question free of a
# registry and of the network (PROP-075 `#VERSIONS-LIST-OUTPUT`), and
# nothing here decides what the default is — it only reads it.
__vibenvm_default_version() {
    __vibenvm_vibe app versions "$VIBENVM_SLOT" --installed --all --json 2>/dev/null |
        sed -n 's/^[[:space:]]*"default": "[^"@]*@\([^"]*\)".*$/\1/p' |
        head -1
}

# The installed version a requirement selects, or nothing. `vibe app env`
# resolves and prints; it changes no state, so this is a question and not an
# act (PROP-075 `#ACTIVATION-ENV-OUTPUT`).
__vibenvm_installed_version() {
    __vibenvm_iv="$(__vibenvm_vibe app env --shell posix --use "$VIBENVM_SLOT=$1" 2>/dev/null |
        sed -n "s/^export VIBE_APP_USE='$VIBENVM_SLOT=[^@]*@\\(.*\\)';\$/\\1/p" |
        head -1)"
    [ -n "$__vibenvm_iv" ] || return 0
    # The version categories narrow vibe's answer: one the selection
    # excludes is no answer, which is how `--only=` and `$NVM_ONLY` reach a
    # resolution this file does not perform.
    __vibenvm_is_version_selected "v$__vibenvm_iv" || return 0
    __vibenvm_echo "$__vibenvm_iv"
}

# The version a requirement selects among everything the registries and the
# template offer — vibe's own resolution, with nothing installed and nothing
# downloaded (`--plan-only`).
__vibenvm_remote_version() {
    __vibenvm_rv="$(__vibenvm_vibe install -g "$VIBENVM_PACKAGE@$1" --plan-only --json 2>/dev/null |
        sed -n 's/^[[:space:]]*"version": "\([^"]*\)".*$/\1/p' |
        head -1)"
    [ -n "$__vibenvm_rv" ] || return 0
    __vibenvm_is_version_selected "v$__vibenvm_rv" || return 0
    __vibenvm_echo "$__vibenvm_rv"
}

# One field of what this directory's declared version file resolves to,
# read by vibe and never by this file: the `version_file` selection of
# `vibe-app-env/1` (PROP-075 `#VERSION-FILE-FORMATS`). `requested` is the
# value the file carries — asked for only to tell "there is a file" from
# "there is none" — and `version` is what vibe resolved it to.
#
# Nothing here translates that value. A version file's value already means
# in vibe what it means in nvm: a complete version selects itself and a
# partial one is a prefix, which is why `nvm install` with no version is
# one `vibe install -g` with no version at all.
__vibenvm_version_file_field() { # __vibenvm_version_file_field <field>
    __vibenvm_vibe app env --project --json 2>/dev/null |
        awk -v slot="$VIBENVM_SLOT" -v field="$1" '
            $0 ~ "\"slot\": \"" slot "\"" { seen = 1 }
            seen && /"source": "version_file"/ { file = 1 }
            seen && file && $0 ~ "\"" field "\": \"" {
                sub(/.*": "/, ""); sub(/".*/, "")
                print; exit
            }
            seen && /^    }/ { seen = 0; file = 0 }
        '
}

# Every installed version a pattern selects, as `vN.N.N` lines: vibe's own
# listing, restricted to what is installed, which makes the question free of
# a registry and of the network. The rows are reversed because vibe lists
# newest first and nvm lists oldest first — an ordering, not a comparison:
# no version is parsed here.
__vibenvm_installed_versions() { # [<pattern>]
    __vibenvm_vibe app versions "$VIBENVM_SLOT" --installed --all --json \
        ${1:+"$1"} 2>/dev/null |
        sed -n 's/^[[:space:]]*"version": "\([^"]*\)".*$/v\1/p' |
        __vibenvm_reverse
}

# Every version the registries and the template offer, the same way.
__vibenvm_remote_versions() { # [<pattern>] [<channel requirement>]
    # Deliberate word splitting: `--channel` and its value are two words.
    # shellcheck disable=SC2086
    __vibenvm_vibe app versions "$VIBENVM_PACKAGE" --all --json \
        ${2:+--channel "$2"} ${1:+"$1"} 2>/dev/null |
        sed -n 's/^[[:space:]]*"version": "\([^"]*\)".*$/v\1/p' |
        __vibenvm_reverse
}

__vibenvm_reverse() {
    command awk '{ lines[NR] = $0 } END { for (n = NR; n > 0; n--) print lines[n] }'
}

# The node a shell finds with the slot off: nvm's `system`. Asked in a
# subshell, so the question never changes the caller's PATH.
__vibenvm_system_node() {
    (
        __vibenvm_sys_lines="$(__vibenvm_vibe app env --shell posix --unset 2>/dev/null)" &&
            eval "$__vibenvm_sys_lines"
        command -v node 2>/dev/null
    )
}

# The version vibe's activation put on this shell, read out of the variable
# it sets. `__vibenvm_current` asks node itself, as nvm does; this asks vibe,
# which still knows the answer when something else has edited `$PATH`.
__vibenvm_active_version() {
    case "${VIBE_APP_USE-}" in
        *"$VIBENVM_SLOT="*)
            __vibenvm_echo "${VIBE_APP_USE-}" |
                sed -n "s/.*${VIBENVM_SLOT}=[^@]*@\\([^ ;']*\\).*/\\1/p" |
                head -1
            ;;
    esac
}

# The version this shell is using: vibe's own answer, from the variable its
# activation sets, with nvm's two other answers for the two other states.
__vibenvm_current() {
    __vibenvm_cur_node="$(command -v node 2>/dev/null)"
    if [ -z "$__vibenvm_cur_node" ]; then
        __vibenvm_echo 'none'
        return 0
    fi
    case "${VIBE_APP_USE-}" in
        *"$VIBENVM_SLOT="*)
            command node -v 2>/dev/null || __vibenvm_echo 'none'
            return 0
            ;;
    esac
    __vibenvm_echo 'system'
}

# Apply one `vibe app env` invocation to this shell. The caller evaluates,
# because only the caller is the shell.
__vibenvm_env() {
    if [ "${__vibenvm_silent:-0}" = 1 ]; then
        __vibenvm_vibe app env "$@" 2>/dev/null
    else
        __vibenvm_vibe app env "$@"
    fi
}

# -------------------------------------------------------------- colours ---
#
# nvm's palette is nvm's own: five letters from `rRgGbBcCyYmMkKeW` naming the
# installed, LTS-and-system, current, not-installed and default colours, held
# in `$NVM_COLORS` and nowhere on disk. It paints the rows **this file**
# prints — its own listings and its own alias rows — and nothing vibe prints:
# vibe's display decision stays vibe's, taken once for every vibe command,
# and `set-colors` never reaches it.

__vibenvm_echo_with_colors() { printf '%b\n' "$*"; }
__vibenvm_err_with_colors() { printf '%b\n' "$*" >&2; }

# nvm's three conditions, all of them: stdout is a terminal, the terminal has
# at least eight colours, and `$NVM_NO_COLORS` is not exactly `--no-colors`.
__vibenvm_has_colors() {
    __vibenvm_num_colors=''
    if command -v tput >/dev/null 2>&1; then
        __vibenvm_num_colors="$(command tput -T "${TERM:-vt100}" colors 2>/dev/null)"
    fi
    case "$__vibenvm_num_colors" in
        '' | *[!0-9]*) __vibenvm_num_colors='' ;;
    esac
    [ -t 1 ] && [ "${__vibenvm_num_colors:--1}" -ge 8 ] &&
        [ "${NVM_NO_COLORS-}" != '--no-colors' ]
}

# Terminals without italics render the italic escape as reverse video, so the
# capability is asked for rather than assumed.
__vibenvm_has_italics() {
    __vibenvm_has_colors &&
        command tput -T "${TERM:-vt100}" sitm >/dev/null 2>&1
}

# One character of a string, by position, without forking: the palette is
# read on every painted row.
__vibenvm_char() { # __vibenvm_char <string> <1-based position>
    __vibenvm_char_rest="$1"
    __vibenvm_char_n="$2"
    while [ "$__vibenvm_char_n" -gt 1 ]; do
        __vibenvm_char_rest="${__vibenvm_char_rest#?}"
        __vibenvm_char_n=$((__vibenvm_char_n - 1))
    done
    __vibenvm_echo "${__vibenvm_char_rest%"${__vibenvm_char_rest#?}"}"
}

# nvm's table, including the trailing `m` of each code — the callers
# concatenate it straight after `\033[`. `0` is "no colour": it succeeds with
# empty output, which is how a palette position turns painting off.
__vibenvm_print_color_code() {
    case "${1-}" in
        '0') return 0 ;;
        'r') __vibenvm_echo '0;31m' ;;
        'R') __vibenvm_echo '1;31m' ;;
        'g') __vibenvm_echo '0;32m' ;;
        'G') __vibenvm_echo '1;32m' ;;
        'b') __vibenvm_echo '0;34m' ;;
        'B') __vibenvm_echo '1;34m' ;;
        'c') __vibenvm_echo '0;36m' ;;
        'C') __vibenvm_echo '1;36m' ;;
        'm') __vibenvm_echo '0;35m' ;;
        'M') __vibenvm_echo '1;35m' ;;
        'y') __vibenvm_echo '0;33m' ;;
        'Y') __vibenvm_echo '1;33m' ;;
        'k') __vibenvm_echo '0;30m' ;;
        'K') __vibenvm_echo '1;30m' ;;
        'e') __vibenvm_echo '0;37m' ;;
        'W') __vibenvm_echo '1;37m' ;;
        *)
            __vibenvm_err "Invalid color code: ${1-}"
            return 1
            ;;
    esac
}

# The code of one palette position: 1 installed, 2 LTS and system, 3 current,
# 4 not installed, 5 default — and 6, which is position 2 bolded, nvm's LTS
# colour. `bygre` is the palette when the user has set none.
__vibenvm_get_colors() {
    __vibenvm_colors="${NVM_COLORS:-bygre}"
    case "$1" in
        1 | 2 | 3 | 4 | 5)
            __vibenvm_color="$(__vibenvm_print_color_code \
                "$(__vibenvm_char "$__vibenvm_colors" "$1")")"
            ;;
        6)
            __vibenvm_color="$(__vibenvm_print_color_code \
                "$(__vibenvm_char "$__vibenvm_colors" 2)" |
                command tr '0;' '1;')"
            ;;
        *)
            __vibenvm_err "Invalid color index, ${1-}"
            return 1
            ;;
    esac
    __vibenvm_echo "$__vibenvm_color"
}

# Paint text, or do not. A caller inside a command substitution cannot ask
# `[ -t 1 ]` for itself — the capture pipe answers — so one that already
# knows passes the answer in through `$NVM_HAS_COLORS`.
__vibenvm_wrap_with_color_code() {
    __vibenvm_wrap_code="$(__vibenvm_print_color_code "$1" 2>/dev/null || :)"
    if { [ "${NVM_HAS_COLORS-}" = 1 ] || __vibenvm_has_colors; } &&
        [ -n "$__vibenvm_wrap_code" ]; then
        __vibenvm_echo_with_colors "\033[${__vibenvm_wrap_code}${2-}\033[0m"
    else
        __vibenvm_echo "${2-}"
    fi
}

# The legend `nvm --help` ends with, and the one `set-colors` points at.
__vibenvm_print_color_legend() {
    # Resolved once here: every line below is built in a command
    # substitution, which cannot detect colour support itself, and a leaked
    # flag would override `--no-colors` for every later call.
    local NVM_HAS_COLORS
    NVM_HAS_COLORS=0
    if __vibenvm_has_colors; then
        NVM_HAS_COLORS=1
    fi
    __vibenvm_echo 'Initial colors are:'
    __vibenvm_echo_with_colors "  $(__vibenvm_wrap_with_color_code 'b' 'b')$(__vibenvm_wrap_with_color_code 'y' 'y')$(__vibenvm_wrap_with_color_code 'g' 'g')$(__vibenvm_wrap_with_color_code 'r' 'r')$(__vibenvm_wrap_with_color_code 'e' 'e')"
    __vibenvm_echo 'Color codes:'
    __vibenvm_echo_with_colors "  $(__vibenvm_wrap_with_color_code 'r' 'r')/$(__vibenvm_wrap_with_color_code 'R' 'R') = $(__vibenvm_wrap_with_color_code 'r' 'red') / $(__vibenvm_wrap_with_color_code 'R' 'bold red')"
    __vibenvm_echo_with_colors "  $(__vibenvm_wrap_with_color_code 'g' 'g')/$(__vibenvm_wrap_with_color_code 'G' 'G') = $(__vibenvm_wrap_with_color_code 'g' 'green') / $(__vibenvm_wrap_with_color_code 'G' 'bold green')"
    __vibenvm_echo_with_colors "  $(__vibenvm_wrap_with_color_code 'b' 'b')/$(__vibenvm_wrap_with_color_code 'B' 'B') = $(__vibenvm_wrap_with_color_code 'b' 'blue') / $(__vibenvm_wrap_with_color_code 'B' 'bold blue')"
    __vibenvm_echo_with_colors "  $(__vibenvm_wrap_with_color_code 'c' 'c')/$(__vibenvm_wrap_with_color_code 'C' 'C') = $(__vibenvm_wrap_with_color_code 'c' 'cyan') / $(__vibenvm_wrap_with_color_code 'C' 'bold cyan')"
    __vibenvm_echo_with_colors "  $(__vibenvm_wrap_with_color_code 'm' 'm')/$(__vibenvm_wrap_with_color_code 'M' 'M') = $(__vibenvm_wrap_with_color_code 'm' 'magenta') / $(__vibenvm_wrap_with_color_code 'M' 'bold magenta')"
    __vibenvm_echo_with_colors "  $(__vibenvm_wrap_with_color_code 'y' 'y')/$(__vibenvm_wrap_with_color_code 'Y' 'Y') = $(__vibenvm_wrap_with_color_code 'y' 'yellow') / $(__vibenvm_wrap_with_color_code 'Y' 'bold yellow')"
    __vibenvm_echo_with_colors "  $(__vibenvm_wrap_with_color_code 'k' 'k')/$(__vibenvm_wrap_with_color_code 'K' 'K') = $(__vibenvm_wrap_with_color_code 'k' 'black') / $(__vibenvm_wrap_with_color_code 'K' 'bold black')"
    __vibenvm_echo_with_colors "  $(__vibenvm_wrap_with_color_code 'e' 'e')/$(__vibenvm_wrap_with_color_code 'W' 'W') = $(__vibenvm_wrap_with_color_code 'e' 'light grey') / $(__vibenvm_wrap_with_color_code 'W' 'white')"
}

# Exactly five characters of the sixteen, or 17 — the status the subcommand
# reads to print the legend. The palette lives in the environment only: nvm
# writes nothing to disk for it, and neither does this.
__vibenvm_set_colors() {
    if [ "${#1}" -eq 5 ] &&
        __vibenvm_echo "$1" | command grep -E '^[rRgGbBcCyYmMkKeW]{1,}$' >/dev/null; then
        local INSTALLED_COLOR LTS_AND_SYSTEM_COLOR CURRENT_COLOR
        local NOT_INSTALLED_COLOR DEFAULT_COLOR NVM_HAS_COLORS
        NVM_HAS_COLORS=0
        INSTALLED_COLOR="$(__vibenvm_char "$1" 1)"
        LTS_AND_SYSTEM_COLOR="$(__vibenvm_char "$1" 2)"
        CURRENT_COLOR="$(__vibenvm_char "$1" 3)"
        NOT_INSTALLED_COLOR="$(__vibenvm_char "$1" 4)"
        DEFAULT_COLOR="$(__vibenvm_char "$1" 5)"
        if ! __vibenvm_has_colors; then
            __vibenvm_echo "Setting colors to: ${INSTALLED_COLOR} ${LTS_AND_SYSTEM_COLOR} ${CURRENT_COLOR} ${NOT_INSTALLED_COLOR} ${DEFAULT_COLOR}"
            __vibenvm_echo 'WARNING: Colors may not display because they are not supported in this shell.'
        else
            NVM_HAS_COLORS=1
            __vibenvm_echo_with_colors "Setting colors to: $(__vibenvm_wrap_with_color_code "${INSTALLED_COLOR}" "${INSTALLED_COLOR}")$(__vibenvm_wrap_with_color_code "${LTS_AND_SYSTEM_COLOR}" "${LTS_AND_SYSTEM_COLOR}")$(__vibenvm_wrap_with_color_code "${CURRENT_COLOR}" "${CURRENT_COLOR}")$(__vibenvm_wrap_with_color_code "${NOT_INSTALLED_COLOR}" "${NOT_INSTALLED_COLOR}")$(__vibenvm_wrap_with_color_code "${DEFAULT_COLOR}" "${DEFAULT_COLOR}")"
        fi
        export NVM_COLORS="$1"
    else
        return 17
    fi
}

# ------------------------------------------------------------- listings ---
#
# The rows of `nvm ls` and `nvm ls-remote`, in nvm's own shape: a fifteen
# column field (wider when a version needs it), ` *` after an installed
# version where there is no colour, `-> ` before the current one, and the
# annotation columns starting in the same column on every row so the output
# stays `cut`-able. What is *in* the rows is vibe's answer; only their shape
# is this file's.
#
# Which rows count as installed comes from `$__vibenvm_installed`, filled by
# the caller out of one vibe listing, rather than from a question asked again
# per row.
__vibenvm_print_versions() { # <lines> [<latest alias>] [<named aliases>]
    local NVM_CURRENT
    NVM_CURRENT="$(__vibenvm_current)"

    local INSTALLED_COLOR SYSTEM_COLOR CURRENT_COLOR DEFAULT_COLOR LTS_COLOR
    local NVM_HAS_COLORS NVM_HAS_ITALICS
    NVM_HAS_COLORS=0
    NVM_HAS_ITALICS=0
    INSTALLED_COLOR="$(__vibenvm_get_colors 1)"
    SYSTEM_COLOR="$(__vibenvm_get_colors 2)"
    CURRENT_COLOR="$(__vibenvm_get_colors 3)"
    DEFAULT_COLOR="$(__vibenvm_get_colors 5)"
    LTS_COLOR="$(__vibenvm_get_colors 6)"
    if __vibenvm_has_colors; then
        NVM_HAS_COLORS=1
    fi
    if [ "$NVM_HAS_COLORS" = 1 ] && [ -n "${2-}${3-}" ] && __vibenvm_has_italics; then
        NVM_HAS_ITALICS=1
    fi

    NVM_NAMED_ALIASES="${3-}" \
        command awk \
        -v versions="$(printf '%s' "${1-}" | command tr '\n' '|')" \
        -v latest_alias="${2-}" \
        -v installed_versions="$(printf '%s' "${__vibenvm_installed-}" | command tr '\n' '|')" \
        -v current="$NVM_CURRENT" \
        -v installed_color="$INSTALLED_COLOR" -v system_color="$SYSTEM_COLOR" \
        -v current_color="$CURRENT_COLOR" -v default_color="$DEFAULT_COLOR" \
        -v old_lts_color="$DEFAULT_COLOR" -v has_colors="$NVM_HAS_COLORS" \
        -v has_italics="$NVM_HAS_ITALICS" '
function alen(arr, i, len) { len=0; for(i in arr) len++; return len; }
function paint(color, text) { return (has_colors && color) ? ("\033[" color text "\033[0m") : text; }
function spaces(count, result) { result = ""; while (count-- > 0) result = result " "; return result; }
function italicize(text) { return has_italics ? ("\033[3m" text "\033[23m") : text; }
BEGIN {
  named_alias_list = ENVIRON["NVM_NAMED_ALIASES"];
  # wide enough for the longest version, plus the arrow before the current one
  column = 15;
  column_rows = split(versions, column_lines, "|");
  for (n = 1; n <= column_rows; n++) {
    split(column_lines[n], column_fields, "[[:blank:]]+");
    column_width = length(column_fields[1]) + (column_fields[1] == current ? 2 : 0);
    if (column_width > column) {
      column = column_width;
    }
  }
  fmt_column = "%" column "s";
  fmt_arrow = "->%" (column - 2) "s";
  fmt_installed = has_colors ? (installed_color ? "\033[" installed_color fmt_column "\033[0m" : fmt_column) : fmt_column " *";
  fmt_system = has_colors ? (system_color ? "\033[" system_color fmt_column "\033[0m" : fmt_column) : fmt_column " *";
  fmt_current = has_colors ? (current_color ? "\033[" current_color fmt_arrow "\033[0m" : fmt_column) : fmt_arrow " *";

  latest_lts_color = current_color;
  sub(/0;/, "1;", latest_lts_color);
  alias_color = current_color;
  sub(/^1;/, "0;", alias_color);

  fmt_latest_lts = has_colors && latest_lts_color ? ("\033[" latest_lts_color " (Latest LTS: %s)\033[0m") : " (Latest LTS: %s)";
  fmt_old_lts = has_colors && old_lts_color ? ("\033[" old_lts_color " (LTS: %s)\033[0m") : " (LTS: %s)";
  fmt_system_target = has_colors && system_color ? (" (\033[" system_color "-> %s\033[0m)") : " (-> %s)";

  split(versions, lines, "|");
  split(installed_versions, installed, "|");
  rows = alen(lines);

  for (n = 1; n <= rows; n++) {
    split(lines[n], fields, "[[:blank:]]+");
    if (fields[1] ~ /^iojs-/) {
      latest_iojs = fields[1];
    } else if (fields[1] ~ /^v0\.[0-9]*[13579]\./) {
      latest_unstable = fields[1];
    } else if (fields[1] ~ /^v[0-9]/) {
      latest_stable = fields[1];
    }
  }

  named_alias_rows = split(named_alias_list, named_alias_lines, "\n");
  for (a = 1; a <= named_alias_rows; a++) {
    tab_position = index(named_alias_lines[a], "\t");
    if (tab_position < 2) {
      continue;
    }
    alias_target = substr(named_alias_lines[a], 1, tab_position - 1);
    alias_name = substr(named_alias_lines[a], tab_position + 1);
    if (alias_name == "") {
      continue;
    }

    alias_version = "";
    if (alias_target == "node" || alias_target == "stable") {
      alias_version = latest_stable;
    } else if (alias_target == "unstable") {
      alias_version = latest_unstable;
    } else if (alias_target == "iojs" || alias_target == "iojs-") {
      alias_version = latest_iojs;
    } else {
      for (n = 1; n <= rows; n++) {
        split(lines[n], fields, "[[:blank:]]+");
        if (fields[1] == alias_target || index(fields[1], alias_target ".") == 1) {
          alias_version = fields[1];
        }
      }
    }

    if (alias_version != "") {
      # mawk creates the assigned element before evaluating the right side, so `in` must be checked first
      if (alias_version in named_aliases) {
        named_aliases[alias_version] = named_aliases[alias_version] ", " alias_name;
        italic_aliases[alias_version] = italic_aliases[alias_version] ", " italicize(alias_name);
      } else {
        named_aliases[alias_version] = alias_name;
        italic_aliases[alias_version] = italicize(alias_name);
      }
    }
  }

  for (n = 1; n <= rows; n++) {
    split(lines[n], fields, "[[:blank:]]+");
    cols = alen(fields);
    version = fields[1];
    is_installed = 0;

    for (i in installed) {
      if (version == installed[i]) {
        is_installed = 1;
        break;
      }
    }

    fmt_version = fmt_column;
    if (version == current) {
      fmt_version = fmt_current;
    } else if (version == "system") {
      fmt_version = fmt_system;
    } else if (is_installed) {
      fmt_version = fmt_installed;
    }

    padding[n] = (!has_colors && is_installed) ? "" : "  ";

    output[n] = sprintf(fmt_version, version);
    version_width[n] = output[n] padding[n];
    gsub(/\033\[[0-9;]*m/, "", version_width[n]);
    version_width[n] = length(version_width[n]);
    if (version_width[n] > max_version_width) {
      max_version_width = version_width[n];
    }
    for (c = 1; c <= 3; c++) {
      text[n, c] = "";
      cell[n, c] = "";
    }
    if (version == "system" && cols >= 2) {
      output[n] = output[n] sprintf(fmt_system_target, fields[2]);
    } else if (cols == 2) {
      text[n, 1] = sprintf(" (LTS: %s)", fields[2]);
      cell[n, 1] = sprintf(fmt_old_lts, fields[2]);
    } else if (cols == 3 && fields[3] == "*") {
      text[n, 1] = sprintf(" (Latest LTS: %s)", fields[2]);
      cell[n, 1] = sprintf(fmt_latest_lts, fields[2]);
    }

    if (latest_alias != "" && version == latest_stable) {
      text[n, 2] = " (Latest: " latest_alias ")";
      cell[n, 2] = paint(alias_color, " (Latest: " italicize(latest_alias) ")");
    }

    if (version in named_aliases) {
      text[n, 3] = " (Aliases: " named_aliases[version] ")";
      cell[n, 3] = paint(alias_color, " (Aliases: " italic_aliases[version] ")");
    }

    for (c = 1; c <= 3; c++) {
      if (length(text[n, c]) > width[c]) {
        width[c] = length(text[n, c]);
      }
    }
  }

  # each kind of annotation starts in the same column on every row, so the output stays `cut`-able
  for (n = 1; n <= rows; n++) {
    last = 0;
    for (c = 1; c <= 3; c++) {
      if (text[n, c] != "") {
        last = c;
      }
    }
    formatted = output[n];
    if (last) {
      formatted = formatted padding[n];
      if (width[2] || width[3]) {
        formatted = formatted spaces(max_version_width - version_width[n]);
      }
      gap = "";
      for (c = 1; c <= last; c++) {
        if (width[c]) {
          formatted = formatted gap cell[n, c];
          gap = spaces(width[c] - length(text[n, c])) "  ";
        }
      }
    }
    print formatted
  }

  exit
}'
}

# ------------------------------------------------------- nvm's own root ---
#
# Where nvm's own files live: the alias store, and the records the later
# sections keep beside it. `$NVM_DIR` wins when the user set it — a user who
# set it means it, and their alias files are already there — and otherwise it
# is vibe's own settings root (`$VIBE_SETTINGS`, else `$HOME/.vibe`) under
# `apps/nvm`, so this state sits where vibe keeps a user's state rather than
# in a third place nobody looks.
__vibenvm_root() {
    if [ -n "${NVM_DIR-}" ]; then
        __vibenvm_echo "${NVM_DIR}"
    else
        __vibenvm_echo "${VIBE_SETTINGS:-$HOME/.vibe}/apps/nvm"
    fi
}

__vibenvm_alias_path() { __vibenvm_echo "$(__vibenvm_root)/alias"; }

# --------------------------------------------------------------- aliases ---
#
# nvm's alias store, in nvm's own layout, byte for byte: one file per alias
# under `<root>/alias`, an `lts/` subdirectory, the target plus a newline,
# flags such as `--lts` space-separated before it on the first line, `#`
# starting a comment and every line right-trimmed. A user who moves between
# nvm and this file finds their aliases where they left them, which is the
# whole reason not to invent a format.
#
# **`default` is not in that store.** It is the slot's default version, which
# is vibe's own fact: `nvm alias default X` makes it through `vibe app use`,
# and `nvm alias default` and the `default` row of a listing are rendered
# from vibe's answer. One source of truth, so the two can never disagree.

# nvm's own prefix rule: a version gains its `v`, anything else is left alone.
__vibenvm_ensure_version_prefix() {
    case "${1-}" in
        [0-9]*) __vibenvm_echo "v$1" ;;
        *) __vibenvm_echo "${1-}" ;;
    esac
}

# `lts/-N` counts back through the LTS lines the store knows, and an `lts/`
# name must be lowercase. Everything else passes through unchanged.
__vibenvm_normalize_lts() {
    __vibenvm_lts_value="${1-}"
    case "$__vibenvm_lts_value" in
        lts/-[123456789] | lts/-[123456789][0123456789]*)
            __vibenvm_lts_n="${__vibenvm_lts_value#lts/-}"
            case "$__vibenvm_lts_n" in
                *[!0123456789]*)
                    __vibenvm_echo "$__vibenvm_lts_value"
                    return 0
                    ;;
            esac
            __vibenvm_lts_n=$((__vibenvm_lts_n + 1))
            __vibenvm_lts_result="$(command ls "$(__vibenvm_alias_path)/lts" 2>/dev/null |
                command tail -n "$__vibenvm_lts_n" | command head -n 1)"
            if [ -n "$__vibenvm_lts_result" ] && [ "$__vibenvm_lts_result" != '*' ]; then
                __vibenvm_echo "lts/$__vibenvm_lts_result"
            else
                __vibenvm_err 'That many LTS releases do not exist yet.'
                return 2
            fi
            ;;
        *)
            case "$__vibenvm_lts_value" in
                lts/*)
                    if [ "$__vibenvm_lts_value" != "$(__vibenvm_echo "$__vibenvm_lts_value" | command tr '[:upper:]' '[:lower:]')" ]; then
                        __vibenvm_err 'LTS names must be lowercase'
                        return 3
                    fi
                    ;;
            esac
            __vibenvm_echo "$__vibenvm_lts_value"
            ;;
    esac
}

# An alias file, as nvm reads one: a `#` starts a comment, a line that is
# only whitespace is skipped, and what is left is right-trimmed.
__vibenvm_print_alias_file() { # <path>
    while IFS= read -r __vibenvm_alias_line || [ -n "$__vibenvm_alias_line" ]; do
        __vibenvm_alias_line="${__vibenvm_alias_line%%#*}"
        case "$__vibenvm_alias_line" in
            *[![:space:]]*) ;;
            *) continue ;;
        esac
        __vibenvm_alias_line="${__vibenvm_alias_line%"${__vibenvm_alias_line##*[![:space:]]}"}"
        __vibenvm_echo "$__vibenvm_alias_line"
    done <"$1"
}

# What `default` points at, as the store would have spelled it: the version
# vibe's slot default names, with nvm's `v`. Nothing resolves it here.
__vibenvm_default_target() {
    __vibenvm_def_version="$(__vibenvm_default_version)"
    [ -n "$__vibenvm_def_version" ] || return 1
    __vibenvm_echo "v$__vibenvm_def_version"
}

# Whether vibe has this version installed. The set is read from vibe once per
# `nvm` command and remembered in the caller's own local, so a listing of
# twenty aliases asks once rather than twenty times.
__vibenvm_is_version_installed() {
    [ -n "${1-}" ] || return 1
    if [ -z "${__vibenvm_installed_cache-}" ]; then
        __vibenvm_installed_cache="
$(__vibenvm_installed_versions)
"
    fi
    case "$__vibenvm_installed_cache" in
        *"
$1
"*) return 0 ;;
    esac
    return 1
}

__vibenvm_alias() { # <name>
    __vibenvm_alias_name="${1-}"
    if [ -z "$__vibenvm_alias_name" ]; then
        __vibenvm_err 'An alias is required.'
        return 1
    fi
    __vibenvm_alias_name="$(__vibenvm_normalize_lts "$__vibenvm_alias_name")" || return $?
    if [ -z "$__vibenvm_alias_name" ]; then
        return 2
    fi
    # Slashes are legal (`lts/iron`), but a `..` component would read outside
    # the store; the write side rejects the same shape.
    case "/$__vibenvm_alias_name/" in
        */../*)
            __vibenvm_err "invalid alias name: $__vibenvm_alias_name"
            return 3
            ;;
    esac
    if [ "$__vibenvm_alias_name" = 'default' ]; then
        # vibe's answer, never a file — even when `$NVM_DIR` points at a real
        # nvm installation that has one, because two answers would be two
        # truths.
        __vibenvm_default_target && return 0
        __vibenvm_err 'Alias does not exist.'
        return 2
    fi
    __vibenvm_alias_file="$(__vibenvm_alias_path)/$__vibenvm_alias_name"
    if [ ! -f "$__vibenvm_alias_file" ]; then
        __vibenvm_err 'Alias does not exist.'
        return 2
    fi
    if [ ! -r "$__vibenvm_alias_file" ]; then
        # An existing but unreadable alias yields empty output and a
        # **success**: a failure here would make `nvm install` overwrite a
        # default it merely could not read.
        __vibenvm_err "Alias file is not readable: $__vibenvm_alias_file"
        return 0
    fi
    __vibenvm_print_alias_file "$__vibenvm_alias_file"
}

__vibenvm_make_alias() { # <name> <target>
    if [ -z "${1-}" ]; then
        __vibenvm_err 'an alias name is required'
        return 1
    fi
    if [ -z "${2-}" ]; then
        __vibenvm_err 'an alias target version is required'
        return 2
    fi
    case "/$1/" in
        */../*)
            __vibenvm_err "invalid alias name: $1"
            return 3
            ;;
    esac
    __vibenvm_echo "$2" | command tee "$(__vibenvm_alias_path)/$1" >/dev/null
}

# Follow an alias to what it finally names. The loop is unbounded on purpose
# and ends on a name already seen, which is the literal `∞` nvm prints; only
# the first line of each file is followed; flags are peeled at every hop and
# only the outermost non-empty set survives; and the implicit branch at the
# end **prints and still returns 2**, as nvm's does.
__vibenvm_resolve_alias() { # <pattern>
    if [ -z "${1-}" ]; then
        return 1
    fi
    local PATTERN ALIAS ALIAS_TEMP ALIAS_OUTPUT ALIAS_FLAGS ALIAS_TEMP_FLAGS
    local SEEN_ALIASES IMPLICIT
    PATTERN="${1-}"
    ALIAS="$PATTERN"
    ALIAS_FLAGS=''
    SEEN_ALIASES="
${ALIAS}
"
    while true; do
        ALIAS_OUTPUT="$(__vibenvm_alias "$ALIAS" 2>/dev/null)" || ALIAS_OUTPUT=''
        ALIAS_TEMP="${ALIAS_OUTPUT%%
*}"
        ALIAS_TEMP_FLAGS=''
        while :; do
            case "$ALIAS_TEMP" in
                --*' '*)
                    ALIAS_TEMP_FLAGS="${ALIAS_TEMP_FLAGS:+${ALIAS_TEMP_FLAGS} }${ALIAS_TEMP%% *}"
                    ALIAS_TEMP="${ALIAS_TEMP#* }"
                    ;;
                *) break ;;
            esac
        done
        if [ -z "$ALIAS_FLAGS" ]; then
            ALIAS_FLAGS="$ALIAS_TEMP_FLAGS"
        fi
        if [ -z "$ALIAS_TEMP" ]; then
            break
        fi
        case "$SEEN_ALIASES" in
            *"
${ALIAS_TEMP}
"*)
                ALIAS='∞'
                break
                ;;
        esac
        SEEN_ALIASES="${SEEN_ALIASES}${ALIAS_TEMP}
"
        ALIAS="$ALIAS_TEMP"
    done

    if [ -n "$ALIAS" ] && [ "_$ALIAS" != "_$PATTERN" ]; then
        case "$ALIAS" in
            '∞')
                __vibenvm_echo "$ALIAS"
                ;;
            iojs | iojs- | node)
                __vibenvm_echo "${ALIAS_FLAGS:+${ALIAS_FLAGS} }${ALIAS}"
                ;;
            *)
                __vibenvm_echo "${ALIAS_FLAGS:+${ALIAS_FLAGS} }$(__vibenvm_ensure_version_prefix "$ALIAS")"
                ;;
        esac
        return 0
    fi

    if __vibenvm_validate_implicit_alias "$PATTERN" 2>/dev/null; then
        IMPLICIT="$(__vibenvm_print_implicit_alias local "$PATTERN" 2>/dev/null)"
        if [ -n "$IMPLICIT" ]; then
            __vibenvm_ensure_version_prefix "$IMPLICIT"
        fi
    fi

    return 2
}

__vibenvm_resolve_local_alias() { # <pattern>
    if [ -z "${1-}" ]; then
        return 1
    fi
    local VERSION EXIT_CODE
    VERSION="$(__vibenvm_resolve_alias "${1-}")"
    EXIT_CODE=$?
    if [ -z "$VERSION" ]; then
        return $EXIT_CODE
    fi
    if [ "_$VERSION" = '_∞' ]; then
        __vibenvm_echo "$VERSION"
        return 0
    fi
    if __vibenvm_is_version_installed "$VERSION"; then
        __vibenvm_echo "$VERSION"
        return 0
    fi
    __vibenvm_alias_version "$VERSION"
}

__vibenvm_validate_implicit_alias() {
    case "$1" in
        stable | unstable | iojs | node) return 0 ;;
        *)
            __vibenvm_err "Only implicit aliases 'stable', 'unstable', 'iojs', and 'node' are supported."
            return 1
            ;;
    esac
}

# nvm's four built-in aliases. `node` names `stable`; `stable` and `unstable`
# are the newest even- and odd-minor `0.x` lines and, after `0.x`, simply the
# newest release — which is vibe's answer, not a computation here; `iojs` is
# `N/A`, because `org.vibevm.node/node` carries no io.js version and inventing
# one would be worse than saying so.
__vibenvm_print_implicit_alias() { # <local|remote> <name>
    if [ "_$1" != '_local' ] && [ "_$1" != '_remote' ]; then
        __vibenvm_err 'An implicit alias is local or remote.'
        return 1
    fi
    __vibenvm_validate_implicit_alias "${2-}" || return 2
    case "${2-}" in
        node)
            __vibenvm_echo 'stable'
            return 0
            ;;
        iojs)
            __vibenvm_echo 'N/A'
            return 0
            ;;
    esac
    if [ "_$1" = '_local' ]; then
        __vibenvm_implicit_list="$(__vibenvm_installed_versions)"
    else
        __vibenvm_implicit_list="$(__vibenvm_remote_versions)"
    fi
    __vibenvm_echo "$__vibenvm_implicit_list" | command awk -v want="${2-}" '
        /^v0\.[0-9]*[13579]\./ { if (want == "unstable") { found = $1 }; next }
        /^v[0-9]/ { if (want == "stable") { found = $1 } }
        END { if (found) { print found } }'
}

# The installed version an alias target names, or `N/A`: the flags are peeled
# off, the spelling is translated, and vibe answers.
# **The flags an alias stores are part of its target**, not decoration to be
# peeled off: `--lts` selects among LTS versions and `--only=` among
# categories, and resolving the one without the other would answer a
# different question than the alias asks (nvm.sh 1243-1284).
__vibenvm_alias_version() { # <target, flags and all>
    local NVM_ONLY_SELECTED
    NVM_ONLY_SELECTED="${NVM_ONLY_SELECTED-}"
    __vibenvm_target="${1-}"
    __vibenvm_target_lts=''
    while :; do
        case "$__vibenvm_target" in
            '--lts '*) __vibenvm_target_lts='*' ;;
            --lts=*' '*)
                __vibenvm_target_lts="${__vibenvm_target%% *}"
                __vibenvm_target_lts="${__vibenvm_target_lts#--lts=}"
                ;;
            --only=*' '*)
                __vibenvm_target_only="${__vibenvm_target%% *}"
                NVM_ONLY_SELECTED="$(__vibenvm_normalize_only "${__vibenvm_target_only#--only=}" "an alias's \`--only\`")" || {
                    __vibenvm_echo 'N/A'
                    return 3
                }
                ;;
            --*)
                __vibenvm_echo 'N/A'
                return 3
                ;;
            *) break ;;
        esac
        __vibenvm_target="${__vibenvm_target#* }"
    done
    if [ -z "$__vibenvm_target" ]; then
        __vibenvm_echo 'N/A'
        return 0
    fi
    if [ -n "$__vibenvm_target_lts" ]; then
        # Asking vibe which lines are LTS is what makes them known — to this
        # file, which writes the `lts/` aliases, and to vibe, whose channel
        # answer this is. nvm learns them at exactly this moment too.
        if [ -z "$(command ls "$(__vibenvm_alias_path)/lts" 2>/dev/null)" ]; then
            __vibenvm_learn_lts >/dev/null 2>&1 || :
        fi
        __vibenvm_ensure_lts_status >/dev/null 2>&1 || :
        case "$__vibenvm_target" in
            node | stable | latest)
                # The newest of the line, which is the channel itself.
                __vibenvm_target="lts/${__vibenvm_target_lts}"
                ;;
            *)
                # Any other target keeps its own spelling and is narrowed to
                # LTS versions, as every other selection here narrows.
                NVM_ONLY_SELECTED='lts'
                ;;
        esac
    fi
    __vibenvm_target_req="$(__vibenvm_requirement "$__vibenvm_target" 2>/dev/null)" || {
        __vibenvm_echo 'N/A'
        return 0
    }
    __vibenvm_target_version="$(__vibenvm_installed_version "$__vibenvm_target_req")"
    if [ -z "$__vibenvm_target_version" ]; then
        __vibenvm_echo 'N/A'
        return 0
    fi
    __vibenvm_echo "v$__vibenvm_target_version"
}

# One alias row, in nvm's shapes: `name -> target` when they are the same
# thing, `name -> target (-> version)` when they are not, a trailing ` *` for
# a real version where there is no colour, and ` (default)` for a built-in.
__vibenvm_print_formatted_alias() { # <alias> <dest> [<version>]
    local ALIAS DEST VERSION VERSION_FORMAT ALIAS_FORMAT DEST_FORMAT
    local INSTALLED_COLOR CURRENT_COLOR NOT_INSTALLED_COLOR DEFAULT_COLOR LTS_COLOR
    local NEWLINE ARROW
    ALIAS="${1-}"
    DEST="${2-}"
    VERSION="${3-}"
    if [ -z "$VERSION" ]; then
        VERSION="$(__vibenvm_alias_version "$DEST")" || :
    fi

    INSTALLED_COLOR="$(__vibenvm_get_colors 1)"
    CURRENT_COLOR="$(__vibenvm_get_colors 3)"
    NOT_INSTALLED_COLOR="$(__vibenvm_get_colors 4)"
    DEFAULT_COLOR="$(__vibenvm_get_colors 5)"
    LTS_COLOR="$(__vibenvm_get_colors 6)"

    ALIAS_FORMAT='%s'
    DEST_FORMAT='%s'
    VERSION_FORMAT='%s'
    NEWLINE='\n'
    if [ "_${DEFAULT-}" = '_true' ]; then
        NEWLINE=' (default)\n'
    fi
    ARROW='->'
    if [ "${NVM_HAS_COLORS-}" = 1 ] || __vibenvm_has_colors; then
        ARROW='\033[0;90m->\033[0m'
        if [ "_${DEFAULT-}" = '_true' ]; then
            NEWLINE=" \033[${DEFAULT_COLOR}(default)\033[0m\n"
        fi
        if [ "_${VERSION}" = "_${NVM_CURRENT-}" ]; then
            ALIAS_FORMAT="\033[${CURRENT_COLOR}%s\033[0m"
            DEST_FORMAT="\033[${CURRENT_COLOR}%s\033[0m"
            VERSION_FORMAT="\033[${CURRENT_COLOR}%s\033[0m"
        elif __vibenvm_is_version_installed "$VERSION"; then
            ALIAS_FORMAT="\033[${INSTALLED_COLOR}%s\033[0m"
            DEST_FORMAT="\033[${INSTALLED_COLOR}%s\033[0m"
            VERSION_FORMAT="\033[${INSTALLED_COLOR}%s\033[0m"
        elif [ "$VERSION" = '∞' ] || [ "$VERSION" = 'N/A' ]; then
            ALIAS_FORMAT="\033[${NOT_INSTALLED_COLOR}%s\033[0m"
            DEST_FORMAT="\033[${NOT_INSTALLED_COLOR}%s\033[0m"
            VERSION_FORMAT="\033[${NOT_INSTALLED_COLOR}%s\033[0m"
        fi
        if [ "_${NVM_LTS-}" = '_true' ]; then
            ALIAS_FORMAT="\033[${LTS_COLOR}%s\033[0m"
        fi
        if [ "_${DEST%/*}" = '_lts' ]; then
            DEST_FORMAT="\033[${LTS_COLOR}%s\033[0m"
        fi
    elif [ "_${VERSION}" != '_∞' ] && [ "_${VERSION}" != '_N/A' ]; then
        VERSION_FORMAT='%s *'
    fi
    if [ "$DEST" = "$VERSION" ]; then
        command printf -- "${ALIAS_FORMAT} ${ARROW} ${VERSION_FORMAT}${NEWLINE}" "$ALIAS" "$DEST"
    else
        command printf -- "${ALIAS_FORMAT} ${ARROW} ${DEST_FORMAT} (${ARROW} ${VERSION_FORMAT})${NEWLINE}" "$ALIAS" "$DEST" "$VERSION"
    fi
}

__vibenvm_print_alias_path() { # <alias dir> <alias path>
    local NVM_ALIAS_DIR ALIAS_PATH ALIAS DEST
    NVM_ALIAS_DIR="${1-}"
    if [ -z "$NVM_ALIAS_DIR" ]; then
        __vibenvm_err 'An alias dir is required.'
        return 1
    fi
    ALIAS_PATH="${2-}"
    if [ -z "$ALIAS_PATH" ]; then
        __vibenvm_err 'An alias path is required.'
        return 2
    fi
    ALIAS="${ALIAS_PATH##"${NVM_ALIAS_DIR}"/}"
    DEST="$(__vibenvm_alias "$ALIAS" 2>/dev/null)" || :
    if [ -n "$DEST" ]; then
        DEFAULT=false __vibenvm_print_formatted_alias "$ALIAS" "$DEST"
    fi
}

__vibenvm_print_default_alias() { # <built-in name>
    local ALIAS DEST
    ALIAS="${1-}"
    if [ -z "$ALIAS" ]; then
        __vibenvm_err 'A default alias is required.'
        return 1
    fi
    DEST="$(__vibenvm_print_implicit_alias local "$ALIAS")"
    if [ -n "$DEST" ]; then
        DEFAULT=true __vibenvm_print_formatted_alias "$ALIAS" "$DEST"
    fi
}

# Three blocks, each sorted on its own, exactly as nvm prints them: the user
# aliases (with `default`, which vibe answers for), then the built-ins that
# no real file shadows, then `lts/*`. nvm runs each row as a background job;
# these run in order, because the sort decides the order anyway and a shell
# that forks per alias is a shell that loses an error message.
__vibenvm_list_aliases() { # [<prefix>]
    local ALIAS NVM_CURRENT NVM_ALIAS_DIR NVM_HAS_COLORS ALIAS_PATH ALIAS_NAME
    local LTS_ALIAS DEFAULT_DEST
    ALIAS="${1-}"
    NVM_CURRENT="$(__vibenvm_current)"
    NVM_ALIAS_DIR="$(__vibenvm_alias_path)"
    command mkdir -p "${NVM_ALIAS_DIR}/lts"

    # `nvm alias lts/...` is a question about one file, and answers with its
    # contents rather than a listing.
    if [ "$ALIAS" != "${ALIAS#lts/}" ]; then
        __vibenvm_alias "$ALIAS"
        return $?
    fi

    NVM_HAS_COLORS=0
    if __vibenvm_has_colors; then
        NVM_HAS_COLORS=1
    fi

    (
        for ALIAS_PATH in "${NVM_ALIAS_DIR}/${ALIAS}"*; do
            __vibenvm_print_alias_path "$NVM_ALIAS_DIR" "$ALIAS_PATH"
        done
        case 'default' in
            "$ALIAS"*)
                DEFAULT_DEST="$(__vibenvm_default_target)" &&
                    DEFAULT=false __vibenvm_print_formatted_alias 'default' "$DEFAULT_DEST"
                ;;
        esac
    ) | command sort

    (
        for ALIAS_NAME in node stable unstable iojs; do
            if [ ! -f "${NVM_ALIAS_DIR}/${ALIAS_NAME}" ] &&
                { [ -z "$ALIAS" ] || [ "$ALIAS_NAME" = "$ALIAS" ]; }; then
                __vibenvm_print_default_alias "$ALIAS_NAME"
            fi
        done
    ) | command sort

    (
        for ALIAS_PATH in "${NVM_ALIAS_DIR}/lts/${ALIAS}"*; do
            LTS_ALIAS="$(NVM_LTS=true __vibenvm_print_alias_path "$NVM_ALIAS_DIR" "$ALIAS_PATH")"
            if [ -n "$LTS_ALIAS" ]; then
                __vibenvm_echo "$LTS_ALIAS"
            fi
        done
    ) | command sort
    return 0
}

# The `(Aliases: …)` column of `nvm ls-remote`: every alias whose target is a
# version rather than a flag, as `target<TAB>name`.
__vibenvm_get_remote_aliases() {
    local NVM_ALIAS_DIR NVM_ALIAS_PATH NVM_ALIAS_NAME NVM_ALIAS_TARGET
    NVM_ALIAS_DIR="$(__vibenvm_alias_path)"
    if [ ! -d "$NVM_ALIAS_DIR" ]; then
        return 0
    fi
    # The same glob as the listing, so this never shows an alias `nvm alias`
    # omits.
    for NVM_ALIAS_PATH in "${NVM_ALIAS_DIR}/"*; do
        if [ ! -f "$NVM_ALIAS_PATH" ]; then
            continue
        fi
        NVM_ALIAS_NAME="${NVM_ALIAS_PATH##*/}"
        case "$NVM_ALIAS_NAME" in
            node | iojs | stable | unstable) continue ;;
            *[[:cntrl:]]*) continue ;;
        esac
        NVM_ALIAS_TARGET="$(__vibenvm_resolve_alias "$NVM_ALIAS_NAME" 2>/dev/null)" || continue
        case "$NVM_ALIAS_TARGET" in
            '' | --* | *[[:cntrl:]]*) continue ;;
        esac
        command printf '%s\t%s\n' "$NVM_ALIAS_TARGET" "$NVM_ALIAS_NAME"
    done
    NVM_ALIAS_TARGET="$(__vibenvm_default_target 2>/dev/null)" || return 0
    command printf '%s\t%s\n' "$NVM_ALIAS_TARGET" 'default'
}

# nvm's: an install with no default yet creates one, and says which.
__vibenvm_ensure_default_set() { # <version spelling>
    local VERSION OUTPUT EXIT_CODE
    VERSION="${1-}"
    if [ -z "$VERSION" ]; then
        __vibenvm_err 'a version is required to create the default alias'
        return 1
    elif __vibenvm_alias default >/dev/null 2>&1; then
        return 0
    fi
    OUTPUT="$(nvm alias default "$VERSION")"
    EXIT_CODE=$?
    __vibenvm_echo "Creating default alias: ${OUTPUT}"
    return $EXIT_CODE
}

# ----------------------------------------------- the recorded LTS status ---
#
# `<root>/.lts-status`, nvm's own file in nvm's own place — beside the root,
# **not** under `.cache`, because it is a record and not a cache: one line
# per version, `<version> <lts name lowercased>` or `<version> -`, in the
# order the index gave them and not sorted. nvm fills it while listing
# remote versions, and so does this: the names come from vibe's own `lts/`
# channels, so nothing here decides which version is LTS.

__vibenvm_lts_status_path() { __vibenvm_echo "$(__vibenvm_root)/.lts-status"; }

# The LTS lines vibe declares, by name. The token shape `lts/<name>` is a
# channel id and nothing else in a listing looks like one, which is why this
# reads vibe's answer without depending on its columns.
__vibenvm_lts_lines() {
    __vibenvm_vibe app versions "$VIBENVM_PACKAGE" --all 2>/dev/null |
        command grep -o 'lts/[a-z0-9][a-z0-9._-]*' |
        command sed 's|^lts/||' | command sort -u
}

# Every `<version> <lts name>` pair vibe's own `lts/` channels name.
__vibenvm_lts_map() {
    for __vibenvm_lts_name in $(__vibenvm_lts_lines); do
        for __vibenvm_lts_v in $(__vibenvm_remote_versions '' "lts/$__vibenvm_lts_name"); do
            __vibenvm_echo "${__vibenvm_lts_v} ${__vibenvm_lts_name}"
        done
    done
}

# **Learning which lines are LTS writes nvm's `lts/` aliases**, because that
# is what it does upstream: `alias/lts/<name>` naming each line's newest
# version and `alias/lts/*` naming the newest line are side effects of
# reading `index.tab` (nvm.sh 2800-2823), and everything downstream — `nvm
# alias`'s third block, `lts/-1`, `nvm use lts/iron` offline — reads those
# files afterwards. Here the lines come from vibe's channels instead of an
# index, and the files are written the same way.
#
# Prints the map it learned, so a caller needs no second question.
__vibenvm_learn_lts() {
    __vibenvm_learn_map="$(__vibenvm_lts_map)"
    [ -n "$__vibenvm_learn_map" ] || return 1
    command mkdir -p "$(__vibenvm_alias_path)/lts"
    for __vibenvm_lts_name in $(__vibenvm_lts_lines); do
        __vibenvm_lts_newest="$(__vibenvm_echo "$__vibenvm_learn_map" |
            command awk -v name="$__vibenvm_lts_name" '$2 == name { v = $1 } END { print v }')"
        [ -n "$__vibenvm_lts_newest" ] &&
            __vibenvm_make_alias "lts/$__vibenvm_lts_name" "$__vibenvm_lts_newest" >/dev/null 2>&1
    done
    # `lts/*` is the newest line, which is the line owning the newest LTS
    # version — vibe's own ordering decided that, and nothing here compares
    # one version with another.
    __vibenvm_lts_newest="$(__vibenvm_remote_versions '' lts | command tail -1)"
    if [ -n "$__vibenvm_lts_newest" ]; then
        __vibenvm_lts_name="$(__vibenvm_echo "$__vibenvm_learn_map" |
            command awk -v v="$__vibenvm_lts_newest" '$1 == v { print $2; exit }')"
        [ -n "$__vibenvm_lts_name" ] &&
            __vibenvm_make_alias 'lts/*' "lts/$__vibenvm_lts_name" >/dev/null 2>&1
    fi
    __vibenvm_echo "$__vibenvm_learn_map"
}

# `<version> <lts name>` for the versions vibe's LTS channels name, and
# `<version> -` for every other line given: the shape nvm's record holds.
__vibenvm_lts_status_rows() { # <version lines>
    __vibenvm_lts_known="$(__vibenvm_learn_lts)" || __vibenvm_lts_known=''
    __vibenvm_echo "${1-}" | NVM_LTS_MAP="$__vibenvm_lts_known" command awk '
        BEGIN {
            rows = split(ENVIRON["NVM_LTS_MAP"], lines, "\n");
            for (n = 1; n <= rows; n++) {
                split(lines[n], fields, " ");
                if (fields[1] != "") { lts[fields[1]] = fields[2] }
            }
        }
        $1 != "" { print $1, (($1 in lts) ? lts[$1] : "-") }'
}

# nvm's display rows for a remote listing: a non-LTS version alone, an LTS
# version with its line's codename, and the newest of each line with the `*`
# that marks it. The codename is capitalised for the annotation exactly as
# upstream spells it — vibe's channel ids are lowercase by rule, and nvm's
# own record lowercases them too, so the capital lives only here, where it is
# a label rather than an identifier.
__vibenvm_lts_display_rows() {
    command awk '
        { version[NR] = $1; name[NR] = $2; if ($2 != "-" && $2 != "") { newest[$2] = NR } }
        END {
            for (n = 1; n <= NR; n++) {
                if (name[n] == "-" || name[n] == "") { print version[n]; continue }
                label = toupper(substr(name[n], 1, 1)) substr(name[n], 2);
                if (newest[name[n]] == n) { print version[n], label, "*" }
                else { print version[n], label }
            }
        }'
}

# Record it, keeping the versions the new listing does not mention: a listing
# narrowed by a pattern must not erase what a full one recorded. The write is
# atomic — a temporary beside the record, then `mv -f` — because a half
# written record is worse than none.
__vibenvm_record_lts_status() { # rows on stdin
    local NVM_LTS_STATUS_PATH NVM_LTS_STATUS_TMP
    NVM_LTS_STATUS_PATH="$(__vibenvm_lts_status_path)"
    command mkdir -p "$(__vibenvm_root)" 2>/dev/null || return 1
    NVM_LTS_STATUS_TMP="$(command mktemp "${NVM_LTS_STATUS_PATH}.XXXXXX" 2>/dev/null)" || return 1
    if NVM_LTS_STATUS_PATH="$NVM_LTS_STATUS_PATH" command awk '
        BEGIN { previous = ENVIRON["NVM_LTS_STATUS_PATH"] }
        $1 ~ /^v[0-9]+\.[0-9]+\.[0-9]+/ {
            if (!($1 in lts)) { versions[++rows] = $1 }
            lts[$1] = ($2 ~ /^-?$/ ? "-" : tolower($2));
            if (lts[$1] != "-") { has_lts = 1 }
        }
        END {
            if (!rows) { exit 1 }
            # a listing with no LTS version in it cannot start the record,
            # since every version it does not name counts as not LTS
            if (!has_lts && (getline line < previous) <= 0) { exit 1 }
            close(previous);
            while ((getline line < previous) > 0) {
                split(line, fields, " ");
                if (!(fields[1] in lts)) { print fields[1], fields[2] }
            }
            for (i = 1; i <= rows; i++) { print versions[i], lts[versions[i]] }
        }
    ' >"$NVM_LTS_STATUS_TMP"; then
        command mv -f "$NVM_LTS_STATUS_TMP" "$NVM_LTS_STATUS_PATH" 2>/dev/null && return 0
    fi
    command rm -f "$NVM_LTS_STATUS_TMP"
    return 1
}

# Versions installed before the status was recorded need one listing of it.
__vibenvm_ensure_lts_status() {
    if [ -f "$(__vibenvm_lts_status_path)" ]; then
        return 0
    elif [ "${NVM_OFFLINE-}" = 1 ] || [ -n "${NVM_INDEX_NO_FETCH-}" ]; then
        return 3
    fi
    __vibenvm_record_lts_status <<EOF 2>/dev/null
$(__vibenvm_lts_status_rows "$(__vibenvm_remote_versions)")
EOF
    [ -f "$(__vibenvm_lts_status_path)" ]
}

# --------------------------------------------------- version categories ---
#
# nvm's four: `alpha`, `lts`, `non-lts` and `iojs`. They are nvm's own
# taxonomy — vibe has channels and a prerelease policy, which is a different
# idea — so the selection, its spellings and its diagnostics live here, and
# what they narrow is the list vibe answered with.
#
# A selection **narrows** an answer; it never asks vibe for a different one.
# Where nvm would have skipped past an excluded version to the next one in
# the category, this reports `N/A` with nvm's own explanation instead, since
# choosing which version a pattern selects is vibe's decision and not this
# file's.

# vN.N.N-alpha.N.N.N, and nothing else.
__vibenvm_is_alpha_version() {
    __vibenvm_alpha_version="${1#v}"
    case "$__vibenvm_alpha_version" in
        *-alpha.*) ;;
        *) return 1 ;;
    esac
    for __vibenvm_alpha_part in "${__vibenvm_alpha_version%%-alpha.*}" "${__vibenvm_alpha_version#*-alpha.}"; do
        case "$__vibenvm_alpha_part" in
            *[!0-9.]* | .* | *. | *..* | *.*.*.*) return 1 ;;
            *.*.*) ;;
            *) return 1 ;;
        esac
    done
    return 0
}

# A comma-separated selection, canonically ordered and without duplicates,
# or the one refusal — which names where the value came from, because
# `--only=`, `$NVM_ONLY` and an alias's own `--only=` are three sources and
# a user needs to know which one is wrong.
__vibenvm_normalize_only() { # <value> <source>
    local NVM_ONLY_VALUE NVM_ONLY_SOURCE NVM_ONLY_REST NVM_ONLY_RESULT NVM_ONLY_CATEGORY
    NVM_ONLY_VALUE="${1-}"
    NVM_ONLY_SOURCE="${2-}"
    NVM_ONLY_REST=",${NVM_ONLY_VALUE},"
    NVM_ONLY_RESULT=''
    case "$NVM_ONLY_VALUE" in
        '' | ,* | *, | *,,*) NVM_ONLY_REST='' ;;
    esac
    for NVM_ONLY_CATEGORY in alpha lts non-lts iojs; do
        case "$NVM_ONLY_REST" in
            *",${NVM_ONLY_CATEGORY},"*)
                NVM_ONLY_RESULT="${NVM_ONLY_RESULT:+${NVM_ONLY_RESULT},}${NVM_ONLY_CATEGORY}"
                ;;
        esac
        while :; do
            case "$NVM_ONLY_REST" in
                *",${NVM_ONLY_CATEGORY},"*)
                    NVM_ONLY_REST="${NVM_ONLY_REST%%,"${NVM_ONLY_CATEGORY}",*},${NVM_ONLY_REST#*,"${NVM_ONLY_CATEGORY}",}"
                    ;;
                *) break ;;
            esac
        done
    done
    if [ "$NVM_ONLY_REST" != ',' ]; then
        __vibenvm_err "Invalid ${NVM_ONLY_SOURCE} value \"${NVM_ONLY_VALUE}\": it must be a comma-separated list of any of: alpha, lts, non-lts, iojs"
        return 55
    fi
    __vibenvm_echo "$NVM_ONLY_RESULT"
}

# The categories in effect: the flag if given, else an enclosing command's
# selection, else `$NVM_ONLY`, else every category but alpha. An LTS
# selection picks through LTS channels, so it needs no recorded status — and
# cannot be combined with an `--only=` that excludes LTS versions.
__vibenvm_resolve_only() { # <flag count> <flag value> <lts selection>
    local NVM_ONLY_RESOLVED
    if [ "${1:-0}" -gt 1 ]; then
        __vibenvm_err '`--only` may only be provided once.'
        return 55
    elif [ "${1-}" = 1 ]; then
        NVM_ONLY_RESOLVED="$(__vibenvm_normalize_only "${2-}" '`--only`')" || return $?
    elif [ -n "${NVM_ONLY_SELECTED-}" ]; then
        __vibenvm_echo "$NVM_ONLY_SELECTED"
        return 0
    elif [ -n "${NVM_ONLY-}" ]; then
        NVM_ONLY_RESOLVED="$(__vibenvm_normalize_only "$NVM_ONLY" '`$NVM_ONLY`')" || return $?
    else
        NVM_ONLY_RESOLVED='lts,non-lts,iojs'
    fi
    if [ -n "${3-}" ]; then
        case ",${NVM_ONLY_RESOLVED}," in
            *,lts,*) ;;
            *)
                if [ "${1-}" = 1 ]; then
                    __vibenvm_err "\`--only=${2-}\` excludes LTS versions, so it cannot be combined with an LTS selection like \`--lts\`."
                    return 55
                fi
                ;;
        esac
        NVM_ONLY_RESOLVED='lts,non-lts'
    fi
    if [ -z "${NVM_NO_LTS_STATUS-}" ] && __vibenvm_needs_lts_status "$NVM_ONLY_RESOLVED" &&
        ! __vibenvm_ensure_lts_status; then
        __vibenvm_err 'The LTS status of installed versions is not recorded yet; run `nvm ls-remote` to record it.'
        return 3
    fi
    __vibenvm_echo "$NVM_ONLY_RESOLVED"
}

# Assumes the categories are already normalised.
__vibenvm_only_includes() {
    case ",${NVM_ONLY_SELECTED:-${NVM_ONLY:-lts,non-lts,iojs}}," in
        *",${1-},"*) return 0 ;;
    esac
    return 1
}

# Telling LTS from non-LTS apart needs the recorded status; wanting both, or
# neither, does not.
__vibenvm_needs_lts_status() {
    case ",${1-}," in
        *,lts,*)
            case ",${1-}," in
                *,non-lts,*) return 1 ;;
            esac
            ;;
        *,non-lts,*) ;;
        *) return 1 ;;
    esac
    return 0
}

# Keep the version lines on stdin that the selected categories include, by
# the recorded status: `system` and `N/A` always pass.
__vibenvm_filter_installed_versions() {
    local NVM_NEEDS_LTS_STATUS
    NVM_NEEDS_LTS_STATUS=0
    if __vibenvm_needs_lts_status "${NVM_ONLY_SELECTED:-${NVM_ONLY:-lts,non-lts,iojs}}"; then
        NVM_NEEDS_LTS_STATUS=1
        if [ ! -f "$(__vibenvm_lts_status_path)" ]; then
            __vibenvm_err 'The LTS status of installed versions is not recorded yet; run `nvm ls-remote` to record it.'
            return 3
        fi
    fi
    NVM_LTS_STATUS_PATH="$(__vibenvm_lts_status_path)" command awk \
        -v only=",${NVM_ONLY_SELECTED:-${NVM_ONLY:-lts,non-lts,iojs}}," \
        -v needs_lts_status="$NVM_NEEDS_LTS_STATUS" '
        BEGIN {
          if (needs_lts_status) {
            record = ENVIRON["NVM_LTS_STATUS_PATH"];
            while ((getline line < record) > 0) {
              split(line, fields, " ");
              lts[fields[1]] = fields[2];
            }
          }
        }
        {
          if ($1 == "system" || $1 == "N/A") { print; next }
          if ($1 ~ /^iojs-/) { category = "iojs" }
          else if ($1 ~ /^v[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+\.[0-9]+\.[0-9]+$/) { category = "alpha" }
          else if (!needs_lts_status) { category = index(only, ",lts,") ? "lts" : "non-lts" }
          else { category = (($1 in lts) && lts[$1] != "-") ? "lts" : "non-lts" }
          if (index(only, "," category ",")) { print }
        }'
}

# The same, for rows that carry their own LTS name — a remote listing, whose
# status came with it and needs no record.
__vibenvm_filter_remote_versions() {
    command awk -v only=",${NVM_ONLY_SELECTED:-${NVM_ONLY:-lts,non-lts,iojs}}," '
        {
          if ($1 == "system" || $1 == "N/A") { print; next }
          if ($1 ~ /^iojs-/) { category = "iojs" }
          else if ($1 ~ /^v[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+\.[0-9]+\.[0-9]+$/) { category = "alpha" }
          else if ($2 ~ /^-?$/) { category = "non-lts" }
          else { category = "lts" }
          if (index(only, "," category ",")) { print }
        }'
}

# Whether one version is in the selection at all.
__vibenvm_is_version_selected() { # <version>
    case "${1-}" in
        system) return 0 ;;
        iojs-*)
            __vibenvm_only_includes iojs
            return $?
            ;;
    esac
    if __vibenvm_is_alpha_version "${1-}"; then
        __vibenvm_only_includes alpha
        return $?
    fi
    if ! __vibenvm_needs_lts_status "${NVM_ONLY_SELECTED:-${NVM_ONLY:-lts,non-lts,iojs}}"; then
        __vibenvm_only_includes lts
        return $?
    fi
    [ -n "$(__vibenvm_echo "${1-}" | __vibenvm_filter_installed_versions 2>/dev/null)" ]
}

# nvm's own answer for a version that is not installed: which spelling, what
# it resolved to, and the command that would install it — three lines and a
# blank one, because the first thing a user needs is the next command.
__vibenvm_ensure_version_installed() { # <spelling> [<from a version file>]
    local PROVIDED_VERSION RESOLVED
    PROVIDED_VERSION="${1-}"
    if __vibenvm_explain_excluded_version "$PROVIDED_VERSION"; then
        return 1
    fi
    if RESOLVED="$(__vibenvm_resolve_alias "$PROVIDED_VERSION" 2>/dev/null)" && [ -n "$RESOLVED" ]; then
        __vibenvm_err "N/A: version \"${PROVIDED_VERSION} -> ${RESOLVED}\" is not yet installed."
    else
        __vibenvm_err "N/A: version \"$(__vibenvm_ensure_version_prefix "$PROVIDED_VERSION")\" is not yet installed."
    fi
    __vibenvm_err ''
    if [ "$PROVIDED_VERSION" = 'lts' ]; then
        __vibenvm_err '`lts` is not an alias - you may need to run `nvm install --lts` to install and `nvm use --lts` to use it.'
    elif [ "${2-}" != '1' ]; then
        __vibenvm_err "You need to run \`nvm install ${PROVIDED_VERSION}\` to install and use it."
    else
        __vibenvm_err 'You need to run `nvm install` to install and use the node version specified in `.nvmrc`.'
    fi
    return 1
}

# The categories a selection left out, which is where nvm looks again when
# nothing matched: a version it finds there is the reason, and saying so is
# the difference between "no such version" and "you told me to ignore it".
__vibenvm_excluded_categories() {
    __vibenvm_excluded=''
    for __vibenvm_category in alpha lts non-lts iojs; do
        __vibenvm_only_includes "$__vibenvm_category" ||
            __vibenvm_excluded="${__vibenvm_excluded:+${__vibenvm_excluded},}${__vibenvm_category}"
    done
    # Every alpha is a `vN.0.0`, so no other version can match one: a
    # pattern that could not name an alpha is not explained by alpha being
    # excluded.
    if [ "$__vibenvm_excluded" = 'alpha' ]; then
        case "${1#v}" in
            *[!0-9.]*) ;;
            *.*.*)
                case "${1#v}" in
                    *.0.0) ;;
                    *) __vibenvm_excluded='' ;;
                esac
                ;;
            *.*)
                case "${1#v}" in
                    *.0) ;;
                    *) __vibenvm_excluded='' ;;
                esac
                ;;
        esac
    fi
    __vibenvm_echo "$__vibenvm_excluded"
}

# nvm's explanation, and nvm's success status with it: a version that *is*
# installed but outside the selection is a different story from one that is
# not installed, and a user who sees `N/A` deserves to be told which.
__vibenvm_explain_excluded_version() { # <spelling>
    local NVM_EXCLUDED_VERSION
    NVM_EXCLUDED_VERSION="$(NVM_ONLY_SELECTED='alpha,lts,non-lts,iojs' __vibenvm_alias_version "${1-}" 2>/dev/null)" || :
    if [ "_${NVM_EXCLUDED_VERSION:-N/A}" = '_N/A' ] ||
        ! __vibenvm_is_version_installed "$NVM_EXCLUDED_VERSION"; then
        return 1
    fi
    if [ "_${NVM_EXCLUDED_VERSION}" != "_$(__vibenvm_ensure_version_prefix "${1-}")" ]; then
        NVM_EXCLUDED_VERSION="${1-} -> ${NVM_EXCLUDED_VERSION}"
    fi
    __vibenvm_err "N/A: version \"${NVM_EXCLUDED_VERSION}\" is installed, but excluded by the selected version categories (${NVM_ONLY_SELECTED:-${NVM_ONLY:-lts,non-lts,iojs}})."
    __vibenvm_err ''
    __vibenvm_err 'Include its category with `--only=<categories>`, or in `$NVM_ONLY`.'
    return 0
}

# ----------------------------------------------------------- diagnostics ---
#
# nvm's `debug`, which is a user's first answer to "why did that not work":
# the same twenty-two lines in the same order, all of them on **stderr** and
# always exit 42, with this file's and vibe's values where nvm reports nvm's,
# and one line added — the template revision, so a bug report says which
# translation produced the rest.
#
# What is *not* in it: `$NVM_AUTH_HEADER`, which nvm never prints either.

__vibenvm_has() { type "${1-}" >/dev/null 2>&1; }

# Resolves as `command "$1"` does: executables on PATH, never a function or
# an alias of the user's.
__vibenvm_has_non_aliased() {
    (
        unalias "${1-}" 2>/dev/null || true
        unset -f "${1-}" 2>/dev/null || true
        command -v "${1-}" >/dev/null 2>&1
    )
}

# Every literal occurrence of $2 in $1 replaced by $3. The values travel
# through the environment so that awk reads neither a backslash escape nor a
# regular expression in a path.
__vibenvm_replace_literal() {
    __vibenvm_echo "${1-}" | NVM_FROM="${2-}" NVM_TO="${3-}" command awk '
        BEGIN { from = ENVIRON["NVM_FROM"]; to = ENVIRON["NVM_TO"]; n = length(from) }
        {
            out = ""; s = $0
            while (n > 0 && (i = index(s, from)) > 0) {
                out = out substr(s, 1, i - 1) to
                s = substr(s, i + n)
            }
            print out s
        }'
}

# nvm's own inversion, kept: a value that *is* the root, or the home, is
# printed as it stands, and only a path **containing** one is abbreviated —
# so `${NVM_DIR}: '${NVM_DIR}'` never happens.
__vibenvm_sanitize_path() {
    __vibenvm_sanitized="${1-}"
    if [ "_${__vibenvm_sanitized}" != "_$(__vibenvm_root)" ]; then
        __vibenvm_sanitized="$(__vibenvm_replace_literal "$__vibenvm_sanitized" "$(__vibenvm_root)" '${NVM_DIR}')"
    fi
    if [ "_${__vibenvm_sanitized}" != "_${HOME}" ]; then
        __vibenvm_sanitized="$(__vibenvm_replace_literal "$__vibenvm_sanitized" "$HOME" '${HOME}')"
    fi
    __vibenvm_echo "$__vibenvm_sanitized"
}

# The `user:password@` of a URL becomes `***@`, for printing. As curl and
# wget read it, everything up to the last `@` before the path is userinfo.
__vibenvm_sanitize_url() {
    __vibenvm_echo "${1-}" | command sed -e 's#://[^/[:space:]]*@#://***@#g'
}

__vibenvm_command_info() {
    local COMMAND INFO
    COMMAND="${1-}"
    if type "$COMMAND" | command grep -q hashed; then
        INFO="$(type "$COMMAND" | command sed -E 's/\(|\)//g' | command awk '{print $4}')"
    elif type "$COMMAND" | command grep -q aliased; then
        INFO="$(command -v "$COMMAND") ($(type "$COMMAND" | command awk '{ $1=$2=$3=$4="" ;print }' | command sed -e 's/^\ *//g' -Ee "s/\`|'//g"))"
    elif type "$COMMAND" | command grep -q "^${COMMAND} is an alias for"; then
        INFO="$(command -v "$COMMAND") ($(type "$COMMAND" | command awk '{ $1=$2=$3=$4=$5="" ;print }' | command sed 's/^\ *//g'))"
    elif type "$COMMAND" | command grep -q "^${COMMAND} is /"; then
        INFO="$(type "$COMMAND" | command awk '{print $3}')"
    else
        INFO="$(type "$COMMAND")"
    fi
    __vibenvm_echo "$INFO"
}

# A fact about the machine, which is what nvm reports here. vibe verifies its
# own digests and needs none of these, so the line answers the question a
# user asks it — "can this shell check a checksum" — and not vibe's.
__vibenvm_get_checksum_binary() {
    if __vibenvm_has_non_aliased 'sha256sum'; then
        __vibenvm_echo 'sha256sum'
    elif __vibenvm_has_non_aliased 'shasum'; then
        __vibenvm_echo 'shasum'
    elif __vibenvm_has_non_aliased 'sha256'; then
        __vibenvm_echo 'sha256'
    elif __vibenvm_has_non_aliased 'gsha256sum'; then
        __vibenvm_echo 'gsha256sum'
    elif __vibenvm_has_non_aliased 'openssl'; then
        __vibenvm_echo 'openssl'
    elif __vibenvm_has_non_aliased 'bssl'; then
        __vibenvm_echo 'bssl'
    elif __vibenvm_has_non_aliased 'sha1sum'; then
        __vibenvm_echo 'sha1sum'
    elif __vibenvm_has_non_aliased 'sha1'; then
        __vibenvm_echo 'sha1'
    else
        __vibenvm_err 'Unaliased sha256sum, shasum, sha256, gsha256sum, openssl, or bssl not found.'
        __vibenvm_err 'Unaliased sha1sum or sha1 not found.'
        return 1
    fi
}

# The operating system, in nvm's own vocabulary, which the later sections
# need for their platform policy as much as `debug` does for its lines.
__vibenvm_get_os() {
    __vibenvm_uname="$(command uname -a 2>/dev/null)"
    case "$__vibenvm_uname" in
        Linux\ *) __vibenvm_echo linux ;;
        Darwin\ *) __vibenvm_echo darwin ;;
        SunOS\ *) __vibenvm_echo sunos ;;
        FreeBSD\ *) __vibenvm_echo freebsd ;;
        OpenBSD\ *) __vibenvm_echo openbsd ;;
        AIX\ *) __vibenvm_echo aix ;;
        CYGWIN* | MSYS* | MINGW*) __vibenvm_echo win ;;
        *) __vibenvm_echo '' ;;
    esac
}

# ------------------------------------------------------- npm prefix hygiene ---
#
# npm has four places to learn a `prefix` from, and any of them silently
# sends a global install outside the version a user is standing in. nvm
# refuses to activate a version while one is set, and `--delete-prefix`
# clears the ones it may. That is **npm's** conflict with a version manager,
# not nvm's with itself, and it is as true of a version vibe installed as of
# one nvm did — so the whole check lives here, where vibe has no view.

# Whether a path is inside a tree, by walking up it rather than by matching a
# prefix, so `/foo` does not contain `/foobar`.
__vibenvm_tree_contains_path() { # <tree> <path>
    local tree node_path clean_tree pathdir
    tree="${1-}"
    node_path="${2-}"
    if [ "@${tree}@" = '@@' ] || [ "@${node_path}@" = '@@' ]; then
        __vibenvm_err 'both the tree and the node path are required'
        return 2
    fi
    clean_tree="$tree"
    while [ "$clean_tree" != "${clean_tree%/}" ]; do
        clean_tree="${clean_tree%/}"
    done
    if [ -z "$clean_tree" ]; then
        clean_tree='/'
    fi
    pathdir="$node_path"
    while [ "$pathdir" != '' ] && [ "$pathdir" != '.' ] && [ "$pathdir" != '/' ] &&
        [ "$pathdir" != "$clean_tree" ]; do
        case "$pathdir" in
            */*)
                pathdir="${pathdir%/*}"
                if [ -z "$pathdir" ]; then
                    pathdir='/'
                fi
                ;;
            *) break ;;
        esac
    done
    [ "$pathdir" = "$clean_tree" ]
}

# The project npm would load a `.npmrc` from: the nearest directory upward
# holding a `package.json` or a `node_modules`.
__vibenvm_find_project_dir() {
    local path_ parent_
    path_="$PWD"
    while [ "$path_" != '' ] && [ ! -f "${path_}/package.json" ] && [ ! -d "${path_}/node_modules" ]; do
        parent_="${path_%/*}"
        [ "$parent_" != "$path_" ] || break
        path_="$parent_"
    done
    __vibenvm_echo "$path_"
}

# Whether an npmrc sets `prefix` or `globalconfig`. Fork-free on purpose: it
# runs up to four times on every `nvm use` and every `nvm install`.
__vibenvm_npmrc_bad_news_bears() { # <path>
    local NVM_NPMRC NVM_NPMRC_LINE NVM_NPMRC_KEY
    NVM_NPMRC="${1-}"
    if [ -n "$NVM_NPMRC" ] && [ -f "$NVM_NPMRC" ]; then
        while IFS= read -r NVM_NPMRC_LINE || [ -n "$NVM_NPMRC_LINE" ]; do
            case "$NVM_NPMRC_LINE" in
                *=*) NVM_NPMRC_KEY="${NVM_NPMRC_LINE%%=*}" ;;
                *) continue ;;
            esac
            NVM_NPMRC_KEY="${NVM_NPMRC_KEY%"${NVM_NPMRC_KEY##*[! ]}"}"
            case "$NVM_NPMRC_KEY" in
                prefix | globalconfig) return 0 ;;
            esac
        done <"$NVM_NPMRC"
    fi
    return 1
}

# The directory one installed version lives in, by node's own answer about
# where node is: no path arithmetic over vibe's layout here.
__vibenvm_version_dir() { # <version, without the v>
    __vibenvm_vdir="$(__vibenvm_vibe app exec "$VIBENVM_SLOT@=$1" -- \
        node -p 'process.execPath' 2>/dev/null)"
    [ -n "$__vibenvm_vdir" ] || return 1
    __vibenvm_vdir="${__vibenvm_vdir%/*}"
    __vibenvm_echo "${__vibenvm_vdir%/*}"
}

# The four checks, in npm's own precedence order, each with its own status so
# a script can tell them apart: `$PREFIX` is 3, an `NPM_CONFIG_PREFIX` in any
# case is 4, and an npmrc is 10.
__vibenvm_die_on_prefix() { # <0|1 delete> <the command to suggest> <version dir>
    local NVM_DELETE_PREFIX NVM_COMMAND NVM_VERSION_DIR
    local NVM_NPM_CONFIG_x_PREFIX_ENV NVM_CONFIG_VALUE
    local NVM_NPM_BUILTIN_NPMRC NVM_NPM_GLOBAL_NPMRC NVM_NPM_USER_NPMRC NVM_NPM_PROJECT_NPMRC
    NVM_DELETE_PREFIX="${1-}"
    case "$NVM_DELETE_PREFIX" in
        0 | 1) ;;
        *)
            __vibenvm_err 'First argument "delete the prefix" must be zero or one'
            return 1
            ;;
    esac
    NVM_COMMAND="${2-}"
    NVM_VERSION_DIR="${3-}"
    if [ -z "$NVM_COMMAND" ] || [ -z "$NVM_VERSION_DIR" ]; then
        __vibenvm_err 'Second argument "nvm command", and third argument "nvm version dir", must both be nonempty'
        return 2
    fi

    # npm looks at `$PREFIX` first, and `npm exec` in npm 7.2+ sets it to the
    # version's own directory, which is not a conflict. `--delete-prefix`
    # does **not** apply here: an environment variable is the user's to
    # unset, so the slot comes off this shell and the refusal says how.
    if [ -n "${PREFIX-}" ] && [ "$NVM_VERSION_DIR" != "$PREFIX" ]; then
        nvm deactivate >/dev/null 2>&1
        __vibenvm_err "nvm is not compatible with the \"PREFIX\" environment variable: currently set to \"${PREFIX}\""
        __vibenvm_err 'Run `unset PREFIX` to unset it.'
        return 3
    fi

    # npm normalises every `NPM_CONFIG_`-prefixed variable, so which one wins
    # is not worth replicating: if any spelling of it is set and points
    # outside this root, it errors — and names the spelling it actually found.
    NVM_NPM_CONFIG_x_PREFIX_ENV="$(command awk 'BEGIN { for (name in ENVIRON) if (toupper(name) == "NPM_CONFIG_PREFIX") { print name; break } }')"
    if [ -n "${NVM_NPM_CONFIG_x_PREFIX_ENV-}" ]; then
        eval "NVM_CONFIG_VALUE=\"\$${NVM_NPM_CONFIG_x_PREFIX_ENV}\""
        if [ -n "${NVM_CONFIG_VALUE-}" ] &&
            ! __vibenvm_tree_contains_path "$(__vibenvm_root)" "$NVM_CONFIG_VALUE" &&
            ! __vibenvm_tree_contains_path "${VIBE_SETTINGS:-$HOME/.vibe}" "$NVM_CONFIG_VALUE"; then
            nvm deactivate >/dev/null 2>&1
            __vibenvm_err "nvm is not compatible with the \"${NVM_NPM_CONFIG_x_PREFIX_ENV}\" environment variable: currently set to \"${NVM_CONFIG_VALUE}\""
            __vibenvm_err "Run \`unset ${NVM_NPM_CONFIG_x_PREFIX_ENV}\` to unset it."
            return 4
        fi
    fi

    # Then the four npmrc files npm's own stack reads: builtin, global, user
    # and project. `--prefix` is passed on every delete so npm does not walk
    # up from `$PWD` and load the project npmrc — which is untrusted, and
    # whose own `userconfig`/`globalconfig` would choose the file npm
    # rewrites.
    NVM_NPM_BUILTIN_NPMRC="${NVM_VERSION_DIR}/lib/node_modules/npm/npmrc"
    if __vibenvm_npmrc_bad_news_bears "$NVM_NPM_BUILTIN_NPMRC"; then
        if [ "_${NVM_DELETE_PREFIX}" = '_1' ]; then
            npm config --loglevel=warn delete prefix --userconfig="$NVM_NPM_BUILTIN_NPMRC" --prefix="$NVM_VERSION_DIR"
            npm config --loglevel=warn delete globalconfig --userconfig="$NVM_NPM_BUILTIN_NPMRC" --prefix="$NVM_VERSION_DIR"
        else
            __vibenvm_err "Your builtin npmrc file ($(__vibenvm_sanitize_path "$NVM_NPM_BUILTIN_NPMRC"))"
            __vibenvm_err 'has a `globalconfig` and/or a `prefix` setting, which are incompatible with nvm.'
            __vibenvm_err "Run \`${NVM_COMMAND}\` to unset it."
            return 10
        fi
    fi

    NVM_NPM_GLOBAL_NPMRC="${NVM_VERSION_DIR}/etc/npmrc"
    if __vibenvm_npmrc_bad_news_bears "$NVM_NPM_GLOBAL_NPMRC"; then
        if [ "_${NVM_DELETE_PREFIX}" = '_1' ]; then
            npm config --global --loglevel=warn delete prefix --prefix="$NVM_VERSION_DIR"
            npm config --global --loglevel=warn delete globalconfig --prefix="$NVM_VERSION_DIR"
        else
            __vibenvm_err "Your global npmrc file ($(__vibenvm_sanitize_path "$NVM_NPM_GLOBAL_NPMRC"))"
            __vibenvm_err 'has a `globalconfig` and/or a `prefix` setting, which are incompatible with nvm.'
            __vibenvm_err "Run \`${NVM_COMMAND}\` to unset it."
            return 10
        fi
    fi

    NVM_NPM_USER_NPMRC="${HOME}/.npmrc"
    if __vibenvm_npmrc_bad_news_bears "$NVM_NPM_USER_NPMRC"; then
        if [ "_${NVM_DELETE_PREFIX}" = '_1' ]; then
            npm config --loglevel=warn delete prefix --userconfig="$NVM_NPM_USER_NPMRC" --prefix="$NVM_VERSION_DIR"
            npm config --loglevel=warn delete globalconfig --userconfig="$NVM_NPM_USER_NPMRC" --prefix="$NVM_VERSION_DIR"
        else
            __vibenvm_err "Your user’s .npmrc file ($(__vibenvm_sanitize_path "$NVM_NPM_USER_NPMRC"))"
            __vibenvm_err 'has a `globalconfig` and/or a `prefix` setting, which are incompatible with nvm.'
            __vibenvm_err "Run \`${NVM_COMMAND}\` to unset it."
            return 10
        fi
    fi

    # The project npmrc is **never** modified, even by `--delete-prefix`:
    # it belongs to the project and not to this shell, so the warning is
    # printed and the activation continues.
    NVM_NPM_PROJECT_NPMRC="$(__vibenvm_find_project_dir)/.npmrc"
    if __vibenvm_npmrc_bad_news_bears "$NVM_NPM_PROJECT_NPMRC"; then
        if [ "_${NVM_DELETE_PREFIX}" = '_1' ]; then
            __vibenvm_err "Your project npmrc file ($(__vibenvm_sanitize_path "$NVM_NPM_PROJECT_NPMRC"))"
            __vibenvm_err 'has a `globalconfig` and/or a `prefix` setting, which are incompatible with nvm.'
            __vibenvm_err 'Project npmrc files are not modified by `--delete-prefix`; edit that file to unset it.'
        else
            __vibenvm_err "Your project npmrc file ($(__vibenvm_sanitize_path "$NVM_NPM_PROJECT_NPMRC"))"
            __vibenvm_err 'has a `globalconfig` and/or a `prefix` setting, which are incompatible with nvm.'
            __vibenvm_err "Run \`${NVM_COMMAND}\` to unset it."
            return 10
        fi
    fi
    return 0
}

# ---------------------------------------------------------- source builds ---
#
# `-s` builds from source, `-b` refuses to, and `-j N` says how many `make`
# jobs. In vibe the build is an **installer option** of the Node package,
# which sits under its own platform id, so the three flags are a platform and
# a parameter and nothing here compiles anything:
#
#   -s      `--platform linux-source` / `--platform macos-source`
#   -b      no flag at all — the prebuilt row is what vibe picks anyway
#   -j N    `--set jobs=N` on that option
#
# Bare `nvm install` is nvm's binary-first-then-source fallback. vibe has no
# fallback chain, because an installer option is a choice and not a sequence,
# so the fallback is two runs here: the ordinary one, and a source one if it
# failed. nvm's own validation of `-j` stays here as well, because nvm
# prints a line and carries on where vibe refuses outright — so an invalid
# count never reaches vibe.

__vibenvm_is_natural_num() {
    if [ -z "${1-}" ]; then
        return 4
    fi
    case "$1" in
        0) return 1 ;;
        -*) return 3 ;;
        *[!0-9]*) return 2 ;;
        *) [ "$1" -eq "$1" ] 2>/dev/null ;;
    esac
}

# nvm's own: an explicit count is announced, an invalid one is complained
# about and then **ignored** rather than fatal, and the default is one fewer
# than the cores. `$NVM_MAKE_JOBS` is deliberately global, as nvm's is.
__vibenvm_get_make_jobs() { # [<count>]
    local NVM_OS NVM_CPU_CORES
    if __vibenvm_is_natural_num "${1-}"; then
        NVM_MAKE_JOBS="$1"
        __vibenvm_echo "number of \`make\` jobs: ${NVM_MAKE_JOBS}"
        return 0
    elif [ -n "${1-}" ]; then
        unset NVM_MAKE_JOBS
        __vibenvm_err "$1 is invalid for number of \`make\` jobs, must be a natural number"
    fi
    NVM_OS="$(__vibenvm_get_os)"
    case "_${NVM_OS}" in
        '_linux')
            NVM_CPU_CORES="$(command grep -c -E '^processor.+: [0-9]+' /proc/cpuinfo 2>/dev/null)"
            ;;
        '_freebsd' | '_darwin' | '_openbsd')
            NVM_CPU_CORES="$(sysctl -n hw.ncpu 2>/dev/null)"
            ;;
        '_sunos')
            NVM_CPU_CORES="$(psrinfo 2>/dev/null | command wc -l | command tr -d '[:space:]')"
            ;;
        '_aix')
            NVM_CPU_CORES="$(pmcycles -m 2>/dev/null | command wc -l | command tr -d '[:space:]')"
            ;;
        *)
            NVM_CPU_CORES="$(command getconf _NPROCESSORS_ONLN 2>/dev/null ||
                command getconf NPROCESSORS_ONLN 2>/dev/null ||
                command nproc 2>/dev/null ||
                __vibenvm_echo "${NUMBER_OF_PROCESSORS-}")"
            ;;
    esac
    if ! __vibenvm_is_natural_num "$NVM_CPU_CORES"; then
        __vibenvm_err 'Can not determine how many core(s) are available, running in single-threaded mode.'
        __vibenvm_err 'Please report an issue on GitHub to help us make nvm run faster on your computer!'
        NVM_MAKE_JOBS=1
    else
        __vibenvm_echo "Detected that you have ${NVM_CPU_CORES} CPU core(s)"
        if [ "$NVM_CPU_CORES" -gt 2 ]; then
            NVM_MAKE_JOBS=$((NVM_CPU_CORES - 1))
            __vibenvm_echo "Running with ${NVM_MAKE_JOBS} threads to speed up the build"
        else
            NVM_MAKE_JOBS=1
            __vibenvm_echo 'Number of CPU core(s) less than or equal to 2, running in single-threaded mode'
        fi
    fi
}

# The platform id the Node package keeps its source rows under, for this
# machine. Empty where upstream publishes no source row for the system —
# which is vibe's refusal to give, not this file's to invent.
__vibenvm_source_platform() {
    case "$(__vibenvm_get_os)" in
        linux) __vibenvm_echo 'linux-source' ;;
        darwin) __vibenvm_echo 'macos-source' ;;
        *) __vibenvm_echo '' ;;
    esac
}

# ------------------------------------------------ download authorisation ---
#
# `$NVM_AUTH_HEADER` is the credential a private Node mirror asks for. Two
# rules of nvm's come with it and are kept exactly:
#
#   1. **It is never printed, never logged and never an argument.** Every
#      local user can read a process's arguments, so the value goes to the
#      downloader in a file that only its owner can read, and `nvm debug`
#      does not mention it.
#   2. **It is sanitised** down to `a-zA-Z0-9 :_.+/=~-`, which is the whole
#      of RFC 7235 `token68` plus what `Basic <base64>` and `Bearer <token>`
#      need, so that nothing in the value can mean anything to a shell.
#
# Where it differs from nvm: nvm downloads the archive itself and so decides
# per URL whether the header applies, attaching it only when every http(s)
# argument is under a configured mirror. Here vibe performs the download and
# knows the URLs, so containment is vibe's: the header is handed to the one
# command that downloads this slot's runtime, and to nothing else.

__vibenvm_sanitize_auth_header() {
    __vibenvm_echo "${1-}" | command tr -cd 'a-zA-Z0-9 :_.+/=~-'
}

# Put the header where vibe can read it and nobody else can, and print the
# flags that point at it. Empty when there is no header to pass.
#
# **ASSUMED vibe SURFACE** — the one assumption in this file, deliberately in
# one place so that reconciling it is one edit: a per-invocation
# `--download-header-file <path>` on the commands that download, reading one
# `Name: value` header per line. The shape is chosen so the value stays off
# the command line; if vibe spells it differently, only this function moves.
__vibenvm_auth_header_file() {
    __vibenvm_auth_value="$(__vibenvm_sanitize_auth_header "${NVM_AUTH_HEADER-}")"
    [ -n "$__vibenvm_auth_value" ] || return 0
    __vibenvm_auth_path="$(command mktemp "${TMPDIR:-/tmp}/nvm-auth.XXXXXX")" || {
        __vibenvm_err 'unable to create a temporary file for $NVM_AUTH_HEADER'
        return 1
    }
    command chmod 600 "$__vibenvm_auth_path" 2>/dev/null
    # No `nvm_echo "$value"` anywhere a terminal or a log can see it.
    command printf 'Authorization: %s\n' "$__vibenvm_auth_value" >"$__vibenvm_auth_path" || {
        command rm -f "$__vibenvm_auth_path"
        return 1
    }
    __vibenvm_echo "$__vibenvm_auth_path"
}

# --------------------------------------------------------- install locks ---
#
# Two shells installing the same version at the same time must not race on
# its directory, one replacing it while the other reads it. vibe has its own
# locks for its own work; this is nvm's advisory, per-version lock in nvm's
# own place — a **directory** under `<root>/.cache/locks`, because `mkdir` is
# atomic on every POSIX filesystem — so that two `nvm install`s serialise and
# say so in nvm's words while they wait.
#
#   $NVM_INSTALL_LOCK_TIMEOUT  seconds to wait for a held lock (default 600)
#   $NVM_INSTALL_LOCK_STALE    minutes after which a lock is assumed
#                              abandoned and stolen; 0 (default) never steals

__vibenvm_cache_dir() { __vibenvm_echo "$(__vibenvm_root)/.cache"; }

# A version is already restricted to `[0-9A-Za-z._+-]` by the time it gets
# here; anything else would be a filename this file did not intend.
__vibenvm_install_lock_name() {
    command printf '%s' "${1-}" | command tr -c '0-9A-Za-z._+-' '_'
}

__vibenvm_acquire_install_lock() { # <version>
    local VERSION LOCK_ROOT LOCK TIMEOUT STALE WAITED ANNOUNCED
    VERSION="${1-}"
    if [ -z "$VERSION" ]; then
        return 0
    fi
    LOCK_ROOT="$(__vibenvm_cache_dir)/locks"
    # A lock that cannot be created must not stop the install over it.
    command mkdir -p "$LOCK_ROOT" 2>/dev/null || return 0
    LOCK="${LOCK_ROOT}/$(__vibenvm_install_lock_name "$VERSION")"
    TIMEOUT="${NVM_INSTALL_LOCK_TIMEOUT:-600}"
    STALE="${NVM_INSTALL_LOCK_STALE:-0}"
    WAITED=0
    ANNOUNCED=0
    while ! command mkdir "$LOCK" 2>/dev/null; do
        # Steal a lock a crashed install left behind, once it is old enough.
        if [ "$STALE" != '0' ] &&
            [ -n "$(command find "$LOCK" -maxdepth 0 -type d -mmin "+${STALE}" 2>/dev/null)" ]; then
            __vibenvm_err "Removing stale install lock for ${VERSION} (older than ${STALE} minute(s))"
            command rm -rf "$LOCK" 2>/dev/null
            continue
        fi
        if [ "$WAITED" -ge "$TIMEOUT" ]; then
            __vibenvm_err "Timed out after ${TIMEOUT}s waiting for another install of ${VERSION} to finish."
            __vibenvm_err "If no other install is running, remove ${LOCK} and try again."
            return 1
        fi
        if [ "$ANNOUNCED" -eq 0 ]; then
            __vibenvm_err "Waiting for another install of ${VERSION} to finish..."
            ANNOUNCED=1
        fi
        command sleep 1
        WAITED=$((WAITED + 1))
    done
    NVM_INSTALL_LOCK="$LOCK"
    return 0
}

__vibenvm_release_install_lock() {
    if [ -n "${NVM_INSTALL_LOCK-}" ]; then
        command rmdir "$NVM_INSTALL_LOCK" 2>/dev/null ||
            command rm -rf "$NVM_INSTALL_LOCK" 2>/dev/null || true
        unset NVM_INSTALL_LOCK
    fi
}

# --------------------------------------------------------- "only once" ---
#
# There is no refusal table any more: every surface nvm has is implemented,
# so the two helpers left here are nvm's own "you said that twice", not a
# gap. The two places this file still declines something — `unalias default`
# and a source build's `./configure` parameters — say so where they happen,
# because each has a reason of its own and neither is a flag.

# nvm's "may only be provided once" for the flags it says that about: a
# second `--save`, `--default` or `--reinstall-packages-from=` is exit 6,
# not a last-one-wins silently. Takes the value already recorded, so one
# helper serves both a counter and a string.
__vibenvm_once() { # __vibenvm_once <recorded> <flag>
    case "$1" in
        '' | 0) return 0 ;;
    esac
    __vibenvm_err "nvm: $2 may only be provided once"
    return 6
}

# `--default` and `--alias=<name>` are one choice, taken once: nvm says so
# with one sentence for both, and reads `$ALIAS` to know whether it was.
__vibenvm_alias_once() {
    case "${alias_name-}" in
        '') return 0 ;;
    esac
    __vibenvm_err '--default and --alias are mutually exclusive, and may not be provided more than once'
    return 6
}

# ------------------------------------------------------------------- help --

__vibenvm_help() {
    cat <<'HELP'
nvm — nvm's commands, on vibe

Node Version Manager (org.vibevm.nvm/nvm)

Usage:
  nvm --help | help | -h            Show this message
  nvm --version | -v                Show the nvm version implemented
  nvm --vibenvm-version             Show this package's template revision
  nvm alias [<name> [<version>]]    List aliases, or point one at a version
  nvm unalias <name>                Delete one alias
  nvm install [<version>]           Install a version (the declared version
                                    file decides when none is named)
    (flags may follow the version, except the ones that select it:
     -s, -b, -j, --offline and --lts must precede it, as in nvm)
    -s | -b | -j <N>                Build from source, refuse to, or say
                                    how many `make` jobs (before the version)
    --lts | --lts=<name>            The newest LTS release, or of one line
    --default                       Make it the slot default afterwards
    --alias=<name>                  Point <name> at what you asked for
    --save | -w                     Write the resolved version into the
                                    declared version file
    --reinstall-packages-from=<v>   Carry <v>'s global npm packages over
    --copy-packages-from=<v>        The same
    --latest-npm                    Upgrade the new version's own npm
    --skip-default-packages         Do not apply your own extras list
    --no-progress | --offline       As vibe's own flags
  nvm uninstall <version>           Remove one installed version
  nvm use [<version>]               Switch this shell to a version
    --silent | --save | -w          As above; --save changes this shell
                                    and the file, never the slot default
    --delete-prefix                 Clear npm's `prefix` / `globalconfig`
                                    where it may, instead of refusing
  nvm current                       What this shell is using
  nvm deactivate                    Take the slot off this shell's PATH
  nvm run [<version>] [<args>]      Run node from one version
  nvm exec [<version>] [<cmd>]      Run a command with one version on PATH
  nvm ls [<pattern>]                Installed versions, narrowed
    --no-alias                      Without the alias listing after them
  nvm ls-remote [<pattern>]         Available versions, narrowed
  nvm version <pattern>             Resolve a pattern among installed
  nvm version-remote <pattern>      Resolve a pattern among available
  nvm which [<version>]             The path of a version's node
  nvm reinstall-packages <version>  Carry its global npm packages here
  nvm copy-packages <version>       The same
  nvm install-latest-npm            Upgrade this version's own npm
  nvm cache dir | clear             The download cache, and emptying it
  nvm debug                         Twenty-three lines about this shell
  nvm set-colors <rgBcm>            Five colour codes: installed, LTS and
                                    system, current, not installed, default
  nvm unload                        Remove nvm from this shell

Version categories, on every command that selects a version, and in
`$NVM_ONLY`: `--only=alpha,lts,non-lts,iojs` narrows what a spelling may
select. `nvm ls-remote` records which installed versions are LTS, which
telling `lts` from `non-lts` needs.

`default` is the slot's default version, which vibe remembers: `nvm alias
default <version>` moves it, and it is never a file in the alias store.

Version spellings, besides a version: `node` / `stable` / `latest` are the
newest release, `lts` and `lts/<name>` are the LTS channels, `default` is
the slot's default version and `system` takes the slot off this shell.

Two versions, two questions: `nvm --version` is the nvm release this
installation implements, as nvm's own answer is; `nvm --vibenvm-version` is
the revision of `org.vibevm.nvm/nvm`, the package that implements it, which
`nvm debug` also reports.

Every version is resolved by vibe, every install is `vibe install -g`, and
every activation is `vibe app env`: no version decision is taken here.

HELP
    __vibenvm_print_color_legend
}

# ------------------------------------------------------------------- nvm ---
#
# **How arguments are read, per subcommand, and why it differs.** This is
# nvm's own parsing discipline, taken branch by branch from the pinned
# `nvm.sh` v0.41.0, because where a flag may appear is part of the surface
# a user learned — not an implementation detail of the shim:
#
#   install          two passes. The flags that decide *which* version is
#                    installed (`-s`, `-b`, `-j`, `--offline`, `--lts`)
#                    must precede the version; the flags that decide what
#                    happens *to* it (`--save`, `--default`, `--latest-npm`,
#                    `--skip-default-packages`, `--no-progress`,
#                    `--reinstall-packages-from=`) may follow it. One
#                    appearing on the wrong side of the version is nvm's
#                    own exit 6, not a silently dropped flag.
#   uninstall        the whole list is scanned; exactly one version.
#   use, which       the whole list is scanned, flags anywhere, and the
#                    **last** version named wins. `use --` names the
#                    version next and ends the scan.
#   ls, ls-remote,   the whole list is scanned, and the **first** pattern
#   version,         named wins (nvm's `${PATTERN:-$1}`).
#   version-remote
#   run, exec        parsing stops at the first non-option, because
#                    everything after the version is the command's own
#                    argument list: a `--silent` there belongs to the
#                    command and not to nvm.
#   reinstall-pkgs   the whole list is scanned; exactly one version.
#
# A loop that stopped at the version everywhere would drop every flag
# written after it and exit 0 having done nothing, which is exactly what
# `nvm use 22 --save` did before this revision.

nvm() {
    if [ "$#" -lt 1 ]; then
        __vibenvm_help
        return 0
    fi

    local __vibenvm_silent=0
    local command_name="$1"
    shift

    local lts='' requirement='' version='' key='' rc=0
    local write_file=0 latest_npm=0 no_extras=0 alias_name='' no_alias=''
    local delete_prefix=0 nobinary=0 nosource=0 extra_params=''
    local packages_from='' plain='' progress='' offline='' pattern=''
    local lines='' listing='' from_file=0 requested='' arguments=0
    # nvm's own two painting variables, local so that a `--no-colors` on one
    # command never silences the next one.
    local NVM_NO_COLORS='' NVM_HAS_COLORS=''
    # nvm's version categories: the flag as given, how many times, and the
    # selection in effect — inherited from an enclosing `nvm` call, as nvm's
    # own local does, so a nested command does not resolve them twice.
    local only_flag='' only_count=0
    local NVM_ONLY_SELECTED="${NVM_ONLY_SELECTED-}"
    # vibe's answer about what is installed, asked once per command and
    # remembered here so that a listing of twenty aliases asks once.
    local __vibenvm_installed_cache='' __vibenvm_installed=''

    case "$command_name" in
        # --- the two that answer about themselves --------------------
        --help | -h | help)
            __vibenvm_help
            return 0
            ;;
        --version | -v)
            # nvm's own answer: the nvm version this installation
            # implements, derived from the directory vibe placed it in.
            __vibenvm_echo "$NVM_COMPAT"
            return 0
            ;;
        --vibenvm-version)
            # The other version a user may need: this package's own
            # revision, which moves when the translation moves and not when
            # nvm releases. Two questions, two answers, neither guessed.
            __vibenvm_echo "$VIBENVM_REVISION"
            return 0
            ;;

        # --- install ---------------------------------------------------
        install | i)
            # Pass one: the flags nvm reads before the version, stopping at
            # the version itself.
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --lts) lts='*' ;;
                    --lts=*) lts="${1#--lts=}" ;;
                    --default)
                        __vibenvm_alias_once || return $?
                        alias_name='default'
                        ;;
                    --alias=*)
                        __vibenvm_alias_once || return $?
                        alias_name="${1#--alias=}"
                        ;;
                    --save | -w)
                        __vibenvm_once "$write_file" '--save' || return $?
                        write_file=1
                        ;;
                    --latest-npm) latest_npm=1 ;;
                    --skip-default-packages) no_extras=1 ;;
                    --no-progress) progress='--no-progress' ;;
                    --offline) offline='--offline' ;;
                    --silent) __vibenvm_silent=1 ;;
                    --no-colors) plain='--plain' ;;
                    --reinstall-packages-from=* | --copy-packages-from=*)
                        __vibenvm_once "$packages_from" '--reinstall-packages-from' || return $?
                        packages_from="${1#*=}"
                        ;;
                    --reinstall-packages-from | --copy-packages-from)
                        # nvm takes this one only as `--flag=<version>`: the
                        # space spelling is its own exit 6, because a bare
                        # flag would swallow the version argument.
                        __vibenvm_err "If ${1} is provided, it must point to an installed version of node using \`=\`."
                        return 6
                        ;;
                    ---*)
                        __vibenvm_err 'arguments with `---` are not supported - this is likely a typo'
                        return 55
                        ;;
                    -s)
                        nobinary=1
                        if [ "$nosource" = 1 ]; then
                            __vibenvm_err '-s and -b cannot be set together since they would skip install from both binary and source'
                            return 6
                        fi
                        ;;
                    -b)
                        nosource=1
                        if [ "$nobinary" = 1 ]; then
                            __vibenvm_err '-s and -b cannot be set together since they would skip install from both binary and source'
                            return 6
                        fi
                        ;;
                    -j)
                        # The count is the next argument and nothing else:
                        # nvm has no `-j4` and no `--parallel`.
                        shift
                        __vibenvm_get_make_jobs "${1-}"
                        # The loop's own `shift` consumes the count; where
                        # there was none there is nothing left to consume.
                        [ "$#" -gt 0 ] || break
                        ;;
                    --only | --only=*)
                        only_flag="${1#--only}"
                        only_flag="${only_flag#=}"
                        only_count=$((only_count + 1))
                        ;;
                    --) ;;
                    *) break ;;
                esac
                shift
            done
            if [ -n "$lts" ]; then
                requirement="$(__vibenvm_requirement "lts/$lts")" || return $?
                # nvm narrows an LTS selection with a pattern written beside
                # it, so the pattern is consumed here. Left behind, it would
                # be read as something else entirely further down.
                case "${1-}" in
                    '' | -*) ;;
                    *)
                        requested="$1"
                        shift
                        ;;
                esac
            elif [ -n "${1-}" ]; then
                # The spelling the user typed is kept as well as the
                # requirement it becomes: an alias records what was asked
                # for, not what it resolved to, exactly as nvm's does.
                requested="$1"
                requirement="$(__vibenvm_requirement "$1")" || return $?
                shift
            else
                # No version named: `vibe install -g` with no version
                # consults the declared version file itself, so this file
                # neither reads nor translates what the file says. The one
                # question left is nvm's own refusal when there is no file
                # at all to read.
                if [ -z "$(__vibenvm_version_file_field requested)" ]; then
                    __vibenvm_err 'nvm: no version named, and no declared version file of this directory asks for one'
                    return 3
                fi
                from_file=1
            fi
            # Pass two: the flags nvm accepts after the version, and its own
            # refusal for the ones that had to be read before it. What is
            # left of `"$@"` here is exactly what nvm's second loop sees.
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --default)
                        __vibenvm_alias_once || return $?
                        alias_name='default'
                        ;;
                    --alias=*)
                        __vibenvm_alias_once || return $?
                        alias_name="${1#--alias=}"
                        ;;
                    --save | -w)
                        __vibenvm_once "$write_file" '--save' || return $?
                        write_file=1
                        ;;
                    --latest-npm) latest_npm=1 ;;
                    --skip-default-packages) no_extras=1 ;;
                    --no-progress) progress='--no-progress' ;;
                    --silent) __vibenvm_silent=1 ;;
                    --no-colors) plain='--plain' ;;
                    --reinstall-packages-from=* | --copy-packages-from=*)
                        __vibenvm_once "$packages_from" '--reinstall-packages-from' || return $?
                        packages_from="${1#*=}"
                        ;;
                    --reinstall-packages-from | --copy-packages-from)
                        __vibenvm_err "If ${1} is provided, it must point to an installed version of node using \`=\`."
                        return 6
                        ;;
                    --only | --only=*)
                        only_flag="${1#--only}"
                        only_flag="${only_flag#=}"
                        only_count=$((only_count + 1))
                        ;;
                    ---*)
                        __vibenvm_err 'arguments with `---` are not supported - this is likely a typo'
                        return 55
                        ;;
                    -s | -b | -j | --offline | --lts | --lts=*)
                        # These select the version, or decide how it is
                        # built, so nvm demands them before it.
                        __vibenvm_err "\`$1\` must appear directly after \`nvm install\`, before the version"
                        return 6
                        ;;
                    --) ;;
                    *) extra_params="${extra_params} $1" ;;
                esac
                shift
            done

            # Validated before anything is fetched, and without demanding
            # the recorded LTS status: an install that is about to list
            # remote versions records it on the way.
            NVM_ONLY_SELECTED="$(NVM_NO_LTS_STATUS=1 __vibenvm_resolve_only \
                "$only_count" "$only_flag" "$lts")" || return $?

            local extra=''
            [ "$write_file" = 1 ] && extra="$extra --write-version-file"
            [ "$no_extras" = 1 ] && extra="$extra --no-extras"
            local target="$VIBENVM_PACKAGE"
            [ "$from_file" = 0 ] && target="$VIBENVM_PACKAGE@$requirement"

            # `$NVM_NO_SOURCE_FALLBACK` is `-b` as a standing policy, so
            # that a caller need not thread the flag through every call.
            if [ "${NVM_NO_SOURCE_FALLBACK-}" = '1' ] && [ "$nosource" != 1 ]; then
                if [ "$nobinary" = 1 ]; then
                    __vibenvm_err '-s cannot be combined with NVM_NO_SOURCE_FALLBACK=1 since that would skip install from both binary and source'
                    return 6
                fi
                nosource=1
            fi
            # nvm's own platform policy: the systems upstream publishes no
            # binary for build from source whether or not `-s` was asked for.
            case "$(__vibenvm_get_os)" in
                freebsd)
                    if [ "$nobinary" != 1 ]; then
                        nobinary=1
                        __vibenvm_err 'Currently, there is no binary for FreeBSD'
                    fi
                    ;;
                openbsd)
                    if [ "$nobinary" != 1 ]; then
                        nobinary=1
                        __vibenvm_err 'Currently, there is no binary for OpenBSD'
                    fi
                    ;;
            esac
            if [ "$nobinary" = 1 ] && [ "$(__vibenvm_get_os)" = 'win' ]; then
                __vibenvm_err 'Installing from source on non-WSL Windows is not supported'
                return 87
            fi
            if [ -n "$extra_params" ] && [ "$nobinary" = 1 ]; then
                # nvm hands anything left over to `./configure`. vibe's
                # source option takes its job count and nothing else, so this
                # says so rather than dropping the parameters silently.
                __vibenvm_err "nvm: the source installer option takes no \`./configure\` parameters, so\`${extra_params}\` cannot be passed on"
                return 55
            fi

            # Which version this install is about, before it starts: vibe
            # resolves it with nothing fetched and nothing changed, and the
            # answer names the lock. Where it cannot be had — offline, or a
            # version file this file deliberately does not read — the
            # spelling locks instead, which still serialises two runs of the
            # same command.
            local locked='' resolved='' remote_cmd='nvm ls-remote' lts_msg=''
            if [ "$from_file" = 0 ] && [ -z "$offline" ]; then
                if [ -n "$lts" ] && [ -n "$requested" ]; then
                    # A channel and a pattern are two inputs to one vibe
                    # listing, which is where both belong: the newest row it
                    # answers with is what `--lts <pattern>` selects.
                    resolved="$(__vibenvm_remote_versions "$requested" "$requirement" |
                        command tail -1)"
                    resolved="${resolved#v}"
                    [ -n "$resolved" ] && target="$VIBENVM_PACKAGE@=$resolved"
                else
                    resolved="$(__vibenvm_remote_version "$requirement" 2>/dev/null)"
                fi
                if [ -z "$resolved" ]; then
                    # Nothing to install, and nvm says so **before** it
                    # fetches anything — which is also how `-j4` is
                    # answered, since nvm has no such spelling and reads it
                    # as the version it was written in place of.
                    if [ "$lts" = '*' ]; then
                        lts_msg='(with LTS filter) '
                        remote_cmd='nvm ls-remote --lts'
                    elif [ -n "$lts" ]; then
                        lts_msg="(with LTS filter '${lts}') "
                        remote_cmd="nvm ls-remote --lts=${lts}"
                        if [ -z "$requested" ]; then
                            __vibenvm_err "Version with LTS filter '${lts}' not found - try \`${remote_cmd}\` to browse available versions."
                            return 3
                        fi
                    fi
                    __vibenvm_err "Version '${requested}' ${lts_msg}not found - try \`${remote_cmd}\` to browse available versions."
                    # Look again in only the categories that were not
                    # selected: a version found there is the explanation.
                    local excluded_categories excluded=''
                    excluded_categories="$(__vibenvm_excluded_categories "$requested")"
                    if [ -n "$excluded_categories" ] && [ -z "$lts" ]; then
                        excluded="$(NVM_ONLY_SELECTED="$excluded_categories" \
                            __vibenvm_remote_version "$requirement" 2>/dev/null)"
                    fi
                    if [ -n "$excluded" ]; then
                        __vibenvm_err "It matches v${excluded}, which is excluded by the selected version categories (${NVM_ONLY_SELECTED})."
                        __vibenvm_err 'Include its category with `--only=<categories>`, or in `$NVM_ONLY`.'
                    fi
                    return 3
                fi
            fi
            locked="${resolved:+v}${resolved:-${requested:-$requirement}}"
            # The third-party installer replaces the whole of the install
            # below — the lock, the download and the build — because that is
            # exactly what nvm hands over when it is set.
            if [ -n "${NVM_INSTALL_THIRD_PARTY_HOOK-}" ]; then
                local method='binary' hook_path
                [ "$nobinary" = 1 ] && method='source'
                # The path nvm would have installed into, in nvm's own
                # layout under this file's root: a hook written for nvm
                # expects that directory, and it is the one path here that
                # is this file's to offer.
                hook_path="$(__vibenvm_root)/versions/node/${locked}"
                __vibenvm_err '** $NVM_INSTALL_THIRD_PARTY_HOOK env var set; dispatching to third-party installation method **'
                "${NVM_INSTALL_THIRD_PARTY_HOOK}" "$locked" node std "$method" "$hook_path" || {
                    rc=$?
                    __vibenvm_err '*** Third-party $NVM_INSTALL_THIRD_PARTY_HOOK env var failed to install! ***'
                    return "$rc"
                }
                if [ ! -x "${hook_path}/bin/node" ]; then
                    __vibenvm_err '*** Third-party $NVM_INSTALL_THIRD_PARTY_HOOK env var claimed to succeed, but failed to install! ***'
                    return 33
                fi
                # A tree a third party placed is not an installation vibe
                # knows, so the activation, the default and the alias that
                # follow an ordinary install cannot follow this one. Saying
                # so is the honest end of the command.
                __vibenvm_err "nvm: ${locked} was installed into $(__vibenvm_sanitize_path "$hook_path") by \$NVM_INSTALL_THIRD_PARTY_HOOK, which vibe does not know about, so \`nvm use\` cannot select it"
                return 0
            fi

            __vibenvm_acquire_install_lock "$locked" || return 1

            local build='' jobs=''
            if [ "$nobinary" = 1 ]; then
                # A source build says how many jobs it will use before it
                # starts, as nvm's does — `-j` was validated when it was
                # parsed, but an inherited `$NVM_MAKE_JOBS` was not.
                if ! __vibenvm_is_natural_num "${NVM_MAKE_JOBS-}"; then
                    __vibenvm_get_make_jobs "${NVM_MAKE_JOBS-}"
                fi
                build="--platform $(__vibenvm_source_platform)"
                jobs="--set jobs=${NVM_MAKE_JOBS}"
            fi
            local auth_file auth=''
            auth_file="$(__vibenvm_auth_header_file)" || return 1
            [ -n "$auth_file" ] && auth="--download-header-file $auth_file"
            # Deliberate word splitting: these are vibe's own flags, each
            # one word, assembled from the nvm flags above.
            # shellcheck disable=SC2086
            __vibenvm_vibe install -g "$target" \
                $progress $offline $plain $extra $build $jobs $auth || rc=$?
            if [ "$rc" != 0 ] && [ "$nobinary" != 1 ] && [ "$nosource" != 1 ]; then
                # nvm's fallback, as two runs: the prebuilt archive was not
                # to be had, so the source option is tried.
                if ! __vibenvm_is_natural_num "${NVM_MAKE_JOBS-}"; then
                    __vibenvm_get_make_jobs "${NVM_MAKE_JOBS-}"
                fi
                if [ "$(__vibenvm_get_os)" = 'win' ]; then
                    __vibenvm_err 'Installing from source on non-WSL Windows is not supported'
                    rc=87
                else
                    rc=0
                    # shellcheck disable=SC2086
                    __vibenvm_vibe install -g "$target" \
                        $progress $offline $plain $extra $auth \
                        --platform "$(__vibenvm_source_platform)" \
                        --set "jobs=${NVM_MAKE_JOBS}" || rc=$?
                    [ "$rc" = 0 ] || __vibenvm_err "nvm: install ${locked} failed!"
                fi
            fi
            [ -n "$auth_file" ] && command rm -f "$auth_file"
            __vibenvm_release_install_lock
            if [ "$rc" != 0 ]; then
                return "$rc"
            fi

            if [ "$from_file" = 1 ]; then
                version="$(__vibenvm_version_file_field version)"
            elif [ -n "$resolved" ]; then
                # vibe already said which version this install is, before it
                # started; asking again afterwards would be asking the same
                # resolver the same question.
                version="$resolved"
            else
                version="$(__vibenvm_installed_version "$requirement")"
            fi
            if [ -z "$version" ]; then
                __vibenvm_err "nvm: vibe installed ${requirement:-what the declared version file asks for} but no installed version answers it"
                return 3
            fi
            key="$VIBENVM_PACKAGE@$version"

            if [ -n "$packages_from" ]; then
                local from
                from="$(__vibenvm_installed_version "$(__vibenvm_requirement "$packages_from")")"
                if [ -z "$from" ]; then
                    __vibenvm_err "nvm: \`$packages_from\` is not installed, so it has no global packages to carry"
                    return 3
                fi
                __vibenvm_vibe app migrate "$VIBENVM_SLOT" "$from" "$version" \
                    --only ecosystem:npm --yes || rc=$?
            fi
            if [ "$latest_npm" = 1 ]; then
                __vibenvm_vibe app extras self-upgrade "$VIBENVM_SLOT" --ecosystem npm || rc=$?
            fi
            # nvm's install leaves the shell on the version it installed.
            lines="$(__vibenvm_env --shell posix --use "$VIBENVM_SLOT==$version")" || return 3
            eval "$lines"
            # A first install gets a default, as nvm's does: a user who
            # installed exactly one version means that one.
            if [ -n "$lts" ]; then
                __vibenvm_ensure_default_set "lts/$lts"
            else
                __vibenvm_ensure_default_set "${requested:-$version}"
            fi
            # `--default` and `--alias=<name>` are last and name the version
            # **as the user wrote it**, not as it resolved: `nvm install 22
            # --alias=work` records `22`, so the alias follows the line.
            if [ -n "$alias_name" ]; then
                if [ -z "$requested" ] && [ -n "$lts" ]; then
                    nvm alias "$alias_name" "lts/$lts"
                else
                    nvm alias "$alias_name" "${requested:-v$version}"
                fi
                rc=$?
            fi
            return "$rc"
            ;;

        # --- uninstall -------------------------------------------------
        uninstall)
            # nvm scans the whole list and counts the versions it finds:
            # exactly one, or its usage refusal.
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --lts)
                        lts='*'
                        # nvm's `PATTERN` is the argument as written, and
                        # every message naming it names this, not the
                        # version spelling it was reduced to (nvm.sh
                        # 5612-5650).
                        raw_pattern="${raw_pattern:-$1}"
                        ;;
                    --lts=*)
                        lts="${1#--lts=}"
                        raw_pattern="${raw_pattern:-$1}"
                        ;;
                    --silent) __vibenvm_silent=1 ;;
                    --only | --only=*)
                        only_flag="${1#--only}"
                        only_flag="${only_flag#=}"
                        only_count=$((only_count + 1))
                        ;;
                    --) ;;
                    *)
                        if [ -n "$1" ]; then
                            requested="$1"
                            raw_pattern="${raw_pattern:-$1}"
                            arguments=$((arguments + 1))
                        fi
                        ;;
                esac
                shift
            done
            raw_pattern="${raw_pattern-}"
            if [ -n "$lts" ]; then
                requirement="$(__vibenvm_requirement "lts/$lts")" || return $?
            elif [ "$arguments" = 1 ]; then
                requirement="$(__vibenvm_requirement "$requested")" || return $?
            else
                __vibenvm_err 'Usage: nvm uninstall <version>'
                __vibenvm_err '       nvm uninstall --lts'
                __vibenvm_err '       nvm uninstall --lts=<LTS name>'
                __vibenvm_err '  Run `nvm --help` for full help.'
                return 127
            fi
            NVM_ONLY_SELECTED="$(__vibenvm_resolve_only \
                "$only_count" "$only_flag" "$lts")" || return $?
            version="$(__vibenvm_installed_version "$requirement")"
            # nvm will not remove the version the shell is standing on, and
            # neither will this: the two answers to "which version is that"
            # are node's own and vibe's, and either one naming it is enough.
            if [ -n "$version" ] &&
                { [ "_v$version" = "_$(__vibenvm_current)" ] ||
                    [ "_$version" = "_$(__vibenvm_active_version)" ]; }; then
                __vibenvm_err "nvm: Cannot uninstall currently-active node version, v${version} (inferred from ${requested:-$requirement})."
                return 1
            fi
            if [ -z "$version" ]; then
                # Two different answers, and nvm gives them two different
                # statuses: a version the categories **hid** is exit 1, and
                # a version that is simply not there is a complaint on
                # stderr and exit **0**, because `nvm_err` returns 0.
                if __vibenvm_explain_excluded_version "${requested:-$requirement}"; then
                    return 1
                fi
                # nvm names the **raw** argument here, not the version
                # spelling it was reduced to: `nvm uninstall --lts` with no
                # LTS installed says `Version '--lts' is not installed.`
                # (nvm.sh 5631, 5645 — its `PATTERN` is `$1` untouched).
                __vibenvm_uninstall_resolved="$(__vibenvm_remote_version "$requirement" 2>/dev/null)"
                if [ -n "$__vibenvm_uninstall_resolved" ] &&
                    [ "v$__vibenvm_uninstall_resolved" != "$raw_pattern" ] &&
                    [ "$__vibenvm_uninstall_resolved" != "$raw_pattern" ]; then
                    __vibenvm_err "Version 'v${__vibenvm_uninstall_resolved}' (inferred from ${raw_pattern}) is not installed."
                else
                    __vibenvm_err "Version '${raw_pattern}' is not installed."
                fi
                return 0
            fi
            __vibenvm_vibe uninstall -g "$VIBENVM_PACKAGE@=$version" || return $?
            # An alias that pointed straight at the version just removed
            # points at nothing, so nvm removes it too — and says so, which
            # is how a user learns their alias is gone.
            local alias_file alias_target
            for alias_file in "$(__vibenvm_alias_path)"/*; do
                [ -f "$alias_file" ] || continue
                alias_target="$(__vibenvm_print_alias_file "$alias_file" | command head -n 1)"
                while :; do
                    case "$alias_target" in
                        --*' '*) alias_target="${alias_target#* }" ;;
                        *) break ;;
                    esac
                done
                if [ "_$alias_target" = "_v$version" ]; then
                    nvm unalias "${alias_file##*/}"
                fi
            done
            return 0
            ;;

        # --- use / deactivate / unload ---------------------------------
        use)
            # nvm scans the whole list: a flag may stand before or after the
            # version, and the last version named wins.
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --lts) lts='*' ;;
                    --lts=*) lts="${1#--lts=}" ;;
                    --silent) __vibenvm_silent=1 ;;
                    --save | -w)
                        __vibenvm_once "$write_file" '--save' || return $?
                        write_file=1
                        ;;
                    --no-colors) plain='--plain' ;;
                    --delete-prefix) delete_prefix=1 ;;
                    --only | --only=*)
                        only_flag="${1#--only}"
                        only_flag="${only_flag#=}"
                        only_count=$((only_count + 1))
                        ;;
                    --)
                        # nvm's own rule: `--` names the version next and
                        # ends the scan, so a version spelled like a flag
                        # can still be asked for.
                        if [ -n "${2-}" ]; then
                            requested="$2"
                        fi
                        break
                        ;;
                    --*) ;;
                    *)
                        if [ -n "$1" ]; then
                            requested="$1"
                        fi
                        ;;
                esac
                shift
            done
            # An `lts/` version *is* an LTS selection, as `--lts` is.
            local lts_request=''
            case "$requested" in
                lts/*) lts_request='*' ;;
            esac
            NVM_ONLY_SELECTED="$(__vibenvm_resolve_only \
                "$only_count" "$only_flag" "${lts:-$lts_request}")" || return $?
            if [ -n "$lts" ]; then
                requirement="$(__vibenvm_requirement "lts/$lts")" || return $?
            elif [ -n "$requested" ]; then
                case "$requested" in
                    system)
                        lines="$(__vibenvm_env --shell posix --unset)" || return 3
                        eval "$lines"
                        return 0
                        ;;
                esac
                requirement="$(__vibenvm_requirement "$requested")" || return $?
            fi
            # nvm's `--save` changes the shell and the file and **not** the
            # global default, and so does this: `vibe app env` is the
            # activation surface and writes the file itself, where
            # `vibe app use` would have moved the slot default with it.
            local saving=''
            [ "$write_file" = 1 ] && saving='--write-version-file'
            if [ -z "$requirement" ]; then
                # nvm's bare `use`: the declared version file decides.
                lines="$(__vibenvm_env --shell posix --project)" || return 3
                eval "$lines"
                version="$(__vibenvm_current)"
                case "$version" in
                    none | system)
                        __vibenvm_err 'nvm: no version named and no declared version file of this directory resolves to an installed version'
                        return 3
                        ;;
                esac
                version="${version#v}"
                if [ "$write_file" = 1 ]; then
                    # The file the resolution read is the file it records,
                    # and the write names the version rather than the
                    # project, because a `--project` resolution may answer
                    # for several slots at once.
                    __vibenvm_vibe app env --shell posix \
                        --use "$VIBENVM_SLOT==$version" \
                        --write-version-file >/dev/null || return $?
                fi
            else
                version="$(__vibenvm_installed_version "$requirement")"
                if [ -z "$version" ]; then
                    __vibenvm_ensure_version_installed "${requested:-$requirement}"
                    return 3
                fi
                # shellcheck disable=SC2086
                lines="$(__vibenvm_env --shell posix --use "$VIBENVM_SLOT==$version" $saving)" || return 3
                eval "$lines"
                if [ "$write_file" = 1 ] &&
                    ! NVM_ONLY_SELECTED='' __vibenvm_is_version_selected "v$version" 2>/dev/null; then
                    # A version file cannot store the categories that chose
                    # this version, so reading it back will need them again.
                    __vibenvm_err "Warning: v${version} is not in the default version categories (${NVM_ONLY:-lts,non-lts,iojs}), so using the declared version file needs \`--only=\`, or \`\$NVM_ONLY\`, to include it."
                fi
            fi
            # The version is on this shell's PATH now, so npm's own prefix
            # settings decide where its global installs land: nvm checks
            # them here, and a failure is `nvm use` returning 11 whatever
            # the check's own status was.
            local use_command="nvm use --delete-prefix"
            [ -n "$requested" ] && use_command="${use_command} v${version}"
            [ "${__vibenvm_silent:-0}" = 1 ] && use_command="${use_command} --silent"
            key="$(__vibenvm_version_dir "$version")"
            if [ -n "$key" ] &&
                ! __vibenvm_die_on_prefix "$delete_prefix" "$use_command" "$key"; then
                return 11
            fi
            return 0
            ;;
        deactivate)
            # No `--delete-prefix` here, as nvm has none: taking the slot off
            # this shell cannot conflict with a prefix, so there is nothing
            # to delete.
            case "${1-}" in
                --silent) __vibenvm_silent=1 ;;
            esac
            lines="$(__vibenvm_env --shell posix --unset)" || return 3
            eval "$lines"
            return 0
            ;;
        unload)
            lines="$(__vibenvm_vibe app env --shell posix --unset 2>/dev/null)" && eval "$lines"
            unset -f nvm __vibenvm_echo __vibenvm_err __vibenvm_vibe \
                __vibenvm_derive_compat \
                __vibenvm_requirement __vibenvm_installed_version \
                __vibenvm_remote_version __vibenvm_version_file_field \
                __vibenvm_default_version __vibenvm_current __vibenvm_env \
                __vibenvm_installed_versions __vibenvm_remote_versions \
                __vibenvm_active_version \
                __vibenvm_reverse __vibenvm_system_node \
                __vibenvm_echo_with_colors __vibenvm_err_with_colors \
                __vibenvm_has_colors __vibenvm_has_italics __vibenvm_char \
                __vibenvm_print_color_code __vibenvm_get_colors \
                __vibenvm_wrap_with_color_code __vibenvm_print_color_legend \
                __vibenvm_set_colors __vibenvm_print_versions \
                __vibenvm_root __vibenvm_alias_path \
                __vibenvm_ensure_version_prefix __vibenvm_normalize_lts \
                __vibenvm_print_alias_file __vibenvm_default_target \
                __vibenvm_is_version_installed __vibenvm_alias \
                __vibenvm_make_alias __vibenvm_resolve_alias \
                __vibenvm_resolve_local_alias __vibenvm_validate_implicit_alias \
                __vibenvm_print_implicit_alias __vibenvm_alias_version \
                __vibenvm_print_formatted_alias __vibenvm_print_alias_path \
                __vibenvm_print_default_alias __vibenvm_list_aliases \
                __vibenvm_get_remote_aliases __vibenvm_ensure_default_set \
                __vibenvm_lts_status_path __vibenvm_lts_lines \
                __vibenvm_lts_map __vibenvm_learn_lts \
                __vibenvm_lts_status_rows __vibenvm_lts_display_rows \
                __vibenvm_record_lts_status __vibenvm_ensure_lts_status \
                __vibenvm_is_alpha_version __vibenvm_normalize_only \
                __vibenvm_resolve_only __vibenvm_only_includes \
                __vibenvm_needs_lts_status __vibenvm_filter_installed_versions \
                __vibenvm_filter_remote_versions __vibenvm_is_version_selected \
                __vibenvm_excluded_categories __vibenvm_explain_excluded_version \
                __vibenvm_ensure_version_installed \
                __vibenvm_has __vibenvm_has_non_aliased \
                __vibenvm_replace_literal __vibenvm_sanitize_path \
                __vibenvm_sanitize_url __vibenvm_command_info \
                __vibenvm_get_checksum_binary __vibenvm_get_os \
                __vibenvm_tree_contains_path __vibenvm_find_project_dir \
                __vibenvm_npmrc_bad_news_bears __vibenvm_version_dir \
                __vibenvm_die_on_prefix \
                __vibenvm_sanitize_auth_header __vibenvm_auth_header_file \
                __vibenvm_is_natural_num __vibenvm_get_make_jobs \
                __vibenvm_source_platform \
                __vibenvm_cache_dir __vibenvm_install_lock_name \
                __vibenvm_acquire_install_lock __vibenvm_release_install_lock \
                __vibenvm_once __vibenvm_alias_once \
                __vibenvm_help 2>/dev/null
            unset NVM_COMPAT VIBENVM_REVISION VIBENVM_SLOT VIBENVM_PACKAGE \
                __vibenvm_req_value __vibenvm_req_default \
                __vibenvm_cur_node __vibenvm_self __vibenvm_num_colors \
                __vibenvm_char_rest __vibenvm_char_n __vibenvm_colors \
                __vibenvm_color __vibenvm_wrap_code __vibenvm_lts_value \
                __vibenvm_lts_n __vibenvm_lts_result __vibenvm_alias_line \
                __vibenvm_def_version __vibenvm_alias_name \
                __vibenvm_alias_file __vibenvm_implicit_list \
                __vibenvm_target __vibenvm_target_req __vibenvm_target_version \
                __vibenvm_installed_cache __vibenvm_iv __vibenvm_rv \
                __vibenvm_lts_name __vibenvm_lts_v __vibenvm_lts_newest \
                __vibenvm_learn_map __vibenvm_lts_known \
                __vibenvm_target_lts __vibenvm_target_only \
                __vibenvm_alpha_version __vibenvm_alpha_part \
                __vibenvm_excluded __vibenvm_category \
                __vibenvm_sanitized __vibenvm_uname __vibenvm_vdir \
                NVM_INSTALL_LOCK NVM_MAKE_JOBS \
                __vibenvm_auth_value __vibenvm_auth_path 2>/dev/null
            return 0
            ;;

        # --- current ---------------------------------------------------
        current)
            __vibenvm_current
            return 0
            ;;

        # --- run / exec ------------------------------------------------
        run | exec)
            # Parsing stops at the first non-option, as nvm's does: what
            # follows is the command's own argument list, and a `--silent`
            # there is the command's flag rather than nvm's. An empty
            # argument is skipped rather than ending the scan.
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --lts) lts='*' ;;
                    --lts=*) lts="${1#--lts=}" ;;
                    --silent) __vibenvm_silent=1 ;;
                    --only | --only=*)
                        only_flag="${1#--only}"
                        only_flag="${only_flag#=}"
                        only_count=$((only_count + 1))
                        ;;
                    --)
                        shift
                        break
                        ;;
                    --*)
                        # `exec` refuses an option it does not know, as nvm
                        # does; `run` hands it to node, which is nvm's own
                        # asymmetry and not an oversight here.
                        if [ "$command_name" = exec ]; then
                            __vibenvm_err "Unsupported option \"$1\"."
                            return 55
                        fi
                        break
                        ;;
                    '') ;;
                    *) break ;;
                esac
                shift
            done
            NVM_ONLY_SELECTED="$(__vibenvm_resolve_only \
                "$only_count" "$only_flag" "$lts")" || return $?
            if [ -n "$lts" ]; then
                requirement="$(__vibenvm_requirement "lts/$lts")" || return $?
                version="$(__vibenvm_installed_version "$requirement")"
            elif [ -n "${1-}" ]; then
                # nvm's own rule: the first argument is the version when it
                # resolves to one, and the command's own first word when it
                # does not.
                version="$(__vibenvm_installed_version "$(__vibenvm_requirement "$1" 2>/dev/null)" 2>/dev/null)"
                if [ -n "$version" ]; then
                    shift
                fi
            fi
            if [ -z "$version" ]; then
                # **A version the selected categories hid is not "no
                # version named"**, and nvm says so before it falls back:
                # `nvm run --only=lts <a non-LTS version>` explains the
                # exclusion and exits 1 (nvm.sh 6006 for `run`, 6562 for
                # `exec`). Falling through to this shell's own version
                # would run the wrong one and exit 0, which is the worst
                # of the three possible answers.
                if [ -n "${1-}" ] && __vibenvm_explain_excluded_version "$1"; then
                    return 1
                fi
                version="$(__vibenvm_current)"
                case "$version" in
                    none | system)
                        __vibenvm_err 'nvm: no version named and this shell is not using one'
                        return 3
                        ;;
                esac
                version="${version#v}"
            fi
            if [ "$command_name" = run ]; then
                __vibenvm_vibe app exec "$VIBENVM_SLOT@=$version" -- node "$@"
            else
                __vibenvm_vibe app exec "$VIBENVM_SLOT@=$version" -- "$@"
            fi
            return $?
            ;;

        # --- listings --------------------------------------------------
        ls | list)
            # The whole list is scanned, and the first pattern named wins
            # (nvm's `PATTERN="${PATTERN:-$1}"`).
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --no-colors) NVM_NO_COLORS="$1" ;;
                    --no-alias) no_alias="$1" ;;
                    --only | --only=*)
                        only_flag="${1#--only}"
                        only_flag="${only_flag#=}"
                        only_count=$((only_count + 1))
                        ;;
                    --) ;;
                    --*)
                        __vibenvm_err "Unsupported option \"$1\"."
                        return 55
                        ;;
                    *)
                        if [ -z "$pattern" ]; then
                            pattern="$1"
                        fi
                        ;;
                esac
                shift
            done
            # `node` is nvm's name for the whole node flavour, not a
            # version pattern: it asks for the same list the bare spelling
            # does.
            case "$pattern" in
                node) pattern='' ;;
            esac
            if [ -n "$pattern" ] && [ -n "$no_alias" ]; then
                __vibenvm_err '`--no-alias` is not supported when a pattern is provided.'
                return 55
            fi
            NVM_ONLY_SELECTED="$(__vibenvm_resolve_only \
                "$only_count" "$only_flag" '')" || return $?
            # nvm's `ls <pattern>` is every installed version the pattern
            # selects. `vibe app versions` takes the pattern with the same
            # prefix rule, so the spelling is handed over as the user wrote
            # it and this file does no matching of its own.
            # A named alias is a pattern too: `nvm ls work` lists what
            # `work` resolves to, because nvm resolves the pattern before
            # it matches (`nvm_ls` → `nvm_resolve_local_alias`). Only a
            # name the store actually holds is translated — every other
            # spelling is handed over as the user wrote it, so this file
            # still does no matching of its own.
            __vibenvm_ls_pattern="$pattern"
            if [ -n "$pattern" ] && [ -f "$(__vibenvm_alias_path)/$pattern" ]; then
                __vibenvm_ls_resolved="$(__vibenvm_resolve_local_alias "$pattern" 2>/dev/null)"
                case "$__vibenvm_ls_resolved" in
                    '' | 'N/A' | '∞') ;;
                    *) __vibenvm_ls_pattern="${__vibenvm_ls_resolved#v}" ;;
                esac
            fi
            listing="$(__vibenvm_installed_versions "$__vibenvm_ls_pattern" |
                __vibenvm_filter_installed_versions)" || return $?
            if [ -z "$pattern" ] && [ -n "$(__vibenvm_system_node)" ]; then
                # nvm's own last row: the node a shell finds with the slot
                # off is a version a user may switch to.
                listing="${listing:+$listing
}system"
            fi
            __vibenvm_installed="$listing"
            if [ -z "$listing" ]; then
                listing='N/A'
                __vibenvm_installed=''
                rc=3
            fi
            __vibenvm_print_versions "$listing"
            # nvm ends a full listing with its aliases, because an alias is
            # one more way to name a version a user has.
            if [ -z "$no_alias" ] && [ -z "$pattern" ]; then
                if [ -n "$NVM_NO_COLORS" ]; then
                    nvm alias --no-colors
                else
                    nvm alias
                fi
            fi
            return "$rc"
            ;;
        ls-remote | list-remote)
            # As `ls`: the whole list, first pattern wins. `--lts` and a
            # pattern narrow together — nvm passes both to its own
            # `nvm_remote_versions`, and here they are the channel and the
            # pattern of one `vibe app versions`.
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --lts) lts='*' ;;
                    --lts=*) lts="${1#--lts=}" ;;
                    --no-colors) NVM_NO_COLORS="$1" ;;
                    --only | --only=*)
                        only_flag="${1#--only}"
                        only_flag="${only_flag#=}"
                        only_count=$((only_count + 1))
                        ;;
                    --) ;;
                    --*)
                        __vibenvm_err "Unsupported option \"$1\"."
                        return 55
                        ;;
                    *)
                        if [ -z "$pattern" ]; then
                            pattern="$1"
                        fi
                        ;;
                esac
                shift
            done
            # As for `ls`: `node` names the flavour, which is the whole list.
            case "$pattern" in
                node) pattern='' ;;
                # An `lts/` pattern *is* an LTS selection, as it is for nvm,
                # so it becomes the channel rather than a version pattern no
                # resolver could read.
                'lts/*' | lts)
                    [ -z "$lts" ] && lts='*'
                    pattern=''
                    ;;
                lts/*)
                    [ -z "$lts" ] && lts="${pattern#lts/}"
                    pattern=''
                    ;;
            esac
            NVM_ONLY_SELECTED="$(NVM_NO_LTS_STATUS=1 __vibenvm_resolve_only \
                "$only_count" "$only_flag" "$lts")" || return $?
            local channel=''
            if [ -n "$lts" ]; then
                channel="$(__vibenvm_requirement "lts/$lts")" || return $?
            fi
            # The rows carry their own LTS status, as nvm's index.tab rows
            # do: it is recorded on the way past — this is the listing nvm
            # tells a user to run — and it answers the category filter and
            # the `(LTS: …)` columns without a second question.
            listing="$(__vibenvm_lts_status_rows "$(__vibenvm_remote_versions "$pattern" "$channel")")"
            if [ -n "$listing" ]; then
                __vibenvm_record_lts_status <<EOF 2>/dev/null || :
$listing
EOF
            fi
            listing="$(__vibenvm_echo "$listing" | __vibenvm_filter_remote_versions |
                __vibenvm_lts_display_rows)"
            __vibenvm_installed="$(__vibenvm_installed_versions)"
            if [ -z "$listing" ]; then
                __vibenvm_print_versions 'N/A'
                return 3
            fi
            # A full remote listing names the aliases that point into it, as
            # nvm's does; a narrowed one does not, because the columns would
            # be about versions the listing does not show.
            local latest_alias='' named_aliases=''
            if [ -z "$lts" ] && [ -z "$pattern" ]; then
                latest_alias='node'
                named_aliases="$(__vibenvm_get_remote_aliases)"
            fi
            __vibenvm_print_versions "$listing" "$latest_alias" "$named_aliases"
            return 0
            ;;
        version | version-remote)
            # The whole list, first pattern wins. `version` has no `--lts`
            # of its own upstream and no unknown-option refusal; accepting
            # the channel flag for both spellings is the one place this file
            # is a superset, and it costs nothing a user could trip over.
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --lts) lts='*' ;;
                    --lts=*) lts="${1#--lts=}" ;;
                    --only | --only=*)
                        only_flag="${1#--only}"
                        only_flag="${only_flag#=}"
                        only_count=$((only_count + 1))
                        ;;
                    --) ;;
                    --*)
                        __vibenvm_err "nvm: unsupported option \`$1\`"
                        return 55
                        ;;
                    *)
                        if [ -z "$pattern" ]; then
                            pattern="$1"
                        fi
                        ;;
                esac
                shift
            done
            NVM_ONLY_SELECTED="$(__vibenvm_resolve_only \
                "$only_count" "$only_flag" "$lts")" || return $?
            if [ -n "$lts" ]; then
                requirement="$(__vibenvm_requirement "lts/$lts")" || return $?
            else
                requirement="$(__vibenvm_requirement "${pattern:-latest}")" || return $?
            fi
            if [ "$command_name" = version ]; then
                version="$(__vibenvm_installed_version "$requirement")"
            else
                version="$(__vibenvm_remote_version "$requirement")"
            fi
            if [ -z "$version" ]; then
                __vibenvm_echo 'N/A'
                return 3
            fi
            __vibenvm_echo "v$version"
            return 0
            ;;
        which)
            # The whole list, and the last version named wins — nvm's
            # `provided_version="${1-}"`, assigned rather than defaulted.
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --silent) __vibenvm_silent=1 ;;
                    --only | --only=*)
                        only_flag="${1#--only}"
                        only_flag="${only_flag#=}"
                        only_count=$((only_count + 1))
                        ;;
                    --) ;;
                    *)
                        if [ -n "$1" ]; then
                            pattern="$1"
                        fi
                        ;;
                esac
                shift
            done
            local which_lts_request=''
            case "$pattern" in
                lts/*) which_lts_request='*' ;;
            esac
            NVM_ONLY_SELECTED="$(__vibenvm_resolve_only \
                "$only_count" "$only_flag" "$which_lts_request")" || return $?
            case "${pattern:-current}" in
                current)
                    __vibenvm_cur_node="$(command -v node 2>/dev/null)"
                    if [ -z "$__vibenvm_cur_node" ]; then
                        __vibenvm_echo 'N/A'
                        return 3
                    fi
                    __vibenvm_echo "$__vibenvm_cur_node"
                    return 0
                    ;;
                system)
                    # The node a shell finds with the slot off, which is a
                    # real answer and not vibe's business to give.
                    key="$(__vibenvm_system_node)"
                    if [ -z "$key" ]; then
                        __vibenvm_err 'System version of node not found.'
                        return 127
                    fi
                    __vibenvm_echo "$key"
                    return 0
                    ;;
            esac
            requirement="$(__vibenvm_requirement "$pattern" 2>/dev/null)" || requirement=''
            version=''
            [ -n "$requirement" ] && version="$(__vibenvm_installed_version "$requirement")"
            if [ -z "$version" ]; then
                # nvm's status here is **1**, not 3, and the answer is on
                # stderr rather than an `N/A` on stdout: `nvm which` is a
                # question about an installed version, and "the categories
                # hid it" and "it is not installed" are one answer with two
                # explanations.
                __vibenvm_ensure_version_installed "$pattern"
                return 1
            fi
            # node's own answer about where node is: no path arithmetic here.
            __vibenvm_vibe app exec "$VIBENVM_SLOT@=$version" -- node -p 'process.execPath'
            return $?
            ;;

        # --- the ecosystem verbs ---------------------------------------
        reinstall-packages | copy-packages)
            # The whole list is scanned and exactly one version counted, as
            # nvm's own `NVM_REINSTALL_ARGS` does.
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --only | --only=*)
                        only_flag="${1#--only}"
                        only_flag="${only_flag#=}"
                        only_count=$((only_count + 1))
                        ;;
                    --) ;;
                    *)
                        if [ -n "$1" ]; then
                            pattern="$1"
                            arguments=$((arguments + 1))
                        fi
                        ;;
                esac
                shift
            done
            if [ "$arguments" != 1 ]; then
                __vibenvm_err "Usage: nvm ${command_name} <version>"
                __vibenvm_err '  Run `nvm --help` for full help.'
                return 127
            fi
            NVM_ONLY_SELECTED="$(__vibenvm_resolve_only \
                "$only_count" "$only_flag" '')" || return $?
            version="$(__vibenvm_installed_version "$(__vibenvm_requirement "$pattern")")"
            if [ -z "$version" ]; then
                __vibenvm_err "nvm: \`$pattern\` is not installed"
                return 3
            fi
            key="$(__vibenvm_current)"
            case "$key" in
                none | system)
                    __vibenvm_err 'nvm: this shell is not using a version, so there is nowhere to carry packages to'
                    return 3
                    ;;
            esac
            __vibenvm_vibe app migrate "$VIBENVM_SLOT" "$version" "${key#v}" \
                --only ecosystem:npm --yes
            return $?
            ;;
        install-latest-npm)
            __vibenvm_vibe app extras self-upgrade "$VIBENVM_SLOT" --ecosystem npm
            return $?
            ;;

        # --- the cache -------------------------------------------------
        cache)
            case "${1-}" in
                dir)
                    # Where vibe keeps the archives it fetched for an
                    # application (PROP-059 `#source-build`).
                    key="$(__vibenvm_vibe cache path)" || return $?
                    __vibenvm_echo "$key/app-sources"
                    return 0
                    ;;
                clear)
                    __vibenvm_vibe cache clean --all --assume-yes
                    return $?
                    ;;
                *)
                    __vibenvm_err 'nvm: cache takes `dir` or `clear`'
                    return 3
                    ;;
            esac
            ;;
        clear-cache)
            __vibenvm_vibe cache clean --all --assume-yes
            return $?
            ;;

        # --- the alias store -------------------------------------------
        alias)
            # nvm's own parsing, position by position: the first bare word is
            # the name and the second is the target, `--` standing for "not
            # given" so that an **empty** target can mean `unalias`.
            local alias_name='--' target='--' alias_flags=''
            local NVM_CURRENT
            NVM_CURRENT="$(__vibenvm_current)"
            command mkdir -p "$(__vibenvm_alias_path)/lts"
            while [ "$#" -gt 0 ]; do
                case "${1-}" in
                    --) ;;
                    --no-colors) NVM_NO_COLORS="$1" ;;
                    --lts=)
                        __vibenvm_err '`--lts=` needs an LTS name.'
                        return 55
                        ;;
                    --lts | --lts=*)
                        if [ -n "$alias_flags" ]; then
                            __vibenvm_err '`--lts` may only be provided once.'
                            return 55
                        fi
                        case "${1#--lts=}" in
                            *[!abcdefghijklmnopqrstuvwxyz0123456789._-]*)
                                __vibenvm_err 'LTS names must be lowercase'
                                return 3
                                ;;
                        esac
                        alias_flags="$1"
                        ;;
                    --only | --only=*)
                        only_flag="${1#--only}"
                        only_flag="${only_flag#=}"
                        only_count=$((only_count + 1))
                        ;;
                    --*)
                        __vibenvm_err "Unsupported option \"$1\"."
                        return 55
                        ;;
                    *)
                        if [ "$alias_name" = '--' ]; then
                            alias_name="${1-}"
                        elif [ "$target" = '--' ]; then
                            target="${1-}"
                        fi
                        ;;
                esac
                shift
            done

            # Resolving an alias's target checks for the recorded LTS
            # status if it needs it, which is why this is not deferred.
            NVM_ONLY_SELECTED="$(NVM_NO_LTS_STATUS=1 __vibenvm_resolve_only \
                "$only_count" "$only_flag" "$alias_flags")" || return $?

            if [ -z "$target" ]; then
                # An explicitly empty target means: remove it.
                nvm unalias "$alias_name"
                return $?
            elif __vibenvm_echo "$alias_name" | command grep -q '#'; then
                __vibenvm_err 'Aliases with a comment delimiter (#) are not supported.'
                return 1
            elif [ "$target" != '--' ]; then
                if [ "${alias_name#*/}" != "$alias_name" ]; then
                    __vibenvm_err 'Aliases in subdirectories are not supported.'
                    return 1
                fi
                if [ "$only_count" -gt 0 ]; then
                    # An alias remembers the categories that chose its
                    # target, so that resolving it later chooses the same
                    # one; the flags are stored before the target, in nvm's
                    # own order.
                    alias_flags="--only=$(__vibenvm_normalize_only "$only_flag" '`--only`')${alias_flags:+ ${alias_flags}}"
                fi
                target="${alias_flags:+${alias_flags} }${target}"
                version="$(__vibenvm_alias_version "$target")"
                if [ "$version" = 'N/A' ] && ! __vibenvm_explain_excluded_version "$target"; then
                    __vibenvm_err "! WARNING: Version '${target}' does not exist."
                fi
                if [ "$alias_name" = 'default' ]; then
                    # The slot default is vibe's, so this is `vibe app use`
                    # and no file at all. A default that named nothing
                    # installed would be a default vibe could not honour, so
                    # unlike a store alias it is a refusal rather than a
                    # dangling row.
                    if [ "$version" = 'N/A' ]; then
                        __vibenvm_err "nvm: the \`$VIBENVM_SLOT\` slot's default must name an installed version"
                        return 3
                    fi
                    # `vibe app use` takes an installation key, which names
                    # the version exactly and is not a requirement.
                    __vibenvm_vibe app use "$VIBENVM_SLOT" \
                        "$VIBENVM_PACKAGE@${version#v}" >/dev/null || return $?
                else
                    __vibenvm_make_alias "$alias_name" "$target" || return $?
                fi
                DEFAULT=false __vibenvm_print_formatted_alias \
                    "$alias_name" "$target" "$version"
                return 0
            elif [ -n "$alias_flags" ]; then
                __vibenvm_err "\`${alias_flags}\` needs a target version, like \`nvm alias ${alias_name#--} ${alias_flags} node\`."
                return 55
            else
                if [ "$alias_name" = '--' ]; then
                    alias_name=''
                fi
                __vibenvm_list_aliases "$alias_name"
                return $?
            fi
            ;;
        unalias)
            local alias_dir
            alias_dir="$(__vibenvm_alias_path)"
            command mkdir -p "$alias_dir"
            if [ "$#" -ne 1 ]; then
                __vibenvm_err 'Usage: nvm unalias <name>'
                __vibenvm_err '  Run `nvm --help` for full help.'
                return 127
            fi
            if [ "${1#*/}" != "${1-}" ]; then
                __vibenvm_err 'Aliases in subdirectories are not supported.'
                return 1
            fi
            if [ "$1" = 'default' ]; then
                # The one alias this file does not own. vibe has no verb that
                # forgets a remembered default — `vibe app use <slot> --none`
                # turns the slot **off**, which is `nvm use system` and a
                # different act — and a second store to forget it in is
                # exactly the one thing that must not exist here. So this
                # says so, rather than reporting a deletion that did not
                # happen. `nvm alias default <version>` moves it.
                __vibenvm_err "nvm: \`default\` is the \`$VIBENVM_SLOT\` slot's default version, which vibe remembers and this file does not store, so there is no alias here to delete"
                __vibenvm_err "nvm: move it with \`nvm alias default <version>\`, or take the slot off this shell with \`nvm use system\`"
                return 55
            fi
            if [ ! -f "${alias_dir}/${1}" ]; then
                case "$1" in
                    stable | unstable | iojs | node | system)
                        __vibenvm_err "${1-} is a default (built-in) alias and cannot be deleted."
                        return 1
                        ;;
                esac
                # nvm's own oddity: the complaint goes to stderr and the
                # command still succeeds, because its `nvm_err` returns 0.
                __vibenvm_err "Alias ${1-} doesn't exist!"
                return 0
            fi
            local alias_original alias_original_flags
            alias_original="$(__vibenvm_alias "$1")"
            command rm -f "${alias_dir}/${1}"
            alias_original_flags=''
            while :; do
                case "$alias_original" in
                    --*' '*)
                        alias_original_flags="${alias_original_flags}${alias_original%% *} "
                        alias_original="${alias_original#* }"
                        ;;
                    *) break ;;
                esac
            done
            __vibenvm_echo "Deleted alias ${1} - restore it with \`nvm alias \"${1}\" ${alias_original_flags}\"${alias_original}\"\`"
            return 0
            ;;
        set-colors)
            __vibenvm_set_colors "${1-}"
            rc=$?
            if [ "$rc" -eq 17 ]; then
                # nvm's own shape, oddities included: the whole help goes to
                # **stderr**, a blank line to stdout, and the complaint is
                # painted. nvm writes no `return` after it, so a palette it
                # refused still leaves the command successful, and so does
                # this — a status is part of a surface too.
                __vibenvm_help >&2
                __vibenvm_echo
                __vibenvm_err_with_colors '\033[1;37mPlease pass in five \033[1;31mvalid color codes\033[1;37m. Choose from: rRgGbBcCyYmMkKeW\033[0m'
            fi
            return 0
            ;;
        debug)
            # Every line to stderr, in nvm's order, and always exit 42 —
            # which is how a user can pipe the report somewhere and how a
            # script can tell `debug` ran. `vibe self doctor` answers about
            # vibe; this answers about the shell a user is standing in.
            local os_version tool tool_version test_tools add_test_tools
            local shell_version debug_command debug_output
            __vibenvm_err "nvm --version: v$(nvm --version)"
            # The one line nvm has no equivalent for: which translation this
            # is. It sits directly after the nvm version, because the two
            # questions are asked together.
            __vibenvm_err "vibenvm: org.vibevm.nvm/nvm template revision $VIBENVM_REVISION"
            if [ -n "${TERM_PROGRAM-}" ]; then
                __vibenvm_err "\$TERM_PROGRAM: ${TERM_PROGRAM}"
            fi
            __vibenvm_err "\$SHELL: ${SHELL}"
            __vibenvm_err "\$SHLVL: ${SHLVL-}"
            __vibenvm_err "whoami: '$(command whoami)'"
            __vibenvm_err "\${HOME}: ${HOME}"
            __vibenvm_err "\${NVM_DIR}: '$(__vibenvm_sanitize_path "$(__vibenvm_root)")'"
            __vibenvm_err "\${PATH}: $(__vibenvm_sanitize_path "${PATH}")"
            __vibenvm_err "\$PREFIX: '$(__vibenvm_sanitize_path "${PREFIX-}")'"
            __vibenvm_err "\${NPM_CONFIG_PREFIX}: '$(__vibenvm_sanitize_path "${NPM_CONFIG_PREFIX-}")'"
            __vibenvm_err "\$NVM_NODEJS_ORG_MIRROR: '$(__vibenvm_sanitize_url "${NVM_NODEJS_ORG_MIRROR-}")'"
            __vibenvm_err "\$NVM_IOJS_ORG_MIRROR: '$(__vibenvm_sanitize_url "${NVM_IOJS_ORG_MIRROR-}")'"
            # busybox's shells have no `--version` and start an interactive
            # shell instead, which would hang this command.
            if command ls -l "$(command -v "${SHELL}" 2>/dev/null)" 2>/dev/null | command grep -q busybox; then
                shell_version="$(${SHELL} --help 2>&1 </dev/null | command head -n 1)"
            else
                shell_version="$(${SHELL} --version </dev/null 2>/dev/null | command head -n 1)"
            fi
            __vibenvm_err "shell version: '${shell_version}'"
            __vibenvm_err "uname -a: '$(command uname -a | command awk '{$2=""; print}' | command xargs)'"
            __vibenvm_err "checksum binary: '$(__vibenvm_get_checksum_binary 2>/dev/null)'"
            os_version=''
            if [ "$(__vibenvm_get_os)" = 'darwin' ] && __vibenvm_has sw_vers; then
                os_version="$(sw_vers | command awk '{print $2}' | command xargs)"
            elif [ -r '/etc/issue' ]; then
                os_version="$(command head -n 1 /etc/issue | command sed 's/\\.//g')"
                if [ -z "$os_version" ] && [ -r '/etc/os-release' ]; then
                    # shellcheck disable=SC1091
                    os_version="$(. /etc/os-release && echo "${NAME}" "${VERSION}")"
                fi
            fi
            if [ -n "$os_version" ]; then
                __vibenvm_err "OS version: ${os_version}"
            fi
            if __vibenvm_has 'awk'; then
                __vibenvm_err "awk: $(__vibenvm_command_info awk), $({ command awk --version 2>/dev/null || command awk -W version; } | command head -n 1)"
            else
                __vibenvm_err 'awk: not found'
            fi
            if __vibenvm_has 'curl'; then
                __vibenvm_err "curl: $(__vibenvm_command_info curl), $(command curl -V | command head -n 1)"
            else
                __vibenvm_err 'curl: not found'
            fi
            if __vibenvm_has 'wget'; then
                __vibenvm_err "wget: $(__vibenvm_command_info wget), $(command wget -V | command head -n 1)"
            else
                __vibenvm_err 'wget: not found'
            fi
            test_tools='git grep'
            add_test_tools='sed cut basename rm mkdir xargs'
            if [ 'darwin' != "$(__vibenvm_get_os)" ] && [ 'freebsd' != "$(__vibenvm_get_os)" ]; then
                test_tools="${test_tools} ${add_test_tools}"
            else
                for tool in ${add_test_tools}; do
                    if __vibenvm_has "$tool"; then
                        __vibenvm_err "${tool}: $(__vibenvm_command_info "$tool")"
                    else
                        __vibenvm_err "${tool}: not found"
                    fi
                done
            fi
            for tool in ${test_tools}; do
                if __vibenvm_has "$tool"; then
                    if command ls -l "$(__vibenvm_command_info "$tool" | command awk '{print $1}')" 2>/dev/null | command grep -q busybox; then
                        tool_version="$(command "$tool" --help 2>&1 | command head -n 1)"
                    else
                        tool_version="$(command "$tool" --version 2>&1 | command head -n 1)"
                    fi
                    __vibenvm_err "${tool}: $(__vibenvm_command_info "$tool"), ${tool_version}"
                else
                    __vibenvm_err "${tool}: not found"
                fi
            done
            for debug_command in 'nvm current' 'which node' 'which iojs' 'which npm' 'npm config get prefix' 'npm root -g'; do
                debug_output="$(${debug_command} 2>&1)"
                __vibenvm_err "${debug_command}: $(__vibenvm_sanitize_path "${debug_output}")"
            done
            return 42
            ;;

        *)
            # nvm's own answer to a command it does not have: the help, on
            # stderr, and 127.
            __vibenvm_help >&2
            return 127
            ;;
    esac
}

# -------------------------------------------------------- sourcing flags ---
#
# nvm's own two, and nothing invented: `--no-use` applies nothing now (which
# is this file's own default, because vibe's PATH is already the user's),
# and `--install` installs the slot's runtime as nvm's installer does.

# Read in a function, as nvm.sh does, so a file sourced with no arguments
# of its own never consumes the caller's positional parameters.
__vibenvm_source_parameters() {
    # nvm's own two checks before a shell start-up uses anything: an invalid
    # `$NVM_ONLY` is refused here rather than on the first command, and a
    # selection that needs the recorded LTS status cannot fetch it while a
    # shell is starting.
    if [ -n "${NVM_ONLY-}" ] &&
        ! __vibenvm_normalize_only "$NVM_ONLY" '`$NVM_ONLY`' >/dev/null; then
        return 55
    fi
    if __vibenvm_needs_lts_status "${NVM_ONLY-}" &&
        [ ! -f "$(__vibenvm_lts_status_path)" ]; then
        __vibenvm_err 'The LTS status of installed versions is not recorded yet; run `nvm ls-remote` to record it.'
        return 3
    fi
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --install) nvm install ;;
            --no-use | *) ;;
        esac
        shift
    done
}

__vibenvm_source_parameters "$@"
unset -f __vibenvm_source_parameters
