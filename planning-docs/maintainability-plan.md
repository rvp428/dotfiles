# Dotfiles Maintainability and DRY Implementation Plan

## Goals

- Make each behavior have one clear owner.
- Replace repeated implementations with small, explicit abstractions.
- Keep Home Manager modules composable for external wrapper flakes.
- Preserve current workstation behavior while removing obsolete experimental paths.
- Test behavior at the layer where it actually runs, rather than only evaluating Nix expressions.

## Baseline

- `nix flake check --no-build --no-write-lock-file` passed on 2026-07-13.
- The repository worktree already contains an unrelated modification to `home-manager/common.nix`; preserve it throughout this work.
- Runtime validation for Poetry shells exists in `scripts/validate-devshells`, but is not currently exposed through `just` or included in the flake checks.

## Phase 0: Record the supported behavior

### Why first

The Python devshells represent several historical approaches. Refactoring before selecting the supported contract would risk turning legacy behavior into an abstraction that must be maintained indefinitely.

### Tasks

1. Add a short `devshells/README.md` or a section in the main README documenting the public shell names and their guarantees.
2. Classify the existing shells:

   | Shell | Decision to make |
   | --- | --- |
   | `py311`, `py311new` | Pick one supported Nix-provided-Poetry workflow or remove both. |
   | `py313new` | Decide whether automatic `.venv` creation/sync is a supported policy. |
   | `py313-poetry`, `py314-poetry` | Retain as the supported project-local pipx Poetry shells. |
   | `py311-pipx` | Repair through the shared implementation or remove as obsolete. |
   | `npx`, `java25`, `tecton` | Keep separate; they are distinct toolchains. |

