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
      nvim   = ./home-manager/nvim.nix;
      shell  = ./home-manager/shell.nix;
      # nixvim lives in the nixvim input
    };
  in {
    # Export your HM modules so others can import them
    hmModules = hmModules;

    # Export a nix-darwin module that carries your macOS defaults + HM wiring.
    darwinModules.base = { lib, config, nixvim, home-manager, ... }:
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
      };

      # Pull in Home Manager as a module here so the wrapper doesn't have to
      imports = [ home-manager.darwinModules.home-manager ];

      config = lib.mkIf cfg.enable {
        # macOS (nix-darwin) defaults you wanted in-repo
        services.nix-daemon.enable = true;
        programs.zsh.enable = true;
        nix.settings.experimental-features = [ "nix-command" "flakes" ];

        # HM integration
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;

        # Reasonable default home path on macOS (override from wrapper if needed)
        users.users.${cfg.user}.home = lib.mkDefault "/Users/${cfg.user}";

        # Your HM stack
        home-manager.users.${cfg.user}.imports = [
          nixvim.homeManagerModules.nixvim
          hmModules.common
          hmModules.nvim
          hmModules.shell
        ];
      };
    };
  };
}

