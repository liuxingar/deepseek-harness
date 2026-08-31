# Fork 维护指南（同步官方上游）

本 fork（`liuxingar/deepseek-harness`）在官方 `deepseek-ai/deepseek-harness` 基础上做了 Docker/群晖部署相关改动。
**原则：不改动官方源码文件**，所有部署改动都放在 fork 独有文件里，官方代码的少量修改在镜像构建时注入。

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
| `Dockerfile` | 镜像构建（群晖/通用 amd64+arm64），构建时调用补丁脚本 |
| `docker-compose.yml` | 群晖部署编排 |
| `docker-patch.yml` | 运行配置：监听 0.0.0.0 + `/api` 信任围栏读环境变量 `DSH_TRUSTED_HOSTS` |
| `.env.example` | 环境变量模板 |
| `.dockerignore` | 构建排除 |
| `.github/workflows/docker-build.yml` | 唯一保留的 CI：push 自动构建镜像到 GHCR + 可选发邮件 |
| `README-docker-setup.md` | 部署说明 |
| `scripts/sync-upstream.sh` | 同步上游脚本 |
| `scripts/apply-lan-settings-patch.py` | 构建时给官方源码打补丁（局域网 settings 修复） |
| `entrypoint.sh` | 容器入口：启动时自动修正挂载卷属主（解决 NAS bind mount 目录 EACCES），再降权到 dsh 用户运行 |
| `docs/fork-maintenance.md` | 本文档 |

### 删除的官方文件（用户要求去掉无关构建）
官方原有一批 CI/发布 workflow（`ci.yml`、`e2e.yml`、`release*.yml`、`sandbox.yml`、`docs-pages.yml` 等）已删除，
只保留 `docker-build.yml`。同步时若官方更新这些文件，git 可能报冲突，保持删除即可。

### 官方源码修改（**不提交到 fork**，构建时注入）
**官方源码文件保持原样**，仅有的改动通过 Dockerfile 构建时调用 `scripts/apply-lan-settings-patch.py` 注入：

| 目标文件 | 注入内容 |
|---|---|
| `packages/client/ui-settings/src/client/index.ts` | 强制 settings 持久化为 `host`，使局域网（非 loopback）访问时模型/API key 配置可用 |

> 背景：官方默认只在 loopback（127.0.0.1）访问时启用 settings 持久化；
> 通过群晖局域网 IP 访问会降级为 memory 模式，报 "settings are unavailable in this browser"。
>
> 优点：fork 源码与官方一致，同步上游时**不会**对这个文件产生冲突；
> 构建时脚本精确替换，若官方重构该文件会明确报错提醒更新。

## 同步后自检清单（sync-upstream.sh 自动执行）

1. `docker-patch.yml` 存在，且 `!!js` 表达式是**双引号标量**（不是 flow 序列，否则启动失败）
2. 官方源码 `ui-settings/index.ts` 保持原样（含 `isLoopback` 原逻辑），由构建时脚本注入修复
3. `Dockerfile` 包含 `RUN python3 scripts/apply-lan-settings-patch.py` 和 `ENTRYPOINT ["/bin/sh", "/app/entrypoint.sh"]`
4. `.github/workflows/docker-build.yml` 存在（唯一保留的 CI）

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
