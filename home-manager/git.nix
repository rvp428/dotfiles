{
  config,
  lib,
  pkgs,
  ...
}: let
  meldBin = lib.getExe pkgs.meld;
  identity = config.dotfiles.identity;
in {
  options.dotfiles.identity = lib.mkOption {
    type = lib.types.submodule {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "Commit author name shared by Git and Jujutsu.";
        };
        email = lib.mkOption {
          type = lib.types.str;
          description = "Commit author email shared by Git and Jujutsu.";
        };
      };
    };
    description = "Commit identity shared by Git-compatible version control tools.";
  };

  config = {
    home.packages = with pkgs; [
      delta
      meld
    ];

    programs.jujutsu = {
      enable = true;
      settings.user = identity;
    };

    programs.git = {
      enable = lib.mkForce true;

      settings = {
        user = identity;

        alias = {
          cp = "cherry-pick";
          cpc = "cherry-pick --continue";
          cpa = "cherry-pick --abort";

          rb = "rebase";
          rbc = "rebase --continue";
          rba = "rebase --abort";
          meld = "difftool -t meld -y";
        };

        core.pager = "delta";
        interactive.diffFilter = "delta --color-only";
        pull.rebase = true;
        init.defaultBranch = "main";

        merge.tool = "meld";
        mergetool = {
          keepBackup = false;
          prompt = false;

          # Pin exact binary + command so PATH doesn't matter
          "meld" = {
            path = meldBin;
            useAutoMerge = true;
            trustExitCode = true;
            cmd = ''"${meldBin}" --auto-merge --output "$MERGED" "$LOCAL" "$BASE" "$REMOTE"'';
          };
        };

        diff.tool = "meld";
        diff.colorMoved = "default";

        difftool.prompt = false;
        difftool."meld".cmd = ''"${meldBin}" "$LOCAL" "$REMOTE"'';
        delta = {
          navigate = true;
          side-by-side = false;
          line-numbers = true;
          hyperlinks = true;
          keep-plus-minus-markers = false;

          syntax-theme = "Dracula";
          plus-style = "syntax auto";
          minus-style = "syntax auto";
          file-style = "bold yellow";
          hunk-header-style = "syntax bold";
          conflict-style = "diff3";
        };

        pager.pager = "less -FRSX";
      };
    };
  };
}
