{nixvim}: {pkgs, ...}: let
  system = pkgs.stdenv.hostPlatform.system;
  nixvimPkgs = import (import "${nixvim.outPath}/nixpkgs.nix") {
    inherit system;
  };
  statixNoCheck = nixvimPkgs.statix.overrideAttrs {
    doCheck = false;
  };
  nvim = nixvim.legacyPackages.${system}.makeNixvimWithModule {
    extraSpecialArgs = {inherit statixNoCheck;};
    pkgs = nixvimPkgs;
    module = import ./nixvim-config.nix;
  };
in {
  home.packages = [nvim];
  xdg.configFile."nvim/lua".source = ../nvim/lua;
}
