#!/usr/bin/env bash
# =============================================================================
# CI guard: 平台开屏资源漂移检测 (spec §8, board 建议, 非阻塞)
# =============================================================================
# 跑 `flutter_native_splash:create` 后检查 android/ ios/ 有无文件漂移。
# 漂移 = 当前 pubspec 配置生成的 drawable / storyboard 跟 repo 里的不一致。
# 这类漂移正是本次设计修复的 broken-drawable bug 的根因 —— 配置改了但
# `:create` 没重跑，导致 Android 12+ 走旧 SplashScreen API、iOS 缺暗色变体。
#
# 用法 (本地手跑或接入 CI)：
#   ./scripts/check-platform-splash.sh
#
# 接入 CI/pre-commit 的 wiring 见 plan Task 9 Step 3 —— 本次未接入
# (pre-commit hook 是 Iron Laws 守门员，改动有风险；留作后续单独 PR)。
set -euo pipefail

# 1. 重新生成平台开屏资源
dart run flutter_native_splash:create

# 2. 检查 android/ ios/ 有无未提交变更（create 之后）
if ! git diff --exit-code android/ ios/ > /dev/null; then
  echo "ERROR: platform splash files drifted." >&2
  echo "Run 'dart run flutter_native_splash:create' and commit the result." >&2
  git diff --stat android/ ios/ >&2
  exit 1
fi

echo "OK: no platform splash drift."
