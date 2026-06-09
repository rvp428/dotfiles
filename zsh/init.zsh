bindkey -v

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

xh-update-session() {
  local token
  token="$(gcloud auth print-identity-token --audiences="$1")" || return
  xh --session sandbox get "https://$2/ping" Authorization:"Bearer $token" X-Oscilar-Env-ID:"$3"
}
