# home.nix
{ config, pkgs, ... }:

{
  xdg.configFile."pypoetry/config.toml".text = ''
    [virtualenvs]
    create = true
    use-poetry-python = true
    in-project = true
  '';

  home.sessionVariables = {
    POETRY_CONFIG_DIR = "${config.xdg.configHome}/pypoetry";
  };

  # Unfortunately this wants to write to the "Application Support" directory and
  # .config/pypoetry is more clear
  #  programs.poetry = {
  #    enable = true;
  #
  #    # This writes to ~/.config/pypoetry/config.toml
  #    settings = {
  #      virtualenvs.create = false;               # use current env (e.g., Nix devshell)
  #      virtualenvs.prefer-active-python = true;  # stick to the active python
  #      virtualenvs.in-project = false;           # (ignored when create=false)
  #    };
  #  };
}

