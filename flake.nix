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
  };

  outputs = { self, nixpkgs, home-manager, devshells, nixvim, nix-index-database, ... }:
  let
    lib = nixpkgs.lib;

    hmModules = {
      common = ./home-manager/common.nix;
      git    = ./home-manager/git.nix;
      nvim   = ./home-manager/nvim.nix;
      shell  = ./home-manager/shell.nix;
      pytools = ./home-manager/pytools.nix;
      # nixvim lives in the nixvim input
    };
  in {
    # Export your HM modules so others can import them
    hmModules = hmModules;

    # Export a nix-darwin module that carries your macOS defaults + HM wiring.
    darwinModules.base = { lib, pkgs, config, nixvim, ... }:
    let
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
        
        homebrew = {
          enable = lib.mkEnableOption "Enable Homebrew management via nix-darwin";

          brewPrefix = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null; # let nix-darwin pick; set to /opt/homebrew on Apple Silicon if needed
            description = "Homebrew prefix (e.g. /opt/homebrew).";
          };

          taps = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
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
            default = [ "visual-studio-code" "1password" "1password-cli" ];
            description = "Base casks for all machines.";
          };
          baseMasApps = lib.mkOption {
            type = lib.types.attrsOf lib.types.int;
            default = { };
            description = "Base Mac App Store apps for all machines (name = id).";
          };

          # Per-machine add-ons
          extraBrews = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
          extraCasks = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
          extraMasApps = lib.mkOption { type = lib.types.attrsOf lib.types.int; default = { }; };

          cleanupMode = lib.mkOption {
            type = lib.types.enum [ "none" "uninstall" "zap" ];
            default = "uninstall";
            description = "Cleanup behavior on activation.";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        nix.settings.experimental-features = [ "nix-command" "flakes" ];
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
              "36" = { enabled = false; };
            };
          };

          "com.microsoft.VSCode" = { ApplePressAndHoldEnabled = false; };
        };

        # Removing remaining beeps
        system.activationScripts.soundPrefs.text = ''
          /usr/bin/defaults write -g com.apple.sound.uiaudio.enabled -bool false
          /usr/bin/killall cfprefsd 2>/dev/null || true
          /usr/bin/killall SystemUIServer 2>/dev/null || true
        '';


        # HM integration
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;

        home-manager.users.${cfg.user} = { ... }: {
          dotfiles.pytools = {
            enable = true;
            manageXdgBinHome = true;
            pyPkgs = ps: [ps.ruamel-yaml ];
            scripts.fold-scalars-yaml = "py/fold_scalars_yaml.py";
          };
        };

        programs.fish.enable = true;
        environment.shells = [ pkgs.fish ];

        # Reasonable default home path on macOS (override from wrapper if needed)
        users.users.${cfg.user} = {
          home = lib.mkDefault "/Users/${cfg.user}";
          shell = pkgs.fish;
	};

        system.primaryUser = lib.mkDefault cfg.user;

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

        home-manager.sharedModules = [
          nixvim.homeManagerModules.nixvim
          nix-index-database.hmModules.nix-index
          (import ./home-manager/common.nix)
          (import ./home-manager/git.nix)
          (import ./home-manager/nvim.nix)
          (import ./home-manager/shell.nix)
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
      };

    };

    devShells = devshells.devShells;
  };
}

