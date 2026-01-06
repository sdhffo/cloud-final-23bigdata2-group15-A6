# 云计算技术期末大作业：Docker 镜像构建与管理项目
## 项目总览
本项目聚焦 Docker 镜像的规范化构建、灵活配置与版本管理，旨在解决传统应用部署中环境不一致、版本混乱、部署繁琐等核心问题。基于 Python Flask 框架实现 Web 应用容器化封装，通过 Dockerfile 定义构建流程、环境变量与端口映射实现动态配置、镜像标签与 Registry 实现版本管控，并通过多阶段构建优化镜像体积，最终达成应用的快速部署、环境一致性保障与可追溯版本管理。

项目不涉及容器编排平台（如 Docker Swarm/K8s）、CI/CD 自动构建流水线及自定义镜像仓库开发，专注于核心镜像构建与管理能力的实现。

## 项目结构
```
cloud-final-23bigdata2-group15-A6/
├── README.md                  # 项目总说明（功能、部署、结构）
├── report/
│   └── 《云计算技术》期末大作业报告.md  # 完整实验报告
├── slides/
│   └── 答辩PPT.pdf            # 答辩演示文稿
├── src/
│   ├── PyDockerManager/       # Python-Docker 一体化管理工具
│   │   ├── app.py             # Python 业务代码入口（Flask应用）
│   │   ├── docker-manager.conf  # 多环境配置文件（镜像名、端口等）
│   │   ├── docker-manager-utils.sh  # 工具函数库（依赖安装、日志输出）
│   │   └── python-docker-manager.sh  # 主脚本入口（命令解析、逻辑分发）
│   └── docker-demo/           # Docker 演示案例（Flask应用）
│       ├── app.py             # 演示应用主程序
│       ├── Dockerfile         # 基础镜像构建文件
│       ├── Dockerfile.slim    # 多阶段构建瘦身镜像文件
│       ├── manage-flask.sh    # 镜像瘦身效果验证脚本
│       └── requirements.txt   # Python 依赖清单
└── assets/                    # 项目截图、拓扑图、日志片段等资源
```

## 核心功能
### 1. 镜像规范化构建
- 基于 Dockerfile 实现 Python Flask 应用的容器化封装，遵循分层构建最佳实践
- 支持多阶段构建（Dockerfile.slim），将镜像体积从 97MB 优化至 86.1MB
- 基础镜像选用官方安全镜像（python:3.9-alpine），避免高危漏洞组件

### 2. 容器灵活配置
- 环境变量注入：支持动态配置应用名称、端口、日志级别等参数
- 端口映射：可自定义宿主机与容器端口映射关系
- 目录挂载：支持主机目录实时同步（开发环境代码热更新）与命名卷挂载（日志数据持久化）

### 3. 镜像版本管理
- 遵循语义化版本规范的标签策略：`应用名:主版本号.次版本号.修订号-环境标识`（如 `docker-demo:1.0.0-dev`）
- 支持多标签管理（如开发版、测试版、生产版）与版本回滚
- 兼容本地 Registry 镜像推送/拉取，实现版本存储与共享

### 4. 一体化管理工具
提供 `PyDockerManager` 轻量化工具，支持：
- 环境自动化部署（Docker 安装、镜像源配置、依赖补全）
- 镜像构建、推送、拉取、删除与容器全生命周期管理（启动、停止、日志查看）
- 多环境隔离（dev/prod 等）、资源统计与批量操作

## 快速开始
### 前置条件
#### 硬件要求
- 处理器：Intel Core i5 及以上或同等性能 AMD 处理器
- 内存：≥ 4GB（推荐 8GB 及以上，确保容器运行流畅）
- 存储空间：≥ 30GB 可用磁盘空间（用于存储基础镜像、构建产物及依赖）
- 网络环境：可访问互联网（用于拉取基础镜像、依赖包及配置镜像源）

#### 软件环境
- 操作系统：支持 Linux（Ubuntu 20.04 LTS 及以上、CentOS 7 及以上等）、macOS（10.15 及以上）、Windows 10/11（需启用 WSL2 或 Docker Desktop）
- 核心软件：Docker 20.0 及以上版本、Docker Compose v2.0 及以上版本
- 依赖组件：Python 3.7 及以上（基础镜像内置，本地环境可选）、Git（用于代码仓库克隆）

#### 权限要求
-  Linux/macOS：具备 sudo 权限（用于安装 Docker、配置系统环境）
-  Windows：使用管理员权限运行 Docker Desktop 或 WSL2 终端

### 环境准备
1. 克隆代码仓库
```bash
git clone https://github.com/sdhffo/cloud-final-23bigdata2-group15-A6.git
cd cloud-final-23bigdata2-group15-A6
```

2. 一键安装 Docker（若未安装）
```bash
# Linux/macOS 一键安装脚本
curl -fsSL https://get.docker.com -o install-docker.sh
sudo sh install-docker.sh

# Windows 用户：直接下载 Docker Desktop 安装（https://www.docker.com/products/docker-desktop/）

# 配置用户免 sudo 执行 Docker 命令（Linux/macOS，需重新登录终端生效）
sudo usermod -aG docker $USER
newgrp docker
```

3. 配置 Docker 国内镜像源（加速镜像拉取）
```bash
# Linux/macOS 配置方式
sudo vim /etc/docker/daemon.json

# Windows/macOS：通过 Docker Desktop 图形界面配置（设置 -> Docker Engine）
```
粘贴以下配置并重启 Docker：
```json
{
    "registry-mirrors": [
        "https://docker.m.daocloud.io",
        "https://docker.1panel.live",
        "https://hub.rat.dev",
        "https://mirror.ccs.tencentyun.com"
    ]
}
```
```bash
# Linux/macOS 重启 Docker
sudo service docker restart

# Windows/macOS：在 Docker Desktop 中点击重启按钮
```

