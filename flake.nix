{
  description = "Dotfiles (HM modules + nix-darwin module)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    devshells.url = "path:./devshells";
    devshells.inputs.nixpkgs.follows = "nixpkgs";

    nixvim.url = "github:nix-community/nixvim";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    nixpkgs,
    devshells,
    nix-index-database,
    ...
  }: let
    hmModules = {
      unfree = ./home-manager/unfree.nix;
      common = ./home-manager/common.nix;
      git = ./home-manager/git.nix;
      nvim = ./home-manager/nvim.nix;
      shell = ./home-manager/shell.nix;
      poetry = ./home-manager/poetry.nix;
      pytools = ./home-manager/pytools.nix;
      # nixvim lives in the nixvim input
    };
  in {
    # Export your HM modules so others can import them
    inherit hmModules;

    # Export a nix-darwin module that carries your macOS defaults + HM wiring.
    darwinModules.base = {
      lib,
      pkgs,
      config,
      nixvim,
      ...
    }: let
      cfg = config.dotfiles;
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

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [];
          description = "Additional packages to install via home-manager";
        };

        homebrew = {
          enable = lib.mkEnableOption "Enable Homebrew management via nix-darwin";

          brewPrefix = lib.mkOption {
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
            default = [];
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
            type = lib.types.enum ["none" "uninstall" "zap"];
            default = "uninstall";
            description = "Cleanup behavior on activation.";
          };
        };
      };

      config = lib.mkIf cfg.enable (let
        homebrewExposedCommands = lib.unique cfg.homebrew.exposedCommands;
        defaultBrewPrefix =
          if pkgs.stdenv.hostPlatform.system == "aarch64-darwin"
          then "/opt/homebrew"
          else "/usr/local";
        effectiveBrewPrefix =
          if cfg.homebrew.brewPrefix != null
          then toString cfg.homebrew.brewPrefix
          else defaultBrewPrefix;
        brewBinDir = "${effectiveBrewPrefix}/bin";
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
        nix.settings.experimental-features = ["nix-command" "flakes"];
        nix.enable = true;

        system.stateVersion = 6;

        system.defaults = {
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
        };
        system.defaults.CustomUserPreferences = {
          "com.apple.symbolichotkeys" = {
            AppleSymbolicHotKeys = {
              "36" = {enabled = false;};
            };
          };

          "com.microsoft.VSCode" = {ApplePressAndHoldEnabled = false;};
        };

        # Removing remaining beeps
        system.activationScripts.soundPrefs.text = ''
          /usr/bin/defaults write -g com.apple.sound.uiaudio.enabled -bool false
          /usr/bin/killall cfprefsd 2>/dev/null || true
          /usr/bin/killall SystemUIServer 2>/dev/null || true
        '';

        # HM integration

        home-manager.users.${cfg.user} = {...}: {
          home.packages = cfg.extraPackages;

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
        environment.shells = [pkgs.fish];

        # Reasonable default home path on macOS (override from wrapper if needed)
        users.users.${cfg.user} = {
          home = lib.mkDefault "/Users/${cfg.user}";
          shell = pkgs.fish;
        };

        system.primaryUser = lib.mkDefault cfg.user;

        assertions = [
          {
            assertion = lib.all (cmd: builtins.match "^[A-Za-z0-9._+-]+$" cmd != null) cfg.homebrew.exposedCommands;
            message = "dotfiles.homebrew.exposedCommands must contain command names only (letters, numbers, ., _, +, -).";
          }
        ];

        environment.systemPackages = lib.optionals (cfg.homebrew.enable && builtins.length homebrewExposedCommands > 0) [
          brewCliWrappers
        ];

        # ---------- Homebrew via nix-darwin ----------
        # Only configure if enabled
        homebrew = lib.mkIf cfg.homebrew.enable {
          enable = true;

          # Set brewPrefix only when provided
          # (avoids overriding nix-darwin's defaults)
          brewPrefix = lib.mkIf (cfg.homebrew.brewPrefix != null) cfg.homebrew.brewPrefix;

          taps = cfg.homebrew.taps;

          brews = cfg.homebrew.baseBrews ++ cfg.homebrew.extraBrews;
          casks = cfg.homebrew.baseCasks ++ cfg.homebrew.extraCasks;
          masApps = cfg.homebrew.baseMasApps // cfg.homebrew.extraMasApps;

          onActivation = {
            autoUpdate = true;
            upgrade = true;
            cleanup = cfg.homebrew.cleanupMode;
          };

          extraConfig = ''cask_args appdir: "/Applications"'';
        };

        home-manager.sharedModules =
          lib.optionals (!config.home-manager.useGlobalPkgs) [
            (import ./home-manager/unfree.nix)
          ]
          ++ [
            nixvim.homeModules.nixvim
            nix-index-database.homeModules.nix-index
            (import ./home-manager/common.nix)
            (import ./home-manager/git.nix)
            (import ./home-manager/nvim.nix)
            (import ./home-manager/shell.nix)
            (import ./home-manager/poetry.nix)
            (import ./home-manager/pytools.nix)
          ];

        nix = {
          registry = {
            nixpkgs.flake = nixpkgs;
            "raoul-dotfiles".to = {
              type = "path";
              path = "${config.users.users.${cfg.user}.home}/dotfiles";
            };
          };
        };
      });
    };

    devShells = devshells.devShells;
  };
}
