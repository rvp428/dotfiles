{ lib, pkgs, ... }:

let
  meldBin = lib.getExe pkgs.meld;
in {
  home.packages = [ pkgs.meld ];

  programs.git = {
    enable = lib.mkForce true;

    aliases = {
      cp = "cherry-pick";
      cpc = "cherry-pick --continue";
      cpa = "cherry-pick --abort";
    };

    extraConfig = {
      pull.rebase = true;
      init.defaultBranch = "main";
      
      merge.tool = "meld";
      mergetool.keepBackup = false;
      mergetool.prompt = false;

      # Pin exact binary + command so PATH doesn’t matter
      mergetool."meld" = {
        path = meldBin;
        useAutoMerge = true;
        trustExitCode = true;
        cmd = ''"${meldBin}" --auto-merge --output "$MERGED" "$LOCAL" "$BASE" "$REMOTE"'';
      };

      diff.tool = "meld";
      difftool.prompt = false;
      difftool."meld".cmd = ''"${meldBin}" "$LOCAL" "$REMOTE"'';
    };

    aliases.meld = "difftool -t meld -y";
  };
}

