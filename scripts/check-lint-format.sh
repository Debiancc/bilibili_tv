#!/usr/bin/env bash
#
# SwiftLint + swift-format 统一检查入口（CI 与本地 git hook 共用）。
# 必须与 .github/workflows/objective-c-xcode.yml 的 lint job 保持一致；
# 任何改动都应同时同步两处，或直接让 CI 调用本脚本。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

echo "==> swiftlint lint --quiet"
swiftlint lint --quiet
swiftlint_status=$?

echo "==> xcrun swift-format lint --recursive"
xcrun swift-format lint \
    --configuration .swift-format \
    --recursive bilibili_tv bilibili_tvTests bilibili_tvUITests \
    > /tmp/swiftformat-lint.log 2>&1
format_status=$?
issues=$(grep -vE '\.pb\.swift|Vendor/|bilibili_tvApp|bilibili_tvTests\.swift|TypeNamesShouldBeCapitalized.*bilibili_tvUITests|ep_id|DanmakuTrack|NoBlockComments' /tmp/swiftformat-lint.log | grep -E 'warning|error' || true)

if [ $swiftlint_status -ne 0 ]; then
    echo "::error::swiftlint found violations" >&2
    exit 1
fi

if [ $format_status -ne 0 ] || [ -n "$issues" ]; then
    echo "$issues"
    echo "::error::swift-format found formatting issues" >&2
    exit 1
fi

echo "==> lint & format check passed"
