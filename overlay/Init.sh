#!/bin/bash
set -euo pipefail

COMMAND=${1:-""}

echo "Container started with command: ${COMMAND:-<empty>}"

case "$COMMAND" in
  login)
    echo "Starting GitHub CLI login process..."
    echo "You may need to complete device authentication in the browser."
    gh auth login
    echo "GitHub authentication completed."
    ;;

  "")
    echo "No command provided. Executing ExportToS3.sh..."
    exec /ExportToS3.sh
    ;;

  *)
    echo "ERROR: Unknown command '$COMMAND'"
    echo "Supported commands:"
    echo "  login   - Authenticate GitHub CLI"
    echo "  <empty> - Run repository export workflow"
    exit 1
    ;;
esac
