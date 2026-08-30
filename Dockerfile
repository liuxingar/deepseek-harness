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

# 安装依赖 + 构建
RUN pnpm install --frozen-lockfile && pnpm run build

# ---- 运行阶段（更小的最终镜像）----
FROM node:22-slim

RUN corepack enable && corepack prepare pnpm@11.7.0 --activate

# 运行时仍需要 git（部分插件操作会用到）
RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 只从 builder 阶段复制构建产物
COPY --from=builder /app /app

# 非 root 用户运行（安全加固）
RUN groupadd -r dsh && useradd -r -g dsh -d /app dsh && \
    chown -R dsh:dsh /app && \
    mkdir -p /workspace && chown dsh:dsh /workspace

USER dsh

# Web UI 默认端口
EXPOSE 3080

# 健康检查
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3080').then(r=>{if(!r.ok)throw r.status}).catch(()=>process.exit(1))"

# 启动命令：--patch 让 Web UI 监听 0.0.0.0，局域网才能访问
CMD ["pnpm", "dsh", "web", "--patch", "/app/docker-patch.yml"]
