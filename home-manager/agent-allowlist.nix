{
  config,
  lib,
  ...
}: let
  cfg = config.dotfiles.agentAllowlist;

  mkCommand = prefix: {inherit prefix;};
  defaultCommands = map mkCommand [
    ["nix" "build"]
    ["nix" "eval"]
    ["nix" "flake" "check"]
    ["nix" "flake" "lock"]
    ["nix" "flake" "metadata"]
    ["nix" "flake" "show"]
    ["nix-store" "-q" "--references"]
    ["nix-store" "--gc" "--print-roots"]
    ["nix-store" "-l"]
    ["just" "check"]
    ["just" "build"]
    ["just" "bootstrap-check"]
    ["just" "vm-test"]
    ["just" "k3s-test"]
    ["darwin-rebuild" "build"]
    ["jj" "status"]
    ["jj" "log"]
    ["jj" "diff"]
    ["jj" "bookmark" "list"]
    ["jj" "git" "remote" "list"]
    ["git" "ls-remote"]
    ["ssh" "-T"]
    ["ssh-add" "-l"]
    ["ps" "-axo" "pid,ppid,stat,etime,command"]
    ["alejandra"]
  ];

  commandType = lib.types.submodule {
    options = {
      prefix = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.str;
        description = "Command argument prefix to allow without agent escalation prompts.";
        example = ["nix" "flake" "check"];
      };

      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional human context for why this command prefix is allowed.";
      };
    };
  };

  codexRuleFor = command: ''prefix_rule(pattern=${builtins.toJSON command.prefix}, decision="allow")'';
  codexRules = lib.concatMapStringsSep "\n" codexRuleFor cfg.commands + "\n";

  claudeToolFor = command: "Bash(${lib.concatStringsSep " " command.prefix}:*)";
  claudeSettings = lib.recursiveUpdate cfg.claude.extraSettings {
    permissions.allow = map claudeToolFor cfg.commands;
  };
in {
  options.dotfiles.agentAllowlist = {
    enable = lib.mkEnableOption "shared Codex and Claude Code command allowlist";

    commands = lib.mkOption {
      type = lib.types.listOf commandType;
      default = defaultCommands;
      description = "Shared command prefixes rendered to Codex rules and Claude Code permissions.";
    };

    claude.extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = {
        theme = "dark";
      };
      description = "Additional Claude Code settings to preserve alongside generated permissions.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file.".codex/rules/dotfiles.rules".text = codexRules;

    home.file.".claude/settings.json" = {
      force = true;
      text = builtins.toJSON claudeSettings;
    };
  };
}