3. Standardize the Poetry contract for retained shells:

   - Python is selected from the active Nix shell.
   - Project environments live in `.venv` when Poetry is configured for in-project environments.
   - Poetry's own isolated pipx environment is rooted under the project `.direnv/pipx` directory.
   - The current Poetry configuration name is used: `POETRY_VIRTUALENVS_USE_POETRY_PYTHON=0`; remove the obsolete `POETRY_VIRTUALENVS_PREFER_ACTIVE_PYTHON` setting.
   - Startup must detect a stale Poetry executable or symlink outside `$PIPX_HOME` and reinstall it.
   - The project root is derived robustly from `DIRENV_FILE` (stripping direnv's leading `-`) when available, with a documented fallback.

### Acceptance criteria

- Every retained shell has a documented purpose.
- No supported shell relies on deprecated Poetry configuration names.
- There is one stated policy for automatic `poetry sync` on shell entry.

## Phase 1: Consolidate Poetry devshells

### Current issue

`devshells/flake.nix` contains repeated environment variables, pipx setup, project-root resolution, Poetry installation, interpreter binding, and lockfile-sync logic. The variants have drifted in behavior.

`py311-pipx` also has a real broken path: it checks for `poetry` and exits before the later installation branch, and that installation branch interpolates an undefined `SPEC` variable.

### Design

Add local Nix helpers near the top of `devshells/flake.nix`:

```nix
mkPoetryEnv = { ... };
mkProjectRootSnippet = { ... };
mkPipxPoetryStartup = {
  python,
  poetryVersion ? null,
  syncOnEnter ? false,
}: ...;
mkPoetryShell = {
  name,
  python,
  pythonPackages,
  extraPackages ? [],
  poetryVersion ? null,
  syncOnEnter ? false,
}: ...;
```

The helpers should make the differences declarative instead of copying shell scripts. Use a single startup implementation for the pipx Poetry workflow and pass only the version-specific Python executable/package set.

Do not create a universal abstraction for all shells. `npx`, Java, and Tecton have different lifecycle requirements and should remain small standalone definitions. If Tecton continues to use project-local pipx, extract only a neutral `mkProjectLocalPipxTool` helper after the Poetry consolidation proves its shape.

### Implementation steps

1. Introduce a `pythonForVersion` or direct `python` parameter, rather than embedding `python3.13`/`python3.14` throughout shell snippets.
2. Define the common Poetry environment variables once.
3. Implement project-root resolution once and use it in every pipx shell.
4. Install or repair Poetry before calling `poetry env use`.
5. Determine whether the installed Poetry path is inside `$PIPX_HOME`; force a reinstall if it is missing, non-executable, stale, or outside that directory.
6. Bind Poetry to the chosen shell interpreter after it is known to exist.
7. If automatic sync remains supported, put interpreter alignment, lockfile timestamp handling, and PATH export in the same helper.
8. Delete unsupported legacy shells and remove them from the `checks` attrset.
9. Keep `py313-poetry` and `py314-poetry` as thin calls to the factory, unless Phase 0 explicitly selects different public names.

### Tests and validation

1. Update `scripts/validate-devshells` to cover every supported Poetry shell, not only the two current fixtures.
2. Add a stale-pipx regression case: create a Poetry symlink/metadata path pointing outside the temporary fixture and assert entry repairs it.
3. Add `test-devshells` to `justfile` that invokes `scripts/validate-devshells`.
4. Keep runtime tests separate from pure flake evaluation because pipx setup may access the network.
5. Run:

   ```sh
   nix fmt
   nix flake check --no-build
   just test-devshells
   ```

### Acceptance criteria

- One implementation owns pipx Poetry setup.
- Each supported Python version differs only through declarative parameters.
- Re-entering a shell repairs stale local pipx state.
- Runtime validation is easy to discover and run.

## Phase 2: Extract wrapper command logic from Just

### Current issue

`just/wrapper.just` duplicates target detection and Darwin/Home Manager dispatch across local build, local switch, GitHub build, GitHub switch, and bootstrap validation.

Just recipes run independently, so adding shell functions inside one recipe would not provide a durable abstraction.

### Design

Create `scripts/dotfiles-wrapper` as a Bash command with explicit arguments:

```text
scripts/dotfiles-wrapper build   --host HOST --source local|locked
scripts/dotfiles-wrapper switch  --host HOST --source local|locked
scripts/dotfiles-wrapper bootstrap-check --host HOST
```

The script owns:

- validating `DOTFILES_WRAPPER`, `DOTFILES_DEV`, and host input;
- resolving `darwin` vs `home` when `DOTFILES_TARGET` is unset;
- forming the optional `--override-input dotfiles path:...` arguments;
- performing build/switch/activation dispatch;
- bootstrap SSH key validation.

The Justfile should remain the user-facing shorthand and call the script with an explicit action and source mode.

### Implementation steps

1. Move the repeated target-resolution code into `resolve_target`.
2. Represent override arguments as a Bash array to preserve quoting and eliminate two nearly identical target probes.
3. Add `run_build`, `run_switch`, and `bootstrap_check` functions.
4. Move shared prerequisite checks into named functions.
5. Reduce `just/wrapper.just` recipes to one-line or short delegations.
6. Preserve command names during the first change (`build`, `switch`, `build-github`, `switch-github`, `bootstrap-check`, `bootstrap-switch`). Renaming can be a later compatibility decision.

### Tests and validation

1. Add shell tests with mocked `nix`, `darwin-rebuild`, and `ssh` commands to cover:

   - explicit Darwin and Home Manager targets;
   - automatic target detection;
   - local override args only in local mode;
   - Home Manager activation after a successful switch;
   - unknown hosts and invalid targets.

2. Run `shellcheck` if it is added as a development tool.
3. Manually run `just doctor` and a non-switching `just build HOST` against a real wrapper host before using `switch`.

### Acceptance criteria

- Target detection has one implementation.
- A source mode changes only the input/override handling, not a whole copied recipe.
- Existing wrapper commands remain compatible.

## Phase 3: Define a deliberate Home Manager module API

### Current issue

The flake exposes `homeModules.base` and `homeModules.default`, while `home-manager/aws-sso.nix` and `home-manager/ops-env.nix` are neither included in `homeModuleBase` nor exported individually. Consumers cannot configure those option namespaces through the published module without importing internal files directly.

### Design

Use an explicit module catalog in the top-level flake:

```nix
homeModules = rec {
  common = import ./home-manager/common.nix;
  git = import ./home-manager/git.nix;
  shell = import ./home-manager/shell.nix;
  aws = import ./home-manager/aws-sso.nix;
  opsEnv = import ./home-manager/ops-env.nix;
  # profile and Nixvim modules need their existing special arguments.
  base = { imports = [ ... ]; };
  default = base;
};
```

Import disabled-by-default feature modules into `base` if their option declarations have no side effects. Otherwise, publish them as named modules and document the required composition. The former is preferable here: a consumer can set `dotfiles.aws.enable = true` without knowing implementation paths.

### Implementation steps

1. Add AWS and ops-env module declarations to the public module composition.
2. Export named modules for advanced consumers even if they are included in `base`.
3. Extract the inline Darwin module from `flake.nix` into `modules/darwin/default.nix`.
4. Split the Darwin module further only where it has coherent boundaries:

   - `modules/darwin/options.nix` for the `dotfiles` option schema;
   - `modules/darwin/homebrew.nix` for Homebrew setup and checks;
   - `modules/darwin/defaults.nix` for macOS preferences, hosts, and login-shell activation.

5. Keep `flake.nix` focused on inputs, shared arguments, exports, and module composition.
6. Add an architecture section explaining which modules are core, optional, and Darwin-only.

### Tests and validation

1. Evaluate a small Home Manager fixture that imports `homeModules.default` and enables `dotfiles.aws`.
2. Evaluate a fixture that enables `dotfiles.opsEnv` with one environment.
3. Evaluate the Darwin module with Homebrew disabled and enabled configuration values.
4. Run `nix flake check --all-systems --no-build` when cache availability permits.

### Acceptance criteria

- Every module in `home-manager/` is either intentionally private, imported into `base`, or exported by name.
- A consumer can discover and use optional features through flake outputs alone.
- `flake.nix` is primarily composition, not a monolithic implementation file.

## Phase 4: Centralize shared configuration data

### 4.1 Shared interactive command catalog

The Zsh aliases in `home-manager/shell.nix` and Fish abbreviations in `fish/conf.d/abbr.fish` mirror the same command list.

Create a single Nix attribute set, for example in `home-manager/aliases.nix`:

```nix
{
  ".." = "cd ..";
  ga = "git add";
  # ...
}
```

Apply it to Zsh aliases and Fish shell abbreviations. Keep the existing Fish files only for Fish-specific behavior, such as key bindings.

Before implementing, verify the exact Home Manager option for Fish abbreviations in the pinned release and preserve Fish abbreviation semantics rather than silently changing them to aliases.

### 4.2 AWS commands

The Fish helper bodies in `home-manager/aws-sso.nix` and the Zsh functions in `zsh/aws-sso.zsh` implement the same commands.

Replace both with shell-agnostic executable commands generated by `pkgs.writeShellApplication` or managed `home.file` scripts. Install them through `home.packages`, so they work in Fish, Zsh, non-interactive scripts, and future shells.

### 4.3 Package ownership

`common.nix` installs `awscli2`, Docker, and `jq`, while `aws-sso.nix` declares overlapping AWS tooling. Decide one of these policies and document it:

1. **Core workstation policy:** common tools remain in `common.nix`; the AWS module adds only `aws-sso-util` and ECR-specific tooling.
2. **Feature ownership policy:** AWS tooling moves fully into the AWS module; `common.nix` becomes cloud-neutral.

The feature ownership policy is the clearer long-term default if profiles may differ between personal and work machines.

### 4.4 Reusable option schemas

The same identity schema is declared in `flake.nix`, `home-manager/profile.nix`, and `home-manager/git.nix`. `dotfilesDir` and `extraPackages` have similar duplication.

Add a small `lib/options.nix` with option constructors such as `mkIdentityOption`. Use it wherever the schema is repeated. Keep platform-specific mapping code separate: the Darwin module may still accept a Darwin-level identity input, but its type and documentation should come from the shared constructor.

### Acceptance criteria

- The alias catalog has one source of truth.
- AWS helper behavior has one executable implementation.
- Each package has a clear owner (core profile or optional feature).
- Changes to shared identity fields cannot drift between modules.

## Phase 5: Add lightweight quality gates and documentation

### Tasks

1. Add a root `README.md` covering:

   - repository architecture;
   - the distinction between this shared dotfiles flake and host-specific wrapper flakes;
   - supported systems and primary commands;
   - module composition and optional features;
   - the devshell test command.

2. Keep `just check` as the fast structural check and add named recipes for formatting, devshell runtime tests, and wrapper-script tests.
3. Consider adding `deadnix` and `statix` to a dedicated lint recipe. The tools are already installed in the profile, but a reproducible CI/devshell invocation is more reliable than relying on workstation state.
4. Avoid forcing side-effectful tests (pipx, network, SSH) into the default pure `nix flake check`; expose them as explicit integration tests instead.
5. Add a short deprecation policy for renamed devshells and Just commands.

## Proposed delivery order

| Pull request | Scope | Main verification |
| --- | --- | --- |
| 1 | Phase 0 and Poetry-shell consolidation | `nix flake check --no-build`, `just test-devshells` |
| 2 | Wrapper script extraction | mocked script tests, `just doctor`, real `just build` |
| 3 | Public module catalog and Darwin-module extraction | fixture evaluation, all-system flake evaluation |
| 4 | aliases, AWS commands, package ownership, shared option constructors | Home Manager evaluation and interactive smoke test |
| 5 | README and quality-gate wiring | all prior checks from documented commands |

## Risks and safeguards

- **Changing Poetry startup can alter existing project environments.** Preserve a backup/restore note, test with disposable fixtures first, and avoid deleting `.venv` without an explicit stale-interpreter condition.
- **Project-local pipx depends on network and mutable state.** Keep its validation in integration tests and make repair actions explicit in logs.
- **Wrapper commands may be used by external host flakes.** Preserve command names and environment variables in the first extraction; add compatibility aliases before any rename.
- **Home Manager option additions can evaluate on multiple platforms.** Guard platform-specific package/configuration use with `stdenv.hostPlatform` checks and evaluate fixtures for Linux and Darwin.
- **Abbreviations and aliases are not semantically identical.** Confirm Fish behavior with the pinned Home Manager release before replacing raw Fish configuration.

## Definition of done

The work is complete when the repo has one supported implementation for each repeated workflow, all public feature modules are composable through flake outputs, behavior-level tests are exposed through documented commands, and a new contributor can identify the correct owner for a package, shell command, module option, or devshell behavior without tracing duplicate definitions.
