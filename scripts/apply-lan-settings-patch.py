#!/usr/bin/env python3
"""构建时对官方源码应用局域网 settings 修复（保持官方源码不提交改动）。

背景：官方 dsh 默认只在 loopback(127.0.0.1) 访问时启用 settings 持久化，
通过局域网 IP（如 192.168.50.100）访问会降级为 memory 模式，导致模型设置页
报 "settings are unavailable in this browser"。
本脚本在镜像构建时把 persistence 强制设为 host，使局域网访问也能配置模型/API key。
官方源码文件保持原样，只在构建产物里生效。

如果官方更新后找不到目标行，脚本会以非零退出，构建即失败并提示更新本脚本。
"""
from pathlib import Path
import sys

# 容器内路径（WORKDIR /app）
TARGET = Path('/app/packages/client/ui-settings/src/client/index.ts')

OLD = "  const persistence = ctx.remote.$host.isLoopback ? 'host' : 'memory'"
NEW = "  const persistence: 'host' | 'memory' = 'host'"


def main() -> int:
    if not TARGET.exists():
        print(f'[apply-lan-settings] ERROR: {TARGET} not found', file=sys.stderr)
        return 1
    src = TARGET.read_text(encoding='utf-8')
    if OLD in src:
        src = src.replace(OLD, NEW)
        TARGET.write_text(src, encoding='utf-8')
        print('[apply-lan-settings] OK: settings persistence forced to host')
        return 0
    if NEW in src:
        print('[apply-lan-settings] OK: already applied')
        return 0
    print('[apply-lan-settings] ERROR: persistence line not found; '
          'upstream may have refactored this file. Update scripts/apply-lan-settings-patch.py.',
          file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main())
