{
  config,
  lib,
  ...
}: let
  cfg = config.dotfiles.opsEnv;
  q = value: lib.escapeShellArg (toString value);
  nullable = value:
    if value == null
    then ""
    else value;
  envNames = lib.attrNames cfg.environments;
  reservedCommands = ["ecr" "envs" "help" "k" "login" "pods" "psql" "who"];

  renderAssoc = name: attr:
    ''
      typeset -gA ${name}=(
      ${lib.concatMapStringsSep "\n" (env: "  ${q env} ${q cfg.environments.${env}.${attr}}") envNames}
      )
    '';

  opsZsh = ''
    typeset -ga DOTFILES_OPS_ENV_NAMES=( ${lib.concatMapStringsSep " " q envNames} )
    typeset -g DOTFILES_OPS_DEFAULT_AWS_PROFILE=${q (nullable cfg.defaultAwsProfile)}
    typeset -g DOTFILES_OPS_ECR_ACCOUNT_ID=${q (nullable cfg.ecrAccountId)}
    typeset -g DOTFILES_OPS_PSQL_ENABLED=${q (if cfg.psql.enable then "1" else "0")}
    typeset -g DOTFILES_OPS_PSQL_SECRET=${q cfg.psql.secretName}
    typeset -g DOTFILES_OPS_PSQL_DEPLOYMENT=${q cfg.psql.deploymentName}
    typeset -g DOTFILES_OPS_PSQL_DATABASE=${q cfg.psql.databaseName}
    typeset -g DOTFILES_OPS_PSQL_USER=${q cfg.psql.user}
    typeset -g DOTFILES_OPS_PSQL_IMAGE=${q cfg.psql.image}

    ${renderAssoc "DOTFILES_OPS_ENV_REGION" "region"}
    ${renderAssoc "DOTFILES_OPS_ENV_CONTEXT" "context"}
    ${renderAssoc "DOTFILES_OPS_ENV_NAMESPACE" "namespace"}
    ${renderAssoc "DOTFILES_OPS_ENV_TIER" "tier"}

    _dotfiles_ops_envs() {
      print -r -- "''${DOTFILES_OPS_ENV_NAMES[*]}"
    }

    _dotfiles_ops_require_env() {
      if [[ -z "''${DOTFILES_OPS_ENV:-}" || -z "''${DOTFILES_OPS_NAMESPACE:-}" ]]; then
        print -u2 "ops: select an environment first, e.g. ops ''${DOTFILES_OPS_ENV_NAMES[1]}"
        return 1
      fi
    }

    _dotfiles_ops_select_env() {
      local env_name="$1"

      if [[ -z "''${DOTFILES_OPS_ENV_REGION[$env_name]:-}" ]]; then
        print -u2 "ops: unknown environment '$env_name'"
        print -u2 "usage: ops <''${DOTFILES_OPS_ENV_NAMES[*]// /|}>"
        return 1
      fi

      export DOTFILES_OPS_ENV="$env_name"
      export DOTFILES_OPS_REGION="''${DOTFILES_OPS_ENV_REGION[$env_name]}"
      export DOTFILES_OPS_NAMESPACE="''${DOTFILES_OPS_ENV_NAMESPACE[$env_name]}"
      export DOTFILES_OPS_TIER="''${DOTFILES_OPS_ENV_TIER[$env_name]}"
      export AWS_REGION="$DOTFILES_OPS_REGION"
      export AWS_DEFAULT_REGION="$DOTFILES_OPS_REGION"
      export K8S_NAMESPACE="$DOTFILES_OPS_NAMESPACE"

      kubectl config use-context "''${DOTFILES_OPS_ENV_CONTEXT[$env_name]}" || return
      kubectl config set-context --current --namespace="$DOTFILES_OPS_NAMESPACE" >/dev/null || return

      DOTFILES_PROMPT_KUBE_CONTEXT="''${DOTFILES_OPS_ENV_CONTEXT[$env_name]}"
      DOTFILES_PROMPT_KUBE_CHECKED="''${EPOCHREALTIME:-0}"

      print -r -- "DOTFILES_OPS_ENV=$DOTFILES_OPS_ENV"
      print -r -- "AWS_REGION=$AWS_REGION"
      print -r -- "DOTFILES_OPS_NAMESPACE=$DOTFILES_OPS_NAMESPACE"
      [[ "$DOTFILES_OPS_TIER" == "prod" ]] && print -u2 "WARNING: You are operating in production."
    }

    _dotfiles_ops_login() {
      local profile="''${1:-$DOTFILES_OPS_DEFAULT_AWS_PROFILE}"

      if [[ -z "$profile" ]]; then
        print -u2 "ops: no AWS profile supplied and no default profile configured"
        return 1
      fi

      aws sso login --profile "$profile" || return
      eval "$(aws configure export-credentials --profile "$profile" --format env)" || return
      export AWS_PROFILE="$profile"
    }

    _dotfiles_ops_ecr() {
      local region="''${DOTFILES_OPS_REGION:-''${AWS_REGION:-''${AWS_DEFAULT_REGION:-}}}"
      local registry

      if [[ -z "$DOTFILES_OPS_ECR_ACCOUNT_ID" ]]; then
        print -u2 "ops: no ECR account ID configured"
        return 1
      fi
      if [[ -z "$region" ]]; then
        print -u2 "ops: select an environment or set AWS_REGION before ECR login"
        return 1
      fi

      registry="$DOTFILES_OPS_ECR_ACCOUNT_ID.dkr.ecr.$region.amazonaws.com"
      aws ecr get-login-password --region "$region" \
        | docker login --username AWS --password-stdin "$registry"
    }

    _dotfiles_ops_who() {
      print -r -- "DOTFILES_OPS_ENV:       ''${DOTFILES_OPS_ENV:-}"
      print -r -- "AWS_PROFILE:            ''${AWS_PROFILE:-}"
      print -r -- "AWS_REGION:             ''${AWS_REGION:-}"
      print -r -- "DOTFILES_OPS_NAMESPACE: ''${DOTFILES_OPS_NAMESPACE:-}"
      print -r -- "kubectl ctx:            $(kubectl config current-context 2>/dev/null)"
      print -r -- "kubectl ns:             $(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null)"
    }

    _dotfiles_ops_psql() {
      _dotfiles_ops_require_env || return

      if [[ "$DOTFILES_OPS_PSQL_ENABLED" != "1" ]]; then
        print -u2 "ops: psql helper is not enabled for this configuration"
        return 1
      fi

      local password host
      password="$(kubectl get secret "$DOTFILES_OPS_PSQL_SECRET" -n "$DOTFILES_OPS_NAMESPACE" -o json | jq -r .data.password | base64 --decode)" || return
      host="$(kubectl -n "$DOTFILES_OPS_NAMESPACE" describe deployment "$DOTFILES_OPS_PSQL_DEPLOYMENT" | grep POSTGRES_URL | cut -d/ -f 3)" || return
      if [[ -z "$password" ]]; then
        print -u2 "ops: could not read Postgres password from secret $DOTFILES_OPS_PSQL_SECRET"
        return 1
      fi
      if [[ -z "$host" ]]; then
        print -u2 "ops: could not find POSTGRES_URL in deployment $DOTFILES_OPS_PSQL_DEPLOYMENT"
        return 1
      fi

      kubectl -n "$DOTFILES_OPS_NAMESPACE" run -i --tty --rm "psql-$USER" \
        --image="$DOTFILES_OPS_PSQL_IMAGE" \
        --restart=Never \
        --env="PGPASSWORD=$password" \
        -- psql -d "$DOTFILES_OPS_PSQL_DATABASE" -U "$DOTFILES_OPS_PSQL_USER" -h "$host"
    }

    _dotfiles_ops_help() {
      cat <<EOF
    usage:
      ops <env>           switch kubectl context and namespace together
      ops envs            list configured environments
      ops who             show selected AWS/Kubernetes target
      ops login [profile] login to AWS SSO and export credentials
      ops ecr             login Docker to ECR for the selected/current region
      ops psql            open Postgres through kubectl when enabled
      ops pods [args...]  kubectl get pods in DOTFILES_OPS_NAMESPACE
      ops k [args...]     kubectl -n DOTFILES_OPS_NAMESPACE ...

    envs:
      ''${DOTFILES_OPS_ENV_NAMES[*]}
    EOF
    }

    ops() {
      local command_name="''${1:-help}"
      [[ $# -gt 0 ]] && shift

      if [[ -n "''${DOTFILES_OPS_ENV_REGION[$command_name]:-}" ]]; then
        _dotfiles_ops_select_env "$command_name"
        return
      fi

      case "$command_name" in
        envs)
          _dotfiles_ops_envs
          ;;
        who)
          _dotfiles_ops_who
          ;;
        login)
          _dotfiles_ops_login "$@"
          ;;
        ecr)
          _dotfiles_ops_ecr
          ;;
        psql)
          _dotfiles_ops_psql
          ;;
        pods)
          _dotfiles_ops_require_env || return
          kubectl -n "$DOTFILES_OPS_NAMESPACE" get pods "$@"
          ;;
        k)
          _dotfiles_ops_require_env || return
          kubectl -n "$DOTFILES_OPS_NAMESPACE" "$@"
          ;;
        help|-h|--help)
          _dotfiles_ops_help
          ;;
        *)
          print -u2 "ops: unknown command '$command_name'"
          _dotfiles_ops_help
          return 1
          ;;
      esac
    }
  '';
