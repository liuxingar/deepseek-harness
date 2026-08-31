# DeepSeek Harness (dsh) Docker 镜像
# 用于 GitHub Actions 自动构建，推送到 GHCR
# 参考官方仓库 https://github.com/deepseek-ai/deepseek-harness

# ---- 构建阶段 ----
FROM node:22-slim AS builder

# node-pty 等原生模块编译需要 python3 / make / g++
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 make g++ git && \
    rm -rf /var/lib/apt/lists/*

# 启用 corepack 并锁定 pnpm 版本
# 注意：如果上游 package.json 的 packageManager 字段升级了 pnpm，需同步更新此行
RUN corepack enable && corepack prepare pnpm@11.7.0 --activate

WORKDIR /app

# 复制全部源码（.dockerignore 控制排除项）
COPY . .

# 构建脚本 scripts/build.ts 会调用 git rev-parse HEAD 获取 commit hash 注入前端版本信息，
# 但 .dockerignore 排除了 .git 目录，导致容器内无 git 仓库而构建失败。
# 这里初始化一个临时 git 仓库并创建一个空 commit，使 git rev-parse HEAD 能返回 hash。
RUN git init && \
    git config user.email "build@local" && \
    git config user.name "build" && \
    git commit --allow-empty -m "snapshot"

# 应用 fork 专属补丁：官方源码保持原样，仅在构建产物里注入局域网 settings 修复
# （通过局域网 IP 访问时 settings 持久化强制为 host，否则模型设置页不可用）
RUN python3 scripts/apply-lan-settings-patch.py

# 安装依赖 + 构建
RUN pnpm install --frozen-lockfile && pnpm run build

# 减小最终镜像体积：构建产物就绪后清理运行时不需要的内容
# （测试/快照/文档/website 源码/sourcemap/缓存。dsh 用 tsx 跑源码，
#  这些只在开发/测试用，删掉不影响运行，能显著减小 pull 下载量）
RUN find /app -type d \( -name tests -o -name '__snapshots__' -o -name 'e2e' -o -name 'fixtures' \) -prune -exec rm -rf {} + ; \
    find /app -type f \( -name '*.spec.ts' -o -name '*.test.ts' -o -name '*.e2e.ts' -o -name '*.map' \) -delete ; \
    rm -rf /app/website /app/docs /app/.github ; \
    find /app/node_modules -type d -name '.cache' -prune -exec rm -rf {} + ; \
    true

# ---- 运行阶段（更小的最终镜像）----
FROM node:22-slim

RUN corepack enable && corepack prepare pnpm@11.7.0 --activate

# 运行时仍需要 git（部分插件操作会用到）
RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*

# 先创建 dsh 用户（COPY --chown 需要目标用户已存在）
RUN groupadd -r dsh && useradd -r -g dsh -d /app dsh && \
    mkdir -p /workspace && chown dsh:dsh /workspace

# 只从 builder 阶段复制构建产物；COPY 时直接设置属主为 dsh。
# 注意：不能在 COPY 后再 chown -R /app——那会产生一个与 COPY 层
# 几乎一样大的额外镜像层（每次 pull 都要下载两个大文件的原因）。
WORKDIR /app
COPY --from=builder --chown=dsh:dsh /app /app

# 入口脚本：以 root 启动 → 修正挂载卷属主（NAS bind mount 会遮蔽镜像内 chown，
# 导致 dsh 用户对 /app/.dsh 无写权限而 EACCES）→ 降权到 dsh 用户运行
COPY entrypoint.sh /app/entrypoint.sh

# Web UI 默认端口
EXPOSE 3080

# 健康检查：只要求服务有 HTTP 响应即可（dsh web 根路径需要 token 才返回 2xx，
# 无 token 会返回 401/404，但说明服务在运行，视为健康）
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:3080').catch(()=>process.exit(1))"

# 入口脚本负责修正挂载卷权限并以 dsh 用户启动 dsh web
# （--patch 让 Web UI 监听 0.0.0.0，局域网才能访问）
ENTRYPOINT ["/bin/sh", "/app/entrypoint.sh"]
