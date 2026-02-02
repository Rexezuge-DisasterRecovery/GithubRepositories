#!/bin/bash
set -euo pipefail

TMP_DIR=$(mktemp -d)

cleanup() {
    local exit_code=$?   # 保存脚本退出码
    echo "Cleaning up temporary directory: $TMP_DIR"
    rm -rf "$TMP_DIR"
    exit $exit_code      # 保持原始退出状态
}

# 无论成功或失败都会触发
trap cleanup EXIT

# 配置变量
GITHUB_ORGS=${GITHUB_ORGS:-""}
S3_BUCKET=${S3_BUCKET:-""}
SSH_KEY_PATH="${SSH_KEY_PATH:-}"

# 检查必需环境变量
if [[ -z "$GITHUB_ORGS" ]]; then
  echo "Error: GITHUB_ORGS is not set."
  exit 1
fi

if [[ -z "$S3_BUCKET" ]]; then
  echo "Error: S3_BUCKET is not set."
  exit 1
fi

if [ -n "$SSH_KEY_PATH" ]; then
    if [ ! -f "$SSH_KEY_PATH" ]; then
        echo "ERROR: SSH key file not found at $SSH_KEY_PATH" >&2
        exit 1
    fi
    GITHUB_SSH_COMMAND="ssh -i \"$SSH_KEY_PATH\" -o StrictHostKeyChecking=no"
else
    GITHUB_SSH_COMMAND="ssh -o StrictHostKeyChecking=no"
fi

echo "Using temporary working directory: $TMP_DIR"

# 使用 SSH Key 执行 git 命令
export GIT_SSH_COMMAND="$GITHUB_SSH_COMMAND"

# 遍历每个组织
for ORG in $GITHUB_ORGS; do
    echo "Processing organization: $ORG"

    # 获取组织所有仓库 URL (需要安装 gh CLI 或者使用 GitHub API)
    # 这里使用 GitHub CLI gh，需要事先 gh auth login
    REPOS=$(gh repo list "$ORG" --limit 1000 --json name,sshUrl -q '.[].sshUrl')

    if [[ -z "$REPOS" ]]; then
        echo "No repositories found for $ORG"
        continue
    fi

    # 遍历每个仓库
    for REPO_URL in $REPOS; do
        REPO_NAME=$(basename "$REPO_URL" .git)
        CLONE_DIR="$TMP_DIR/$ORG/$REPO_NAME"
        mkdir -p "$(dirname "$CLONE_DIR")"
        echo "Cloning $REPO_URL into $CLONE_DIR"
        git clone --mirror "$REPO_URL" "$CLONE_DIR"

        # 压缩仓库
         TAR_FILE="$TMP_DIR/$ORG/$REPO_NAME.tar.xz"
        echo "Compressing $CLONE_DIR to $TAR_FILE"
        tar -cJf "$TAR_FILE" -C "$(dirname "$CLONE_DIR")" "$REPO_NAME"
    done
done

# 上传到 S3
echo "Uploading tar.xz files to S3 bucket: $S3_BUCKET"
for FILE in "$TMP_DIR"/*.tar.xz "$TMP_DIR"/*/*.tar.xz; do
    if [[ -f "$FILE" ]]; then
        KEY=${FILE#"$TMP_DIR/"}
        AWS_CMD=(aws s3 cp "$FILE" "s3://$S3_BUCKET/$KEY")

        # 若环境变量存在且非空，则追加 endpoint 参数
        if [[ -n "${S3_ENDPOINT_URL:-}" ]]; then
            # 可选：基础格式校验（防止误配置）
            if [[ ! "$S3_ENDPOINT_URL" =~ ^https?:// ]]; then
                echo "ERROR: Invalid S3_ENDPOINT_URL format: $S3_ENDPOINT_URL" >&2
                exit 1
            fi
            AWS_CMD+=(--endpoint-url "$S3_ENDPOINT_URL")
        fi

        # 执行上传
        "${AWS_CMD[@]}"

        echo "Uploaded $KEY"
    fi
done

echo "All repositories processed successfully."
