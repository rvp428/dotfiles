{ pkgs, ... }:

let
  nixFishPlugin = {
    name = "nix.fish";

    src = pkgs.fetchFromGitHub {
      owner = "kidonng";
      repo = "nix.fish";
      rev = "ad57d970841ae4a24521b5b1a68121cf385ba71e";
      sha256 = "13x3bfif906nszf4mgsqxfshnjcn6qm4qw1gv7nw89wi4cdp9i8q";
    };
  };
in
{
  home.file = {
    ".config/fish" = {
      source = ../fish;
      recursive = true;
    };
  };

  programs.fish = {
    enable = true;

    plugins = [
      nixFishPlugin
    ];
  };

  programs.bash.enable = true;

  programs.zsh.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  programs.atuin = {
    enable = true;
  };
}