in {
  options.dotfiles.opsEnv = {
    enable = lib.mkEnableOption "generic operational environment shell helpers";

    defaultAwsProfile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default AWS profile for `ops login` when no profile is supplied.";
    };

    ecrAccountId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "AWS account ID used by `ops ecr` to build the ECR registry host.";
    };

    environments = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          region = lib.mkOption {type = lib.types.str;};
          context = lib.mkOption {type = lib.types.str;};
          namespace = lib.mkOption {type = lib.types.str;};
          tier = lib.mkOption {
            type = lib.types.enum ["prod" "nonprod"];
            default = "nonprod";
          };
        };
      });
      default = {};
      description = "Named operational environments available through `ops <env>`.";
    };

    psql = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the conventional Kubernetes Postgres helper.";
      };
      secretName = lib.mkOption {
        type = lib.types.str;
        default = "database";
      };
      deploymentName = lib.mkOption {
        type = lib.types.str;
        default = "decision";
      };
      databaseName = lib.mkOption {
        type = lib.types.str;
        default = "deployment";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "postgres";
      };
      image = lib.mkOption {
        type = lib.types.str;
        default = "postgres";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.environments != {};
        message = "dotfiles.opsEnv.environments must define at least one environment.";
      }
      {
        assertion = lib.all (name: builtins.match "^[A-Za-z0-9._-]+$" name != null) envNames;
        message = "dotfiles.opsEnv environment names may only contain letters, numbers, dots, underscores, and dashes.";
      }
      {
        assertion = lib.all (name: !(builtins.elem name reservedCommands)) envNames;
        message = "dotfiles.opsEnv environment names cannot be reserved ops subcommands.";
      }
    ];

    programs.zsh = {
      enable = true;
      initContent = lib.mkAfter opsZsh;
    };
  };
}
