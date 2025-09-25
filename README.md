# vimtex-spell-diagnostics
Show VimTeX spell checking errors as Neovim diagnostics. 
(I got annoyed with other alternatives flagging commands as mispellings)



## Features

- Converts VimTeX spell checking into Neovim diagnostics 
- Respects the syntax-aware spell checking regions VimTex provides (for the most part, this is still WIP)
- Configurable severity levels for different spelling error types
- Configurable debounce to updates for performance


## Requirements
- [VimTeX](https://github.com/lervag/vimtex) plugin
- `spell` option enabled (`:set spell`)


## Installation

lazy.nvim:
```lua
{
  "sparkylc2/vimtex-spell-diagnostics.nvim",
  ft = "tex",
  dependencies = { "lervag/vimtex" },
  config = function()
    require("vimtex-spell-diagnostics").setup()
  end,
}
```

packer.nvim:
```lua
use {
  "yourusername/vimtex-spell-diagnostics.nvim",
  ft = { "tex" },
  requires = { "lervag/vimtex" },
  config = function()
    require("vimtex-spell-diagnostics").setup()
  end,
}
```

## Configuration
```lua
require("vimtex-spell-diagnostics").setup({
  enabled = true,
  severity = {
    bad = vim.diagnostic.severity.ERROR,    -- misspelled words
    caps = vim.diagnostic.severity.WARN,    -- capitalization errors
    rare = vim.diagnostic.severity.HINT,    -- rare words
    loc = vim.diagnostic.severity.INFO,     -- local/regional spellings
  },
  debounce_time = 500,  -- ms to wait before updating diagnostics
  check_on = {          -- events that trigger spell checking
    "BufReadPost",
    "BufWritePost", 
    "TextChanged",
    "InsertLeave"
  },
})
```

## Commands
- `:VimtexSpellEnable`- Enable spell diagnostics
- `:VimtexSpellDisable` - Disable spell diagnostics
- `:VimtexSpellToggle`- Toggle spell diagnostics
- `:VimtexSpellRefresh` - Manually refresh current buffer
