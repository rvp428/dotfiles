{ config, pkgs, ... }:

{
  programs.nixvim = {
    enable = true;

    plugins.treesitter = {
      enable = true;
      package = pkgs.vimPlugins.nvim-treesitter;
      nixGrammars = true;

      settings = {
        highlight = {
          enable = true;
          additional_vim_regex_highlighting = false;
        };
        indent.enable = true;
      };

    };

    extraConfigLua = ''
      require("settings")
    '';

  };

  xdg.configFile."nvim/lua".source = ../nvim/lua;
}
