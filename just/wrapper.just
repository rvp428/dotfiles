default: build

_require-host host:
    @if [ -z "{{ host }}" ]; then \
      echo "no default host configured" >&2; \
      echo "run: just use-host HOST" >&2; \
      echo "or pass a host explicitly: just build HOST" >&2; \
      exit 1; \
    fi

_require-wrapper:
    @if [ -z "{{ DOTFILES_WRAPPER }}" ]; then \
      echo "DOTFILES_WRAPPER is not configured" >&2; \
      exit 1; \
    fi
    @if [ ! -d "{{ DOTFILES_WRAPPER }}" ]; then \
      echo "DOTFILES_WRAPPER does not exist or is not a directory: {{ DOTFILES_WRAPPER }}" >&2; \
      exit 1; \
    fi

_require-dev:
    @if [ -z "{{ DOTFILES_DEV }}" ]; then \
      echo "DOTFILES_DEV is not configured" >&2; \
      exit 1; \
    fi
    @if [ ! -d "{{ DOTFILES_DEV }}" ]; then \
      echo "DOTFILES_DEV does not exist or is not a directory: {{ DOTFILES_DEV }}" >&2; \
      exit 1; \
    fi

_print-target host mode:
    @echo "{{ mode }} {{ DOTFILES_WRAPPER }}#{{ host }}"

build host=DOTFILES_HOST: (_require-host host) _require-wrapper _require-dev (_print-target host "building local")
    #!/usr/bin/env bash
    set -euo pipefail

    cd "{{ DOTFILES_WRAPPER }}"
    target="{{ DOTFILES_TARGET }}"
    if [ -z "$target" ]; then
      if nix eval --raw --override-input dotfiles "path:{{ DOTFILES_DEV }}" "{{ DOTFILES_WRAPPER }}#darwinConfigurations.{{ host }}.config.networking.hostName" >/dev/null 2>&1; then
        target=darwin
      elif nix eval --raw --override-input dotfiles "path:{{ DOTFILES_DEV }}" "{{ DOTFILES_WRAPPER }}#homeConfigurations.{{ host }}.config.home.username" >/dev/null 2>&1; then
        target=home
      else
        echo "unknown host: {{ host }}" >&2
        exit 1
      fi
    fi

    case "$target" in
      darwin)
        darwin-rebuild build --flake "{{ DOTFILES_WRAPPER }}#{{ host }}" --override-input dotfiles "path:{{ DOTFILES_DEV }}"
        ;;
      home)
        nix build "{{ DOTFILES_WRAPPER }}#homeConfigurations.{{ host }}.activationPackage" --override-input dotfiles "path:{{ DOTFILES_DEV }}"
        ;;
      *)
        echo "unknown DOTFILES_TARGET: $target" >&2
        exit 1
        ;;
    esac

switch host=DOTFILES_HOST: (_require-host host) _require-wrapper _require-dev (_print-target host "switching local")
    #!/usr/bin/env bash
    set -euo pipefail

    cd "{{ DOTFILES_WRAPPER }}"
    target="{{ DOTFILES_TARGET }}"
    if [ -z "$target" ]; then
      if nix eval --raw --override-input dotfiles "path:{{ DOTFILES_DEV }}" "{{ DOTFILES_WRAPPER }}#darwinConfigurations.{{ host }}.config.networking.hostName" >/dev/null 2>&1; then
        target=darwin
      elif nix eval --raw --override-input dotfiles "path:{{ DOTFILES_DEV }}" "{{ DOTFILES_WRAPPER }}#homeConfigurations.{{ host }}.config.home.username" >/dev/null 2>&1; then
        target=home
      else
        echo "unknown host: {{ host }}" >&2
        exit 1
      fi
    fi

    case "$target" in
      darwin)
        sudo darwin-rebuild switch --flake "{{ DOTFILES_WRAPPER }}#{{ host }}" --override-input dotfiles "path:{{ DOTFILES_DEV }}"
        ;;
      home)
        nix build "{{ DOTFILES_WRAPPER }}#homeConfigurations.{{ host }}.activationPackage" --override-input dotfiles "path:{{ DOTFILES_DEV }}"
        ./result/activate
        ;;
      *)
        echo "unknown DOTFILES_TARGET: $target" >&2
        exit 1
        ;;
    esac

