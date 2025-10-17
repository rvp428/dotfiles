{ config, lib, pkgs, ... }:
let
  cfg = config.dotfiles.pytools;

  # Python for tools = whatever python3 is in your pinned nixpkgs
  py = pkgs.python3.withPackages (ps: cfg.pyPkgs ps);

  # Resolve absolute vs relative script paths
  mkScriptPath = path:
    if lib.hasPrefix "/" path then path else "${cfg.dotfilesDir}/${path}";

  # Safe default for XDG_BIN_HOME if not defined elsewhere
  defaultBin = "${config.home.homeDirectory}/.local/bin";
  xdgBin = (config.home.sessionVariables.XDG_BIN_HOME or defaultBin);
in
{
  options.dotfiles.pytools = {
    enable = lib.mkEnableOption "Expose dotfiles Python tools via a pinned python3 env";

    # Root of your dotfiles so you can use relative script paths
    dotfilesDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/dotfiles";
      description = "Root directory of your dotfiles; relative script paths are resolved against this.";
    };

    # Function: ps -> [ python packages ]
    pyPkgs = lib.mkOption {
      type = lib.types.functionTo (lib.types.listOf lib.types.package);
      default = (ps: [ ps.ruamel-yaml ]);
      example = (ps: [ ps.ruamel-yaml ps.rich ]);
      description = "Python packages to include in python3.withPackages.";
    };

    # name -> script path (absolute or relative to dotfilesDir)
    scripts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { "fold-scalars-yaml" = "py/fold_scalars_yaml.py"; };
      description = "CLI shims created in $XDG_BIN_HOME that invoke your scripts with the pinned python3.";
    };

    # Create/export XDG_BIN_HOME (default ~/.local/bin) and add it to PATH
    manageXdgBinHome = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "If true, defines $XDG_BIN_HOME (~/.local/bin), adds to PATH, and ensures dir exists.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf cfg.manageXdgBinHome {
      xdg.enable = true;
      home.sessionVariables.XDG_BIN_HOME = lib.mkDefault defaultBin;
      home.sessionPath = [ "$XDG_BIN_HOME" ];
      home.activation.ensureXdgBinHome =
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          mkdir -p ${xdgBin}
        '';
    })
    {
      # Put the interpreter on PATH (fast; no nix-shell)
      home.packages = [ py ];

      # One tiny shim per script into $XDG_BIN_HOME
      home.file = lib.mapAttrs'
        (name: relOrAbs: {
          name = "${xdgBin}/${name}";
          value = {
            executable = true;
            text = ''
              #!/usr/bin/env bash
              set -euo pipefail
              exec ${py}/bin/python "${mkScriptPath relOrAbs}" "$@"
            '';
          };
        })
        cfg.scripts;
    }
  ]);
}

