#!/usr/bin/env bash
#
# 把 .swiftlint_baseline.json 中的 file 路径从绝对 file:// 形式转为相对路径。
#
# 背景：SwiftLint ≤ 0.65.0 写 baseline 时直接序列化绝对路径（file:///...），
# 而读取时按当前工作目录前缀剥离做匹配 key，导致 baseline 只在生成机器的
# 同 CWD 下有效，CI（不同 checkout 路径）上全部失效。
# 修复（realm/SwiftLint#5599）要到未发布的 main 才有；这里用文本替换规避。
#
# 用法：`swiftlint lint --write-baseline .swiftlint_baseline.json` 之后运行本脚本。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$ROOT/.swiftlint_baseline.json"

if [ ! -f "$BASELINE" ]; then
    echo "::error::baseline 文件不存在: $BASELINE" >&2
    exit 1
fi

ORIG_PREFIX='file:\/\/\/'
# 去掉任意机器的绝对路径前缀，只保留项目根以下的相对路径。
# 形式： "file":"file:///任意绝对路径/bilibili_tv/Core/... " -> "file":"bilibili_tv/Core/..."
python3 - "$BASELINE" << 'EOF'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

import re
# 原始 JSON 是转义形式（\/ = 两字符），匹配 "file":"file: 后任意转义绝对路径，
# 直到 \/bilibili_tv\/ 为止，把整段绝对前缀替换为空，保留 bilibili_tv/ 相对路径。
pattern = re.compile(r'("file":"file:)((?:\\\/|\\|[^"])*?bilibili_tv\\\/)')
matches = pattern.findall(content)
if not matches:
    print("baseline 无绝对路径，无需规范化")
    sys.exit(0)

content = pattern.sub(r'"file":"', content)
with open(path, 'w') as f:
    f.write(content)
print(f"已把 {len(matches)} 处 file 路径相对化: {path}")
EOF
