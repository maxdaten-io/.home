default:
    update-switch

switch:
    sudo darwin-rebuild switch --flake . --verbose
    @just _prompt-commit

_prompt-commit:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ""
    echo "Darwin rebuild complete!"
    echo ""
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Changes detected. Would you like to commit them? (y/n)"
        read -r answer
        if [ "$answer" = "y" ]; then
            git add -A
            git commit -m "chore: Update darwin configuration"
            echo "Changes committed!"
        else
            echo "Skipping commit"
        fi
    fi

update:
    devenv update
    git add devenv.lock && git commit -m "chore(devenv): Update devenv.lock" || true
    nix flake update --commit-lock-file

# Update flake inputs and switch in one command
update-switch: update fmt switch

# List all secrets in the flake
sops-list-secrets:
    find . -type f \
        | grep -E "$(yq -r '.creation_rules[].path_regex' .sops.yaml | paste -sd '|')"

# Format all files
fmt:
    treefmt

# Check formatting without changing files
check-fmt:
    treefmt --fail-on-change

run-hooks:
    pre-commit run --verbose

# Update claude-code to a specific version (or latest if no version given)
update-claude-code version="":
    ./scripts/update-claude-code.sh {{version}}
