
#!/bin/bash

# Build and package TradersRush.app,
# then commit and push changes to Git.

set -euo pipefail

cd "$(dirname "$0")"

# Build application
echo "==> Building TradersRush.app..."
./AppPackaging/make_app.sh

# Stage changes
echo "==> Staging Git changes..."
git add -A

# Commit if changes exist
if ! git diff --cached --quiet; then
    COMMIT_MESSAGE="${1:-Build TradersRush - $(date '+%Y-%m-%d %H:%M:%S')}"
    
    echo "==> Committing changes..."
    git commit -m "$COMMIT_MESSAGE"
else
    echo "==> No changes to commit."
fi

# Push current branch
echo "==> Pushing to remote repository..."
git push origin "$(git branch --show-current)"

echo "==> Build, commit and push completed successfully."
