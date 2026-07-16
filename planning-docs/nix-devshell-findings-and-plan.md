# Nix Devshell Findings And Plan

## Purpose

This document is a handoff for fixing and hardening the Nix devshell setup in the dotfiles repo. It summarizes the regressions observed in the current `direnv` + Nix + Poetry + `pipx` setup, explains the most likely root causes, and proposes a concrete validation strategy so future changes do not silently re-break old behavior.

The findings below were gathered from the current machine state on 2026-04-17 in:

- Dotfiles repo: `/Users/raoul/dotfiles`
- Backend repo using the shells: `/Users/raoul/src/backend`


## Executive Summary

There are two distinct classes of issues:

1. `pipx`-bootstrapped Poetry can become stale because it stores absolute paths in project-local `.direnv/pipx` state. If a project directory is renamed or copied, the exposed `poetry` symlink can point to a deleted path and `direnv reload` will not repair it automatically.
2. Nix-provided Poetry can select the wrong Python interpreter because the active Poetry configuration currently forces `use-poetry-python = true`, which means "use the Python used to build Poetry itself", not "use the Python from the active devshell".

There is also a third consistency problem:

3. The shell config is mixing old and new Poetry config keys. The shells still export `POETRY_VIRTUALENVS_PREFER_ACTIVE_PYTHON`, but Poetry 2.2+ reads `virtualenvs.use-poetry-python`.

These three issues together explain why the setup has felt fragile and why switching between Nix-provided Poetry and `pipx`-provided Poetry changed behavior in non-obvious ways.


## Confirmed Findings

### 1. The current broken `poetry` in `pre-commit-dependency-sync` is a stale `pipx` symlink

Project:

- `/Users/raoul/src/backend/scripts/pre-commit-dependency-sync`

Observed behavior:

- `direnv reload` reports that Poetry is already installed via `pipx`
- `poetry` is still not found on `PATH`

Confirmed cause:

- `.direnv/pipx/bin/poetry` is a symlink to a deleted project path:
  - `/Users/raoul/src/backend/scripts/mypy-hook-dependencies/.direnv/pipx/venvs/poetry/bin/poetry`
- The metadata in:
  - `/Users/raoul/src/backend/scripts/pre-commit-dependency-sync/.direnv/pipx/venvs/poetry/pipx_metadata.json`
  still records app paths under `scripts/mypy-hook-dependencies/...`

Why this happens:

- `pipx` stores absolute paths for installed app entrypoints
- `pipx` also exposes those apps by symlinking directly to those absolute paths
- if the original project directory goes away or is renamed, the exposed app path becomes stale

Relevant evidence:

- Dotfiles shell startup for `py314-poetry`:
  - `/Users/raoul/dotfiles/devshells/flake.nix:265`
- Stale metadata:
  - `/Users/raoul/src/backend/scripts/pre-commit-dependency-sync/.direnv/pipx/venvs/poetry/pipx_metadata.json:4`


### 2. The first bad `pipx` install was already using the deleted project path

The earliest relevant install log found was:

- `/Users/raoul/src/backend/scripts/pre-commit-dependency-sync/.direnv/pipx/logs/cmd_2026-04-16_16.49.58.log`

That log shows `pipx install poetry --python ...` creating the Poetry venv under:

- `/Users/raoul/src/backend/scripts/mypy-hook-dependencies/.direnv/pipx/...`

This indicates the bad path was present at initial install time, not introduced later by a partial upgrade.

Best inference:

- the project likely existed locally as `scripts/mypy-hook-dependencies` when Poetry was first bootstrapped
- later, the project directory was renamed or copied to `scripts/pre-commit-dependency-sync`
- `.direnv` was preserved across that rename/copy

I could not prove the exact rename command from git history or shell history, but the absolute-path evidence strongly supports this reconstruction.


### 3. Later `direnv reload` calls do not self-heal stale `pipx` installs

Why reload does not fix it:

- the startup script only runs `pipx install poetry --python ...` if `poetry` is not found
- once the local `pipx` venv exists, `pipx install poetry` exits early with:
  - "`poetry` already seems to be installed. Not modifying existing installation ..."

So the shell does not rebuild the bad symlink or metadata automatically.

Relevant upstream `pipx` behavior examined locally:

- install short-circuit:
  - `/nix/store/i9ycmi6jhvngkvv37psdpb5964qysw7i-python3.11-pipx-1.8.0/lib/python3.11/site-packages/pipx/commands/install.py:77`
