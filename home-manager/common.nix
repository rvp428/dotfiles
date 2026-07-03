{
  config,
  lib,
  pkgs,
  ...
}: let
  githubSsh = config.dotfiles.ssh.github;
  githubSshSettings = lib.optionalAttrs (githubSsh.identityFile != null) {
    "github.com" =
      {
        AddKeysToAgent = "yes";
        IdentitiesOnly = "yes";
        IdentityFile = [githubSsh.identityFile];
        User = "git";
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        UseKeychain = "yes";
      };
  };
in {
  options.dotfiles.ssh.github = {
    identityFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "~/.ssh/id_rsa";
      description = "Path to the private SSH key to use for GitHub. The key must be restored outside Nix.";
    };
  };

  config = {
    # Home Manager needs a bit of information about you and the paths it should
    # manage.
    home = {
      # Username/homeDirectory are intentionally wrapper-owned so shared modules
      # stay portable across work/personal hosts.

      # This value determines the Home Manager release that your configuration is
      # compatible with. This helps avoid breakage when a new Home Manager release
      # introduces backwards incompatible changes.
      #
      # You should not change this value, even if you update Home Manager. If you do
      # want to update the value, then make sure to first check the Home Manager
      # release notes.
      stateVersion = "26.05"; # Please read the comment before changing.

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
        direnv
        docker
        docker-compose
        gh
        git-spice
        just
        jq
        jqp
        kubectl
        nix-direnv
        pre-commit
        yq-go

        # Nix logistics -- should these just be devshells also?
        alejandra
        deadnix
        nixfmt-tree
        (statix.overrideAttrs {
          doCheck = false;
        })
      ];

      file."Library/Fonts/Nix/IosevkaTerm".source = "${pkgs.iosevka-bin.override {variant = "SGr-IosevkaTerm";}}/share/fonts/truetype";
    };

    targets = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      darwin = {
        copyApps.enable = true;
        linkApps.enable = false;
      };
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
        settings =
          {
            "*" = {
              ForwardAgent = false;
              AddKeysToAgent = "no";
              Compression = false;
              ServerAliveInterval = 0;
              ServerAliveCountMax = 3;
              HashKnownHosts = false;
              UserKnownHostsFile = "~/.ssh/known_hosts";
              ControlMaster = "no";
              ControlPath = "~/.ssh/master-%r@%n:%p";
              ControlPersist = "no";
            };
          }
          // githubSshSettings;
      };

      nix-index-database.comma.enable = true;

      man = {
        package = null;
        generateCaches = false;
      };

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
    xdg = {
      enable = true;
      userDirs.setSessionVariables = false;
      configFile."ghostty/config".text = ''
        command = /run/current-system/sw/bin/zsh
        font-family = Iosevka Term
        font-size = 14
      '';
    };
  };
}
