## Usage

### 1. Login to Github CLI

```bash
docker run -it --rm \
  -v $HOME/.ssh:/root/.ssh \
  -v $HOME/.gh:/root/.config/gh \
  rexezugedisasterrecovery/githubrepositories login
```

---

```text
Container started with command: login
Starting GitHub CLI login process...
You may need to complete device authentication in the browser.
? What account do you want to log into? GitHub.com
? What is your preferred protocol for Git operations? SSH
? Upload your SSH public key to your GitHub account? /root/.ssh/id_ed25519.pub
? Title for your SSH key: GitHub CLI
? How would you like to authenticate GitHub CLI? Login with a web browser

! First copy your one-time code: 1111-2222
Press Enter to open github.com in your browser... 
! Failed opening a web browser at https://github.com/login/device
  exec: "xdg-open,x-www-browser,www-browser,wslview": executable file not found in $PATH
  Please try entering the URL in your browser manually
✓ Authentication complete.
- gh config set -h github.com git_protocol ssh
✓ Configured git protocol
✓ Uploaded the SSH key to your GitHub account: /root/.ssh/id_ed25519.pub
✓ Logged in as XXXXX
GitHub authentication completed.
```

### 2. Perform Backup

```bash
docker run -it --rm \
  -v $HOME/.ssh:/root/.ssh \
  -v $HOME/.gh:/root/.config/gh \
  -e GITHUB_ORGS="org1 org2" \
  -e S3_BUCKET="my-backup-bucket" \
  -e AWS_ACCESS_KEY_ID=xxx \
  -e AWS_SECRET_ACCESS_KEY=xxx \
  -e AWS_DEFAULT_REGION=us-east-1 \
  rexezugedisasterrecovery/githubrepositories
```