- symlink exposure behavior:
  - `/nix/store/i9ycmi6jhvngkvv37psdpb5964qysw7i-python3.11-pipx-1.8.0/lib/python3.11/site-packages/pipx/commands/common.py:54`
  - `/nix/store/i9ycmi6jhvngkvv37psdpb5964qysw7i-python3.11-pipx-1.8.0/lib/python3.11/site-packages/pipx/commands/common.py:168`


### 4. The Poetry virtualenv location flags were not the cause of the stale `pipx` install

For the `py314-poetry` shell, these are already set:

- `POETRY_VIRTUALENVS_CREATE=1`
- `POETRY_VIRTUALENVS_IN_PROJECT=1`

That governs where the project env lives, typically `.venv`, not whether the `poetry` CLI exists on `PATH`.

The broken case was the CLI bootstrap, not the project virtualenv location.

Relevant shell definition:

- `/Users/raoul/dotfiles/devshells/flake.nix:275`


### 5. The active global Poetry config forces interpreter selection toward Poetry's own build Python

Home Manager config currently writes:

- `/Users/raoul/dotfiles/home-manager/poetry.nix:5`

Contents:

```toml
[virtualenvs]
create = true
use-poetry-python = true
in-project = true
```

This is critical.

With Nix-provided Poetry, `use-poetry-python = true` means:

- when Poetry chooses a Python for the project env, it prefers the Python used to build the Poetry package itself
- not the active devshell Python

That is exactly the behavior that can make a `python311` or `python314` shell create a project env using Python 3.13 or some other Nixpkgs-selected Poetry runtime.

Relevant Poetry implementation examined locally:

- config key handling:
  - `/nix/store/9fsr5qar7zgakd3c8xh38fzh99nrrdcq-python3.13-poetry-2.2.1/lib/python3.13/site-packages/poetry/config/config.py:386`
- preferred interpreter logic:
  - `/nix/store/9fsr5qar7zgakd3c8xh38fzh99nrrdcq-python3.13-poetry-2.2.1/lib/python3.13/site-packages/poetry/utils/env/python/manager.py:273`
- env creation flow:
  - `/nix/store/9fsr5qar7zgakd3c8xh38fzh99nrrdcq-python3.13-poetry-2.2.1/lib/python3.13/site-packages/poetry/utils/env/env_manager.py:399`


### 6. The current shells are still using the old Poetry env var name

The devshells currently export:

- `POETRY_VIRTUALENVS_PREFER_ACTIVE_PYTHON`

Example:

- `/Users/raoul/dotfiles/devshells/flake.nix:285`

However, Poetry 2.2+ migrated:

- old key: `virtualenvs.prefer-active-python`
- new key: `virtualenvs.use-poetry-python`

Relevant migration logic:

- `/nix/store/9fsr5qar7zgakd3c8xh38fzh99nrrdcq-python3.13-poetry-2.2.1/lib/python3.13/site-packages/poetry/console/commands/config.py:39`

This means the shell environment may not be overriding the active config the way it was originally intended to.


### 7. Current effective Poetry config in working `pipx` shells still reports `virtualenvs.use-poetry-python = true`

Observed in current working shells:

- `oscibot`
- `oscibot-eval`

Running `poetry config --list` in those shells showed:

- `virtualenvs.create = true`
- `virtualenvs.in-project = true`
- `virtualenvs.use-poetry-python = true`

This implies the global Home Manager config is still dominating interpreter selection behavior unless explicitly corrected by `poetry env use ...` in shell startup.

That likely explains why the current `pipx` shells appear to work only because they immediately bind Poetry to the shell interpreter after startup.


### 8. The "writing to the Nix store" concern is probably not normal project env creation

The current Poetry runtime paths are in user-writable locations:

- cache dir:
  - `~/Library/Caches/pypoetry`
- data dir:
  - `~/Library/Application Support/pypoetry`

Relevant code path:

- `/nix/store/9fsr5qar7zgakd3c8xh38fzh99nrrdcq-python3.13-poetry-2.2.1/lib/python3.13/site-packages/poetry/locations.py:1`

So normal `poetry install`, `poetry sync`, and `.venv` creation are not supposed to write into `/nix/store`.

The more likely Nix-store write failures are operations like:

- `poetry self update`
- `poetry self add <plugin>`
- any attempt to mutate the Nix-installed Poetry distribution itself


### 9. `DIRENV_DIR` usage in the startup scripts is brittle

Multiple startup blocks use:

```sh
ROOT="${DIRENV_DIR:-$PWD}"
ROOT="$(cd "$ROOT" && pwd -P)"
```

