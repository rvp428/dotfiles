{ config, lib, pkgs, ... }:

let
  cfg = config.dotfiles.aws;

  # Render AWS config from sessions + profiles
  renderAwsConfig = sessions: profiles:
    let
      sessionBlock = s: ''
        [sso-session ${s.name}]
        sso_start_url = ${s.startUrl}
        sso_region = ${s.region}
        ${lib.optionalString (s.registrationScopes != null) "sso_registration_scopes = ${s.registrationScopes}"}
      '';
      profileBlock = p: ''
        [profile ${p.name}]
        sso_session = ${p.ssoSessionName}
        sso_start_url = ${p.startUrl}
        sso_account_id = ${p.accountId}
        sso_role_name = ${p.role}
        sso_region = ${p.region}
        ${lib.optionalString p.useCredentialProcess "credential_process = ${if p.credentialProcessCmd != null then p.credentialProcessCmd else "aws-sso-util credential-process --profile ${p.name}"}"}
      '';
    in
    lib.concatStringsSep "\n\n"
      (map sessionBlock sessions ++ map profileBlock profiles
        ++ lib.optional (cfg.extraConfig != "") cfg.extraConfig);

  # Build Docker credHelpers JSON for ECR
  dockerConfigJson =
    let
      pairs = lib.listToAttrs (map
        (r: {
          name = "${r.accountId}.dkr.ecr.${r.region}.amazonaws.com";
          value = "ecr-login";
        })
        cfg.ecrRegistries);
    in
    builtins.toJSON { credHelpers = pairs; };
in
{
  options.dotfiles.aws = {
    enable = lib.mkEnableOption "AWS SSO + ECR helpers via Home Manager";

    # Install tooling
    installPackages = lib.mkOption {
      type = lib.types.bool; default = true;
      description = "Install awscli2, aws-sso-util (via pipx), docker-credential-ecr-login, jq";
    };

    # Manage ~/.aws/config (single, composed file from below lists)
    manageAwsConfig = lib.mkOption {
      type = lib.types.bool; default = true;
      description = "Write ~/.aws/config from sessions and profiles.";
    };

    # Optional: manage ~/.docker/config.json credHelpers for ECR
    manageDockerConfig = lib.mkOption {
      type = lib.types.bool; default = false;
      description = "Write ~/.docker/config.json with ECR credential helpers.";
    };

    # Extra literal text appended to ~/.aws/config (optional)
    extraConfig = lib.mkOption {
      type = lib.types.str; default = "";
      description = "Literal extra text to append to ~/.aws/config.";
    };

    # SSO sessions (personal and/or work)
    ssoSessions = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; };
          startUrl = lib.mkOption { type = lib.types.str; };
          region = lib.mkOption { type = lib.types.str; };
          registrationScopes = lib.mkOption { type = lib.types.nullOr lib.types.str; default = "sso:account:access"; };
        };
      });
      default = [];
      description = "One or more [sso-session] blocks.";
    };

    # Profiles bound to SSO sessions
    profiles = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; };
          ssoSessionName = lib.mkOption { type = lib.types.str; };
          startUrl = lib.mkOption { type = lib.types.str; };
          accountId = lib.mkOption { type = lib.types.str; };
          role = lib.mkOption { type = lib.types.str; };
          region = lib.mkOption { type = lib.types.str; };
          useCredentialProcess = lib.mkOption { type = lib.types.bool; default = true; };
          credentialProcessCmd = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
        };
      });
      default = [];
      description = "Profiles that use SSO sessions (and optional credential_process).";
    };

    # ECR registries for Docker helper
    ecrRegistries = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          accountId = lib.mkOption { type = lib.types.str; };
          region = lib.mkOption { type = lib.types.str; };
        };
      });
      default = [];
    };

    # Optional fish helpers
    installFishFunctions = lib.mkOption {
      type = lib.types.bool; default = true;
    };
  };

  config = lib.mkIf cfg.enable {

    # Tooling
    home.packages = lib.mkIf cfg.installPackages (with pkgs; [
      amazon-ecr-credential-helper
      awscli2
      aws-sso-util
      jq
    ]);

    # ~/.aws/config (composed)
    home.file.".aws/config" = lib.mkIf cfg.manageAwsConfig {
      text = renderAwsConfig cfg.ssoSessions cfg.profiles;
    };

    # ~/.docker/config.json (ECR credHelpers only)
    home.file.".docker/config.json" = lib.mkIf (cfg.manageDockerConfig && cfg.ecrRegistries != []) {
      text = dockerConfigJson;
      # set overwrite = true if you want HM to fully own it
      # overwrite = false;
    };

    # Fish helpers
    programs.fish = lib.mkIf cfg.installFishFunctions {
      enable = true;
      functions = {
        "aws-sso-status".body = ''
          aws-sso-util whoami
        '';
        "aws-sso-ensure".body = ''
          set -l profile $argv[1]
          if test -z "$profile"
            echo "usage: aws-sso-ensure <profile>" >&2
            return 2
          end
          aws sts get-caller-identity --profile $profile >/dev/null 2>&1
          or aws-sso-util login --profile $profile
          aws sts get-caller-identity --profile $profile
        '';
        "ecr-login".body = ''
          if test (count $argv) -lt 1
            echo "usage: ecr-login <registry-host> [region]" >&2
            return 2
          end
          set -l REG $argv[1]
          set -l REGION $argv[2]
          if test -z "$REGION"
            set REGION (aws configure get region)
          end
          aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REG
        '';
      };
    };
  };
}

