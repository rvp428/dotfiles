{ lib, pkgs, ... }:

let
  meldBin = lib.getExe pkgs.meld;
in {
  home.packages = [ pkgs.meld ];

  # Sentinel so we can prove HM applied
  home.file.".hm-meld-test".text = "meld-module-loaded";

  programs.git = {
    enable = lib.mkForce true;

    extraConfig = {
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

