{pkgs, ...}: {
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home = {
    username = "raoul";
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
    stateVersion = "25.05"; # Please read the comment before changing.

    # The home.packages option allows you to install Nix packages into your
    # environment.
    packages = with pkgs; [
      # General use
      asciidoctor
      atuin
      bat
      eza
      fd # find replacement
      fzf
      haskellPackages.pandoc-cli
      htop
      (iosevka-bin.override {variant = "SGr-IosevkaTerm";})
      obsidian
      ripgrep
      viddy
      xh

      # shell
      alacritty
      nushell

      # dev
      awscli2
      delta
      direnv
      docker
      docker-compose
      gh
      git
      git-spice
      jq
      jqp
      kubectl
      meld
      nix-direnv
      yq-go

      # Nix logistics -- should these just be devshells also?
      alejandra
      deadnix
      nixfmt-tree
      statix
    ];

    file."Library/Fonts/Nix/IosevkaTerm".source = "${pkgs.iosevka-bin.override {variant = "SGr-IosevkaTerm";}}/share/fonts/truetype";
  };

  programs = {
    home-manager.enable = true;

    tmux = {
      enable = true;
      extraConfig = builtins.readFile ../tmux/tmux.conf;
    };

    ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks = {
        "*" = {
          forwardAgent = false;
          addKeysToAgent = "no";
          compression = false;
          serverAliveInterval = 0;
          serverAliveCountMax = 3;
          hashKnownHosts = false;
          userKnownHostsFile = "~/.ssh/known_hosts";
          controlMaster = "no";
          controlPath = "~/.ssh/master-%r@%n:%p";
          controlPersist = "no";
        };

        "github.com" = {
          identityFile = "~/.ssh/id_github";
          user = "git";
        };
      };
    };

    nix-index-database.comma.enable = true;

    pay-respects = {
      enable = true;
      enableFishIntegration = true;
      enableZshIntegration = true;
      options = [
        "--alias"
        "pls"
      ];
    };

    zoxide = {
      enable = true;
      enableFishIntegration = true;
      enableZshIntegration = true;
    };
  };

  # 2) Ghostty config
  xdg.enable = true;
  xdg.configFile."ghostty/config".text = ''
    font-family = Iosevka Term
    font-size = 14
  '';
}