Relevant locations:

- `/Users/raoul/dotfiles/devshells/flake.nix:245`
- `/Users/raoul/dotfiles/devshells/flake.nix:293`
- `/Users/raoul/dotfiles/devshells/flake.nix:335`
- `/Users/raoul/dotfiles/devshells/flake.nix:526`

Observed runtime behavior under `direnv exec`:

- `DIRENV_DIR` is exported as `-/Users/raoul/src/backend/scripts/pre-commit-dependency-sync`

That leading `-` means raw `cd "$DIRENV_DIR"` is not a robust way to determine the project root.

Safer anchor:

- `dirname "$DIRENV_FILE"`

This is not proven to be the cause of the stale path incident, but it is a real consistency risk and should be fixed.


### 10. The Nix-provided Poetry shells are currently not build-stable

Trying to evaluate/build the `py311` and `py311new` shells via `nix develop` hit a Nix dependency failure in the Poetry chain:

- `python3.13-rapidfuzz-3.14.3` failed to build
- therefore `python3.13-poetry-2.2.1` failed to build
- therefore the devshells depending on `pkgs.poetry` failed

This is separate from the interpreter-selection issue, but it matters operationally:

- even if the config is corrected, the direct Nix Poetry path is not currently reliable unless Nixpkgs is pinned to a known-good state or Poetry is overridden


## Likely Root Cause Tree

### Root cause A: mutable per-project `pipx` state stores absolute paths

Impact:

- renames and copies can break `poetry` exposure
- stale symlinks persist until explicitly repaired

Symptoms:

- `pipx` says Poetry is installed
- `poetry` is not actually runnable


### Root cause B: global Poetry config is misaligned with devshell expectations

Current global config:

- `use-poetry-python = true`

Expected shell behavior:

- use the shell Python for the project env

Impact:

- Nix Poetry may create `.venv` with the wrong Python version
- current `pipx` shells depend on explicit `poetry env use ...` calls to correct this


### Root cause C: Poetry config migration is incomplete

Current shell env vars and local files still use the old key:

- `prefer-active-python`

Poetry 2.2+ uses:

- `use-poetry-python`

Impact:

- configuration may not be overriding what it appears to override
- behavior depends on Poetry version and whether startup scripts force a correction


### Root cause D: startup code is duplicated and not systematically validated

The shell behaviors are encoded as long inline shell snippets in:

- `/Users/raoul/dotfiles/devshells/flake.nix`

Impact:

- fixes are easy to make inconsistently across shells
- regressions are hard to test
- there is no automated matrix checking behavior across shells


## Recommended Direction

## Option 1: Keep `pipx`-managed Poetry, but make it robust

This is the most practical short-term path.

Rationale:

- it avoids current Nixpkgs Poetry build instability
- it keeps Poetry tied to the shell Python when installed correctly
- it reduces interpreter mismatch risk

Required fixes:

1. change the global Poetry config so it does not prefer Poetry's own Python
2. migrate shell env vars and local config away from `prefer-active-python`
3. switch project-root detection from `DIRENV_DIR` to `DIRENV_FILE`
4. make the `pipx` bootstrap detect and repair stale app paths


## Option 2: Use Nix-provided Poetry only, but make interpreter selection explicit

This is viable if the Nix Poetry build instability is resolved.

Rationale:

- simpler runtime model
- fewer mutable components under `.direnv/pipx`

Required fixes:

1. stop using `use-poetry-python = true`
2. use a Poetry package matched to the shell Python when possible
3. keep explicit `poetry env use "$(command -v pythonX.Y)"` or create `.venv` first and point Poetry at it
4. avoid all `poetry self ...` operations


## Recommended Immediate Changes

### 1. Fix the global Poetry config

File:

- `/Users/raoul/dotfiles/home-manager/poetry.nix`

Change:

- replace `use-poetry-python = true`
- with `use-poetry-python = false`

Reason:

- project envs should follow the active shell interpreter, not Poetry's build interpreter


### 2. Update all devshell env vars to the new Poetry key

Change:

- stop exporting `POETRY_VIRTUALENVS_PREFER_ACTIVE_PYTHON`
- export `POETRY_VIRTUALENVS_USE_POETRY_PYTHON=0` instead

Reason:

- aligns with Poetry 2.2+
- removes version-dependent confusion


### 3. Replace `DIRENV_DIR` root detection with `DIRENV_FILE`

Current pattern:

