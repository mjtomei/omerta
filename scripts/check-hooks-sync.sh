#!/bin/bash
# CI script to verify .githooks are in sync across all repositories
# Works with both cloned sub-repos and stub directories

set -e

PARENT_HOOKS=".githooks"
SUBREPOS=(
    "omerta_infra"
    "omerta_lang"
    "omerta_mesh"
    "omerta_node"
    "omerta_protocol"
)

if [ ! -d "$PARENT_HOOKS" ]; then
    echo "ERROR: Parent .githooks directory not found"
    exit 1
fi

FAILED=0

for repo in "${SUBREPOS[@]}"; do
    if [ ! -d "$repo" ]; then
        echo "SKIP: $repo not found"
        continue
    fi

    SUB_HOOKS="$repo/.githooks"

    if [ ! -d "$SUB_HOOKS" ]; then
        # Stub directory (not cloned) — skip gracefully
        echo "SKIP: $repo/.githooks not present (not cloned?)"
        continue
    fi

    # Compare each hook file
    for hook in "$PARENT_HOOKS"/*; do
        hook_name=$(basename "$hook")
        sub_hook="$SUB_HOOKS/$hook_name"

        if [ ! -f "$sub_hook" ]; then
            echo "ERROR: $repo is missing hook: $hook_name"
            FAILED=1
        elif ! diff -q "$hook" "$sub_hook" > /dev/null 2>&1; then
            echo "ERROR: $repo has outdated hook: $hook_name"
            echo "  Run: cp .githooks/$hook_name $repo/.githooks/"
            FAILED=1
        else
            echo "OK: $repo/$hook_name is in sync"
        fi
    done
done

if [ $FAILED -eq 1 ]; then
    echo ""
    echo "Hooks are out of sync. Copy from parent repo to sub-repos:"
    echo "  for dir in ${SUBREPOS[*]}; do cp .githooks/* \$dir/.githooks/; done"
    exit 1
fi

echo ""
echo "All hooks are in sync."
exit 0