bootstrap-check host=DOTFILES_HOST: (_require-host host) _require-wrapper _require-dev
    #!/usr/bin/env bash
    set -euo pipefail

    cd "{{ DOTFILES_WRAPPER }}"
    target="{{ DOTFILES_TARGET }}"
    if [ -z "$target" ]; then
      if nix eval --raw --override-input dotfiles "path:{{ DOTFILES_DEV }}" "{{ DOTFILES_WRAPPER }}#darwinConfigurations.{{ host }}.config.networking.hostName" >/dev/null 2>&1; then
        target=darwin
      elif nix eval --raw --override-input dotfiles "path:{{ DOTFILES_DEV }}" "{{ DOTFILES_WRAPPER }}#homeConfigurations.{{ host }}.config.home.username" >/dev/null 2>&1; then
        target=home
      else
        echo "unknown host: {{ host }}" >&2
        exit 1
      fi
    fi

    missing=0
    required=(nix git just ssh ssh-add)
    case "$target" in
      darwin) required+=(darwin-rebuild) ;;
      home) ;;
      *)
        echo "unknown DOTFILES_TARGET: $target" >&2
        exit 1
        ;;
    esac
    for cmd in "${required[@]}"; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing required command: $cmd" >&2
        missing=1
      fi
    done

    if [ "$missing" -ne 0 ]; then
      exit 1
    fi

    case "$target" in
      darwin)
        user=$(nix eval --raw --override-input dotfiles "path:{{ DOTFILES_DEV }}" "{{ DOTFILES_WRAPPER }}#darwinConfigurations.{{ host }}.config.dotfiles.user")
        key=$(nix eval --raw --override-input dotfiles "path:{{ DOTFILES_DEV }}" "{{ DOTFILES_WRAPPER }}#darwinConfigurations.{{ host }}.config" --apply "config: config.home-manager.users.\"$user\".dotfiles.ssh.github.identityFile")
        ;;
      home)
        user=$(nix eval --raw --override-input dotfiles "path:{{ DOTFILES_DEV }}" "{{ DOTFILES_WRAPPER }}#homeConfigurations.{{ host }}.config.home.username")
        key=$(nix eval --raw --override-input dotfiles "path:{{ DOTFILES_DEV }}" "{{ DOTFILES_WRAPPER }}#homeConfigurations.{{ host }}.config.dotfiles.ssh.github.identityFile")
        ;;
    esac

    case "$key" in
      "~/"*) key="$HOME/${key#"~/"}" ;;
    esac

    if [ ! -f "$key" ]; then
      echo "missing GitHub SSH key for {{ host }}: $key" >&2
      echo "restore/import the private key before switching this profile" >&2
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
      echo "GitHub SSH auth works for {{ host }} using $key"
    elif grep -q 'successfully authenticated' "$ssh_output"; then
      echo "GitHub SSH auth works for {{ host }} using $key"
    else
      cat "$ssh_output" >&2
      echo "GitHub SSH auth failed for {{ host }} using $key" >&2
      if [ "$target" = darwin ]; then
        echo "if the key is passphrase-protected, run: ssh-add --apple-use-keychain '$key'" >&2
      else
        echo "if the key is passphrase-protected, run: ssh-add '$key'" >&2
      fi
      exit 1
    fi

bootstrap-switch host=DOTFILES_HOST: (bootstrap-check host) (switch host)

