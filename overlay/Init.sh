#!/bin/bash
set -euo pipefail

# Single-run mode: no volume mounts required.
# Flow for no-arg invocation: ensure_ssh_dir -> ensure_gh_auth -> generate -> upload -> ExportToS3.sh
# Auth runs BEFORE key generation so `gh auth login` never sees an ephemeral
# key to offer to upload as "GitHub CLI" (avoids HTTP 422 double-upload).
# Ephemeral SSH keys generated in-container are uploaded via `gh ssh-key add`
# and deleted on exit so GitHub doesn't accumulate deploy keys.
# Adopted pre-existing keys (e.g. "GitHub CLI") are reused with a warning and
# NEVER deleted on exit.

EPHEMERAL_KEY=0
UPLOADED_KEY_TITLE=""
ADOPTED_KEY_TITLE=""

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
    elif [[ -n "$ADOPTED_KEY_TITLE" ]]; then
        echo "Preserving adopted pre-existing SSH key '$ADOPTED_KEY_TITLE' (not deleting)."
    fi
    rm -rf ~/.ssh
    exit "$exit_code"
}
trap cleanup EXIT

ensure_ssh_dir() {
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
}

generate_ephemeral_if_missing() {
    # Generate an ephemeral key when nothing usable exists.
    # Must run AFTER gh auth so interactive `gh auth login` never offers to
    # upload this key itself (the old setup_ssh -> login order caused 422).
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

setup_ssh() {
    # Backwards-compatible wrapper (old order). New code calls
    # ensure_ssh_dir -> ensure_gh_auth -> generate_ephemeral_if_missing.
    ensure_ssh_dir
    generate_ephemeral_if_missing
}

gh_login_interactive() {
    # Interactive device/browser flow.
    # With the new auth-before-keygen order there is normally no key on disk
    # yet, so `gh auth login` has nothing to offer to upload. Still pass
    # --skip-ssh-key when supported and let maybe_upload_ephemeral_key() do
    # the single controlled upload afterwards.
    local gh_ver=""
    gh_ver=$(gh --version 2>/dev/null | head -n1 || echo "gh version unknown")
    echo "GitHub CLI version: $gh_ver"
    if gh auth login --help 2>/dev/null | grep -q -- "--skip-ssh-key"; then
        echo "Using 'gh auth login --skip-ssh-key' (single controlled upload later)."
        gh auth login -p ssh --skip-ssh-key
    else
        echo "WARNING: this gh build lacks --skip-ssh-key; relying on auth-before-keygen order to avoid double upload."
        gh auth login
    fi
    # Backup clones via sshUrl, so force SSH regardless of what was picked.
    gh config set -h github.com git_protocol ssh >/dev/null 2>&1 || true
}

find_existing_key_by_body() {
    # $1 = local key body (base64 part). Prints "<id><TAB><title>" or nothing.
    local key_body="$1"
    local keys_json=""
    keys_json=$(gh ssh-key list --json id,title,key 2>/dev/null || true)
    if [[ -z "$keys_json" ]]; then
        return 0
    fi
    if command -v jq >/dev/null 2>&1; then
        echo "$keys_json" | jq -r --arg k "$key_body" '.[] | select(.key | contains($k)) | "\(.id)\t\(.title)"' 2>/dev/null | head -n1 || true
    else
        # Fallback without jq: gh's builtin query language.
        gh ssh-key list --json id,title,key -q ".[] | select(.key | contains(\"$key_body\")) | \"\(.id)\t\(.title)\"" 2>/dev/null | head -n1 || true
    fi
}

maybe_upload_ephemeral_key() {
    if [[ "$EPHEMERAL_KEY" != "1" ]]; then
        return 0
    fi
    if [[ -n "$UPLOADED_KEY_TITLE" || -n "$ADOPTED_KEY_TITLE" ]]; then
        return 0
    fi
    local pubkey_file="$HOME/.ssh/id_ed25519.pub"
    if [[ ! -f "$pubkey_file" ]]; then
        echo "WARNING: ephemeral key flag set but $pubkey_file not found, skipping upload." >&2
        return 0
    fi
    # If the same key material is already on the account (e.g. `gh auth login`
    # uploaded it as "GitHub CLI"), adopt it with a warning instead of
    # failing with HTTP 422. Adopted keys are NEVER deleted on exit.
    local local_key_body=""
    local_key_body=$(awk '{print $2}' "$pubkey_file" 2>/dev/null || true)
    if [[ -n "$local_key_body" ]]; then
        local existing=""
        existing=$(find_existing_key_by_body "$local_key_body" || true)
        if [[ -n "$existing" ]]; then
            local existing_title=""
            existing_title=$(printf '%s' "$existing" | cut -f2-)
            if [[ -n "$existing_title" && "$existing_title" != "null" ]]; then
                echo "WARNING: ephemeral SSH public key already exists on GitHub account as '$existing_title'. Reusing it; it will NOT be deleted on exit."
                ADOPTED_KEY_TITLE="$existing_title"
                return 0
            fi
        fi
    fi
    local host_id
    host_id=$(cat /etc/hostname 2>/dev/null || echo "container")
    local title="githubrepositories-${host_id}-$(date +%s)"
    echo "Uploading ephemeral SSH public key to GitHub account (title: $title)..."
    local add_output=""
    if add_output=$(gh ssh-key add "$pubkey_file" --title "$title" 2>&1); then
        UPLOADED_KEY_TITLE="$title"
        echo "Ephemeral key uploaded. It will be removed automatically on exit."
        return 0
    fi
    echo "$add_output" >&2
    # Proceed + warn on duplicate-key race: adopt if possible, otherwise still
    # proceed since SSH will typically work via the already-uploaded key
    # (e.g. "GitHub CLI"). Only hard-fail on genuine non-duplicate errors.
    if printf '%s' "$add_output" | grep -qiE "already in use|Validation Failed|already exists"; then
        local retry=""
        retry=$(find_existing_key_by_body "$local_key_body" || true)
        if [[ -n "$retry" ]]; then
            local retry_title=""
            retry_title=$(printf '%s' "$retry" | cut -f2-)
            if [[ -n "$retry_title" && "$retry_title" != "null" ]]; then
                echo "WARNING: key material already on account as '$retry_title'. Reusing it; it will NOT be deleted on exit. Proceeding with backup."
                ADOPTED_KEY_TITLE="$retry_title"
                return 0
            fi
        fi
        echo "WARNING: key already in use on GitHub account but could not confirm via 'gh ssh-key list' (possible scope/API lag). Proceeding with backup via existing key; nothing will be deleted on exit." >&2
        ADOPTED_KEY_TITLE="unknown-duplicate"
        return 0
    fi
    echo "ERROR: failed to upload ephemeral SSH key." >&2
    return 1
}

ensure_gh_auth() {
    # Authenticate only. Callers run generate_ephemeral_if_missing +
    # maybe_upload_ephemeral_key afterwards (auth-before-keygen order).
    if gh auth status >/dev/null 2>&1; then
        echo "GitHub CLI already authenticated."
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
        gh_login_interactive
        echo "GitHub authentication completed."
    fi
}

COMMAND=${1:-""}

GIT_SHA_RAW="${GIT_SHA:-$(cat /GIT_SHA 2>/dev/null || echo unknown)}"
GIT_SHA_RAW="$(printf '%s' "$GIT_SHA_RAW" | tr -d '[:space:]')"
if [[ -z "$GIT_SHA_RAW" ]]; then
    GIT_SHA_RAW="unknown"
fi
if [[ "$GIT_SHA_RAW" == "unknown" ]]; then
    GIT_SHA_SHORT="unknown"
else
    GIT_SHA_SHORT="$(printf '%s' "$GIT_SHA_RAW" | cut -c1-7)"
fi
echo "Image commit: $GIT_SHA_SHORT"

echo "Container started with command: ${COMMAND:-<empty>}"

case "$COMMAND" in
  login)
    ensure_ssh_dir
    # Manual login-only (legacy). Reuses token if provided, else interactive.
    # Auth first so `gh auth login` never sees the ephemeral key.
    if gh auth status >/dev/null 2>&1; then
        echo "GitHub CLI already authenticated."
    elif [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
        ensure_gh_auth
    else
        echo "Starting GitHub CLI login process..."
        echo "You may need to complete device authentication in the browser."
        gh_login_interactive
        echo "GitHub authentication completed."
    fi
    generate_ephemeral_if_missing
    maybe_upload_ephemeral_key
    ;;

  "")
    echo "No command provided. Running single-run backup (auth + export)..."
    ensure_ssh_dir
    ensure_gh_auth
    generate_ephemeral_if_missing
    maybe_upload_ephemeral_key
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
