#!/bin/bash
# 同步 skill 到独立 Gitee 仓库 (skills.git)
# 用法: bash scripts/sync-skill-to-gitee.sh <skill-name> ["更新说明"]
#   skill-name: coding-advisor | architecture-review-board | all
set -e

SKILL_REPO="$HOME/coding-advisor-skill"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="${1:-}"
MSG="${2:-update}"

if [ -z "$SKILL" ]; then
  echo "用法: bash scripts/sync-skill-to-gitee.sh <coding-advisor|architecture-review-board|all> [更新说明]"
  exit 1
fi

sync_coding_advisor() {
  echo "==> [coding-advisor] 复制 skill 文件..."
  mkdir -p "$SKILL_REPO/coding-advisor/agents"
  cp "$PROJECT_ROOT/.claude/skills/coding-advisor/SKILL.md" "$SKILL_REPO/coding-advisor/"
  cp "$PROJECT_ROOT/.claude/skills/coding-advisor/README.md" "$SKILL_REPO/coding-advisor/"

  echo "==> [coding-advisor] 复制 agent 模板..."
  cp "$PROJECT_ROOT/.claude/agents/architecture-reviewer.md" "$SKILL_REPO/coding-advisor/agents/"
  cp "$PROJECT_ROOT/.claude/agents/solution-explorer.md" "$SKILL_REPO/coding-advisor/agents/"
  cp "$PROJECT_ROOT/.claude/agents/security-auditor.md" "$SKILL_REPO/coding-advisor/agents/"
  cp "$PROJECT_ROOT/.claude/agents/refactoring-engineer.md" "$SKILL_REPO/coding-advisor/agents/"
}

sync_arch_review() {
  # 一次性迁移：仓库里如果还存在旧的 arch-review/ 目录，用 git mv 改名为
  # architecture-review-board/（保留历史）。之后本次及后续运行都使用新目录名。
  if [ -d "$SKILL_REPO/arch-review" ] && [ ! -d "$SKILL_REPO/architecture-review-board" ]; then
    echo "==> [architecture-review-board] 检测到旧目录 arch-review/，执行 git mv 迁移..."
    (cd "$SKILL_REPO" && git mv arch-review architecture-review-board)
  fi

  echo "==> [architecture-review-board] 复制 skill 文件..."
  mkdir -p "$SKILL_REPO/architecture-review-board/scripts" "$SKILL_REPO/architecture-review-board/references" "$SKILL_REPO/architecture-review-board/examples"
  cp "$PROJECT_ROOT/.claude/skills/architecture-review-board/SKILL.md" "$SKILL_REPO/architecture-review-board/"
  cp "$PROJECT_ROOT/.claude/skills/architecture-review-board/README.md" "$SKILL_REPO/architecture-review-board/"
  cp "$PROJECT_ROOT/.claude/skills/architecture-review-board/scripts/review-board.js" "$SKILL_REPO/architecture-review-board/scripts/"
  cp "$PROJECT_ROOT/.claude/skills/architecture-review-board/references/lightweight-mode.md" "$SKILL_REPO/architecture-review-board/references/"
  cp "$PROJECT_ROOT/.claude/skills/architecture-review-board/references/dimension-rubrics.md" "$SKILL_REPO/architecture-review-board/references/"
  cp "$PROJECT_ROOT/.claude/skills/architecture-review-board/examples/example-lightweight.md" "$SKILL_REPO/architecture-review-board/examples/"
  cp "$PROJECT_ROOT/.claude/skills/architecture-review-board/examples/example-full.md" "$SKILL_REPO/architecture-review-board/examples/"
}

case "$SKILL" in
  coding-advisor)
    sync_coding_advisor
    LABEL="coding-advisor"
    ;;
  architecture-review-board)
    sync_arch_review
    LABEL="architecture-review-board"
    ;;
  all)
    sync_coding_advisor
    sync_arch_review
    LABEL="coding-advisor + architecture-review-board"
    ;;
  *)
    echo "未知 skill: $SKILL (可用: coding-advisor, architecture-review-board, all)"
    exit 1
    ;;
esac

echo "==> 提交并推送..."
cd "$SKILL_REPO"
git add -A
git commit -m "sync($LABEL): $(date +%Y-%m-%d) — $MSG" || echo "无变更，跳过 commit"
git push origin master

echo "==> 完成"
