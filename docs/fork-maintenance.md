# Fork 维护指南（同步官方上游）

本 fork（`liuxingar/deepseek-harness`）在官方 `deepseek-ai/deepseek-harness` 基础上做了 Docker/群晖部署相关改动。
**原则：官方源码零改动**，所有部署改动都放在 fork 独有文件里；早期那种「构建时给官方源码打补丁」的做法已全部弃用。

## 为什么需要维护

官方仓库会持续更新。你希望"官方有更新 → 更新 fork → 自动构建新镜像"。
fork 的独有改动不会自动跟随官方，同步时可能需要处理。

## 同步官方上游（一条命令）

```bash
bash scripts/sync-upstream.sh
```

脚本会：拉取官方 master → 合并 → 自检关键改动 → 推送 fork（触发 GitHub Actions 自动构建）。

## Fork 独有改动清单

### 新增文件（官方没有，merge 时 git 自动保留，不会冲突）
| 文件 | 作用 |
|---|---|
| `Dockerfile` | 镜像构建（群晖/通用 amd64+arm64），基于官方源码零改动构建 |
| `docker-compose.yml` | 群晖部署编排（含 `DSH_LAN_URL` 透传） |
| `docker-patch.yml` | 运行配置：监听 0.0.0.0 + `/api` 信任围栏读环境变量 `DSH_TRUSTED_HOSTS` |
| `.env.example` | 环境变量模板 |
| `.dockerignore` | 构建排除 |
| `.github/workflows/docker-build.yml` | 唯一保留的 CI：push 自动构建镜像到 GHCR + 可选发 MeoW 通知 |
| `README-docker-setup.md` | 部署说明 |
| `scripts/sync-upstream.sh` | 同步上游脚本 |
| `entrypoint.sh` | 容器入口：启动时自动修正挂载卷属主（解决 NAS bind mount 目录 EACCES），把 `$DSH_LAN_URL` 作为官方 `--public-url` 传入，再降权到 dsh 用户运行 |
| `docs/fork-maintenance.md` | 本文档 |

### 删除的官方文件（用户要求去掉无关构建）
官方原有一批 CI/发布 workflow（`ci.yml`、`e2e.yml`、`release*.yml`、`sandbox.yml`、`docs-pages.yml` 等）已删除，
只保留 `docker-build.yml`。同步时若官方更新这些文件，git 可能报冲突，保持删除即可。

### 官方源码零改动（曾用构建期补丁，现已弃用）

两个构建期源码补丁脚本（`scripts/apply-lan-settings-patch.py`、`scripts/apply-lan-url-patch.py`）已删除，
原因：官方已原生提供等价能力，逐字匹配官方源码的补丁会随上游重构反复失效（2026-10-03、2026-10-15 各一次失败）。

| 原补丁目的 | 官方原生能力 | 现在的做法 |
|---|---|---|
| 局域网（非 loopback）访问时 settings 降级为 memory，模型设置页不可用 | 上游 2026-10-09 `23c29d067`（PR #4201）：**任何已认证浏览器**都通过 Host 文档持久化，不再按 loopback 区分 | 无需任何处理 |
| 启动日志打印容器内网地址（如 172.26.0.2:3080），局域网打不开 | 上游 2026-09-30 `a7c3ad99b`：`--public-url` 指定对外广告地址（用于日志行、`DSH_WEB_URL`、agent 上下文） | `entrypoint.sh` 读取 `$DSH_LAN_URL` 后传 `--public-url`；未设置则不传，保持官方行为 |

> 这样上游重构 `packages/client/ui-settings` 或 `packages/bundle/web-app` 时，构建不再失败。

## 同步后自检清单（sync-upstream.sh 自动执行）

1. `docker-patch.yml` 存在，且 `!!js` 表达式是**双引号标量**（不是 flow 序列，否则启动失败）
2. `Dockerfile` 不含任何构建期源码补丁调用（`apply-lan-*`）
3. 上游仍具备两项原生能力：ui-settings 不再按 loopback 区分持久化；web-app 支持 `--public-url`（`startup.ts` + `index.ts`）
4. `entrypoint.sh` 通过 `--public-url` 传入 `$DSH_LAN_URL`
5. `.github/workflows/docker-build.yml` 存在（唯一保留的 CI）

自检未通过时脚本会暂停推送（`exit 1`），需人工确认后再 `git add -A && git push origin master`。

## 群晖部署常见问题

### EACCES: permission denied, mkdir '/app/.dsh/profiles/web'（容器崩溃重启）
原因：NAS 上挂载到 `/app/.dsh` 的目录归 root 所有，容器内 dsh 用户无写权限。
镜像已内置 `entrypoint.sh` 启动时自动 `chown` 修正，**新镜像无需手动处理**。
若使用旧镜像，可手动执行：`chmod -R 777 <data目录> <workspace目录>` 后重建容器。

### pull 镜像很大 / 每次下载两个大文件
镜像已做瘦身优化（`Dockerfile`）：
1. `COPY --from=builder --chown=dsh:dsh /app /app` 替代"复制后再 `chown -R /app`"——后者会产生与 COPY 层几乎一样大的额外镜像层
2. 构建后清理运行时不需要的内容（tests/快照/e2e/website/docs/sourcemap/缓存）
同步官方后重建镜像体积明显变小，pull 更快。

### 启动日志里的 URL 是 172.x/容器内网地址，局域网打不开
说明容器没拿到 `DSH_LAN_URL`。检查 `.env` 里是否设置（例如 `DSH_LAN_URL=http://192.168.50.100:16200`，
即「宿主 IP + compose 里映射的宿主端口」），以及 `docker-compose.yml` 的 `environment` 是否透传该变量。
设置后重新 `docker compose up -d`，启动日志的第一行 `dsh web: ...` 会变成该可达地址（自动带 `?token=...`）。

### 构建失败为什么没人发现
`docker-build.yml` 的 `Notify MeoW` 只在「定时同步 + 有上游更新 + 构建成功」时发通知。
如需失败也通知，需要另加一个 `if: failure()` 的 MeoW 步骤。
