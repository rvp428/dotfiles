set positional-arguments

default: check

fmt:
  nix fmt

check:
  nix flake check

lock:
  nix flake lock

doctor:
  #!/usr/bin/env bash
  set -euo pipefail

  missing=0
  for cmd in nix git just; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "missing required command: $cmd" >&2
      missing=1
    fi
  done

  if [ "$missing" -ne 0 ]; then
    exit 1
  fi

  echo "shared dotfiles checkout: {{justfile_directory()}}"
  git -C "{{justfile_directory()}}" status --short
