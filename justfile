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
            claude \
              -p "Create a conventional commit for all current changes. Stage all files and commit." \
              --allow-dangerously-skip-permissions --dangerously-skip-permissions \
              --model haiku
            echo "Changes committed!"
        else
            echo "Skipping commit"
        fi
    fi

update:
    devenv update
    git add devenv.lock && git commit -m "chore(devenv): Update devenv.lock" || true
    nix flake update --commit-lock-file
    just _update-and-commit-npm claude-code
    just _update-and-commit-npm playwright-cli

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

# Update playwright-cli to a specific version (or latest if no version given)
update-playwright-cli version="":
    ./scripts/update-playwright-cli.sh {{version}}

# Internal: update an npm package to latest and commit atomically if changed
_update-and-commit-npm name:
    #!/usr/bin/env bash
    set -euo pipefail
    nix_file="users/jloos/modules/{{name}}.nix"
    lock_file="users/jloos/modules/{{name}}/package-lock.json"
    old_version=$(grep 'version = "' "$nix_file" | head -1 | sed 's/.*version = "\([^"]*\)".*/\1/')
    ./scripts/update-{{name}}.sh latest
    new_version=$(grep 'version = "' "$nix_file" | head -1 | sed 's/.*version = "\([^"]*\)".*/\1/')
    if [[ "$old_version" != "$new_version" ]]; then
        git add "$nix_file" "$lock_file"
        git commit -m "build({{name}}): ${old_version} → ${new_version}"
    fi
