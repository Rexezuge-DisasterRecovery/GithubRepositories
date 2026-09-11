## Usage (single run, recommended)

No volume mounts required. The container auto-authenticates, generates an
ephemeral SSH key, uploads its public half to your GitHub account, runs the
backup, then deletes the public key on exit.

Required token scopes (classic PAT): `repo`, `read:org`, `admin:public_key`.
Fine-grained PAT: repository read + organization read + public key read/write
for the account that owns the key.

### Single run with token (non-interactive, CI/cron)

```bash
docker run --rm \
  -e GH_TOKEN="$GH_TOKEN" \
  -e GITHUB_ORGS="org1 org2" \
  -e S3_BUCKET="my-backup-bucket" \
  -e AWS_ACCESS_KEY_ID=xxx \
  -e AWS_SECRET_ACCESS_KEY=xxx \
  -e AWS_DEFAULT_REGION=us-east-1 \
  -e PASSPHRASE="YOUR_ENCRYPTION_PASSWORD" \
  rexezugedisasterrecovery/githubrepositories
```

`GITHUB_TOKEN` works as an alias for `GH_TOKEN`.

### Single run without token (interactive)

```bash
docker run -it --rm \
  -e GITHUB_ORGS="org1 org2" \
  -e S3_BUCKET="my-backup-bucket" \
  -e AWS_ACCESS_KEY_ID=xxx \
  -e AWS_SECRET_ACCESS_KEY=xxx \
  -e AWS_DEFAULT_REGION=us-east-1 \
  -e PASSPHRASE="YOUR_ENCRYPTION_PASSWORD" \
  rexezugedisasterrecovery/githubrepositories
```

You will be guided through the `gh auth login` device flow once, then the
backup starts immediately in the same container.

Ephemeral key notes:

- Title format: `githubrepositories-<hostname>-<unix-timestamp>`.
- Deleted automatically via `gh ssh-key delete` on container exit.
- If the container is hard-killed (`docker kill -9`), cleanup is skipped;
  prune leftovers with `gh ssh-key list` / `gh ssh-key delete`.

### Legacy two-step with persistent mounts (optional)

If you prefer reusing your own SSH key and `gh` config across runs:

```bash
docker run -it --rm \
  -v $HOME/.ssh:/root/.ssh.d \
  -v $HOME/.gh:/root/.config/gh \
  rexezugedisasterrecovery/githubrepositories login
```

```bash
docker run -it --rm \
  -v $HOME/.ssh:/root/.ssh.d \
  -v $HOME/.gh:/root/.config/gh \
  -e GITHUB_ORGS="org1 org2" \
  -e S3_BUCKET="my-backup-bucket" \
  -e AWS_ACCESS_KEY_ID=xxx \
  -e AWS_SECRET_ACCESS_KEY=xxx \
  -e AWS_DEFAULT_REGION=us-east-1 \
  -e PASSPHRASE="YOUR_ENCRYPTION_PASSWORD" \
  rexezugedisasterrecovery/githubrepositories
```

When `~/.ssh.d` is mounted, its keys are used as-is (no ephemeral key is
generated or uploaded).

## Restore

### 1. Decrypt Archive

```bash
PASSPHRASE="YOUR_ENCRYPTION_PASSWORD"

gpg --batch --yes --passphrase "$PASSPHRASE" \
    -d "$TAR_FILE" | tar -xJf -
```

### 2. Restore Worktree

```bash
git clone $PATH_TO_UNARCHIVE_DIRECTORY $REPOSITORY_NAME
```
