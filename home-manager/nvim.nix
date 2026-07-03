{nixvim}: {pkgs, ...}: let
  system = pkgs.stdenv.hostPlatform.system;
  nixvimPkgs = import (import "${nixvim.outPath}/nixpkgs.nix") {
    inherit system;
  };
  nvim = nixvim.legacyPackages.${system}.makeNixvimWithModule {
    pkgs = nixvimPkgs;
    module = import ./nixvim-config.nix;
  };
in {
  home.packages = [nvim];
  xdg.configFile."nvim/lua".source = ../nvim/lua;
}
