# DeepSeek Harness — Fork + GitHub Actions 自动构建镜像方案

通过 Fork 官方仓库、加入 Docker 文件、用 GitHub Actions 自动构建并推送到 GHCR，NAS 直接拉镜像运行。官方更新后，同步 Fork 即自动构建新镜像。

## 一、整体流程

```
官方仓库 deepseek-ai/deepseek-harness
        │  (你 Fork)
        ▼
你的 Fork (master 分支，含 Dockerfile / docker-patch.yml / .dockerignore / .github/workflows/)
        │  push / 每天定时同步上游
        ▼
GitHub Actions 自动构建 (amd64 + arm64)
        │
        ▼
GHCR 镜像  ghcr.io/你的用户名/deepseek-harness:latest
        │  (NAS docker pull)
        ▼
NAS 上 docker compose up -d 运行
```

## 二、首次设置步骤

### 1. Fork 官方仓库
打开 https://github.com/deepseek-ai/deepseek-harness ，点右上角 **Fork**，创建到你自己的 GitHub 账号下。

### 2. 把本目录的文件加入你的 Fork
把以下文件复制到你 Fork 仓库的根目录：
- `Dockerfile`
- `docker-patch.yml`
- `.dockerignore`
- `.github/workflows/docker-build.yml`

> `docker-compose.yml` 和 `.env.example` 是 NAS 上用的，不需要提交到 Fork（可选提交）。

可以用网页上传，或：
```bash
git clone https://github.com/你的用户名/deepseek-harness.git
cd deepseek-harness
# 复制上述文件到这里
git add -A
git commit -m "add docker build workflow"
git push
```

### 3. 开启 GitHub Actions 权限
进入你的 Fork 仓库 → **Settings** → **Actions** → **General**：
- **Workflow permissions** 选 **Read and write permissions**（允许同步上游时 push 到 master）
- 保存

### 4. 首次手动触发构建
进入仓库 → **Actions** → 左侧选 **Build and Push Docker Image** → 右侧 **Run workflow** → 选 master 分支 → 运行。

构建约 10–20 分钟（多架构 arm64 较慢）。成功后在仓库主页右侧 **Packages** 能看到镜像。

### 5. 把 GHCR 包设为公开（可选但推荐）
默认 GHCR 包是 private。NAS 匿名拉取需要公开：
- 进入 **Packages** → 点 `deepseek-harness` → 底部 **Package settings** → **Change package visibility** → 选 **Public**。
- 或者保持 private，在 NAS 上 `docker login ghcr.io -u 你的用户名 -p 你的PAT` 后再拉。

## 三、日常更新（两种方式）

### 方式 A：手动一键同步（推荐，可控）
在你的 Fork 仓库主页，分支名旁边会出现 **Sync fork** 按钮（当上游有更新时），点 **Update branch**，push 到 master 后 Actions 自动构建新镜像。

### 方式 B：定时自动同步（全自动）
工作流已配置每天北京时间 11:00 自动 `git merge upstream/master` 并构建。如果合并冲突，会跳过并发 warning，需要你手动处理。

> 注意：GitHub Actions 用 `GITHUB_TOKEN` push 不会再次触发工作流（防循环），所以定时任务里同步和构建在同一个 job 里完成。

## 四、NAS 上部署（拉镜像，无需构建）

1. 在 NAS 上建一个目录，例如 `docker/dsh`。
2. 把 `docker-compose.yml` 和 `.env.example` 放进去，`.env.example` 改名为 `.env` 并填入你的 API Key 和工作区路径。
3. 编辑 `docker-compose.yml`，把 `image: ghcr.io/你的GitHub用户名/deepseek-harness:latest` 里的用户名改成你的 GitHub 用户名（小写）。
4. 启动：
   ```bash
   docker compose pull
   docker compose up -d
   ```
5. 浏览器打开 `http://NAS的IP:3080`。

以后更新镜像：
```bash
docker compose pull
docker compose up -d
```

## 五、注意事项

| 事项 | 说明 |
|------|------|
| 上游处于开发者预览 | 可能有破坏性变更；自动构建 latest 可能拉到不稳定版本。生产环境建议用 `ghcr.io/用户名/deepseek-harness:<commit-sha>` 固定版本 |
| pnpm 版本 | Dockerfile 里 pin 了 `pnpm@11.7.0`；如果上游 `package.json` 的 `packageManager` 字段升级，需同步更新 Dockerfile 里的版本，否则构建可能失败 |
| 构建时间 | 多架构（amd64+arm64）构建约 10–20 分钟；如果你的 NAS 是 x86，可以把 workflow 里 `platforms` 改成只 `linux/amd64` 加速 |
| Actions 额度 | 公开仓库免费；私有仓库有每月分钟数限制。Fork 公开仓库默认是公开的 |
| 合并冲突 | 上游未来如果也加了 Dockerfile 等同名文件，定时同步可能冲突，需手动处理 |
| 镜像标签 | 同时打 `latest`、`commit-sha`、`master` 三个标签，方便回滚 |

## 六、文件清单

| 文件 | 用途 | 提交到 Fork? |
|------|------|-------------|
| `Dockerfile` | 镜像构建定义 | ✅ 必须 |
| `docker-patch.yml` | 让 Web UI 监听 0.0.0.0 | ✅ 必须 |
| `.dockerignore` | 构建上下文排除 | ✅ 必须 |
| `.github/workflows/docker-build.yml` | GitHub Actions 自动构建+同步 | ✅ 必须 |
| `docker-compose.yml` | NAS 拉镜像运行 | ❌ NAS 用（可选提交） |
| `.env.example` | NAS 环境变量模板 | ❌ NAS 用（可选提交） |
