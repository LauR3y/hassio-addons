# Aider AI Coding Assistant

AI pair programming in your terminal - edit your Home Assistant configuration with Claude, GPT-4, DeepSeek, and other LLMs.

## About

[Aider](https://aider.chat) is an AI-powered coding assistant that works directly in your terminal. This add-on integrates Aider with Home Assistant, allowing you to use AI to help edit your configuration files, automations, and scripts.

## Features

- **Web Terminal**: Access Aider through your browser via Home Assistant's UI
- **Multiple LLM Providers**: Support for OpenAI, Anthropic (Claude), DeepSeek, Google, and OpenRouter
- **Git Integration**: Automatic git initialization and commit tracking of changes
- **Direct Config Access**: Edit your Home Assistant configuration files directly

## Installation

1. Add this repository to your Home Assistant Add-on Store
2. Install the "Aider AI Coding Assistant" add-on
3. Configure at least one API key in the add-on settings
4. Start the add-on
5. Click "Open Web UI" to access the Aider terminal

## Configuration

| Option | Description |
|--------|-------------|
| `openai_api_key` | OpenAI API key (for GPT-4, etc.) |
| `anthropic_api_key` | Anthropic API key (for Claude) |
| `deepseek_api_key` | DeepSeek API key |
| `google_api_key` | Google API key (for Gemini) |
| `openrouter_api_key` | OpenRouter API key |
| `default_model` | Default model to use (e.g., `sonnet`, `gpt-4o`, `deepseek`) |
| `auto_commits` | Automatically commit changes made by Aider |
| `git_user_name` | Git user name for commits |
| `git_user_email` | Git email for commits |
| `init_git` | Initialize git repository in /config if not present |
| `extra_args` | Additional command-line arguments for Aider |

## Usage

Once started, you'll have access to a web terminal running Aider. You can:

- Ask Aider to modify your configuration files
- Request help writing automations and scripts
- Get explanations of existing code
- Refactor and improve your YAML configurations

### Example Commands

```
# Add a new automation
/add automations.yaml
Can you create an automation that turns on the lights at sunset?

# Explain existing code
/add scripts.yaml
Explain what the morning_routine script does

# Refactor configuration
/add configuration.yaml
Help me organize my configuration into packages
```

## Supported Models

Aider works best with:
- **Claude 3.5 Sonnet** (`sonnet`) - Recommended
- **GPT-4o** (`gpt-4o`)
- **DeepSeek Chat V3** (`deepseek`)
- **GPT-4 Turbo** (`gpt-4-turbo`)

See [Aider's model documentation](https://aider.chat/docs/llms.html) for a full list.

## Security Notes

- API keys are stored in Home Assistant's add-on configuration
- Keys are only passed as environment variables at runtime
- The default `.gitignore` excludes `secrets.yaml` and other sensitive files
- Access is protected by Home Assistant authentication

## Links

- [Aider Documentation](https://aider.chat/docs/)
- [Aider GitHub](https://github.com/paul-gauthier/aider)
- [Report Issues](https://github.com/LauR3y/hassio-addons/issues)
