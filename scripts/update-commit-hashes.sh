#!/bin/bash
# Auto-correct stale .commit hashes during pre-commit
# Called from .githooks/pre-commit; harmless no-op in sub-repos (script won't exist)

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_BASE="https://github.com/mjtomei"
MODULES=(omerta_node omerta_mesh omerta_lang omerta_protocol omerta_infra)

changed=0
for mod in "${MODULES[@]}"; do
    commit_file="$REPO_ROOT/$mod/.commit"
    [ -f "$commit_file" ] || continue

    current_sha=$(tr -d '[:space:]' < "$commit_file")
    remote_sha=$(git ls-remote "$REPO_BASE/$mod" refs/heads/master 2>/dev/null | cut -f1)

    if [ -z "$remote_sha" ]; then
        continue
    fi

    if [ "$remote_sha" != "$current_sha" ]; then
        echo "$remote_sha" > "$commit_file"
        git add "$commit_file"
        echo "Updated $mod/.commit: ${current_sha:0:8} -> ${remote_sha:0:8}"
        changed=1
    fi
done

if [ $changed -eq 1 ]; then
    echo "Staged updated .commit files"
fi
