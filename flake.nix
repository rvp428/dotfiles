{
  description = "Dotfiles (HM modules + nix-darwin module)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixvim.url = "github:nix-community/nixvim";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, nixvim, ... }:
  let
    lib = nixpkgs.lib;

    hmModules = {
      common = ./home-manager/common.nix;
      git    = ./home-manager/git.nix;
      nvim   = ./home-manager/nvim.nix;
      shell  = ./home-manager/shell.nix;
      # nixvim lives in the nixvim input
    };
  in {
    # Export your HM modules so others can import them
    hmModules = hmModules;

    # Export a nix-darwin module that carries your macOS defaults + HM wiring.
    darwinModules.base = { lib, pkgs, config, nixvim, home-manager, ... }:
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

      # Pull in Home Manager as a module here so the wrapper doesn't have to
      imports = [ home-manager.darwinModules.home-manager ];

      config = lib.mkIf cfg.enable {
        nix.settings.experimental-features = [ "nix-command" "flakes" ];
        nix.enable = true;

        system.stateVersion = 6;

        system.defaults = {
          # Enable function keys without fn key
          NSGlobalDomain = {
              "com.apple.keyboard.fnState" = true;
            };

          # Disable F11 getting claimed by the system
          "com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
            "36" = { enabled = 0; };
          };
        };

        # HM integration
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;

        programs.fish.enable = true;
        # environment.shells = lib.mkAfter [ pkgs.fish ];
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

	# Your HM stack
	home-manager.users.${cfg.user}.imports = [
	  nixvim.homeManagerModules.nixvim
	  hmModules.common
          hmModules.git
	  hmModules.nvim
	  hmModules.shell
	];
      };
        launchd.user.agents.set-display-sleep = {
    serviceConfig = {
      Label = "set-display-sleep";
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          /usr/bin/pmset -b displaysleep 2
          /usr/bin/pmset -c displaysleep 10
        ''
      ];
      RunAtLoad = true;
    };
  };
    };
  };
}

