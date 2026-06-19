#!/bin/bash
# 同步 skill 到独立 Gitee 仓库 (skills.git)
# 用法: bash scripts/sync-skill-to-gitee.sh <skill-name> ["更新说明"]
#   skill-name: coding-advisor | arch-review | all
set -e

SKILL_REPO="$HOME/coding-advisor-skill"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="${1:-}"
MSG="${2:-update}"

if [ -z "$SKILL" ]; then
  echo "用法: bash scripts/sync-skill-to-gitee.sh <coding-advisor|arch-review|all> [更新说明]"
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
  echo "==> [arch-review] 复制 skill 文件..."
  mkdir -p "$SKILL_REPO/arch-review/scripts" "$SKILL_REPO/arch-review/references" "$SKILL_REPO/arch-review/examples"
  cp "$PROJECT_ROOT/.claude/skills/arch-review/SKILL.md" "$SKILL_REPO/arch-review/"
  cp "$PROJECT_ROOT/.claude/skills/arch-review/README.md" "$SKILL_REPO/arch-review/"
  cp "$PROJECT_ROOT/.claude/skills/arch-review/scripts/review-board.js" "$SKILL_REPO/arch-review/scripts/"
  cp "$PROJECT_ROOT/.claude/skills/arch-review/references/lightweight-mode.md" "$SKILL_REPO/arch-review/references/"
  cp "$PROJECT_ROOT/.claude/skills/arch-review/references/dimension-rubrics.md" "$SKILL_REPO/arch-review/references/"
  cp "$PROJECT_ROOT/.claude/skills/arch-review/examples/example-lightweight.md" "$SKILL_REPO/arch-review/examples/"
  cp "$PROJECT_ROOT/.claude/skills/arch-review/examples/example-full.md" "$SKILL_REPO/arch-review/examples/"
}

case "$SKILL" in
  coding-advisor)
    sync_coding_advisor
    LABEL="coding-advisor"
    ;;
  arch-review)
    sync_arch_review
    LABEL="arch-review"
    ;;
  all)
    sync_coding_advisor
    sync_arch_review
    LABEL="coding-advisor + arch-review"
    ;;
  *)
    echo "未知 skill: $SKILL (可用: coding-advisor, arch-review, all)"
    exit 1
    ;;
esac

echo "==> 提交并推送..."
cd "$SKILL_REPO"
git add -A
git commit -m "sync($LABEL): $(date +%Y-%m-%d) — $MSG" || echo "无变更，跳过 commit"
git push origin master

echo "==> 完成"
