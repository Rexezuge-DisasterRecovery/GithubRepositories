## Usage

### 1. Login to Github CLI

```bash
docker run -it --rm \
  -v $HOME/.ssh:/root/.ssh \
  -v $HOME/.gh:/root/.config/gh \
  rexezugedisasterrecovery/githubrepositories login
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
