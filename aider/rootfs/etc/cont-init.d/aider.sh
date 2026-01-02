#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Add-on: Aider AI Coding Assistant
# Initializes Aider configuration and git repository
# ==============================================================================

bashio::log.info "Initializing Aider..."

# Initialize git in /config if requested and not present
if bashio::config.true 'init_git' && [ ! -d "/config/.git" ]; then
    bashio::log.info "Initializing git repository in /config..."
    cd /config
    git init
    git config user.name "$(bashio::config 'git_user_name')"
    git config user.email "$(bashio::config 'git_user_email')"

    # Create .gitignore for Home Assistant
    cat > .gitignore << 'EOF'
# Secrets and credentials
secrets.yaml
*.pem
*.key

# Home Assistant specific
.storage/
home-assistant_v2.db
home-assistant_v2.db-shm
home-assistant_v2.db-wal
.cloud/

# Python
__pycache__/

# Aider
.aider*
EOF

    git add -A
    git commit -m "Initial commit by Aider add-on" || true
    bashio::log.info "Git repository initialized"
elif [ -d "/config/.git" ]; then
    bashio::log.info "Git repository already exists in /config"
    cd /config
    git config user.name "$(bashio::config 'git_user_name')"
    git config user.email "$(bashio::config 'git_user_email')"
fi

bashio::log.info "Aider initialization complete"
