<div align="center">

## 🤖 Enlighten

### Turn Neovim into an AI Code Editor

| Edit                                                                                                                                             | Chat                                                                                                                                             |
| ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| <video src="https://github.com/user-attachments/assets/24edff3c-26b2-4830-828b-9cc64e1e19a5" controls autoplay style="max-width: 100%;"></video> | <video src="https://github.com/user-attachments/assets/853bf773-2bf8-4bfe-94e5-8be1e90872c0" controls autoplay style="max-width: 100%;"></video> |

</div>

### 🔦 Philosophy

I like Neovim. I like writing the code. I also like _some_ AI editing features _sometimes_.

This plugin does not strive to implement every feature in AI code editors (such as Cursor). It should have just enough power to get you unblocked or plow through some tedium - without leaving the terminal - so you can get on with your day. It should feel like a native Neovim experience.

See **TODO**'s for a list of things I will eventually get to.

### 🥖 Features

- Generate code from a prompt.
- Edit selected code in place without leaving the buffer.
- Highlight differences in generated or edited code.
- Conversational chat without leaving Neovim.
- Conversation and prompt history.
- OpenAI and Anthropic models are supported.

### 💾 Setup

Must have Neovim 0.10.0+

`curl` is required.

You will also need to set the environment variable `$OPENAI_API_KEY` or `$ANTHROPIC_API_KEY` depending on the AI provider you are using.

Installation with [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
  {
    "evanmcneely/enlighten.nvim",
    event = "VeryLazy",
    opts = {
      -- ...
    },
    keys = {
      { "<leader>ae", function() require("enlighten").edit() end, desc = "Edit", mode = { "n", "v" } },
      { "<leader>ac", function() require("enlighten").chat() end, desc = "Chat", mode = { "n", "v" } },
      { "<leader>ay", function() require("enlighten").keep() end, desc = "Keep change", mode = { "n", "v" } },
      { "<leader>aY", function() require("enlighten").keep_all() end, desc = "Keep all changes", mode = "n" },
      { "<leader>an", function() require("enlighten").discard() end, desc = "Discard change", mode = { "n", "v" } },
      { "<leader>aN", function() require("enlighten").discard_all() end, desc = "Discard all changes", mode = "n" },
    },
  },
```

### ⚙️ Configuration

This is the default configuration.

```lua
  {
    ai = {
      provider = "openai", -- AI provider. Only "openai" or "anthropic" or supported.
      model = "gpt-4o", -- model name for the specified provider. Only chat completion models are supported (plus the o3-mini reasoning model)
      temperature = 0,
      tokens = 4096,
      timeout = 60,
    },
    settings = {
      context = 500 -- lines above and below the selected text passed to the model as context
        -- Can be "diff" or "change" or "off":
        -- - "diff" will show added and removed lines with DiffAdd and DiffRemove highlights
        -- - "change" when a hunk has both added and removed lines, this will show only generated content with DiffText highlights
        -- - "off" will not add highlights around generated content
      diff_mode = "diff"
      edit = {
        width = 80, -- prompt window width
        height = 5, -- prompt window height
        showTitle = true, -- show the title in the prompt window
        showHelp = true, -- show the help footer in the prompt window
        border = "═" -- top/bottom border character of prompt window
      },
      chat = {
        width = 80, -- chat window width
        split = "right", -- split the chat window left or right
      },
    },
  }
```

To customize this configuration, pass overrides into setup: `require('enlighten').setup({...}) `.

#### Using Anthropic as the provider

Example configuration to use Anthropic AI as the completion provider:

```lua
  {
    ai = {
      provider = "anthropic",
      model = "claude-3-5-sonnet-20240620",
    },
  }
```

At the moment, OpenAI's `gpt-4o` model is a fair bit better at generating code that respects the indentation and formatting of existing code in the buffer.

#### Feature specific configuration

You can override the AI configuration for the prompt-completion or chat feature using the following feature specific overrides:

```lua
  {
    ai = {
      edit = {
        timeout = 10, -- set a lower timeout for the prompt feature only
      },
      chat = {
        model = "gpt-3.5-turbo", -- use a different model for the chat feature only
      }
    },
  }
```

These are just examples, all `ai` configurations can be overridden in this way.

### 📖 Usage

#### Prompt completion

Select the code you want to edit (from normal mode, the line under the cursor is considered selected). Open the prompt and write your instructions. The keymaps available to you are:

- `<CR>` - submit the prompt for completion
- `q` - close the prompt window (clears any generated code)
- `<C-y>` - accept the generated code
- `<C-o>` - scroll back through past prompts
- `<C-i>` - scroll forward through past prompts

Generated code is diff'd against the initially selected code and highlighted as green (add) or red (remove) appropriately.

#### Chat

Open the chat window. You can optionally select code from the buffer to have it populate the prompt. The keymaps available to you are:

- `<CR>` - submit the prompt for completion (normal mode)
- `<C-CR>` - submit the prompt for completion (insert mode)
- `<S-C-CR` - AI edit buffer with context from chat
- `q` - close the chat window
- `<C-o>` - scroll back through past chat conversations
- `<C-i>` - scroll forward through past chat conversations
- `<C-x>` - stop the streamed response

Chat responses are streamed into the chat buffer. Chat conversations will only be available for the current Neovim session

### 👍 Kudos

- [aduros/ai.vim](https://github.com/aduros/ai.vim) which provided the foundation of this project. The two projects look nothing the same now, but ai.vim made me think this was possible.

- [Cursor](https://www.cursor.com/) the AI Code Editor which, in my opinion, has pioneered AI-editor integrations and inspired the features here and on the roadmap.

### 🏎️ TODO

- Persist history across Neovim sessions. ✅
- Approve/Reject generated chunks from file. ✅
- Edit buffer with context from the chat.
- Use codebase as context (files, functions, classes, etc.).
