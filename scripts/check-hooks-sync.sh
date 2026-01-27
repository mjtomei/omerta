#!/bin/bash
# CI script to verify .githooks are in sync across all repositories
# This ensures the parent repo's hooks are propagated to submodules

set -e

PARENT_HOOKS=".githooks"
SUBMODULES=(
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

for submodule in "${SUBMODULES[@]}"; do
    if [ ! -d "$submodule" ]; then
        echo "SKIP: $submodule not found (submodule not checked out?)"
        continue
    fi

    SUB_HOOKS="$submodule/.githooks"

    if [ ! -d "$SUB_HOOKS" ]; then
        echo "ERROR: $submodule is missing .githooks directory"
        FAILED=1
        continue
    fi

    # Compare each hook file
    for hook in "$PARENT_HOOKS"/*; do
        hook_name=$(basename "$hook")
        sub_hook="$SUB_HOOKS/$hook_name"

        if [ ! -f "$sub_hook" ]; then
            echo "ERROR: $submodule is missing hook: $hook_name"
            FAILED=1
        elif ! diff -q "$hook" "$sub_hook" > /dev/null 2>&1; then
            echo "ERROR: $submodule has outdated hook: $hook_name"
            echo "  Run: cp .githooks/$hook_name $submodule/.githooks/"
            FAILED=1
        else
            echo "OK: $submodule/$hook_name is in sync"
        fi
    done
done

if [ $FAILED -eq 1 ]; then
    echo ""
    echo "Hooks are out of sync. Copy from parent repo to submodules:"
    echo "  for dir in ${SUBMODULES[*]}; do cp .githooks/* \$dir/.githooks/; done"
    exit 1
fi

echo ""
echo "All hooks are in sync."
exit 0
