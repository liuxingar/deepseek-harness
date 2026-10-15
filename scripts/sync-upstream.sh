#!/usr/bin/env bash
# 同步官方上游 deepseek-ai/deepseek-harness 到本 fork，并保留 Docker 部署改动。
# 原则：官方源码零改动（不做任何构建期源码补丁）；$DSH_LAN_URL 由 entrypoint.sh
# 通过官方 --public-url 传入，局域网 settings 由上游原生支持。
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
  echo "  - 官方源码零改动：不做构建期源码补丁；局域网 settings 由上游 #4201 原生支持，"
  echo "    登录 URL 由 entrypoint.sh 的 --public-url 传入，冲突时应保留官方版本"
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

# 4.2 官方源码保持零改动（不再做任何构建期源码补丁）
if grep -rq "apply-lan-" Dockerfile; then
  echo "  [WARN] Dockerfile 仍在调用构建期源码补丁脚本（已弃用，应删除）"
  SELF_CHECK_OK=0
else
  echo "  [OK] Dockerfile 无构建期源码补丁"
fi

# 4.3 上游已提供 $DSH_LAN_URL 所需的原生能力：
#     a) 认证浏览器 settings 走 Host 持久化（2026-10-09 PR #4201）
#     b) --public-url / printUrl（2026-09-30 a7c3ad99b）
if grep -q "isLoopback ? 'host' : 'memory'" packages/client/ui-settings/src/client/index.ts; then
  echo "  [WARN] ui-settings 又按 loopback 区分持久化（上游疑似回退 #4201），局域网 settings 可能失效"
  SELF_CHECK_OK=0
else
  echo "  [OK] ui-settings 已按认证浏览器统一持久化（#4201）"
fi
if grep -q "publicUrl" packages/bundle/web-app/src/index.ts \
  && grep -q -- "--public-url" packages/bundle/web-app/src/startup.ts; then
  echo "  [OK] web-app 原生支持 --public-url"
else
  echo "  [WARN] web-app 不再支持 --public-url，需重新评估 $DSH_LAN_URL 的实现方式"
  SELF_CHECK_OK=0
fi
if grep -q -- "--public-url" entrypoint.sh; then
  echo "  [OK] entrypoint.sh 通过 --public-url 传入 \$DSH_LAN_URL"
else
  echo "  [WARN] entrypoint.sh 未传 --public-url，启动日志将显示容器内网地址"
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
