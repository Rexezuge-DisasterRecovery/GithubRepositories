#!/bin/bash
set -euo pipefail

# Single-run mode: no volume mounts required.
# Flow for no-arg invocation: setup_ssh -> ensure_gh_auth -> run ExportToS3.sh
# Ephemeral SSH keys generated in-container are uploaded via `gh ssh-key add`
# and deleted on exit so GitHub doesn't accumulate deploy keys.

EPHEMERAL_KEY=0
UPLOADED_KEY_TITLE=""

cleanup() {
    local exit_code=$?
    set +e
    if [[ -n "$UPLOADED_KEY_TITLE" ]]; then
        echo "Removing ephemeral SSH key from GitHub account: $UPLOADED_KEY_TITLE"
        # Prefer deleting by key ID (titles can collide); fall back to title.
        local key_id=""
        key_id=$(gh ssh-key list --json id,title -q ".[] | select(.title == \"$UPLOADED_KEY_TITLE\") | .id" 2>/dev/null || true)
        if [[ -n "$key_id" ]]; then
            gh ssh-key delete "$key_id" --yes 2>/dev/null || \
                gh ssh-key delete "$UPLOADED_KEY_TITLE" --yes 2>/dev/null || true
        else
            gh ssh-key delete "$UPLOADED_KEY_TITLE" --yes 2>/dev/null || true
        fi
    fi
    rm -rf ~/.ssh
    exit "$exit_code"
}
trap cleanup EXIT

setup_ssh() {
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    # Legacy path: import user-mounted keys if present (optional, no longer required).
    if [[ -d ~/.ssh.d ]]; then
        echo "Importing SSH keys from ~/.ssh.d ..."
        cp -a ~/.ssh.d/. ~/.ssh/
        chmod 700 ~/.ssh
        chmod 600 ~/.ssh/id_* 2>/dev/null || true
        chmod 644 ~/.ssh/*.pub 2>/dev/null || true
    fi

    # Fix permissions on any pre-existing keys.
    chmod 600 ~/.ssh/id_ed25519 ~/.ssh/id_ecdsa ~/.ssh/id_rsa 2>/dev/null || true

    # Generate an ephemeral key when nothing usable exists.
    if [[ ! -f ~/.ssh/id_ed25519 && ! -f ~/.ssh/id_ecdsa && ! -f ~/.ssh/id_rsa ]]; then
        echo "No SSH key found. Generating ephemeral ed25519 key..."
        ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 -C "githubrepositories-backup-ephemeral"
        chmod 600 ~/.ssh/id_ed25519
        chmod 644 ~/.ssh/id_ed25519.pub
        EPHEMERAL_KEY=1
    else
        EPHEMERAL_KEY=0
    fi
}

maybe_upload_ephemeral_key() {
    if [[ "$EPHEMERAL_KEY" != "1" ]]; then
        return 0
    fi
    if [[ -n "$UPLOADED_KEY_TITLE" ]]; then
        return 0
    fi
    local host_id
    host_id=$(cat /etc/hostname 2>/dev/null || echo "container")
    local title="githubrepositories-${host_id}-$(date +%s)"
    echo "Uploading ephemeral SSH public key to GitHub account (title: $title)..."
    gh ssh-key add ~/.ssh/id_ed25519.pub --title "$title"
    UPLOADED_KEY_TITLE="$title"
    echo "Ephemeral key uploaded. It will be removed automatically on exit."
}

ensure_gh_auth() {
    if gh auth status >/dev/null 2>&1; then
        echo "GitHub CLI already authenticated."
        maybe_upload_ephemeral_key
        return 0
    fi

    local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    if [[ -n "$token" ]]; then
        echo "Authenticating GitHub CLI with token from environment (non-interactive)..."
        echo "$token" | gh auth login --with-token -h github.com
        gh config set -h github.com git_protocol ssh >/dev/null 2>&1 || true
        echo "GitHub authentication completed (token)."
    else
        echo "Starting GitHub CLI login process..."
        echo "You may need to complete device authentication in the browser."
        gh auth login
        echo "GitHub authentication completed."
    fi

    maybe_upload_ephemeral_key
}

COMMAND=${1:-""}

echo "Container started with command: ${COMMAND:-<empty>}"

case "$COMMAND" in
  login)
    setup_ssh
    # Manual login-only (legacy). Reuses token if provided, else interactive.
    if gh auth status >/dev/null 2>&1; then
        echo "GitHub CLI already authenticated."
        maybe_upload_ephemeral_key
    elif [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
        ensure_gh_auth
    else
        echo "Starting GitHub CLI login process..."
        echo "You may need to complete device authentication in the browser."
        gh auth login
        echo "GitHub authentication completed."
        maybe_upload_ephemeral_key
    fi
    ;;

  "")
    echo "No command provided. Running single-run backup (auth + export)..."
    setup_ssh
    ensure_gh_auth
    # NOTE: intentionally NOT exec'd so the EXIT trap can remove the
    # ephemeral SSH public key from the GitHub account afterwards.
    /ExportToS3.sh
    ;;

  *)
    echo "ERROR: Unknown command '$COMMAND'"
    echo "Supported commands:"
    echo "  login   - Authenticate GitHub CLI (manual, legacy)"
    echo "  <empty> - Single-run: auto-auth (token or interactive) + backup"
    exit 1
    ;;
esac
