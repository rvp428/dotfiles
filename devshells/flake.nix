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
      formatter = pkgs.alejandra;
    });
}
