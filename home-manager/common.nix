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
    atuin
    alacritty
    htop
    ripgrep

    # dev
    awscli2
    direnv
    docker
    docker-compose
    gh
    git
    jq
    jqp
    kubectl
    meld
    yq

    # For now, ideally move all of these to devshells instead
    poetry

    # Nix logistics
    alejandra
    nixfmt-tree
    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];

  programs.ssh = {
    enable = true;
    matchBlocks = {
      "github.com" = {
        identityFile = "~/.ssh/id_github";
        user = "git";
      };
    };
  };

  programs.home-manager.enable = true;
}
