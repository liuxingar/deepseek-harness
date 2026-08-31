#!/bin/sh
# DeepSeek Harness 容器入口脚本
#
# 背景：镜像内 dsh 以非 root 用户运行（安全加固），但用户挂载到
# /app/.dsh（DSH_HOME）和 /workspace 的宿主目录在 bind mount 后会
# 遮蔽镜像内 chown 的属主设置——NAS 上目录通常归 root 所有，导致
# dsh 用户无法写入，启动即报：
#   Error: EACCES: permission denied, mkdir '/app/.dsh/profiles/web'
#
# 处理：以 root 启动 → 修正挂载卷属主为 dsh → 降权到 dsh 用户运行。
# 这样无论宿主机目录权限如何，容器都能自动工作，无需手动 chmod。
set -e

# 修正挂载卷属主；目录不存在或属主已正确时跳过，避免每次启动递归 chown 大目录
for dir in /app/.dsh /workspace; do
  [ -d "$dir" ] || continue
  owner="$(stat -c %u "$dir" 2>/dev/null || echo '')"
  want="$(id -u dsh 2>/dev/null || echo '')"
  if [ -n "$owner" ] && [ -n "$want" ] && [ "$owner" != "$want" ]; then
    chown -R dsh:dsh "$dir" 2>/dev/null || true
  fi
done

# 降权到 dsh 用户运行 dsh web（显式设置 HOME=/app，确保默认 home 解析为 /app/.dsh）
exec su -s /bin/sh dsh -c "export HOME=/app && cd /app && exec pnpm dsh web --patch /app/docker-patch.yml"
