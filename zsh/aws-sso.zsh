aws-sso-status() {
  aws-sso-util whoami
}

aws-sso-ensure() {
  local profile="$1"
  if [[ -z "$profile" ]]; then
    echo "usage: aws-sso-ensure <profile>" >&2
    return 2
  fi

  aws sts get-caller-identity --profile "$profile" >/dev/null 2>&1 \
    || aws-sso-util login --profile "$profile"
  aws sts get-caller-identity --profile "$profile"
}

ecr-login() {
  if [[ $# -lt 1 ]]; then
    echo "usage: ecr-login <registry-host> [region]" >&2
    return 2
  fi

  local reg="$1"
  local region="$2"
  if [[ -z "$region" ]]; then
    region="$(aws configure get region)"
  fi

  aws ecr get-login-password --region "$region" \
    | docker login --username AWS --password-stdin "$reg"
}
