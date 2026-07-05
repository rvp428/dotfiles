{nixpkgs-master}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.profile;
  codexPkgs = import nixpkgs-master {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [
      ];
  };
in {
  options.dotfiles.profile = {
    enable = lib.mkEnableOption "shared dotfiles Home Manager profile";

    identity = lib.mkOption {
      type = lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Commit author name shared by Git and Jujutsu.";
            example = "Raoul van Prooijen";
          };
          email = lib.mkOption {
            type = lib.types.str;
            description = "Commit author email shared by Git and Jujutsu.";
            example = "146374886+rvp428@users.noreply.github.com";
          };
        };
      };
      description = "Commit identity to expose to Git-compatible version control tools.";
    };

    dotfilesDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/dotfiles";
      description = "Absolute path to the dotfiles checkout on the target machine.";
      example = "/home/raoul/dotfiles";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional packages to install through Home Manager.";
    };

    desktop.enable = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isDarwin;
      description = "Enable desktop packages and GUI-oriented configuration.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      (with codexPkgs; [
        codex
      ])
      ++ cfg.extraPackages;

    dotfiles.identity = cfg.identity;

    dotfiles.pytools = {
      enable = true;
      manageXdgBinHome = true;
      dotfilesDir = cfg.dotfilesDir;
      pyPkgs = ps: [ps.ruamel-yaml];
      scripts.fold-scalars-yaml = "py/fold_scalars_yaml.py";
    };
  };
}
