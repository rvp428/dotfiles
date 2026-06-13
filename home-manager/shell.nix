{
  config,
  pkgs,
  ...
}: let
  nixFishPlugin = {
    name = "nix.fish";

    src = pkgs.fetchFromGitHub {
      owner = "kidonng";
      repo = "nix.fish";
      rev = "ad57d970841ae4a24521b5b1a68121cf385ba71e";
      sha256 = "13x3bfif906nszf4mgsqxfshnjcn6qm4qw1gv7nw89wi4cdp9i8q";
    };
  };
in {
  home.file = {
    ".config/fish" = {
      source = ../fish;
      recursive = true;
    };
  };

  programs = {
    fish = {
      enable = true;

      plugins = [
        nixFishPlugin
      ];
    };

    bash.enable = true;

    zsh = {
      enable = true;
      dotDir = "${config.xdg.configHome}/zsh";
      autosuggestion.enable = true;
      shellAliases = {
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";

        ga = "git add";
        gaa = "git add --all";
        gc = "git commit";
        gca = "git commit --amend";
        gcm = "git commit -m";
        gcn = "git commit -n";
        gcp = "git cherry-pick";
        gb = "git branch";
        gbd = "git branch -d";
        gbr = "git branch -r";
        gd = "git diff";
        gds = "git diff --staged";
        gf = "git fetch";
        gl = "git log -n 10";
        glo = "git log --oneline --graph --decorate";
        gp = "git push";
        gpf = "git push --force-with-lease";
        gpu = "git push -u origin HEAD";
        gpr = "git pull --rebase";
        gra = "git rebase --abort";
        grc = "git rebase --continue";
        grom = "git rebase origin/main";
        gromi = "git rebase origin/main -i";
        gsh = "git show";
        gst = "git status";
        gsw = "git switch";
        gswc = "git switch -c";

        d = "docker";
        db = "docker build .";
        dr = "docker run -it --rm";
        dps = "docker ps";
        dpsa = "docker ps -a";
        dimg = "docker images";
        drm = "docker rm";
        drmi = "docker rmi";
        dex = "docker exec -it";
        dlogs = "docker logs -f";
        dstop = "docker stop";
        dprune = "docker system prune -af";

        dc = "docker compose";
        dcu = "docker compose up -d";
        dcb = "docker compose build";
        dcd = "docker compose down";
        dcr = "docker compose run";
        dcl = "docker compose logs -f";
      };
      initContent = builtins.readFile ../zsh/init.zsh;
    };
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
