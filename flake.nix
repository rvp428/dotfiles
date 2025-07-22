{
  description = "Home Config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixvim,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      genAttrs = nixpkgs.lib.genAttrs;
    in
    {
      homeConfigurations = genAttrs systems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            nixvim.homeManagerModules.nixvim
            ./home-manager/common.nix
            ./home-manager/nvim.nix
            ./home-manager/shell.nix
          ];
        }
      );

      formatter = genAttrs systems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.nixfmt-tree
      );

      apps = nixpkgs.lib.genAttrs systems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          updateHomeDrv = pkgs.writeShellScriptBin "updateHome" ''
            # update all inputs (including home-manager)
            nix flake update
            # rebuild & activate your home‐manager config
            nix run .#homeConfigurations.${system}.activationPackage
          '';
        in
        {
          updateHome = {
            type = "app";
            program = "${updateHomeDrv}/bin/updateHome";
          };
        }
      );
    };
}
