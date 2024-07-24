<div align="center">

# 🤖 Enlighten

#### Turn Neovim into an AI code editor

</div>

## 🥖 Features

- Powered by OpenAI's `gpt-4o`.
- Generate code from a prompt.
- Edit selected code in place without leaving the buffer.
- Ask questions in an interactive chat without leaving Neovim.

## 📖 Philosophy

AI code autocompletion is an amazing technical achievement. But I fear it has turned us software developers into tab-completion machines - wait for the next completion, accept, correct, and repeat. AI should be tool that is used deliberately, when needed, to extend our knowledge and ability to solve problems with code. Enlighten is such a tool. Write your own code and use the AI integration when needed, to get through a block, and then shove it aside and continue on your merry way.

## 💾 Setup

`curl` is required.

You will also need to set the environment variable `$OPENAI_API_KEY` with your OpenAI API key. Other AI providers and private models will be supported in the future (just not now).

Installation with [lazy.vim](https://github.com/folke/lazy.nvim)

```lua
{
  "evanmcneely/enlighten.nvim",
  lazy = "BufReadPost",
  config = function()
    require('enlighten'):setup() -- REQUIRED
    vim.keymap.set("v", "<leader>ae", function() require("enlighten"):toggle_prompt() end)
    vim.keymap.set("n", "<leader>ae", function() require("enlighten"):toggle_prompt() end)
    vim.keymap.set("n", "<leader>aE", function() require("enlighten"):focus_prompt() end)
    vim.keymap.set("v", "<leader>ac", function() require("enlighten"):toggle_chat() end)
    vim.keymap.set("n", "<leader>ac", function() require("enlighten"):toggle_chat() end)
    vim.keymap.set("n", "<leader>aC", function() require("enlighten"):focus_chat() end)
  end
}
```

## 📖 Usage

### Generate ✍️

From normal mode, position the cursor where you want code to generate code. Open the prompt and write your instructions. Hit 'Enter' from normal mode to generate a completion in buffer.

### Edit ♻️

Edit: Select the code you want to edit. Open the prompt and write your instructions. Hit 'Enter' from normal mode to edit the selected code in buffer.

### Chat 💬

Chat: Open the chat. Hitting 'Enter' from normal mode submits the prompt. Completions are streamed into the buffer.

## 🌠 Kudos

Shout out to [aduros/ai.vim](https://github.com/aduros/ai.vim) which provided the foundation of this project. The two projects look nothing the same now, but ai.vim made me think this was possible.

Shout out to [ThePrimeagen/harpoon](https://github.com/ThePrimeagen/harpoon/tree/harpoon2) which inspired how this project is laid out.

Shout out to [Cursor](https://www.cursor.com/) the AI Code Editor which [in my opinion] has pioneered AI-Editor integrations and inspired many of the features here and on the roadmap.

## 🏎️ Roadmap

- [ ] Allow cancelling/stopping generation.
- [ ] Prompt: Show a diff of generated text against existing text so a developer can review the modified code and allow approve or decline it.
- [ ] Prompt: Retry completion with another prompt so a developer can iteratively refine the models output before approving.
- [ ] Chat: @use directive to edit buffer with context from the chat.
- [ ] Completion without prompt - just use code context to try and generate code (inserting at the cursor).
- [ ] Add Anthropic as a provider for generating content (abstraction to allow adding more model providers and local models in the future).
- [ ] Prompt and Chat: @ directive for searching code base for functions, classes, etc. to be added to context when generating a completion. Create codebase embeddings.
