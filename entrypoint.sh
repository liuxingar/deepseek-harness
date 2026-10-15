#!/bin/sh
# DeepSeek Harness 容器入口脚本
#
# 背景：镜像内 dsh 以非 root 用户运行（安全加固），但用户挂载到
# /app/.dsh（DSH_HOME）、/workspace 和 /data（对话数据卷）的宿主目录
# 在 bind mount 后会遮蔽镜像内 chown 的属主设置——NAS 上目录通常归 root
# 所有，导致 dsh 用户无法写入，启动即报：
#   Error: EACCES: permission denied, mkdir '/app/.dsh/profiles/web'
#
# 处理：以 root 启动 → 修正挂载卷属主为 dsh → 降权到 dsh 用户运行。
# 这样无论宿主机目录权限如何，容器都能自动工作，无需手动 chmod。
set -e

# 修正挂载卷属主；目录不存在或属主已正确时跳过，避免每次启动递归 chown 大目录
for dir in /app/.dsh /workspace /data; do
  [ -d "$dir" ] || continue
  owner="$(stat -c %u "$dir" 2>/dev/null || echo '')"
  want="$(id -u dsh 2>/dev/null || echo '')"
  if [ -n "$owner" ] && [ -n "$want" ] && [ "$owner" != "$want" ]; then
    chown -R dsh:dsh "$dir" 2>/dev/null || true
  fi
done

# 打印的登录 URL：官方 --public-url 会把它用于启动日志行、DSH_WEB_URL 以及
# agent 上下文里的 "Current DeepSeek Harness Web GUI URL"。
# 容器无法知道自己被端口映射后的外部地址（NAS 上是 http://192.168.50.100:16200），
# 所以由 $DSH_LAN_URL 提供；未设置时完全不传该参数，保持官方原行为
# （打印容器内网地址）。这样官方源码零改动，上游重构不再影响构建。
#
# 取值校验：只接受 http(s):// 开头、且仅含 URL 安全字符的值；否则忽略并告警，
# 避免把 shell 元字符拼进下面的 su -c 命令串。
LAN_URL=''
if [ -n "${DSH_LAN_URL:-}" ]; then
  # 去掉可能的回车与首尾空白（.env 复制粘贴常见）
  DSH_LAN_URL="$(printf '%s' "$DSH_LAN_URL" | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
fi
if [ -n "${DSH_LAN_URL:-}" ]; then
  case "$DSH_LAN_URL" in
    http://*|https://*) ;;
    *)
      echo "entrypoint: DSH_LAN_URL 必须以 http:// 或 https:// 开头，已忽略：$DSH_LAN_URL" >&2
      DSH_LAN_URL=''
      ;;
  esac
fi
if [ -n "${DSH_LAN_URL:-}" ]; then
  # 用 tr 反选字符集做校验：case 模式里不能出现 & ; | ( ) 等元字符
  unsafe="$(printf '%s' "$DSH_LAN_URL" | tr -d 'A-Za-z0-9:/._~%&-' 2>/dev/null || printf 'x')"
  if [ -n "$unsafe" ]; then
    echo "entrypoint: DSH_LAN_URL 含不受支持的字符（仅允许字母 数字 : / . _ ~ % & -），已忽略：$DSH_LAN_URL" >&2
    DSH_LAN_URL=''
  fi
fi
[ -n "${DSH_LAN_URL:-}" ] && LAN_URL="--public-url $DSH_LAN_URL"
if [ -n "$LAN_URL" ]; then
  echo "entrypoint: 启动日志将显示外部可达地址 $DSH_LAN_URL（官方 --public-url）" >&2
fi

# 直接用 node 启动 dsh web，绕过 pnpm。
# package.json 里 "dsh": "node --import tsx/esm apps/cli/src/bin.ts"，
# 直接用 node 跑完全等价，但避免了 pnpm 的运行时依赖检查（会触发
# pnpm install -> ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY）。
# 也不需要 corepack 下载 pnpm，启动更快更稳定。
exec su -s /bin/sh dsh -c "export HOME=/app && cd /app && exec node --import tsx/esm apps/cli/src/bin.ts web --patch /app/docker-patch.yml $LAN_URL"
