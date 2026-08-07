#!/usr/bin/env bats

@test "deploy CLI exposes non-interactive subcommands" {
    run ./deploy.sh help
    [ "$status" -eq 0 ]
    [[ "$output" == *"install"* ]]
    [[ "$output" == *"reconfigure"* ]]
    [[ "$output" == *"purge --yes-i-understand"* ]]
}

@test "data safety guard rejects filesystem and project ancestors" {
    local env_file project_root
    env_file=$(mktemp)
    project_root="$BATS_TEST_TMPDIR/project/repository"
    mkdir -p "$project_root"
    printf 'DATA_DIR=/\n' >"$env_file"
    run env ENV_FILE="$env_file" PROJECT_ROOT="$project_root" bash -c \
        'source scripts/deploy/config.sh; source scripts/deploy/common.sh; safe_data_path'
    [ "$status" -ne 0 ]
    [[ "$output" == *"不安全的数据目录"* ]]

    printf 'DATA_DIR=%s\n' "$(dirname "$project_root")" >"$env_file"
    run env ENV_FILE="$env_file" PROJECT_ROOT="$project_root" bash -c \
        'source scripts/deploy/config.sh; source scripts/deploy/common.sh; safe_data_path'
    [ "$status" -ne 0 ]
    [[ "$output" == *"上级路径"* ]]
    rm -f "$env_file"
}