### 核心功能使用
#### 1. 基础镜像构建与运行（快速验证）
```bash
# 进入演示案例目录
cd src/docker-demo
# 构建基础镜像（标签：docker-demo:v1.0）
docker build -t docker-demo:v1.0 .
# 启动容器（环境变量注入+端口映射）
docker run -d -p 8080:5000 -e APP_NAME="MyDockerApp" --name demo-container docker-demo:v1.0
# 访问应用（浏览器打开或 curl）
curl http://localhost:8080
```

#### 2. 镜像瘦身验证（使用专用脚本）
```bash
# 赋予脚本执行权限（Linux/macOS）
chmod +x manage-flask.sh
# Windows 用户：在 WSL2 或 Git Bash 中执行
# 一键构建基础镜像与瘦身镜像
./manage-flask.sh build
# 启动瘦身镜像容器（端口 8081）
./manage-flask.sh start
# 查看镜像体积对比
./manage-flask.sh status
# 停止并清理容器/镜像
./manage-flask.sh stop
```

#### 3. 一体化管理工具使用（PyDockerManager）
```bash
# 进入工具目录
cd src/PyDockerManager
# 赋予脚本执行权限（Linux/macOS）
chmod +x python-docker-manager.sh docker-manager-utils.sh
# Windows 用户：在 WSL2 或 Git Bash 中执行
# 初始化环境（生成依赖文件、Dockerfile）
./python-docker-manager.sh init
# 构建 dev 环境镜像
./python-docker-manager.sh --env dev build
# 启动 prod 环境容器（端口映射可在配置文件定义）
./python-docker-manager.sh --env prod start
# 查看容器日志
./python-docker-manager.sh --env dev logs
# 推送镜像到本地 Registry
./python-docker-manager.sh --env dev push
# 查看所有容器状态
./python-docker-manager.sh list-containers
```

## 关键技术要点
1. **Dockerfile 最佳实践**：利用层缓存（先复制依赖文件再安装）、去缓存安装（`--no-cache-dir`）、合并 RUN 指令减少镜像层
2. **多阶段构建**：分离构建阶段（安装依赖）与运行阶段（仅保留运行时），结合 Alpine 基础镜像实现瘦身
3. **版本管理策略**：语义化标签 + 环境标识 + 仓库适配标签，确保版本可追溯、环境隔离
4. **容器配置灵活度**：通过 `-e`（环境变量）、`-p`（端口映射）、`-v`（目录挂载）实现动态调整，适配不同场景

## 验证用例
| 功能                | 操作命令                                                                 | 验证方式                                  |
|---------------------|--------------------------------------------------------------------------|-------------------------------------------|
| 基础镜像运行        | `docker run -p 8080:5000 docker-demo:v1.0`                               | 访问 http://localhost:8080 显示默认页面    |
| 环境变量注入        | `docker run -p 8080:5000 -e APP_NAME="TestApp" docker-demo:v1.0`          | 页面显示 "Hello from TestApp"             |
| 端口映射            | `docker run -p 8081:5000 docker-demo:v1.0`                               | 访问 http://localhost:8081 正常响应       |
| 代码热更新          | `docker run -p 8080:5000 -v $(pwd):/app docker-demo:v1.0`                 | 修改本地 app.py 后刷新页面生效            |
| 版本切换            | `docker tag docker-demo:v1.0 docker-demo:v1.0-test && docker run docker-demo:v1.0-test` | 新标签镜像正常运行                        |
| 镜像瘦身效果        | `docker build -f Dockerfile.slim -t docker-demo:v1.0-slim .`              | `docker images` 查看体积（≈86.1MB）       |

## 常见问题与排错
1. **依赖安装速度慢/超时**：Dockerfile 中已配置清华大学镜像源，若仍有问题可检查网络或更换 `daemon.json` 中的 Docker 镜像源
2. **容器启动后无法访问**：确保 Flask 应用绑定 `host='0.0.0.0'`（已在 app.py 中配置），且端口映射正确（`-p 宿主机端口:5000`）
3. **代码修改后不生效**：开发环境需开启 Flask 调试模式（`debug=True`），并通过 `-v` 挂载主机目录，确保文件同步后应用自动重载
4. **镜像推送 Registry 失败**：确认本地 Registry 已启动（`docker run -d -p 5000:5000 registry:2`），镜像标签包含仓库地址前缀（如 `localhost:5000/docker-demo:v1.0`）

## 项目成员与分工
| 成员       | 学号         | 负责模块                     | 核心贡献                                 |
|------------|--------------|------------------------------|------------------------------------------|
| 王公泽     | 2362160044   | 脚本程序、PPT、答辩          | 编写 manage-flask.sh、协助制作PPT、现场答辩 |
| 沈旭涛     | 2362160045   | 脚本程序、实验报告、验证与排错 | 编写 PyDockerManager、撰写实验报告、问题排查 |
| 徐兢男     | 2362160046   | 实验程序、PPT                | 编写 Dockerfile、制作答辩PPT              |
| 沈浩男     | 2362160047   | 环境搭建、实验程序           | 搭建实验环境、编写容器运行相关命令        |

## 参考资料
1. 《Docker 实战》第 3 章：Docker 镜像构建（人民邮电出版社）
2. Docker 官方文档：Dockerfile 参考（https://docs.docker.com/engine/reference/builder/）
3. Docker Compose 官方文档：环境变量配置（https://docs.docker.com/compose/environment-variables/）

## 代码仓库地址
https://github.com/sdhffo/cloud-final-23bigdata2-group15-A6
