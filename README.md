# nvm, on vibe

This package is [nvm](https://github.com/nvm-sh/nvm)'s command surface for
[vibe](https://github.com/vibevm/vibevm). It is one shell file you source, as
`nvm.sh` is, and it defines one function, `nvm`:

```sh
vibe install -g org.vibevm.nvm/nvm
. "$HOME/.vibe/opt/apps/nvm/org.vibevm.nvm.nvm@0.41.0/nvm.sh"

nvm install 22.9.0
nvm use --lts
nvm ls
```

It is sourced rather than run because `nvm use` changes the **current**
shell's `PATH`, which a child process cannot do.

It replaces the retired `org.vibevm.node/vibenvm`, and it carries **no
accepted gaps**: every command, flag, environment variable and file of the
pinned nvm release is implemented here.

## Two versions, two questions

| question | answer | example |
| --- | --- | --- |
| `nvm --version` | the **nvm** version this installation implements, as nvm's own answer is | `0.41.0` |
| `nvm --vibenvm-version` | the **template revision** of `org.vibevm.nvm/nvm`, the package that implements it | `1.0.0` |

`nvm debug` reports both: its first line is nvm's own `nvm --version: v…`,
and the line directly after it reads
`vibenvm: org.vibevm.nvm/nvm template revision <R>`.

The nvm version is not baked into the file. vibe names an installed
application's directory after the installation key, so the sourced file sits
in `…/org.vibevm.nvm.nvm@<version>/`, and `nvm --version` reads that `@`
tail. A shell that cannot say which file it is sourcing — dash's `$0` is the
shell's name — falls back to the constant `NVM_COMPAT` in the file.

## The versions this package produces are nvm's versions

`vibe.toml` declares a template domain:

```toml
[template.versions]
kind = "list"

[[template.versions.item]]
version = "0.41.0"
```

One row today: `0.41.0`, the tag the differential conformance suite pins.
`[package] version` is therefore **the template revision** — the version of
this translation — and never an nvm version.

**Adding a version is four steps, in this order:**

1. re-pin the conformance suite to the new nvm tag;
2. prove it: the suite passes against that tag with no exclusions;
3. add a `[[template.versions.item]]` row here;
4. bump the template revision (`[package] version` and `VIBENVM_REVISION`
   in `nvm.sh`, which are kept equal).

A row whose behaviour nothing proved is a claim, not a version. Two of the
four steps happen outside this repository, which is the point: this package
does not get to decide on its own that it implements a release.

There is **no `[template.digests]`**, deliberately. The versions this
template produces download nothing: the payload is the `nvm.sh` this package
carries, placed by a `kind = "copy"` installer step out of the rendered tree.
A template that declares no digest source may name no digest variable, and
this manifest names none (PROP-075 `#TEMPLATE-NO-DIGEST`).

## What is vibe's, and what is this file's

Every **version decision** is vibe's and is never recomputed here: what a
spelling selects, what gets installed, what a shell activates, what a listing
contains, what the slot's default is, what the declared version file says,
which versions a channel holds, the download cache and every digest.

The **state nvm owns** is this file's, because the concept is nvm's and vibe
has no counterpart to read:

| state | where | what it is |
| --- | --- | --- |
| alias store | `<root>/alias/` | nvm's own layout, byte for byte |
| recorded LTS status | `<root>/.lts-status` | `<version> <lts name>` or `<version> -` |
| install locks | `<root>/.cache/locks/<version>/` | an advisory per-version lock directory |
| colour palette | `$NVM_COLORS` | five letters, in the environment and nowhere on disk |
| version categories | `--only=` / `$NVM_ONLY` | `alpha`, `lts`, `non-lts`, `iojs` |
| npm prefix hygiene | npm's own four npmrc files | the checks, and `--delete-prefix` |

`<root>` is **`$NVM_DIR` when the user has set it** — a user who set it means
it, and their alias files are already there — and otherwise
`${VIBE_SETTINGS:-$HOME/.vibe}/apps/nvm`, which is vibe's own settings-root
rule. Directories are created with `mkdir -p` exactly where nvm creates them.

## `default` is vibe's slot default, and nothing else

The alias store never holds a `default` file. `default` is the slot's default
version, which is vibe's own fact, so there is one source of truth:

| what you type | what happens |
| --- | --- |
| `nvm alias default <version>` | the version is resolved, then `vibe app use node <key>` makes it the slot default |
| `nvm alias default` | the row is rendered from vibe's answer: `default -> v22.9.0 *` |
| the `default` row of `nvm alias` | the same, sorted among the user's aliases |
| `nvm install <v> --default` | the same, after the install |
| `nvm install <v> --alias=default` | the same |
| `nvm use default`, `nvm ls default`, … | `default` resolves to that version, everywhere a version may be named |

A `default` file left behind by a real nvm installation under `$NVM_DIR` is
ignored, not read: two answers would be two truths.

One difference from nvm follows from that, and it is this package's only
deliberate decline on the alias surface:

### `nvm unalias default`

nvm deletes the `default` alias file and says so. Here there is no file, and
**vibe has no verb that forgets a remembered default** — `vibe app use <slot>
--none` turns the slot *off*, which is what `nvm use system` maps to and a
different act entirely. Rather than report a deletion that did not happen, or
keep a second store so that there is something to delete, `nvm unalias
default` explains and exits 55:

```
nvm: `default` is the `node` slot's default version, which vibe remembers
and this file does not store, so there is no alias here to delete
nvm: move it with `nvm alias default <version>`, or take the slot off this
shell with `nvm use system`
```

Everything else `unalias` does is nvm's, including the exit **127** for the
wrong number of arguments, the refusal for a built-in name, and the
`Alias foo doesn't exist!` that still **succeeds**.

## The command surface

| nvm | vibe |
| --- | --- |
| `nvm install <version>` | `vibe install -g org.vibevm.node/node@<requirement>`, then the activation below |
| `nvm install` (no version) | `vibe install -g org.vibevm.node/node` — the install reads the directory's declared version file itself |
| `nvm install --lts` / `--lts=<name>` | `@lts` / `@lts/<name>` — vibe's channels |
| `nvm install -s` | `--platform linux-source` / `macos-source` — the Node package's source installer option |
| `nvm install -b` | no flag: the prebuilt row is what vibe picks anyway |
| `nvm install -j <N>` | `--set jobs=<N>` on that option |
| `nvm install` (neither) | binary first; on failure, a second run with the source platform — vibe has no fallback chain, so the fallback is two runs |
| `nvm install --default` / `--alias=<name>` | `vibe app use` / an alias file, recording the version **as you wrote it** |
| `nvm install --save` / `-w` | `vibe install -g … --write-version-file` |
| `nvm install --reinstall-packages-from=<v>` | `vibe app migrate node <v> <new> --only ecosystem:npm` |
| `nvm install --latest-npm`, `nvm install-latest-npm` | `vibe app extras self-upgrade node --ecosystem npm` |
| `nvm install --skip-default-packages` | `--no-extras` |
| `nvm uninstall <version>` | `vibe uninstall -g org.vibevm.node/node@=<version>`, then nvm's own unalias of what pointed at it |
| `nvm use [<version>]` | `eval "$(vibe app env --use node==<version>)"`, or `--project` for a version file |
| `nvm use --save` / `-w` | `vibe app env --use … --write-version-file` — the shell and the file, never the slot default |
| `nvm use --delete-prefix` | npm's own `npm config delete prefix` / `globalconfig`, per npmrc level |
| `nvm current` | the version `VIBE_APP_USE` names, else `system` / `none` |
| `nvm deactivate` | `eval "$(vibe app env --unset)"` |
| `nvm run` / `nvm exec` | `vibe app exec node@=<version> -- …` |
| `nvm ls [<pattern>]` | `vibe app versions node --installed --all`, rendered in nvm's columns, with the alias listing after it |
| `nvm ls --no-alias` | the same without that listing |
| `nvm ls-remote [<pattern>]` | `vibe app versions org.vibevm.node/node --all`, with the LTS columns and the recorded status |
| `nvm version` / `version-remote` | the version the requirement selects, installed or available |
| `nvm which [<version>]` | `vibe app exec node@=<version> -- node -p process.execPath`; `which system` is the node a shell finds with the slot off |
| `nvm alias` / `unalias` | nvm's own alias store, and `vibe app use` for `default` |
| `nvm set-colors <five>` | `$NVM_COLORS`, which paints this file's own rows and nothing vibe prints |
| `nvm debug` | nvm's twenty-two lines about this shell, on stderr, exit 42, plus the revision line |
| `nvm reinstall-packages` / `copy-packages` | `vibe app migrate node <v> <current> --only ecosystem:npm` |
| `nvm cache dir` / `clear` | `vibe cache path`'s `app-sources`, and `vibe cache clean --all` |
| `nvm unload` | the unset lines, then `unset -f nvm` |
| `. nvm.sh --install` / `--no-use` | the two sourcing flags, as nvm's |

### nvm's version spellings

nvm matches a version by prefix; a vibe **requirement** takes a semver range.
The file translates the spelling and nothing else:

| nvm | vibe |
| --- | --- |
| `22.9.0`, `v22.9.0` | `=22.9.0` (that release) |
| `22.9` | `~22.9` (the newest of that minor) |
| `22` | `22` (the newest of that major) |
| `node`, `stable` | `latest` |
| `lts`, `lts/*` | `lts` |
| `lts/jod` | `lts/jod` |
| `lts/-1` | the line before the newest, counted in the alias store as nvm counts it |
| `default` | the slot's default version |
| `system` | the slot off this shell |
| `iojs`, `iojs-*` | selects nothing: `org.vibevm.node/node` carries no io.js version, which is the answer nvm gives where no io.js is available |

Anything else is handed to vibe as written, so a vibe requirement you already
know — `^22`, `>=20, <23` — works here too.

### Where a flag may stand

nvm reads a different argument list per subcommand, and that is part of the
surface a user learned. This file takes the same rule from the same place —
the pinned `nvm.sh` — branch by branch:

| subcommand | how the arguments are read |
| --- | --- |
| `install` | two passes: the flags that select or build the version (`-s`, `-b`, `-j`, `--offline`, `--lts`) must precede it, and the flags that act on it (`--save`, `--default`, `--alias=`, `--latest-npm`, `--skip-default-packages`, `--no-progress`, `--reinstall-packages-from=`, `--only=`) may follow it. One on the wrong side is exit 6 |
| `use`, `which` | the whole list, flags anywhere, and the **last** version named wins; `use -- <version>` names it and ends the scan |
| `ls`, `ls-remote`, `version`, `version-remote` | the whole list, flags anywhere, and the **first** pattern named wins |
| `run`, `exec` | parsing stops at the first non-option: everything after the version is the command's own argument list |
| `uninstall`, `reinstall-packages`, `copy-packages` | the whole list, and exactly one version |
| `alias` | the first bare word is the name and the second is the target; an explicitly empty target means `unalias` |

## Version categories, and the LTS status they need

`--only=alpha,lts,non-lts,iojs` and `$NVM_ONLY` narrow what a spelling may
select, on every verb that selects a version. An alias remembers the
categories that chose its target, stored before the target in its own file,
exactly as nvm stores `--lts`.

Telling `lts` from `non-lts` apart needs the recorded status of installed
versions, which `nvm ls-remote` writes to `<root>/.lts-status`. Until it has
run, a selection that needs it says so:

```
The LTS status of installed versions is not recorded yet; run `nvm ls-remote` to record it.
```

**One honest difference.** A selection *narrows* vibe's answer; it never asks
vibe for a different one. Where nvm would skip past an excluded version to
the next one in the category, this reports `N/A` with nvm's own explanation
of why. Choosing which version a spelling selects is vibe's decision, and
re-searching here would be this file resolving versions — the one thing it
must not do.

## Colours

`nvm set-colors <rgBcm>` takes five letters of `rRgGbBcCyYmMkKeW` for the
installed, LTS-and-system, current, not-installed and default colours, and
keeps them in `$NVM_COLORS` — in the environment, and nowhere on disk. They
paint the rows **this file** prints: its listings and its alias rows. They
never reach vibe, whose display decision is taken once for every vibe
command; `set-colors` does not touch it.

## Downloads, and the credential for a private mirror

`$NVM_AUTH_HEADER` is passed to the install that downloads the runtime. Two
of nvm's rules come with it:

- it is **never printed, never logged and never an argument** — every local
  user can read a process's arguments, so it travels in a file only its owner
  can read, and `nvm debug` does not mention it;
- it is **sanitised** to `a-zA-Z0-9 :_.+/=~-`, which is RFC 7235 `token68`
  plus what `Basic` and `Bearer` values need.

nvm attaches the header per URL, because nvm performs the download. Here vibe
performs it and knows the URLs, so that containment is vibe's: the header
reaches the one command that downloads this slot's runtime and nothing else.

## The third-party installer hook

`$NVM_INSTALL_THIRD_PARTY_HOOK` replaces the whole install — the lock, the
download and the build — and is called with nvm's five arguments: the
resolved version, the flavor, the literal `std`, `binary` or `source`, and
the path to install into, which is `<root>/versions/node/<version>` in nvm's
own layout. nvm's three lines come with it, including exit 33 for a hook that
claims success and installs nothing.

A tree a third party placed is **not an installation vibe knows**, so the
activation, the default and the alias that follow an ordinary install cannot
follow this one. The command says where the version was put and that
`nvm use` cannot select it, and stops there.

## Where it runs: POSIX `sh`, so Linux and macOS

`nvm.sh` is a **POSIX shell** file you source — `sh`, `dash`, `bash`, `ksh`,
`zsh` — and the package declares an installer option for Linux (glibc x86-64
and arm64, musl x86-64) and macOS (Intel and Apple silicon) and for nothing
else. On Windows there is therefore no option to select, and
`vibe install -g org.vibevm.nvm/nvm` refuses by platform rather than
installing something that cannot run.

**Windows `cmd` and PowerShell are not supported**, which is a statement of
scope rather than an omission: upstream nvm is a POSIX shell function too, and
`nvm-windows` is a different program by a different author. Inside WSL, Git
Bash or MSYS the shell is an ordinary POSIX one and this works there exactly
as it does on Linux. A source build on non-WSL Windows is nvm's own
`Installing from source on non-WSL Windows is not supported`, exit 87.

A Windows user reaches every outcome through vibe's own commands, which are
the ones this file would have called:

| instead of | in `cmd` / PowerShell |
| --- | --- |
| `nvm install 22` | `vibe install -g org.vibevm.node/node@22` |
| `nvm alias default 22` | `vibe app use node org.vibevm.node/node@22` |
| `nvm ls` | `vibe app versions node --installed --all` |
| `nvm use 22` (this shell) | the lines `vibe app env` prints, applied below |

```bat
for /f "usebackq tokens=1,* delims==" %a in (`vibe app env --use node=22 --shell cmd`) do @set "%a=%b"
```

```powershell
Invoke-Expression (vibe app env --use node=22 --shell powershell | Out-String)
```

## It requires no Node.js of its own, deliberately

The package declares **no** `[recommends]` row on `org.vibevm.node/node` and
no requirement on it. nvm carries no Node.js either: you install the version
manager, and the versions arrive when you ask for one. `nvm install 22` is
`vibe install -g org.vibevm.node/node@22`, which installs the package then —
so a declared recommendation would install a Node.js version nobody asked for
at the moment this package is installed, and would make a fresh installation
differ from a fresh nvm one in the first thing the conformance suite observes.

## The proof

That this is a complete nvm replacement is not an opinion here. The vibevm
repository carries a differential conformance suite — `conformance/vibenvm/`
— which runs the same command sequences against pinned upstream nvm-sh and
against this file, in two isolated homes against one local Node mirror with
no network at all, and compares the observation record after every step. Its
exit code is the verdict, every command and flag of the pinned nvm must have
a passing case, and there is no exclusion list.

## Licence

UPL-1.0. See `LICENSE.md`.
