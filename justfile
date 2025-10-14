default:
    echo 'Hello, world!'

switch:
    sudo darwin-rebuild switch --flake . --verbose

update:
    devenv update
    nix flake update --commit-lock-file

# List all secrets in the flake
sops-list-secrets:
    find . -type f \
        | grep -E "$(yq -r '.creation_rules[].path_regex' .sops.yaml | paste -sd '|')"

# Format all files
fmt:
    nix fmt

# Check formatting without changing files
check-fmt:
    nix fmt -- --fail-on-change

run-hooks:
    pre-commit run --verbose
