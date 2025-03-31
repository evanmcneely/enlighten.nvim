local config = require("enlighten.config")

local equals = assert.are.same

describe("config", function()
  local want

  before_each(function()
    -- This is the expected default base configuration after it gets built
    want = {
      ai = {
        provider = "openai",
        model = "gpt-4o",
        temperature = 0,
        tokens = 4096,
        timeout = 60,
        edit = {
          provider = "openai",
          model = "gpt-4o",
          temperature = 0,
          tokens = 4096,
          timeout = 60,
        },
        chat = {
          provider = "openai",
          model = "gpt-4o",
          temperature = 0,
          tokens = 4096,
          timeout = 60,
        },
      },
      settings = {
        diff_mode = "diff",
        context = 500,
        edit = {
          width = 80,
          height = 5,
          showTitle = true,
          showHelp = true,
          border = "═",
          diff_mode = "diff",
          context = 500,
        },
        chat = {
          width = 80,
          split = "right",
          diff_mode = "diff",
          context = 500,
        },
      },
    } ---@type EnlightenConfig
  end)

  it("should return default config when no partial is provided", function()
    local got = config.build_config()
    equals(want, got)
  end)

  it("should update both edit and chat config from ai config", function()
    -- When all of the base AI configuration values are overridden
    local ai = {
      provider = "anthropic",
      model = "something",
      temperature = 1,
      tokens = 100000,
      timeout = 70,
    }

    -- Expect the AI configuration above to be set at all levels in the config
    want.ai = {
      provider = ai.provider,
      model = ai.model,
      temperature = ai.temperature,
      tokens = ai.tokens,
      timeout = ai.timeout,
      edit = ai,
      chat = ai,
    }

    local got = config.build_config({
      ai = ai,
    })
    equals(want, got)
  end)

  it("should update both edit and chat config from base settings config", function()
    -- When the base Settings configuration values are overridden
    local settings = {
      context = 1,
      diff_mode = "change",
    }

    -- Expect the Settings config above to be set at all levels
    want.settings = {
      context = settings.context,
      diff_mode = settings.diff_mode,
      edit = vim.tbl_deep_extend("force", want.settings.edit, settings),
      chat = vim.tbl_deep_extend("force", want.settings.chat, settings),
    }

    local got = config.build_config({
      settings = settings,
    })
    equals(want, got)
  end)

  it("should override base ai config with edit and chat values", function()
    -- When the AI edit and chat configuration values have been overridden
    local ai_edit = {
      provider = "anthropic",
      model = "wawawa",
      temperature = 0.5,
      tokens = 1000,
      timeout = 10,
    }
    local ai_chat = {
      provider = "anthropic",
      model = "banana",
      temperature = 0.2,
      tokens = 5000,
      timeout = 30,
    }

    -- Expect the chat and edit configurations to be set with the above values
    want.ai.edit = ai_edit
    want.ai.chat = ai_chat

    local got = config.build_config({
      ai = {
        edit = ai_edit,
        chat = ai_chat,
      },
    })
    equals(want, got)
  end)

  it("should override base settings config with edit and chat values", function()
    -- When the Settings edit and chat configuration values have been overridden
    local settings_edit = {
      context = 2,
      diff_mode = "change",
      width = 100,
      height = 3,
      showTitle = false,
      showHelp = false,
      border = "",
    }
    local settings_chat = {
      context = 1000,
      diff_mode = "change",
      width = 110,
      split = "left",
    }

    -- Expect chat and edit configurations to be set with above values
    want.settings.edit = vim.tbl_deep_extend("force", want.settings.edit, settings_edit)
    want.settings.chat = vim.tbl_deep_extend("force", want.settings.chat, settings_chat)

    local got = config.build_config({
      settings = {
        edit = settings_edit,
        chat = settings_chat,
      },
    })
    equals(want, got)
  end)

  it("should override providers that are invalid", function()
    local got = config.build_config({
      ai = {
        edit = { provider = "invalid" },
        chat = { provider = "invalid" },
      },
    })
    equals(want, got)
  end)
end)
