bindkey -v

setopt prompt_subst

autoload -Uz add-zsh-hook
autoload -Uz colors
colors

zmodload zsh/datetime 2>/dev/null || true

typeset -g DOTFILES_PROMPT_LEFT=""
typeset -g DOTFILES_PROMPT_RIGHT=""
typeset -g DOTFILES_PROMPT_KEYMAP="I"
typeset -g DOTFILES_PROMPT_CMD_START=""
typeset -g DOTFILES_PROMPT_LAST_DURATION=""
typeset -g DOTFILES_PROMPT_PY_PATH=""
typeset -g DOTFILES_PROMPT_PY_VERSION=""
typeset -g DOTFILES_PROMPT_KUBE_CONTEXT=""
typeset -g DOTFILES_PROMPT_KUBE_CHECKED=0

_dotfiles_prompt_git() {
  command git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return

  local branch git_dir line staged dirty untracked ahead behind state
  branch="$(command git symbolic-ref --quiet --short HEAD 2>/dev/null \
    || command git rev-parse --short HEAD 2>/dev/null)" || return
  git_dir="$(command git rev-parse --git-dir 2>/dev/null)" || return

  [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" ]] && state=":rebase"
  [[ -f "$git_dir/CHERRY_PICK_HEAD" ]] && state=":pick"
  [[ -f "$git_dir/MERGE_HEAD" ]] && state=":merge"

  while IFS= read -r line; do
    if [[ "$line" == "## "* ]]; then
      [[ "$line" =~ "ahead ([0-9]+)" ]] && ahead="^${match[1]}"
      [[ "$line" =~ "behind ([0-9]+)" ]] && behind="v${match[1]}"
      continue
    fi

    if [[ "${line[1,2]}" == "??" ]]; then
      untracked="?"
      continue
    fi

    [[ "${line[1,1]}" != " " ]] && staged="+"
    [[ "${line[2,2]}" != " " ]] && dirty="*"
  done < <(command git status --porcelain=v1 -b 2>/dev/null)

  print -r -- "%F{yellow}git:${branch}${staged}${dirty}${untracked}${ahead}${behind}${state}%f"
}

_dotfiles_prompt_devenv() {
  local envrc line shell_name

  if [[ -n "${DEVSHELL_NAME:-}" ]]; then
    print -r -- "%F{green}nix:${DEVSHELL_NAME}%f"
    return
  fi

  if [[ -n "${DIRENV_FILE:-}" ]]; then
    envrc="${DIRENV_FILE#-}"
    if [[ -r "$envrc" ]]; then
      while IFS= read -r line; do
        if [[ "$line" == *"use flake"* && "$line" =~ "#([^[:space:]]+)" ]]; then
          shell_name="${match[1]}"
          break
        fi
      done < "$envrc"
    fi

    if [[ -n "$shell_name" ]]; then
      print -r -- "%F{green}nix:${shell_name}%f"
    else
      print -r -- "%F{green}direnv%f"
    fi
    return
  fi

  [[ -n "${IN_NIX_SHELL:-}" ]] && print -r -- "%F{green}nix%f"
}

_dotfiles_prompt_python() {
  [[ -n "${VIRTUAL_ENV:-}" || -f pyproject.toml || -n "${IN_NIX_SHELL:-}" ]] || return

  local py_path env_name label
  py_path="$(command -v python 2>/dev/null)" || return
  [[ -x "$py_path" ]] || return

  if [[ "$py_path" != "$DOTFILES_PROMPT_PY_PATH" ]]; then
    DOTFILES_PROMPT_PY_PATH="$py_path"
    DOTFILES_PROMPT_PY_VERSION="$("$py_path" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)"
  fi

  [[ -n "$DOTFILES_PROMPT_PY_VERSION" ]] || return

  label="py${DOTFILES_PROMPT_PY_VERSION}"
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    env_name="${VIRTUAL_ENV:t}"
    label="${label}:${env_name}"
  fi

  print -r -- "%F{blue}${label}%f"
}

_dotfiles_prompt_aws() {
  [[ -n "${AWS_PROFILE:-}" ]] && print -r -- "%F{magenta}aws:${AWS_PROFILE}%f"
}

_dotfiles_prompt_ops() {
  local label

  label="${DOTFILES_OPS_ENV:-${DOTFILES_OPS_NAMESPACE:-}}"
  [[ -n "$label" ]] || return

  if [[ "${DOTFILES_OPS_TIER:-}" == "prod" ]]; then
    print -r -- "%F{red}ops:${label}%f"
  else
    print -r -- "%F{green}ops:${label}%f"
  fi
}

_dotfiles_prompt_kube() {
  local kube_label

  command -v kubectl >/dev/null 2>&1 || return

  if [[ -n "${EPOCHREALTIME:-}" ]] && (( EPOCHREALTIME - DOTFILES_PROMPT_KUBE_CHECKED > 30 )); then
    DOTFILES_PROMPT_KUBE_CONTEXT="$(kubectl config current-context 2>/dev/null)"
    DOTFILES_PROMPT_KUBE_CHECKED="$EPOCHREALTIME"
  fi

  [[ -n "$DOTFILES_PROMPT_KUBE_CONTEXT" ]] || return

  kube_label="${DOTFILES_PROMPT_KUBE_CONTEXT##*/}"
  [[ ${#kube_label} -gt 42 ]] && kube_label="${kube_label[1,39]}..."

  print -r -- "%F{cyan}k8s:${kube_label}%f"
}

_dotfiles_prompt_jobs() {
  local job_count
  job_count="${#${(f)$(jobs -p)}}"
  (( job_count > 0 )) && print -r -- "%F{cyan}jobs:${job_count}%f"
}

_dotfiles_prompt_format_duration() {
  [[ -n "$DOTFILES_PROMPT_LAST_DURATION" ]] || return

  local elapsed="$DOTFILES_PROMPT_LAST_DURATION"
  (( elapsed >= 10 )) || return

  if (( elapsed >= 60 )); then
    printf "%%F{blue}%.0fm%%f" "$(( elapsed / 60 ))"
  else
    printf "%%F{blue}%.0fs%%f" "$elapsed"
  fi
}

_dotfiles_prompt_preexec() {
  DOTFILES_PROMPT_CMD_START="${EPOCHREALTIME:-}"
}

_dotfiles_prompt_precmd() {
  local last_status="$?" duration_segment segment
  local -a right_segments

  if [[ -n "$DOTFILES_PROMPT_CMD_START" && -n "${EPOCHREALTIME:-}" ]]; then
    DOTFILES_PROMPT_LAST_DURATION="$(( EPOCHREALTIME - DOTFILES_PROMPT_CMD_START ))"
  else
    DOTFILES_PROMPT_LAST_DURATION=""
  fi
  DOTFILES_PROMPT_CMD_START=""

  DOTFILES_PROMPT_LEFT="%F{cyan}%~%f $(_dotfiles_prompt_git)"

  for segment in \
    "$(_dotfiles_prompt_devenv)" \
    "$(_dotfiles_prompt_python)" \
    "$(_dotfiles_prompt_aws)" \
    "$(_dotfiles_prompt_ops)" \
    "$(_dotfiles_prompt_kube)" \
    "$(_dotfiles_prompt_jobs)" \
    "$(_dotfiles_prompt_format_duration)"
  do
    [[ -n "$segment" ]] && right_segments+=("$segment")
  done

  (( last_status != 0 )) && right_segments+=("%F{red}x:${last_status}%f")
  right_segments+=("%F{white}${DOTFILES_PROMPT_KEYMAP}%f")

  DOTFILES_PROMPT_RIGHT="${(j: :)right_segments}"
}

_dotfiles_prompt_zle_keymap_select() {
  case "$KEYMAP" in
    vicmd) DOTFILES_PROMPT_KEYMAP="N" ;;
    *) DOTFILES_PROMPT_KEYMAP="I" ;;
  esac
  zle reset-prompt
}

_dotfiles_prompt_zle_line_init() {
  DOTFILES_PROMPT_KEYMAP="I"
  zle reset-prompt
}

zle -N zle-keymap-select _dotfiles_prompt_zle_keymap_select
zle -N zle-line-init _dotfiles_prompt_zle_line_init

add-zsh-hook preexec _dotfiles_prompt_preexec
add-zsh-hook precmd _dotfiles_prompt_precmd

PROMPT='${DOTFILES_PROMPT_LEFT} %# '
RPROMPT='${DOTFILES_PROMPT_RIGHT}'

decode-jwt() {
  local token
  if [[ $# -eq 0 ]]; then
    token="$(pbpaste)"
  else
    token="$1"
  fi

  local -a parts
  parts=("${(@s:.:)token}")
  if [[ ${#parts[@]} -lt 2 ]]; then
    echo "decode-jwt: not a valid JWT" >&2
    return 1
  fi

  printf '%s\n' "${parts[2]}" | base64 -D | jq
}
