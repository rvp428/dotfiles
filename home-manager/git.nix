{
  lib,
  pkgs,
  ...
}: let
  meldBin = lib.getExe pkgs.meld;
in {
  home.packages = [pkgs.meld];

  programs.git = {
    enable = lib.mkForce true;

    settings = {
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

        # Pin exact binary + command so PATH doesn’t matter
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
}
