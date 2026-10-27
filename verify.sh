# Included in the flake's generated verification script, after sandbox setup.
# shellcheck shell=bash
# shellcheck disable=SC2154

expect() {
  local expected=$1
  shift
  local actual
  actual=$(evaluate "$@")
  if [[ $actual != "$expected" ]]; then
    printf 'Expected %s, got %s\n' "$expected" "$actual" >&2
    exit 1
  fi
}

expect_denied() {
  local output
  if output=$(evaluate --impure --expr "$1" 2>&1); then
    printf 'Unexpected success: %s\n' "$1" >&2
    exit 1
  fi
  if [[ $output != *'Permission denied'* ]]; then
    printf 'Unexpected error: %s\n' "$output" >&2
    exit 1
  fi
}

printf 'allowed' > "$work/allowed/file"
printf 'denied' > "$work/denied/file"
printf '21 * 2\n' > "$work/allowed/expression.nix"
ln -s file "$work/allowed/link"
ln -s ../denied/file "$work/allowed/denied-link"

expect 2 --expr '1 + 1'
expect 2 --impure --expr '1 + 1'
expect allowed --impure --raw --expr "builtins.readFile $work/allowed/file"
expect allowed --impure --raw --expr "builtins.readFile $work/allowed/link"
expect 42 --impure --expr "import $work/allowed/expression.nix"
expect regular --impure --raw --expr "(builtins.readDir $work/allowed).file"
expect_denied 'builtins.readDir "/"'
expect_denied "builtins.readDir $work"
expect_denied "builtins.readDir $work/denied"
expect_denied "builtins.readFile $work/denied/file"
expect_denied "builtins.readFile $work/allowed/denied-link"
echo 'PASS: evaluation, permitted reads/imports/listings, and symlinks; denied reads/listings remain denied.'
