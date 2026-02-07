# flake.nix
{
  description = "Python 3.11 + Poetry dev shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    devshell,
  }:
    flake-utils.lib.eachSystem [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ] (system: let
      overlays = [devshell.overlays.default];
      pkgs = import nixpkgs {inherit system overlays;};
    in {
      devShells.py311 = pkgs.devshell.mkShell {
        name = "py311";

        packages = with pkgs; [
          python311

          poetry
          semgrep

          openapi-generator-cli
        ];

        devshell.startup.ensure_venv.text = ''
          (
            set -e

            # Only do this in projects with Poetry
            if [ -f pyproject.toml ]; then
              ACTIVE="$(command -v python)"            # current Nix python from this devshell
              if [ ! -d .venv ]; then
                echo ">>> Creating .venv with ''${ACTIVE}"
                poetry env use "''${ACTIVE}"
                poetry sync --with dev
              else
                # Realign venv if Nix python changed
                CURRENT="$(realpath .venv/bin/python 2>/dev/null || true)"
                ACTIVE_REAL="$(realpath "''${ACTIVE}" 2>/dev/null || true)"
                if [ "''${CURRENT}" != "''${ACTIVE_REAL}" ]; then
                  echo ">>> Switching venv interpreter to ''${ACTIVE_REAL}"
                  poetry env use "''${ACTIVE_REAL}"
                  poetry sync --with dev
                fi
              fi

              # Optional: auto-sync when the lockfile changed
              if [ ! -e .venv/.poetry.lock.mtime ] || [ poetry.lock -nt .venv/.poetry.lock.mtime ]; then
                echo ">>> Syncing .venv to poetry.lock"
                poetry sync --with dev
                cp -p poetry.lock .venv/.poetry.lock.mtime
              fi

              # Optional: expose venv binaries for editors & CLIs
              export PATH="$PWD/.venv/bin:$PATH"
            fi
          )
        '';
      };
      devShells.py311new = pkgs.devshell.mkShell {
        name = "py311new";

        packages = with pkgs; [
          python311
          poetry
          semgrep
          openapi-generator-cli
        ];

        env = [
          {
            name = "POETRY_VIRTUALENVS_CREATE";
            value = "1";
          }
          {
            name = "POETRY_VIRTUALENVS_IN_PROJECT";
            value = "1";
          }
          {
            name = "POETRY_VIRTUALENVS_PREFER_ACTIVE_PYTHON";
            value = "0";
          }
        ];

        devshell.startup.ensure_venv.text = ''
          (
            set -euo pipefail

            # Avoid inheriting any foreign venv
            unset VIRTUAL_ENV PYTHONHOME PYTHONPATH

            if [ -f pyproject.toml ]; then
              # Always use the python3.11 from THIS devshell
              PY311="$(command -v python3.11)"
              PY311_REAL="$(realpath "$PY311")"

              create_or_switch () {
                echo ">>> Using interpreter: ''${PY311_REAL}"
                poetry env use "''${PY311_REAL}"
                poetry sync --with dev
              }

              if [ ! -d .venv ]; then
                echo ">>> Creating .venv"
                create_or_switch
              else
                CURRENT="$(realpath .venv/bin/python || true)"
                if [ "$CURRENT" != "$PY311_REAL" ]; then
                  echo ">>> Switching venv interpreter to ''${PY311_REAL}"
                  create_or_switch
                fi
              fi

              # Re-sync if lockfile changed
              if [ ! -e .venv/.poetry.lock.mtime ] || [ poetry.lock -nt .venv/.poetry.lock.mtime ]; then
                echo ">>> Syncing .venv to poetry.lock"
                poetry sync --with dev
                cp -p poetry.lock .venv/.poetry.lock.mtime
              fi

              # Put venv binaries first
              export PATH="$PWD/.venv/bin:$PATH"
            fi
          )
        '';
      };

      devShells.py313new = pkgs.devshell.mkShell {
        name = "py313new";

        packages = with pkgs; [
          python313
          poetry
          semgrep
          openapi-generator-cli
        ];

        env = [
          {
            name = "POETRY_VIRTUALENVS_CREATE";
            value = "1";
          }
          {
            name = "POETRY_VIRTUALENVS_IN_PROJECT";
            value = "1";
          }
          {
            name = "POETRY_VIRTUALENVS_PREFER_ACTIVE_PYTHON";
            value = "0";
          }
        ];

        devshell.startup.ensure_venv.text = ''
          (
            set -euo pipefail

            # Avoid inheriting any foreign venv
            unset VIRTUAL_ENV PYTHONHOME PYTHONPATH

            if [ -f pyproject.toml ]; then
              # Always use the python3.11 from THIS devshell
              PY313="$(command -v python3.13)"
              PY313_REAL="$(realpath "$PY313")"

              create_or_switch () {
                echo ">>> Using interpreter: ''${PY313_REAL}"
                poetry env use "''${PY313_REAL}"
                poetry sync --with dev
              }

              if [ ! -d .venv ]; then
                echo ">>> Creating .venv"
                create_or_switch
              else
                CURRENT="$(realpath .venv/bin/python || true)"
                if [ "$CURRENT" != "$PY313_REAL" ]; then
                  echo ">>> Switching venv interpreter to ''${PY313_REAL}"
                  create_or_switch
                fi
              fi

              # Re-sync if lockfile changed
              if [ ! -e .venv/.poetry.lock.mtime ] || [ poetry.lock -nt .venv/.poetry.lock.mtime ]; then
                echo ">>> Syncing .venv to poetry.lock"
                poetry sync --with dev
                cp -p poetry.lock .venv/.poetry.lock.mtime
              fi

              # Put venv binaries first
              export PATH="$PWD/.venv/bin:$PATH"
            fi
          )
        '';
      };

      devShells.py311-pipx = pkgs.devshell.mkShell {
        name = "py311-pipx";

        packages = with pkgs; [
          pre-commit
          python311
          python311Packages.pipx
          coreutils
          gnused
        ];

        env = [
          {
            name = "POETRY_VERSION";
            value = "2.2.1";
          }
        ];

        devshell.startup.poetry_via_pipx.text = ''
          set -euo pipefail

          # Anchor to the active .envrc directory (fallback: current dir if DIRENV_DIR unset)
          ROOT="''${DIRENV_DIR:-$PWD}"
          ROOT="$(cd "$ROOT" && pwd -P)"  # normalize

          export PIPX_HOME="$ROOT/.direnv/pipx"
          export PIPX_BIN_DIR="$PIPX_HOME/bin"
          export PATH="$PIPX_BIN_DIR:$PATH"

          mkdir -p "$PIPX_BIN_DIR"

          if ! command -v pipx >/dev/null 2>&1; then
            echo "pipx not found (should be in devshell)."
            exit 1
          fi

          # Ensure a local .venv exists
          if [[ ! -d .venv ]]; then
            echo ">>> Creating .venv (python: $(command -v python))"
            python -m venv .venv
          fi

          # Bind Poetry to this exact interpreter
          POE="$(command -v poetry || true)"
          if [[ -z "$POE" ]]; then
            echo "error: poetry not found on PATH (expected via pipx)"; exit 1
          fi

          "$POE" env use "$PWD/.venv/bin/python" >/dev/null


          if ! command -v poetry >/dev/null 2>&1; then
            echo ">>> Installing ''${SPEC} via pipx (isolated to ./.direnv/pipx) ..."
            pipx install "''${SPEC}" --python "$(command -v python)"
          else
            if [ -n "''${POETRY_VERSION}" ]; then
              INSTALLED_VER="$(poetry debug info 2>/dev/null | sed -n '1{s/^Version:[[:space:]]*//p}')"
              if [ "''${INSTALLED_VER:-}" != "''${POETRY_VERSION}" ]; then
                echo ">>> Upgrading poetry to ''${POETRY_VERSION} via pipx ..."
                pipx install --force "poetry==''${POETRY_VERSION}" --python "$(command -v python)"
              fi
            else
              echo ">>> Upgrading poetry to latest via pipx ..."
              pipx upgrade poetry || true
            fi
          fi

          echo ">>> poetry at: $(command -v poetry)"
          poetry --version || true
        '';
      };

      devShells.npx = pkgs.devshell.mkShell {
        name = "npx";
        packages = with pkgs; [
          nodejs_20
          openapi-generator-cli
          git
          coreutils
          gnused
          jre_headless
          pnpm
        ];

        devshell.startup.npx_min.text = ''
          set -euo pipefail
          # Prefer local project tools if present
          export PATH="$PWD/node_modules/.bin:$PATH"
          # Enable Corepack so yarn/pnpm work if a repo expects them
          # command -v corepack >/dev/null 2>&1 && corepack enable || true

          # Quick sanity prints (harmless if you don't want them)
          node -v || true
          npm -v  || true
          npx -v  || true
          openapi-generator-cli version || true
        '';
      };

      devShells.java25 = pkgs.devshell.mkShell {
        name = "java25";

        packages = with pkgs; [
          javaPackages.compiler.temurin-bin.jdk-25

          pre-commit

          # leave this out for now
          # gradle
        ];

        # Keep env tidy & predictable
        env = [
          # JDK path on nix/darwin; includes bin/java, javac, etc.
          #{ name = "JAVA_HOME"; value = "${pkgs.jdk21}/lib/openjdk"; }

          # Prefer XDG for Gradle cache; falls back in startup script if not set
          {
            name = "GRADLE_USER_HOME";
            value = "${builtins.getEnv "HOME"}/.local/share/gradle";
          }
        ];

        devshell.startup.gradle_home.text = ''
          set -euo pipefail

          : "''${HOME:?HOME not set}"  # fail fast if somehow empty

          if [ -n "''${XDG_DATA_HOME:-}" ]; then
            export GRADLE_USER_HOME="$XDG_DATA_HOME/gradle"
          else
            export GRADLE_USER_HOME="$HOME/.local/share/gradle"
          fi

          mkdir -p "$GRADLE_USER_HOME"
          echo ">>> GRADLE_USER_HOME=$GRADLE_USER_HOME"
        '';
        #        devshell.startup.ensure_java.text = ''
        #          set -euo pipefail
        #
        #          # Resolve JAVA_HOME and prepend its bin to PATH
        #          JH="${JAVA_HOME}"
        #          if [ ! -x "$JH/bin/java" ]; then
        #            echo ">>> ERROR: JAVA_HOME seems wrong: $JH"
        #            exit 1
        #          fi
        #          export PATH="$JH/bin:$PATH"
        #          echo ">>> Using JAVA_HOME: $JH ($(java -version 2>&1 | head -n1))"
        #
        #          # Prefer XDG for Gradle cache; fall back to ~/.gradle if XDG not set
        #          if [ -z "${XDG_DATA_HOME:-}" ]; then
        #            export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"
        #          else
        #            export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$XDG_DATA_HOME/gradle}"
        #          fi
        #          mkdir -p "$GRADLE_USER_HOME"
        #          echo ">>> GRADLE_USER_HOME: $GRADLE_USER_HOME"
        #
        #          # If the project has a Gradle wrapper, ensure it's executable and prefer it
        #          if [ -f ./gradlew ]; then
        #            chmod +x ./gradlew || true
        #            export GRADLE="./gradlew"
        #            echo ">>> Using Gradle wrapper: $($GRADLE --version | sed -n '1,3p')"
        #          else
        #            export GRADLE="$(command -v gradle)"
        #            echo ">>> No ./gradlew found; using system Gradle: $($GRADLE --version | sed -n '1,3p')"
        #          fi
        #
        #          # Optionally seed a minimal project gradle.properties if none exists
        #          if [ ! -f ./gradle.properties ]; then
        #            cat > ./gradle.properties <<'PROP'
        #      # Created by devshell (edit as needed)
        #      org.gradle.parallel=true
        #      org.gradle.daemon=true
        #      org.gradle.caching=true
        #      org.gradle.jvmargs=-Xmx4g -Dfile.encoding=UTF-8
        #      PROP
        #            echo ">>> Wrote ./gradle.properties (parallel/daemon/caching/jvmargs)"
        #          fi
        #        '';
      };

      devShells.tecton = pkgs.devshell.mkShell {
        name = "tools";

        packages = with pkgs; [
          pre-commit
          python311
          python311Packages.pipx
          coreutils
          gnused
        ];

        env = [
          {
            name = "TECTON_VERSION";
            value = "1.1.11";
          }
        ];

        commands = [
          {
            name = "path-note";
            command = ''echo "PATH += $PIPX_BIN_DIR"'';
            category = "info";
          }
        ];

        devshell.startup.tecton_via_pipx.text = ''
          set -euo pipefail


          # Anchor to the active .envrc directory (fallback: current dir if DIRENV_DIR unset)
          ROOT="''${DIRENV_DIR:-$PWD}"
          ROOT="$(cd "$ROOT" && pwd -P)"  # normalize

          export PIPX_HOME="$ROOT/.direnv/pipx"
          export PIPX_BIN_DIR="$PIPX_HOME/bin"
          export PATH="$PIPX_BIN_DIR:$PATH"

          mkdir -p "$PIPX_BIN_DIR"

          if ! command -v pipx >/dev/null 2>&1; then
            echo "pipx not found (should be in devshell)."
            exit 1
          fi

          # Choose spec based on TECTON_VERSION (use ''${...} to avoid Nix interpolation)
          if [ -n "''${TECTON_VERSION}" ]; then
            SPEC="tecton==''${TECTON_VERSION}"
          else
            SPEC="tecton"
          fi

          if ! command -v tecton >/dev/null 2>&1; then
            echo ">>> Installing ''${SPEC} via pipx (isolated to ./.direnv/pipx) ..."
            pipx install "''${SPEC}" --python "$(command -v python)"
          else
            if [ -n "''${TECTON_VERSION}" ]; then
              INSTALLED_VER="$(tecton version 2>/dev/null | sed -n '1{s/^Version:[[:space:]]*//p}')"
              if [ "''${INSTALLED_VER:-}" != "''${TECTON_VERSION}" ]; then
                echo ">>> Upgrading tecton to ''${SPEC} via pipx ..."
                pipx install --force "''${SPEC}" --python "$(command -v python)"
              fi
            else
              echo ">>> Upgrading tecton to latest via pipx ..."
              pipx upgrade tecton || true
            fi
          fi

          echo ">>> tecton at: $(command -v tecton)"
          tecton version || true
        '';
      };

      formatter = pkgs.alejandra;
    });
}
