default: build

_print-target host mode:
  @echo "{{mode}} {{DOTFILES_WRAPPER}}#{{host}}"

build host=DOTFILES_HOST: (_print-target host "building local")
  cd "{{DOTFILES_WRAPPER}}" && darwin-rebuild build --flake "{{DOTFILES_WRAPPER}}#{{host}}" --override-input dotfiles "path:{{DOTFILES_DEV}}"

switch host=DOTFILES_HOST: (_print-target host "switching local")
  cd "{{DOTFILES_WRAPPER}}" && sudo darwin-rebuild switch --flake "{{DOTFILES_WRAPPER}}#{{host}}" --override-input dotfiles "path:{{DOTFILES_DEV}}"

bootstrap-check host=DOTFILES_HOST:
  #!/usr/bin/env bash
  set -euo pipefail

  missing=0
  for cmd in nix git just darwin-rebuild ssh ssh-add; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "missing required command: $cmd" >&2
      missing=1
    fi
  done

  for dir in "{{DOTFILES_WRAPPER}}" "{{DOTFILES_DEV}}"; do
    if [ ! -d "$dir" ]; then
      echo "missing directory: $dir" >&2
      missing=1
    fi
  done

  if [ "$missing" -ne 0 ]; then
    exit 1
  fi

  user=$(nix eval --raw --override-input dotfiles "path:{{DOTFILES_DEV}}" "{{DOTFILES_WRAPPER}}#darwinConfigurations.{{host}}.config.dotfiles.user")
  key=$(nix eval --raw --override-input dotfiles "path:{{DOTFILES_DEV}}" "{{DOTFILES_WRAPPER}}#darwinConfigurations.{{host}}.config" --apply "config: config.home-manager.users.\"$user\".dotfiles.ssh.github.identityFile")

  case "$key" in
    "~/"*) key="$HOME/${key#"~/"}" ;;
  esac

  if [ ! -f "$key" ]; then
    echo "missing GitHub SSH key for {{host}}: $key" >&2
    echo "restore/import the private key before running darwin-rebuild switch" >&2
    exit 1
  fi

  perms=$(stat -f '%Lp' "$key" 2>/dev/null || stat -c '%a' "$key" 2>/dev/null || true)
  if [ -n "$perms" ] && [ "$perms" -gt 600 ]; then
    echo "GitHub SSH key permissions are too open: $key has mode $perms" >&2
    echo "run: chmod 600 '$key'" >&2
    exit 1
  fi

  ssh_output=$(mktemp "${TMPDIR:-/tmp}/dotfiles-github-ssh.XXXXXX")
  trap 'rm -f "$ssh_output"' EXIT

  if ssh -F /dev/null -T -o BatchMode=yes -o IdentitiesOnly=yes -i "$key" git@github.com >"$ssh_output" 2>&1; then
    echo "GitHub SSH auth works for {{host}} using $key"
  elif grep -q 'successfully authenticated' "$ssh_output"; then
    echo "GitHub SSH auth works for {{host}} using $key"
  else
    cat "$ssh_output" >&2
    echo "GitHub SSH auth failed for {{host}} using $key" >&2
    echo "if the key is passphrase-protected, run: ssh-add --apple-use-keychain '$key'" >&2
    exit 1
  fi

bootstrap-switch host=DOTFILES_HOST: (bootstrap-check host)
  cd "{{DOTFILES_WRAPPER}}" && sudo darwin-rebuild switch --flake "{{DOTFILES_WRAPPER}}#{{host}}" --override-input dotfiles "path:{{DOTFILES_DEV}}"

build-github host=DOTFILES_HOST: (_print-target host "building github")
  cd "{{DOTFILES_WRAPPER}}" && darwin-rebuild build --flake "{{DOTFILES_WRAPPER}}#{{host}}"

switch-github host=DOTFILES_HOST: (_print-target host "switching github")
  cd "{{DOTFILES_WRAPPER}}" && sudo darwin-rebuild switch --flake "{{DOTFILES_WRAPPER}}#{{host}}"

check:
  cd "{{DOTFILES_WRAPPER}}" && nix flake check --override-input dotfiles "path:{{DOTFILES_DEV}}"

update-dotfiles:
  cd "{{DOTFILES_WRAPPER}}" && nix flake update dotfiles

doctor:
  #!/usr/bin/env bash
  set -euo pipefail

  missing=0
  for cmd in nix git darwin-rebuild just; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "missing required command: $cmd" >&2
      missing=1
    fi
  done

  for dir in "{{DOTFILES_WRAPPER}}" "{{DOTFILES_DEV}}"; do
    if [ ! -d "$dir" ]; then
      echo "missing directory: $dir" >&2
      missing=1
    fi
  done

  if [ "$missing" -ne 0 ]; then
    exit 1
  fi

  if git -C "{{DOTFILES_DEV}}" status --short --untracked-files=all | grep '^??' >/dev/null 2>&1; then
    echo "warning: {{DOTFILES_DEV}} has untracked files; Nix flakes may ignore them until they are added to Git" >&2
  fi

  echo "wrapper: {{DOTFILES_WRAPPER}}"
  echo "shared dotfiles: {{DOTFILES_DEV}}"
  echo "default host: {{DOTFILES_HOST}}"
