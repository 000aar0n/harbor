#!/bin/bash
set -euo pipefail
app_path="$1"
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
"$app_path/Contents/MacOS/Secret" --startup-check "$check_dir/direct-ready" > "$check_dir/direct.log" 2>&1 || {
  cat "$check_dir/direct.log"
  exit 1
}
test -s "$check_dir/direct-ready"
open -n -W "$app_path" --args --startup-check "$check_dir/finder-ready"
test -s "$check_dir/finder-ready"
echo 'PASS: Gecko control panel and Node backend ready through direct launch and LaunchServices'
