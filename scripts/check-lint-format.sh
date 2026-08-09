#!/usr/bin/env bash
#
# SwiftLint + swift-format 统一检查入口（CI 与本地 git hook 共用）。
# 必须与 .github/workflows/objective-c-xcode.yml 的 lint job 保持一致；
# 任何改动都应同时同步两处，或直接让 CI 调用本脚本。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

# 使用 baseline：存量违规已快照静音，只对新增违规报错（--strict 使 warning 也失败）。
# 每阶段完成后需重新 `swiftlint lint --write-baseline .swiftlint_baseline.json` 更新基线，
# 且随后运行 scripts/normalize-baseline-path.sh 把 file 路径相对化（否则跨机器/CI 失效）。
if grep -q 'file:\/\/' .swiftlint_baseline.json; then
    echo "::error::.swiftlint_baseline.json 含绝对路径 (file://)，跨机器失效。请运行 scripts/normalize-baseline-path.sh" >&2
    exit 1
fi
echo "==> swiftlint lint --baseline .swiftlint_baseline.json --strict"
swiftlint lint --baseline .swiftlint_baseline.json --strict
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
