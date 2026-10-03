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

上游 2026-09-30 提交 a7c3ad99b（feat(web): advertise a configured public
application URL）把 announceReady 里的 webUrl 由 localWebUrl(connectionCtx)
改成了 appRootUrl(connectionCtx, publicUrl)。本脚本同时兼容两种布局：
先按当前布局匹配，再回退旧布局；都匹配不到才以非零退出，构建失败并提示更新。

如果官方更新后找不到目标行，脚本会以非零退出，构建即失败并提示更新本脚本。
"""
from pathlib import Path
import sys

# 容器内路径（WORKDIR /app）
TARGET = Path('/app/packages/bundle/web-app/src/index.ts')

# 已打过补丁的标记（任何变体都含这一行）
MARKER = '// Fork patch: honor $DSH_LAN_URL'

# 补丁正文模板：{WEB_URL} 占位，用 str.replace 注入，避免 str.format 与
# JS 模板字符串里的花括号冲突。
NEW_TEMPLATE = '''        const webUrl = {WEB_URL}
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
        const lanUrl = lanCandidate === undefined
          ? undefined
          : connectionCtx.connection.authenticatedUrl(`http://${lanCandidate}:${String(port)}`)
        ANNOUNCED_ROOTS.add(connectionCtx.root)
        if (config.printUrl) {
          if (configuredLanUrl !== '') {
            console.log(`dsh web: ${connectionCtx.connection.authenticatedUrl(configuredLanUrl)}`)
          } else {
            console.log(`dsh web: ${authenticatedUrl}${lanUrl === undefined ? '' : ` (LAN: ${lanUrl})`}`)
          }
        }'''

_TAIL = '''        ANNOUNCED_ROOTS.add(connectionCtx.root)
        if (config.printUrl) {
          console.log(`dsh web: ${authenticatedUrl}${lanUrl === undefined ? '' : ` (LAN: ${lanUrl})`}`)
        }'''


def _old_block(web_url_expr: str) -> str:
    return f'''        const webUrl = {web_url_expr}
        const authenticatedUrl = connectionCtx.connection.authenticatedUrl(webUrl)
        // Reuse the exact LAN snapshot provided to the /api trust fence.
        const lanCandidate = runtime.lanAddresses[0]
        const port = connectionCtx.webServer.port
        const lanUrl = lanCandidate === undefined
          ? undefined
          : connectionCtx.connection.authenticatedUrl(`http://${{lanCandidate}}:${{String(port)}}`)
''' + _TAIL


# 视为候选的官方布局：先当前布局，后上游 1.0 之前（a7c3ad99b 之前）的布局
LAYOUTS = (
    ('current', 'appRootUrl(connectionCtx, publicUrl)'),
    ('legacy', 'localWebUrl(connectionCtx)'),
)


def main() -> int:
    if not TARGET.exists():
        print(f'[apply-lan-url] ERROR: {TARGET} not found', file=sys.stderr)
        return 1
    src = TARGET.read_text(encoding='utf-8')
    if MARKER in src:
        print('[apply-lan-url] OK: already applied')
        return 0
    for name, web_url_expr in LAYOUTS:
        old = _old_block(web_url_expr)
        if old in src:
            src = src.replace(old, NEW_TEMPLATE.replace('{WEB_URL}', web_url_expr), 1)
            TARGET.write_text(src, encoding='utf-8')
            print(f'[apply-lan-url] OK: $DSH_LAN_URL support patched into web-app ({name} layout)')
            return 0
    print('[apply-lan-url] ERROR: announceReady block not found (tried: '
          + ', '.join(name for name, _ in LAYOUTS) + '); '
          'upstream may have refactored web-app. Update scripts/apply-lan-url-patch.py.',
          file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main())
