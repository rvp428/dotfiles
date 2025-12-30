{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "raoul";
  #  home.homeDirectory = lib.mkDefault (
  #    if pkgs.stdenv.isDarwin
  #    then "/Users/${config.home.username}"
  #    else "/home/${config.home.username}";
  #  );

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.05"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # General use
    asciidoctor
    atuin
    alacritty
    fd # find replacement
    fzf
    haskellPackages.pandoc-cli
    htop
    ripgrep
    zoxide
    xh

    # dev
    awscli2
    clickhouse
    delta
    direnv
    docker
    docker-compose
    gh
    git
    jq
    jqp
    kubectl
    meld
    nix-direnv
    yq-go

    # For now, ideally move all of these to devshells instead
    poetry

    # Nix logistics
    alejandra
    deadnix
    nixfmt-tree
    statix
  ];

  programs.home-manager.enable = true;

  programs.ssh = {
    enable = true;
    matchBlocks = {
      "github.com" = {
        identityFile = "~/.ssh/id_github";
        user = "git";
      };
    };
  };

  programs.nix-index-database.comma.enable = true;
}