```sh
ROOT="${DIRENV_DIR:-$PWD}"
ROOT="$(cd "$ROOT" && pwd -P)"
```

Recommended pattern:

```sh
if [ -n "${DIRENV_FILE:-}" ]; then
  ROOT="$(cd "$(dirname "$DIRENV_FILE")" && pwd -P)"
else
  ROOT="$(pwd -P)"
fi
```

Reason:

- avoids the leading-`-` semantics in `DIRENV_DIR`
- matches the actual `.envrc` location


### 4. Make `pipx` Poetry bootstrap self-heal stale installs

For the `py313-poetry`, `py314-poetry`, and `py311-pipx` shells:

- if `poetry` is missing, install it
- if `poetry` exists but resolves outside `$PIPX_HOME`, force reinstall
- if `.direnv/pipx/bin/poetry` is a dead symlink, remove it and force reinstall
- if `pipx_metadata.json` app paths point outside the current project root, force reinstall

At minimum, validate:

```sh
POE="$(command -v poetry || true)"
if [ -z "$POE" ] || [ ! -x "$POE" ]; then
  NEED_REINSTALL=1
elif [ ! "$(readlink "$PIPX_BIN_DIR/poetry" 2>/dev/null || true)" ]; then
  NEED_REINSTALL=1
elif ! readlink "$PIPX_BIN_DIR/poetry" | grep -q "^$PIPX_HOME/"; then
  NEED_REINSTALL=1
fi
```

Then run:

```sh
pipx install --force poetry --python "$(command -v python3.14)"
```

or the shell-appropriate Python.


### 5. Reduce duplication

Refactor shared shell logic into reusable helpers.

Suggested structure in the dotfiles repo:

- `devshells/lib/poetry-bootstrap.sh`
- `devshells/lib/poetry-assertions.sh`
- shell-specific parameters passed from Nix:
  - Python binary name
  - whether to create/sync `.venv`
  - whether to use `pipx`
  - desired Poetry version

Reason:

- one code path to test
- fewer shell-specific drift bugs


## Validation Strategy

Use two layers:

1. pure Nix checks for evaluation/build regressions
2. integration tests for actual shell behavior


## Layer 1: Nix Flake Checks

These should answer:

- does the shell evaluate?
- does its dependency closure build?
- does the shell derivation exist and remain buildable?

Recommended checks:

```nix
checks.py314-poetry-build = self.devShells.${system}.py314-poetry.inputDerivation;
checks.py313-poetry-build = self.devShells.${system}.py313-poetry.inputDerivation;
checks.py311-pipx-build = self.devShells.${system}.py311-pipx.inputDerivation;
checks.py311-build = self.devShells.${system}.py311.inputDerivation;
checks.py311new-build = self.devShells.${system}.py311new.inputDerivation;
checks.py313new-build = self.devShells.${system}.py313new.inputDerivation;
```

This would have caught the current Nix Poetry build failure early.


## Layer 2: Integration Tests

These should run outside pure derivation checks because they depend on:

- `direnv`
- mutable project state
- `.venv`
- `.direnv/pipx`
- actual shell startup behavior

Recommended harness:

- one script entry point, for example:
  - `scripts/validate-devshells`
- fixtures under:
  - `tests/fixtures/poetry-project`
  - `tests/fixtures/non-poetry-project`
- shell tests using `bats` or plain POSIX shell

Each test should isolate machine state:

```sh
env -i \
  HOME="$tmp/home" \
  XDG_CONFIG_HOME="$tmp/config" \
  XDG_CACHE_HOME="$tmp/cache" \
  XDG_DATA_HOME="$tmp/data" \
  PATH="$PATH" \
  direnv exec "$fixture" zsh -lc '... assertions ...'
```

This prevents accidental dependency on the real user config or caches.


## Suggested Validation Matrix

### A. Basic shell availability

For each devshell:

- `command -v python`
- `python -V`
- required CLI binaries exist
- shell exits successfully

Examples:

- `py314-poetry`: `python3.14`, `poetry`, `pipx`
- `py311-pipx`: `python3.11`, `poetry`, `pipx`
- `npx`: `node`, `npm`, `npx`
- `java25`: `java`, `javac`


### B. Poetry config sanity

For Poetry-capable shells:

- `poetry config --list` includes:
  - `virtualenvs.create = true`
  - `virtualenvs.in-project = true`
  - `virtualenvs.use-poetry-python = false`

Also assert:

- config dir is not under `/nix/store`
- cache dir is not under `/nix/store`
- data dir is not under `/nix/store`


### C. Interpreter correctness

