{
  description = "Dotfiles (HM modules + nix-darwin module)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    devshells.url = "path:./devshells";
    devshells.inputs.nixpkgs.follows = "nixpkgs";

    nixvim.url = "github:nix-community/nixvim";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    nixpkgs,
    nixpkgs-master,
    devshells,
    nix-index-database,
    ...
  }: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    formatter = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      pkgs.writeShellApplication {
        name = "alejandra-format";
        runtimeInputs = [pkgs.alejandra];
        text = ''
          if [ "$#" -eq 0 ]; then
            exec alejandra .
          fi

          exec alejandra "$@"
        '';
      });

    # Export a nix-darwin module that carries your macOS defaults + HM wiring.
    darwinModules.base = {
      lib,
      pkgs,
      config,
      nixvim,
      ...
    }: let
      cfg = config.dotfiles;
      codexPkgs = import nixpkgs-master {
        system = pkgs.stdenv.hostPlatform.system;
        config.allowUnfreePredicate = pkg:
          builtins.elem (lib.getName pkg) [
          ];
      };
      codexPackages = with codexPkgs; [
        codex
      ];
      primaryUserCfg = lib.attrByPath [cfg.user] null config.users.users;
      primaryUserShell =
        if primaryUserCfg == null
        then null
        else primaryUserCfg.shell;
      primaryUserShellPath =
        if primaryUserShell == null
        then null
        else if lib.types.shellPackage.check primaryUserShell
        then "/run/current-system/sw${primaryUserShell.shellPath}"
        else toString primaryUserShell;
    in {
      # Make the module configurable by the wrapper
      options.dotfiles = {
        enable = lib.mkEnableOption "dotfiles base macOS settings";
        user = lib.mkOption {
          type = lib.types.str;
          description = "Login username to attach the Home Manager profile to.";
          example = "raoul";
        };
        dotfilesDir = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Absolute path to the dotfiles checkout on the target machine.";
          example = "/Users/raoul/dotfiles";
        };

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

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [];
          description = "Additional packages to install via home-manager";
        };

        hosts = lib.mkOption {
          type = lib.types.attrsOf (lib.types.listOf lib.types.str);
          default = {};
          example = {
            "127.0.0.1" = ["example.test" "api.example.test"];
            "192.168.1.10" = ["nas.local"];
          };
          description = ''
            Custom hosts file entries to append to `/etc/hosts`, keyed by IP
            address with a list of hostnames for each address.
          '';
        };

        homebrew = {
          enable = lib.mkEnableOption "Enable Homebrew management via nix-darwin";

          prefix = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null; # let nix-darwin pick; set to /opt/homebrew on Apple Silicon if needed
            description = "Homebrew prefix (e.g. /opt/homebrew).";
          };
          exposedCommands = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            example = ["codex" "claude" "op"];
            description = "Allowlisted Homebrew commands to expose via system-profile wrappers.";
          };

          taps = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Base Brew taps.";
          };

          baseBrews = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            # default = [ "mas" ];
            default = [];
            description = "Base formulae for all machines.";
          };
          baseCasks = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = ["ghostty"];
            description = "Base casks for all machines.";
          };
          baseMasApps = lib.mkOption {
            type = lib.types.attrsOf lib.types.int;
            default = {};
            description = "Base Mac App Store apps for all machines (name = id).";
          };

          # Per-machine add-ons
          extraBrews = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
          };
          extraCasks = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
          };
          extraMasApps = lib.mkOption {
            type = lib.types.attrsOf lib.types.int;
            default = {};
          };

          cleanupMode = lib.mkOption {
            type = lib.types.enum ["none" "check" "uninstall" "zap"];
            default = "check";
            description = "Cleanup behavior on activation.";
          };
          globalBrewfile = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Expose the nix-darwin generated Brewfile to manual brew bundle commands.";
          };
        };
      };

      config = lib.mkIf cfg.enable (let
        homebrewExposedCommands = lib.unique cfg.homebrew.exposedCommands;
        hostsFile =
          ''
            ##
            # Host Database
            #
            # localhost is used to configure the loopback interface
            # when the system is booting.  Do not change this entry.
            ##
            127.0.0.1       localhost
            255.255.255.255 broadcasthost
            ::1             localhost
          ''
          + lib.optionalString (cfg.hosts != {}) (
            "\n# Custom entries managed by nix-darwin\n"
            + lib.concatStringsSep "\n" (
              lib.mapAttrsToList (address: hostnames: "${address} ${lib.concatStringsSep " " hostnames}")
              cfg.hosts
            )
            + "\n"
          );
        defaultBrewPrefix =
          if pkgs.stdenv.hostPlatform.system == "aarch64-darwin"
          then "/opt/homebrew"
          else "/usr/local";
        effectiveBrewPrefix =
          if cfg.homebrew.prefix != null
          then toString cfg.homebrew.prefix
          else defaultBrewPrefix;
        brewBinDir = "${effectiveBrewPrefix}/bin";
        brewfileFile = pkgs.writeText "Brewfile" config.homebrew.brewfile;
        brewCliWrappers = pkgs.runCommandLocal "homebrew-cli-wrappers" {} ''
          mkdir -p "$out/bin"
          ${lib.concatMapStringsSep "\n" (cmd: ''
              cat > "$out/bin/${cmd}" <<'EOF'
              #!/usr/bin/env bash
              set -euo pipefail

              target="${brewBinDir}/${cmd}"
              if [[ ! -x "$target" ]]; then
                echo "error: expected Homebrew executable not found or not executable: $target" >&2
                exit 127
              fi

              exec "$target" "$@"
              EOF
              chmod +x "$out/bin/${cmd}"
            '')
            homebrewExposedCommands}
        '';
      in {
        nix = {
          enable = true;
          settings.experimental-features = ["nix-command" "flakes"];

          registry = {
            nixpkgs.flake = nixpkgs;
            "raoul-dotfiles".to = {
              type = "path";
              path = "${config.users.users.${cfg.user}.home}/dotfiles";
            };
          };
        };

        system = {
          stateVersion = 7;

          defaults = {
            # Enable function keys without fn key
            NSGlobalDomain = {
              "com.apple.keyboard.fnState" = true;

              # Some of the beeps
              "com.apple.sound.beep.volume" = 0.0;
            };
            menuExtraClock = {
              IsAnalog = false;
              Show24Hour = true;
              ShowDate = 0; # 0 = When space allows 1 = Always 2 = Never
            };

            controlcenter.Bluetooth = true;

            CustomUserPreferences = {
              "com.apple.symbolichotkeys" = {
                AppleSymbolicHotKeys = {
                  "36" = {enabled = false;};
                };
              };

              "com.microsoft.VSCode" = {ApplePressAndHoldEnabled = false;};
            };
          };

          # Removing remaining beeps
          activationScripts.soundPrefs.text = ''
            /usr/bin/defaults write -g com.apple.sound.uiaudio.enabled -bool false
            /usr/bin/killall cfprefsd 2>/dev/null || true
            /usr/bin/killall SystemUIServer 2>/dev/null || true
          '';
        };

        # HM integration

        home-manager.users.${cfg.user} = _: {
          home.packages = codexPackages ++ cfg.extraPackages;

          dotfiles.identity = cfg.identity;

          dotfiles.pytools = {
            enable = true;
            manageXdgBinHome = true;
            dotfilesDir =
              if cfg.dotfilesDir != null
              then cfg.dotfilesDir
              else "${config.users.users.${cfg.user}.home}/dotfiles";
            pyPkgs = ps: [ps.ruamel-yaml];
            scripts.fold-scalars-yaml = "py/fold_scalars_yaml.py";
          };
        };

        programs.fish.enable = true;
        programs.zsh.enable = true;
        environment.shells = [pkgs.fish pkgs.zsh];

        # Reasonable default home path on macOS (override from wrapper if needed)
        users.users.${cfg.user} = {
          home = lib.mkDefault "/Users/${cfg.user}";
          shell = lib.mkDefault pkgs.zsh;
        };

        system.primaryUser = lib.mkDefault cfg.user;

        environment.etc."hosts" = {
          text = hostsFile;
          knownSha256Hashes = [
            # Stock macOS /etc/hosts with tabs between the first two columns.
            "c7dd0e2ed261ce76d76f852596c5b54026b9a894fa481381ffd399b556c0e2da"
          ];
        };

        assertions = [
          {
            assertion = lib.all (cmd: builtins.match "^[A-Za-z0-9._+-]+$" cmd != null) cfg.homebrew.exposedCommands;
            message = "dotfiles.homebrew.exposedCommands must contain command names only (letters, numbers, ., _, +, -).";
          }
          {
            assertion = primaryUserCfg != null && primaryUserShell != null;
            message = ''
              dotfiles primary user shell activation is enabled, but users.users.${cfg.user}.shell is not set.
            '';
          }
        ];

        system.activationScripts.postActivation.text = lib.mkAfter (lib.optionalString (primaryUserShellPath != null) ''
          wanted=${lib.escapeShellArg primaryUserShellPath}
          dsclUser=${lib.escapeShellArg "/Users/${cfg.user}"}

          current=$(/usr/bin/dscl . -read "$dsclUser" UserShell 2>/dev/null \
            | /usr/bin/sed 's/^UserShell: //') || current=""

          if [ "$current" != "$wanted" ]; then
            echo "setting primary user shell to $wanted..." >&2
            /usr/bin/dscl . -create "$dsclUser" UserShell "$wanted"
          fi
        '');

        environment.systemPackages = lib.optionals (cfg.homebrew.enable && builtins.length homebrewExposedCommands > 0) [
          brewCliWrappers
        ];

        # ---------- Homebrew via nix-darwin ----------
        # Only configure if enabled
        homebrew = lib.mkIf cfg.homebrew.enable {
          enable = true;

          # Set prefix only when provided
          # (avoids overriding nix-darwin's defaults)
          prefix = lib.mkIf (cfg.homebrew.prefix != null) cfg.homebrew.prefix;

          taps = cfg.homebrew.taps;

          brews = cfg.homebrew.baseBrews ++ cfg.homebrew.extraBrews;
          casks = cfg.homebrew.baseCasks ++ cfg.homebrew.extraCasks;
          masApps = cfg.homebrew.baseMasApps // cfg.homebrew.extraMasApps;

          onActivation = {
            autoUpdate = true;
            upgrade = true;
            cleanup =
              if cfg.homebrew.cleanupMode == "check"
              then "none"
              else cfg.homebrew.cleanupMode;
          };

          global.brewfile = cfg.homebrew.globalBrewfile;

          extraConfig = ''cask_args appdir: "/Applications"'';
        };

        system.checks.text = lib.mkIf (cfg.homebrew.enable && cfg.homebrew.cleanupMode == "check") ''
          if [ -f "${config.homebrew.prefix}/bin/brew" ]; then
            homebrewCleanupExitCode=0
            homebrewCleanupResult=$(PATH="${config.homebrew.prefix}/bin:${lib.makeBinPath [pkgs.mas]}:$PATH" \
              sudo \
                --preserve-env=PATH \
                --user=${lib.escapeShellArg config.homebrew.user} \
                --set-home \
                env HOMEBREW_NO_AUTO_UPDATE=1 \
                brew bundle cleanup --file='${brewfileFile}' 2>&1) || homebrewCleanupExitCode=$?
            if [ "$homebrewCleanupExitCode" -eq 1 ]; then
              printf >&2 '\e[1;31merror: found Homebrew packages not listed in the Brewfile, aborting activation\e[0m\n'
              printf >&2 '%s\n' "$homebrewCleanupResult"
              printf >&2 '\n'
              printf >&2 'To fix this, either:\n'
              printf >&2 '  - Add the listed packages to your nix-darwin Homebrew configuration\n'
              printf >&2 '  - Remove them by running: ${config.homebrew.prefix}/bin/brew bundle cleanup --file=${lib.escapeShellArg brewfileFile} --force\n'
              printf >&2 '  - Set dotfiles.homebrew.cleanupMode to "uninstall" or "zap"\n'
              exit 2
            elif [ "$homebrewCleanupExitCode" -ne 0 ]; then
              printf >&2 '\e[1;31merror: brew bundle cleanup failed, aborting activation\e[0m\n'
              printf >&2 '%s\n' "$homebrewCleanupResult"
              exit 2
            fi
          fi
        '';

        home-manager.sharedModules =
          lib.optionals (!config.home-manager.useGlobalPkgs) [
            (import ./home-manager/unfree.nix)
          ]
          ++ [
            nix-index-database.homeModules.nix-index
            (import ./home-manager/common.nix)
            (import ./home-manager/git.nix)
            (import ./home-manager/nvim.nix {inherit nixvim;})
            (import ./home-manager/shell.nix)
            (import ./home-manager/poetry.nix)
            (import ./home-manager/pytools.nix)
          ];
      });
    };

    inherit (devshells) checks devShells;
  };
}
