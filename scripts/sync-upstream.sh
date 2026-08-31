#!/usr/bin/env bash
# 同步官方上游 deepseek-ai/deepseek-harness 到本 fork，并保留 Docker 部署改动。
# 原则：不改动官方源码文件——官方代码的少量修改在镜像构建时注入（scripts/apply-lan-settings-patch.py）。
# 用法：bash scripts/sync-upstream.sh
# 流程：fetch upstream -> merge -> 自检关键改动 -> push fork -> 触发自动构建
set -euo pipefail

REPO_URL="https://github.com/deepseek-ai/deepseek-harness.git"
UPSTREAM="upstream"
UPSTREAM_BRANCH="master"

cd "$(dirname "$0")/.."

# 1. 确保 upstream remote 存在
if ! git remote | grep -qx "$UPSTREAM"; then
  echo "添加 upstream remote: $REPO_URL"
  git remote add "$UPSTREAM" "$REPO_URL"
fi

# 2. 拉取官方最新
echo "==> 拉取官方上游 $UPSTREAM_BRANCH ..."
git fetch "$UPSTREAM" "$UPSTREAM_BRANCH"

# 3. 合并（保留本地改动）
echo "==> 合并 upstream/$UPSTREAM_BRANCH ..."
if git merge --no-edit "$UPSTREAM/$UPSTREAM_BRANCH"; then
  echo "==> 合并成功，无冲突。"
else
  echo ""
  echo "!!! merge 冲突，需要手动处理 !!!"
  echo ""
  echo "本 fork 的改动清单见 docs/fork-maintenance.md，要点："
  echo "  - 新增的 docker 部署文件（Dockerfile/compose/patch 等）：保留"
  echo "  - 删除的官方 workflow（ci/release/e2e 等）：保持删除（git checkout --theirs 可一键保持删除）"
  echo "  - 官方源码文件（如 ui-settings）保持官方原样，由构建时补丁注入，一般无需处理"
  echo ""
  echo "处理完冲突后：git add -A && git commit，然后重新运行本脚本（或手动 push）"
  exit 1
fi

# 4. 合并后自检关键改动
echo "==> 自检关键改动 ..."
SELF_CHECK_OK=1

# 4.1 docker-patch.yml 的 !!js 必须是双引号标量（避免启动失败）
if [ -f docker-patch.yml ]; then
  if grep -q 'trustedHosts: !!js "' docker-patch.yml; then
    echo "  [OK] docker-patch.yml !!js 为标量"
  else
    echo "  [WARN] docker-patch.yml 的 trustedHosts 不是 !!js 双引号标量！启动会失败"
    SELF_CHECK_OK=0
  fi
else
  echo "  [WARN] docker-patch.yml 不存在！"
  SELF_CHECK_OK=0
fi

# 4.2 官方源码保持原样（含 isLoopback 原逻辑），由构建时脚本注入
if grep -q "ctx.remote.\$host.isLoopback ? 'host' : 'memory'" packages/client/ui-settings/src/client/index.ts; then
  echo "  [OK] ui-settings 源码保持官方原样（构建时注入补丁）"
else
  echo "  [WARN] ui-settings 源码不含官方 isLoopback 原逻辑，可能已被改动，请检查"
  SELF_CHECK_OK=0
fi

# 4.3 构建时补丁脚本与 Dockerfile 引用
if [ -f scripts/apply-lan-settings-patch.py ] && grep -q "apply-lan-settings-patch.py" Dockerfile; then
  echo "  [OK] 构建时补丁脚本已配置"
else
  echo "  [WARN] scripts/apply-lan-settings-patch.py 或 Dockerfile 引用缺失"
  SELF_CHECK_OK=0
fi

# 4.4 唯一保留的 CI
if [ -f .github/workflows/docker-build.yml ]; then
  echo "  [OK] docker-build.yml 存在"
else
  echo "  [WARN] .github/workflows/docker-build.yml 不存在！"
  SELF_CHECK_OK=0
fi

if [ "$SELF_CHECK_OK" = "0" ]; then
  echo ""
  echo "存在自检未通过项，已暂停推送。请检查后手动 git add -A && git push origin master"
  exit 1
fi

# 5. 推送 fork -> 触发 GitHub Actions 自动构建
echo "==> 推送 fork 到 origin/master（触发自动构建）..."
git push origin master

echo ""
echo "✅ 同步完成！GitHub Actions 正在自动构建新镜像："
echo "   ghcr.io/liuxingar/deepseek-harness:latest"
echo "   构建完成后在群晖上：docker compose pull && docker compose up -d"
