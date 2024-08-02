<div align="center">

## 🤖 Enlighten

#### Turn Neovim into an AI Code Editor

![enlighten-demo](./demo.gif)

</div>

### 🥖 Features

- Powered by OpenAI's `gpt-4o`.
- Generate code from a prompt.
- Edit selected code in place without leaving the buffer.
- Highlight differences in generated or edit code.
- Conversational chat without leaving Neovim.

### 📖 Philosophy

AI code autocompletion is an incredible technical achievement. However, I fear it has turned us into tab-completion machines - waiting for the next completion, accepting, correcting, and repeating. AI should be a tool used deliberately, when needed, to extend our knowledge and ability to solve problems and overcome blocks. Enlighten is such a tool. Write your own code and use the AI integration when needed. Then set it aside and continue on your way.

### 💾 Setup

`curl` is required.

You will also need to set the environment variable `$OPENAI_API_KEY` with your OpenAI API key. Other AI providers and private models will be supported in the future.

Installation with [lazy.vim](https://github.com/folke/lazy.nvim)

```lua
{
  "evanmcneely/enlighten.nvim",
  event = "BufEnter",
  config = function()
    require('enlighten'):setup() -- REQUIRED
    vim.keymap.set("v", "<leader>aa", function() require("enlighten"):toggle_prompt() end)
    vim.keymap.set("n", "<leader>aa", function() require("enlighten"):toggle_prompt() end)
    vim.keymap.set("v", "<leader>ac", function() require("enlighten"):toggle_chat() end)
    vim.keymap.set("n", "<leader>ac", function() require("enlighten"):toggle_chat() end)
    vim.keymap.set("n", "<leader>af", function() require("enlighten"):focus() end)
  end
}
```

### ⚙️ Configuration

This is the default configuration. Pass overrides into setup: `require('enlighten'):setup({...}) `.

```lua
  {
    ai = {
      prompt = {
        provider = "openai", -- doesn't do anything yet
        model = "gpt-4o", -- only OpenAI models are supported
        temperature = 0,
        tokens = 4096,
      },
      chat = {
        provider = "openai",
        model = "gpt-4o",
        temperature = 0,
        tokens = 4096,
      },
      timeout = 60,
    },
    settings = {
      prompt = {
        width = 80, -- prompt window width
        height = 5, -- prompt window height
      },
      chat = {
        width = 80, -- chat window width
        split = "right", -- split the chat window left or right
      },
    },
  }
```

### 📖 Usage

#### Generate

From normal mode, position the cursor where you want to generate code. Open the prompt and write your instructions. Hit 'Enter' from normal mode to generate a completion in buffer. 'C-y' to approve the changes or edit your prompt and hit 'Enter' again to retry.

#### Edit

Edit: Select the code you want to edit. Open the prompt and write your instructions. Hit 'Enter' from normal mode to edit the selected code in buffer. Review the changes and approve them, or edit your prompt and hit 'Enter' again to retry.

#### Chat

Chat: Open the chat. Hitting 'Enter' from normal mode submits the prompt. Responses are streamed into the buffer.

### 👍 Kudos

[aduros/ai.vim](https://github.com/aduros/ai.vim) which provided the foundation of this project. The two projects look nothing the same now, but ai.vim made me think this was possible.

[Cursor](https://www.cursor.com/) the AI Code Editor which, in my opinion, has pioneered AI-editor integrations and inspired the features here and on the roadmap.

### 🏎️ TODO

- Allow cancelling/stopping generation.
- Chat: @use directive to edit buffer with context from the chat.
- Chat: history
- Completion without prompt - just use code context to try and generate code (inserting at the cursor).
- Add Anthropic as a provider for generating content (with an abstraction to allow adding more model providers and local models in the future).
- Prompt and Chat: @ directive for searching codebase for functions, classes, etc. to be added to context when generating a completion. Create codebase embeddings.
