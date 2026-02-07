{pkgs, ...}: {
  programs.nixvim = {
    enable = true;

    opts = {
      # Allow loading local .nvimrc files (secure=true prevents dangerous commands)
      exrc = true;
      secure = true;
    };

    plugins = {
      treesitter = {
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

      lsp = {
        enable = true;
        servers.nixd.enable = true;
      };

      cmp = {
        enable = true;

        # Basic completion behavior
        settings = {
          mapping = {
            "<CR>" = "cmp.mapping.confirm({ select = true })";
            "<Tab>" = "cmp.mapping.select_next_item()";
            "<S-Tab>" = "cmp.mapping.select_prev_item()";
          };

          sources = [
            {name = "nvim_lsp";}
            {name = "path";}
            {name = "buffer";}
          ];
        };
      };

      conform-nvim = {
        enable = true;

        settings = {
          formatters_by_ft = {
            nix = ["alejandra"];
          };

          format_on_save = {
            lsp_fallback = false;
            timeout_ms = 2000;
          };
        };
      };

      lint = {
        enable = true;
        lintersByFt = {
          nix = ["statix" "deadnix"];
        };
      };
    };

    extraConfigLua = ''
      require("init")
    '';
  };

  xdg.configFile."nvim/lua".source = ../nvim/lua;
}
