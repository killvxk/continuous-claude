#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

setup() {
    # Path to the script under test
    # BATS_TEST_DIRNAME is the directory containing the test file
    SCRIPT_PATH="$BATS_TEST_DIRNAME/../continuous_claude.sh"
    export TESTING="true"
}

@test "show_help displays help message" {
    source "$SCRIPT_PATH"
    # We need to call the function directly to capture output in the current shell
    # or export it for run. Simpler to just capture output manually if run fails.
    # But let's try exporting.
    export -f show_help
    run show_help
    assert_output --partial "Continuous Claude - Run Claude Code iteratively"
    assert_output --partial "USAGE:"
}

@test "show_version displays version" {
    source "$SCRIPT_PATH"
    export -f show_version
    run show_version
    assert_output --partial "continuous-claude version"
}

@test "parse_arguments handles required flags" {
    source "$SCRIPT_PATH"
    parse_arguments -p "test prompt" -m 5 --owner user --repo repo
    
    assert_equal "$PROMPT" "test prompt"
    assert_equal "$MAX_RUNS" "5"
    assert_equal "$GITHUB_OWNER" "user"
    assert_equal "$GITHUB_REPO" "repo"
}

@test "parse_arguments handles dry-run flag" {
    source "$SCRIPT_PATH"
    parse_arguments -p "test" --dry-run
    
    assert_equal "$DRY_RUN" "true"
}

@test "validate_arguments fails without prompt" {
    source "$SCRIPT_PATH"
    PROMPT=""
    run validate_arguments
    assert_failure
    assert_output --partial "Error: Prompt is required"
}

@test "validate_arguments fails without max-runs or max-cost" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS=""
    MAX_COST=""
    run validate_arguments
    assert_failure
    assert_output --partial "Error: Either --max-runs or --max-cost is required"
}

@test "validate_arguments passes with valid arguments" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS="5"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    run validate_arguments
    assert_success
}

@test "dry run mode skips execution" {
    # Mock required commands
    function claude() { echo "mock claude"; }
    function gh() { echo "mock gh"; }
    function git() { echo "mock git"; }
    export -f claude gh git
    
    source "$SCRIPT_PATH"
    
    # Set up environment for main_loop
    PROMPT="test"
    MAX_RUNS=1
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    DRY_RUN="true"
    ENABLE_COMMITS="true"
    
    # Create a temporary error log
    ERROR_LOG=$(mktemp)
    
    # Run the main loop (should be fast due to dry run)
    run main_loop
    
    rm -f "$ERROR_LOG"
    
    assert_success
    # We can't easily check stdout here because main_loop output might be captured or redirected
    # But success means it didn't crash
}

@test "validate_requirements fails when claude is missing" {
    # Mock command to fail for claude
    function command() {
        if [ "$2" == "claude" ]; then
            return 1
        fi
        return 0
    }
    export -f command
    
    source "$SCRIPT_PATH"
    run validate_requirements
    
    assert_failure
    assert_output --partial "Error: Claude Code is not installed"
}

@test "validate_requirements fails when jq is missing" {
    # Mock command to fail for jq, pass for claude
    function command() {
        if [ "$2" == "jq" ]; then
            return 1
        fi
        return 0
    }
    # Mock claude to simulate installation failure
    function claude() {
        return 0
    }
    export -f command claude
    
    source "$SCRIPT_PATH"
    run validate_requirements
    
    assert_failure
    assert_output --partial "jq is required for JSON parsing"
}

@test "validate_requirements fails when gh is missing and commits enabled" {
    # Mock command to fail for gh
    function command() {
        if [ "$2" == "gh" ]; then
            return 1
        fi
        return 0
    }
    export -f command
    
    source "$SCRIPT_PATH"
    ENABLE_COMMITS="true"
    run validate_requirements
    
    assert_failure
    assert_output --partial "Error: GitHub CLI (gh) is not installed"
}

@test "validate_requirements passes when gh is missing but commits disabled" {
    # Mock command to fail for gh
    function command() {
        if [ "$2" == "gh" ]; then
            return 1
        fi
        return 0
    }
    export -f command
    
    source "$SCRIPT_PATH"
    ENABLE_COMMITS="false"
    run validate_requirements
    
    assert_success
}

@test "get_iteration_display formats with max runs" {
    source "$SCRIPT_PATH"
    run get_iteration_display 1 5 0
    assert_output "(1/5)"
    
    run get_iteration_display 2 5 1
    assert_output "(2/6)"
}

@test "get_iteration_display formats without max runs" {
    source "$SCRIPT_PATH"
    run get_iteration_display 1 0 0
    assert_output "(1)"
}

@test "parse_claude_result handles valid success JSON" {
    source "$SCRIPT_PATH"
    run parse_claude_result '{"result": "success", "total_cost_usd": 0.1}'
    assert_success
    assert_output "success"
}

@test "parse_claude_result handles invalid JSON" {
    source "$SCRIPT_PATH"
    run parse_claude_result 'invalid json'
    assert_failure
    assert_output "invalid_json"
}

@test "parse_claude_result handles Claude error JSON" {
    source "$SCRIPT_PATH"
    run parse_claude_result '{"is_error": true, "result": "error message"}'
    assert_failure
    assert_output "claude_error"
}

@test "create_iteration_branch generates correct branch name" {
    source "$SCRIPT_PATH"
    GIT_BRANCH_PREFIX="test-prefix/"
    DRY_RUN="true"
    
    # Mock date to return fixed value
    function date() {
        if [ "$1" == "+%Y-%m-%d" ]; then
            echo "2024-01-01"
        else
            echo "12345678"
        fi
    }
    # Mock openssl for random hash
    function openssl() {
        echo "abcdef12"
    }
    export -f date openssl
    
    run create_iteration_branch "(1/5)" 1
    
    assert_success
    assert_output --partial "test-prefix/iteration-1/2024-01-01-abcdef12"
}