build-github host=DOTFILES_HOST: (_require-host host) _require-wrapper (_print-target host "building github")
    #!/usr/bin/env bash
    set -euo pipefail

    cd "{{ DOTFILES_WRAPPER }}"
    target="{{ DOTFILES_TARGET }}"
    if [ -z "$target" ]; then
      if nix eval --raw "{{ DOTFILES_WRAPPER }}#darwinConfigurations.{{ host }}.config.networking.hostName" >/dev/null 2>&1; then
        target=darwin
      elif nix eval --raw "{{ DOTFILES_WRAPPER }}#homeConfigurations.{{ host }}.config.home.username" >/dev/null 2>&1; then
        target=home
      else
        echo "unknown host: {{ host }}" >&2
        exit 1
      fi
    fi

    case "$target" in
      darwin) darwin-rebuild build --flake "{{ DOTFILES_WRAPPER }}#{{ host }}" ;;
      home) nix build "{{ DOTFILES_WRAPPER }}#homeConfigurations.{{ host }}.activationPackage" ;;
      *)
        echo "unknown DOTFILES_TARGET: $target" >&2
        exit 1
        ;;
    esac

switch-github host=DOTFILES_HOST: (_require-host host) _require-wrapper (_print-target host "switching github")
    #!/usr/bin/env bash
    set -euo pipefail

    cd "{{ DOTFILES_WRAPPER }}"
    target="{{ DOTFILES_TARGET }}"
    if [ -z "$target" ]; then
      if nix eval --raw "{{ DOTFILES_WRAPPER }}#darwinConfigurations.{{ host }}.config.networking.hostName" >/dev/null 2>&1; then
        target=darwin
      elif nix eval --raw "{{ DOTFILES_WRAPPER }}#homeConfigurations.{{ host }}.config.home.username" >/dev/null 2>&1; then
        target=home
      else
        echo "unknown host: {{ host }}" >&2
        exit 1
      fi
    fi

    case "$target" in
      darwin) sudo darwin-rebuild switch --flake "{{ DOTFILES_WRAPPER }}#{{ host }}" ;;
      home)
        nix build "{{ DOTFILES_WRAPPER }}#homeConfigurations.{{ host }}.activationPackage"
        ./result/activate
        ;;
      *)
        echo "unknown DOTFILES_TARGET: $target" >&2
        exit 1
        ;;
    esac

check: _require-wrapper _require-dev
    cd "{{ DOTFILES_WRAPPER }}" && nix flake check --override-input dotfiles "path:{{ DOTFILES_DEV }}"

update-dotfiles: _require-wrapper
    cd "{{ DOTFILES_WRAPPER }}" && nix flake update dotfiles

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

    if [ -z "{{ DOTFILES_WRAPPER }}" ]; then
      echo "DOTFILES_WRAPPER is not configured" >&2
      missing=1
    elif [ ! -d "{{ DOTFILES_WRAPPER }}" ]; then
      echo "DOTFILES_WRAPPER does not exist or is not a directory: {{ DOTFILES_WRAPPER }}" >&2
      missing=1
    fi

    if [ -z "{{ DOTFILES_DEV }}" ]; then
      echo "DOTFILES_DEV is not configured" >&2
      missing=1
    elif [ ! -d "{{ DOTFILES_DEV }}" ]; then
      echo "DOTFILES_DEV does not exist or is not a directory: {{ DOTFILES_DEV }}" >&2
      missing=1
    fi

    if [ "$missing" -ne 0 ]; then
      exit 1
    fi

    if git -C "{{ DOTFILES_DEV }}" status --short --untracked-files=all | grep '^??' >/dev/null 2>&1; then
      echo "warning: {{ DOTFILES_DEV }} has untracked files; Nix flakes may ignore them until they are added to Git" >&2
    fi

    echo "wrapper: {{ DOTFILES_WRAPPER }}"
    echo "shared dotfiles: {{ DOTFILES_DEV }}"
    if [ -n "{{ DOTFILES_HOST }}" ]; then
      echo "default host: {{ DOTFILES_HOST }}"
    else
      echo "default host: <unset>"
      echo "run: just use-host HOST"
    fi
    if [ -n "{{ DOTFILES_TARGET }}" ]; then
      echo "default target: {{ DOTFILES_TARGET }}"
    else
      echo "default target: <unset>"
    fi