In a fixture project:

- run `direnv exec <fixture> zsh -lc 'poetry env use "$(command -v python3.14)"'` where relevant
- assert:
  - `realpath .venv/bin/python`
  - `poetry env info --executable`
  both resolve to the expected Python interpreter

This directly tests the previously suspected "wrong Python version" failure mode.


### D. `pipx` locality and stale-symlink healing

For `pipx` shells:

- `readlink .direnv/pipx/bin/poetry` points inside the current project's `.direnv/pipx`
- `pipx_metadata.json` app paths point inside the current project root
- if the symlink is manually rewritten to a dead path, re-entering the shell repairs it

This should become a required regression test.


### E. Rename/copy regression

Fixture flow:

1. create a temporary project directory
2. enter shell to bootstrap Poetry
3. rename the directory
4. re-enter shell
5. assert `poetry` still works and points to the renamed directory's local `.direnv/pipx`

This is the regression that matches the current real-world failure most closely.


### F. Foreign environment leakage

Enter the shell with:

- `VIRTUAL_ENV=/tmp/foreign`
- `PYTHONHOME=...`
- `PYTHONPATH=...`

Assert the shell:

- unsets or neutralizes those values
- still creates/uses the correct project `.venv`


### G. Idempotency

Re-enter the same shell multiple times and assert:

- no interpreter drift
- no repeated destructive recreation unless necessary
- `pipx` state does not drift


### H. Non-Poetry shell checks

For `npx`, `java25`, `tecton`:

- ensure required tools are available
- ensure cache/home paths are writable
- for `tecton`, check local `pipx` install behavior mirrors the Poetry shell strategy


## Proposed Test Layout In The Dotfiles Repo

Suggested structure:

```text
devshells/
  flake.nix
  lib/
    poetry-bootstrap.sh
    direnv-root.sh
tests/
  fixtures/
    poetry-project/
      .envrc
      pyproject.toml
      poetry.lock
    empty-project/
      .envrc
  shell/
    test-py314-poetry.bats
    test-py311-pipx.bats
    test-direnv-root.bats
    test-rename-healing.bats
scripts/
  validate-devshells
```


## Proposed Iteration Plan

### Phase 1: Fix correctness

1. change Home Manager Poetry config to stop preferring Poetry's own interpreter
2. migrate shell env vars to `POETRY_VIRTUALENVS_USE_POETRY_PYTHON=0`
3. fix root detection to use `DIRENV_FILE`
4. add stale-`pipx` repair logic


### Phase 2: Add minimum safety net

1. add `inputDerivation` checks for each devshell
2. add one integration test for:
   - `py314-poetry`
   - `py311-pipx`
   - rename/stale-symlink healing
   - interpreter correctness


### Phase 3: Refactor for maintainability

1. move startup logic out of inline Nix strings into reusable scripts
2. centralize assertions and helper functions
3. reuse the same helpers from both shell startup and tests


### Phase 4: Expand validation coverage

1. add `npx`, `java25`, and `tecton`
2. add foreign-env leakage tests
3. add repeated-entry idempotency tests


## Open Questions

These are still unresolved and worth checking while implementing:

1. Was `scripts/mypy-hook-dependencies` a previous local name for `pre-commit-dependency-sync`, or was `.direnv` copied from another directory manually?
2. Are any workflows relying on `use-poetry-python = true` intentionally?
3. Do any shells still need compatibility with older Poetry 1.x semantics, or can the config be fully standardized on Poetry 2.2+ behavior?
4. Should Nix-provided Poetry remain supported at all, given the current Nixpkgs build instability?


## Immediate Next Step For The Agent Working In The Dotfiles Repo

Suggested first task:

1. patch the config and shell scripts only, without broad refactors
2. add a tiny integration test fixture
3. add a single validation command that checks:
   - shell builds
   - interpreter is correct
   - `poetry` local `pipx` symlink is local and valid
   - renamed-project recovery works

That should give the highest signal quickly and keep the first iteration small enough to verify.


## Short Version

The current setup is failing because:

- `pipx` stores absolute paths under project-local `.direnv/pipx`, so renamed projects can strand dead `poetry` symlinks
- the active global Poetry config tells Poetry to prefer its own build Python
- the shells still use deprecated Poetry config keys
- there are no automated validations covering these behaviors

The fix is:

- standardize interpreter selection on the active shell Python
- make `pipx` self-heal stale installs
- stop using brittle `DIRENV_DIR` root parsing
- add both Nix build checks and integration tests for actual runtime behavior
