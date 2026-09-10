#!/usr/bin/env python3
"""构建时对官方源码应用“打印登录 URL”修复（保持官方源码不提交改动）。

背景：dsh web 默认打印的登录 URL 来自容器自己网卡采样的地址与容器内部端口
（例如桥接网络的 172.26.0.2:3080），局域网浏览器无法访问；端口映射后的
外部地址（如 http://192.168.50.100:16200）容器无从得知。
本补丁让环境变量 $DSH_LAN_URL 生效：
  - 设置时（例如 DSH_LAN_URL=http://192.168.50.100:16200），启动日志直接
    打印该可达地址（自动带上 ?token=...），不再打印无用的容器内网地址；
  - 未设置时完全保持官方原行为。
官方源码文件保持原样，只在构建产物里生效。

如果官方更新后找不到目标行，脚本会以非零退出，构建即失败并提示更新本脚本。
"""
from pathlib import Path
import sys

# 容器内路径（WORKDIR /app）
TARGET = Path('/app/packages/bundle/web-app/src/index.ts')

OLD = '''        const webUrl = localWebUrl(connectionCtx)
        const authenticatedUrl = connectionCtx.connection.authenticatedUrl(webUrl)
        // Reuse the exact LAN snapshot provided to the /api trust fence.
        const lanCandidate = runtime.lanAddresses[0]
        const port = connectionCtx.webServer.port
        const lanUrl = lanCandidate === undefined
          ? undefined
          : connectionCtx.connection.authenticatedUrl(`http://${lanCandidate}:${String(port)}`)
        ANNOUNCED_ROOTS.add(connectionCtx.root)
        if (config.printUrl) {
          console.log(`dsh web: ${authenticatedUrl}${lanUrl === undefined ? '' : ` (LAN: ${lanUrl})`}`)
        }'''

NEW = '''        const webUrl = localWebUrl(connectionCtx)
        const authenticatedUrl = connectionCtx.connection.authenticatedUrl(webUrl)
        // Fork patch: honor $DSH_LAN_URL (an externally reachable URL such as
        // http://192.168.50.100:16200) so the printed login line is usable from
        // a LAN browser instead of the container's own sampled addresses and
        // internal port (e.g. bridge 172.26.0.2:3080). Falls back to the
        // upstream behavior when unset.
        const configuredLanUrl = (process.env.DSH_LAN_URL ?? '').trim()
        // Reuse the exact LAN snapshot provided to the /api trust fence.
        const lanCandidate = runtime.lanAddresses[0]
        const port = connectionCtx.webServer.port
        const lanUrl = configuredLanUrl !== ''
          ? connectionCtx.connection.authenticatedUrl(configuredLanUrl)
          : lanCandidate === undefined
            ? undefined
            : connectionCtx.connection.authenticatedUrl(`http://${lanCandidate}:${String(port)}`)
        ANNOUNCED_ROOTS.add(connectionCtx.root)
        if (config.printUrl) {
          if (configuredLanUrl !== '') {
            console.log(`dsh web: ${lanUrl}`)
          } else {
            console.log(`dsh web: ${authenticatedUrl}${lanUrl === undefined ? '' : ` (LAN: ${lanUrl})`}`)
          }
        }'''


def main() -> int:
    if not TARGET.exists():
        print(f'[apply-lan-url] ERROR: {TARGET} not found', file=sys.stderr)
        return 1
    src = TARGET.read_text(encoding='utf-8')
    if OLD in src:
        src = src.replace(OLD, NEW)
        TARGET.write_text(src, encoding='utf-8')
        print('[apply-lan-url] OK: $DSH_LAN_URL support patched into web-app')
        return 0
    if NEW in src:
        print('[apply-lan-url] OK: already applied')
        return 0
    print('[apply-lan-url] ERROR: announceReady block not found; '
          'upstream may have refactored web-app. Update scripts/apply-lan-url-patch.py.',
          file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main())
