#!/bin/bash
# Home Assistant Add-on: Aider AI Coding Assistant
# Simple init script for non-s6 container

set -e

CONFIG_PATH=/data/options.json

echo "[INFO] Initializing Aider..."

# Read configuration from Home Assistant options
if [ -f "$CONFIG_PATH" ]; then
    OPENAI_KEY=$(jq -r '.openai_api_key // empty' "$CONFIG_PATH")
    ANTHROPIC_KEY=$(jq -r '.anthropic_api_key // empty' "$CONFIG_PATH")
    DEEPSEEK_KEY=$(jq -r '.deepseek_api_key // empty' "$CONFIG_PATH")
    GOOGLE_KEY=$(jq -r '.google_api_key // empty' "$CONFIG_PATH")
    OPENROUTER_KEY=$(jq -r '.openrouter_api_key // empty' "$CONFIG_PATH")
    MODEL=$(jq -r '.default_model // "sonnet"' "$CONFIG_PATH")
    AUTO_COMMITS=$(jq -r '.auto_commits // true' "$CONFIG_PATH")
    EXTRA_ARGS=$(jq -r '.extra_args // empty' "$CONFIG_PATH")
    INIT_GIT=$(jq -r '.init_git // true' "$CONFIG_PATH")
    GIT_USER=$(jq -r '.git_user_name // "Aider"' "$CONFIG_PATH")
    GIT_EMAIL=$(jq -r '.git_user_email // "aider@homeassistant.local"' "$CONFIG_PATH")

    [ -n "$OPENAI_KEY" ] && export OPENAI_API_KEY="$OPENAI_KEY" && echo "[INFO] OpenAI API key configured"
    [ -n "$ANTHROPIC_KEY" ] && export ANTHROPIC_API_KEY="$ANTHROPIC_KEY" && echo "[INFO] Anthropic API key configured"
    [ -n "$DEEPSEEK_KEY" ] && export DEEPSEEK_API_KEY="$DEEPSEEK_KEY" && echo "[INFO] DeepSeek API key configured"
    [ -n "$GOOGLE_KEY" ] && export GEMINI_API_KEY="$GOOGLE_KEY" && echo "[INFO] Google API key configured"
    [ -n "$OPENROUTER_KEY" ] && export OPENROUTER_API_KEY="$OPENROUTER_KEY" && echo "[INFO] OpenRouter API key configured"
else
    echo "[WARN] No config file found at $CONFIG_PATH, using defaults"
    MODEL="${MODEL:-sonnet}"
    AUTO_COMMITS="${AUTO_COMMITS:-true}"
fi

# Initialize git if requested
if [ "$INIT_GIT" = "true" ] && [ ! -d "/config/.git" ]; then
    echo "[INFO] Initializing git repository..."
    cd /config
    git init
    git config user.name "${GIT_USER:-Aider}"
    git config user.email "${GIT_EMAIL:-aider@homeassistant.local}"
    cat > .gitignore << 'EOF'
secrets.yaml
*.pem
*.key
.storage/
home-assistant_v2.db*
.cloud/
__pycache__/
.aider*
EOF
    git add -A
    git commit -m "Initial commit by Aider add-on" || true
fi

# Build aider command
AIDER_CMD="aider --model ${MODEL:-sonnet}"
[ "$AUTO_COMMITS" = "true" ] && AIDER_CMD="$AIDER_CMD --auto-commits" || AIDER_CMD="$AIDER_CMD --no-auto-commits"
[ -n "$EXTRA_ARGS" ] && AIDER_CMD="$AIDER_CMD $EXTRA_ARGS"

echo "[INFO] Starting ttyd with aider..."
echo "[INFO] Model: ${MODEL:-sonnet}"

# Get interface and port from supervisor or use defaults
INTERFACE="${SUPERVISOR_INTERFACE:-0.0.0.0}"
PORT="${SUPERVISOR_PORT:-7681}"

# Create a script to manage tmux sessions
cat > /tmp/aider-tmux.sh << TMUXEOF
#!/bin/bash
cd /config

# If no tmux session exists, create one with first aider
if ! tmux has-session -t aider 2>/dev/null; then
    exec tmux new-session -s aider "$AIDER_CMD"
fi

# Session exists - create new window with another aider agent
WINDOW_NUM=\$(tmux list-windows -t aider | wc -l)
tmux new-window -t aider -n "aider-\$WINDOW_NUM" "$AIDER_CMD"
exec tmux attach-session -t aider
TMUXEOF
chmod +x /tmp/aider-tmux.sh

echo "[INFO] Tmux shortcuts:"
echo "[INFO]   Ctrl+B, N - next agent window"
echo "[INFO]   Ctrl+B, P - previous agent window"
echo "[INFO]   Ctrl+B, 0-9 - switch to window by number"
echo "[INFO]   Ctrl+B, D - detach (keeps agents running)"

exec ttyd -i "$INTERFACE" -p "$PORT" -W \
    -t "titleFixed=Aider - AI Coding Assistant" \
    -t "reconnect=3" \
    /tmp/aider-tmux.sh
