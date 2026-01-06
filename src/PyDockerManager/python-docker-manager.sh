#!/bin/bash
set -euo pipefail

## ===================== 自动安装Docker（核心新增） =====================
install_docker() {
    echo -e "\033[0;34m[INFO]\033[0m 检测Docker环境..."
    if command -v docker &> /dev/null && docker --version &> /dev/null; then
        echo -e "\033[0;32m[SUCCESS]\033[0m Docker已安装（版本：$(docker --version | awk '{print $3}')）"
        
        # 修复：完整加载工具函数文件（提前处理权限）
        if [ -f "./docker-manager-utils.sh" ]; then
            # 临时赋予工具函数文件读权限（避免权限不足）
            chmod +r ./docker-manager-utils.sh
            # 完整加载工具函数（包含颜色配置和日志函数）
            source ./docker-manager-utils.sh
            # 调用镜像源配置（仅首次询问）
            configure_docker_mirror
        fi
        return 0
    fi

    # 未检测到Docker，开始自动安装
    echo -e "\033[1;33m[WARN]\033[0m 未检测到Docker，开始自动安装最新版..."
    # 下载官方安装脚本
    if ! curl -fsSL https://get.docker.com -o install-docker.sh; then
        echo -e "\033[0;31m[ERROR]\033[0m 下载Docker安装脚本失败，请检查网络"
        exit 1
    fi
    # 执行安装脚本（需要sudo权限）
    if ! sudo sh install-docker.sh; then
        echo -e "\033[0;31m[ERROR]\033[0m Docker安装失败，请手动安装（参考：https://docs.docker.com/get-docker/）"
        rm -f install-docker.sh
        exit 1
    fi
    # 删除安装脚本
    rm -f install-docker.sh
    # 配置当前用户免sudo使用Docker（需重新登录生效）
    sudo usermod -aG docker "$USER"
    echo -e "\033[0;32m[SUCCESS]\033[0m Docker安装完成！"
    
    # 安装后调用镜像源配置（仅首次询问）
    if [ -f "./docker-manager-utils.sh" ]; then
        source ./docker-manager-utils.sh
        configure_docker_mirror
    fi
    
    echo -e "\033[1;33m[WARN]\033[0m 需重新登录终端，使Docker用户组配置生效"
    exit 0
}

# 优先执行Docker检测与安装
install_docker

## ===================== 加载工具函数 =====================
# 检查工具函数文件是否存在
if [ ! -f "./docker-manager-utils.sh" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m 工具函数文件不存在：./docker-manager-utils.sh"
    exit 1
fi
# 加载工具函数
source ./docker-manager-utils.sh
# 自动安装bc工具（体积统计依赖）
install_bc

## ===================== 解析命令行参数 =====================
# 默认值
ENV_NAME="default"
COMMAND=""
# 命名参数默认值（会覆盖配置文件）
IMAGE_NAME_OVERRIDE=""
TAG_OVERRIDE=""
CONTAINER_NAME_OVERRIDE=""
PORT_MAP_OVERRIDE=""
# 批量操作参数
BATCH_DIR="./"
BATCH_LIST_FILE="./image-list.txt"

# 解析参数（新增批量操作参数）
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)
            ENV_NAME="$2"
            shift 2
            ;;
        --image)
            IMAGE_NAME_OVERRIDE="$2"
            shift 2
            ;;
        --tag)
            TAG_OVERRIDE="$2"
            shift 2
            ;;
        --container)
            CONTAINER_NAME_OVERRIDE="$2"
            shift 2
            ;;
        --port)
            PORT_MAP_OVERRIDE="$2"
            shift 2
            ;;
        --dir)
            BATCH_DIR="$2"
            shift 2
            ;;
        --list-file)
            BATCH_LIST_FILE="$2"
            shift 2
            ;;
        # 命令入口
        init|build|start|stop-container|rm-container|logs|status|list-containers|list-images|rm-image|clean|info|push|pull|update-container|batch-load-images|batch-save-images)
            COMMAND="$1"
            shift
            ;;
        *)
            log_error "无效参数：$1，执行 ./python-docker-manager.sh info 查看使用指南"
            ;;
    esac
done

# 检查是否指定了命令
if [ -z "${COMMAND}" ]; then
    echo -e "${BLUE}===== Python Docker 管理脚本（增强版） =====${NC}\n"
    echo "基础使用方式：$0 [--env 环境名] 命令 [--image 镜像名] [--tag 标签] [--container 容器名] [--port 端口映射]"
    echo "  核心命令示例："
    echo "    $0 --env dev push                # 推送镜像到仓库"
    echo "    $0 --env prod update-container   # 更新容器"
    echo "    $0 batch-load-images --dir ./images  # 批量加载镜像"
    echo "  执行 $0 info 查看完整使用指南"
    exit 1
fi

## ===================== 加载配置并覆盖参数 =====================
# 加载配置文件
load_config "${ENV_NAME}" "./docker-manager.conf"

# 命名参数覆盖配置文件（优先级：命名参数 > 配置文件 > 默认值）
if [ -n "${IMAGE_NAME_OVERRIDE}" ]; then
    export IMAGE_NAME="${IMAGE_NAME_OVERRIDE}"
    export REMOTE_IMAGE_TAG="${REMOTE_REGISTRY}/${IMAGE_NAME}:${TAG}"
fi
if [ -n "${TAG_OVERRIDE}" ]; then
    export TAG="${TAG_OVERRIDE}"
    export REMOTE_IMAGE_TAG="${REMOTE_REGISTRY}/${IMAGE_NAME}:${TAG}"
fi
if [ -n "${CONTAINER_NAME_OVERRIDE}" ]; then
    export CONTAINER_NAME="${CONTAINER_NAME_OVERRIDE}"
fi
if [ -n "${PORT_MAP_OVERRIDE}" ]; then
    export PORT_MAP="${PORT_MAP_OVERRIDE}"
fi

## ===================== 主命令逻辑 =====================
case "${COMMAND}" in
  init)
    # 初始化流程：检查环境依赖 + 生成依赖文件 + 生成Dockerfile
    log_info "===== 开始初始化环境（${ENV_NAME}） ====="
    check_command docker
    check_command grep
    check_command sed
    check_command bc

    generate_requirements
    generate_dockerfile
    log_success "初始化完成！"
    ;;

  build)
    log_info "===== 开始构建瘦身镜像（${ENV_NAME}） ====="
    if [ ! -f "${REQUIREMENTS_FILE}" ] || [ ! -f "${DOCKERFILE_TEMP}" ]; then
        log_warn "未检测到依赖文件或Dockerfile，自动执行初始化..."
        generate_requirements
        generate_dockerfile
    fi

    log_info "开始构建镜像: ${IMAGE_NAME}:${TAG}"
    retry 3 docker build -f "${DOCKERFILE_TEMP}" -t "${IMAGE_NAME}:${TAG}" "${APP_DIR}"

    IMAGE_SIZE=$(docker inspect -f '{{.Size}}' "${IMAGE_NAME}:${TAG}" 2>/dev/null || echo 0)
    if [ "${IMAGE_SIZE}" != "0" ]; then
        IMAGE_MB=$(echo "scale=2; ${IMAGE_SIZE}/1024/1024" | bc)
        log_success "镜像构建完成！体积: ${IMAGE_MB} MB"
    else
        log_error "镜像构建失败，请检查Dockerfile语法或构建日志"
    fi
    ;;

  start)
    log_info "===== 开始启动容器（${ENV_NAME}） ====="
    if ! docker images -q "${IMAGE_NAME}:${TAG}" &> /dev/null; then
        log_warn "未检测到镜像 ${IMAGE_NAME}:${TAG}，自动执行构建..."
        $0 --env "${ENV_NAME}" build --image "${IMAGE_NAME}" --tag "${TAG}"
    fi

    if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
        log_warn "容器 ${CONTAINER_NAME} 已存在，先停止并删除..."
        docker stop "${CONTAINER_NAME}" >/dev/null 2>&1
        docker rm "${CONTAINER_NAME}" >/dev/null 2>&1
    fi

    mkdir -p "${HOST_LOG_DIR}"
    log_info "日志目录已创建: ${HOST_LOG_DIR}"

    log_info "启动容器参数："
    log_info "  - 镜像: ${IMAGE_NAME}:${TAG}"
    log_info "  - 容器名称: ${CONTAINER_NAME}"
    log_info "  - 端口映射: ${PORT_MAP}"
    log_info "  - 卷挂载: ${VOLUME_MAP}"
    log_info "  - 环境变量: ${ENV_VARS}"
    log_info "  - 自动重启: --restart=unless-stopped"
    
    retry 3 eval "docker run -d \
      --name ${CONTAINER_NAME} \
      --restart=unless-stopped \
      -p ${PORT_MAP} \
      -v ${VOLUME_MAP} \
      ${ENV_VARS} \
      ${IMAGE_NAME}:${TAG}"

    if docker ps -q -f name=${CONTAINER_NAME} &> /dev/null; then
        log_success "容器 ${CONTAINER_NAME} 启动成功！"
        log_info "访问地址: http://localhost:${PORT_MAP%:*}"
        log_info "查看日志: $0 logs --container ${CONTAINER_NAME}"
    else
        log_error "容器 ${CONTAINER_NAME} 启动失败，请执行 $0 logs --container ${CONTAINER_NAME} 查看错误日志"
    fi
    ;;

  stop-container)
    log_info "===== 停止容器 ${CONTAINER_NAME} ====="
    check_container_exists "${CONTAINER_NAME}"
    
    if is_container_running "${CONTAINER_NAME}"; then
        docker stop "${CONTAINER_NAME}"
        log_success "容器 ${CONTAINER_NAME} 已停止"
    else
        log_warn "容器 ${CONTAINER_NAME} 已处于停止状态，无需操作"
    fi
    ;;

  rm-container)
    log_info "===== 删除容器 ${CONTAINER_NAME} ====="
    check_container_exists "${CONTAINER_NAME}"
    
    if is_container_running "${CONTAINER_NAME}"; then
        log_warn "容器 ${CONTAINER_NAME} 仍在运行，先停止..."
        docker stop "${CONTAINER_NAME}" >/dev/null 2>&1
    fi
    
    docker rm "${CONTAINER_NAME}"
    log_success "容器 ${CONTAINER_NAME} 已删除"
    ;;

  logs)
    log_info "===== 实时查看容器 ${CONTAINER_NAME} 日志（按Ctrl+C退出） ====="
    check_container_exists "${CONTAINER_NAME}"
    docker logs -f "${CONTAINER_NAME}"
    ;;

  status)
    log_info "===== 容器/镜像状态信息（${ENV_NAME}） ====="
    log_info "1. 容器状态（${CONTAINER_NAME}）："
    docker ps -a --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || log_warn "无容器 ${CONTAINER_NAME} 相关信息"
    
    log_info "\n2. 镜像状态（${IMAGE_NAME}:${TAG}）："
    docker images "${IMAGE_NAME}:${TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" || log_warn "无镜像 ${IMAGE_NAME}:${TAG} 相关信息"

    log_info "\n3. 远程镜像状态（${REMOTE_IMAGE_TAG}）："
    if docker images -q "${REMOTE_IMAGE_TAG}" &> /dev/null; then
        docker images "${REMOTE_IMAGE_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
    else
        log_warn "本地无远程镜像 ${REMOTE_IMAGE_TAG}，可执行 $0 --env ${ENV_NAME} pull 拉取"
    fi
    ;;

  list-containers)
    log_info "===== 所有现有容器列表 ====="
    if [ -z "$(docker ps -aq)" ]; then
        log_warn "当前无任何容器"
    else
        docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}"
        running_count=$(docker ps -q | wc -l | xargs)
        total_count=$(docker ps -aq | wc -l | xargs)
        stopped_count=$((total_count - running_count))
        log_info "\n统计：总容器数 ${total_count} | 运行中 ${running_count} | 已停止 ${stopped_count}"
    fi
    ;;

  list-images)
    log_info "===== 所有已存在镜像列表 ====="
    if [ -z "$(docker images -q)" ]; then
        log_warn "当前无任何镜像"
    else
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"
        image_count=$(docker images -q | wc -l | xargs)
        total_size_mb=0
        while read -r repo tag size; do
            if [[ $size =~ ([0-9.]+)GiB ]]; then
                size_mb=$(echo "scale=2; ${BASH_REMATCH[1]} * 1024" | bc)
            elif [[ $size =~ ([0-9.]+)MiB ]] || [[ $size =~ ([0-9.]+)MB ]]; then
                size_mb=${BASH_REMATCH[1]}
            elif [[ $size =~ ([0-9.]+)KiB ]]; then
                size_mb=$(echo "scale=2; ${BASH_REMATCH[1]} / 1024" | bc)
            else
                size_mb=$(echo "scale=2; ${size%B} / 1024 / 1024" | bc)
            fi
            total_size_mb=$(echo "scale=2; ${total_size_mb} + ${size_mb}" | bc)
        done < <(docker images --format "{{.Repository}}\t{{.Tag}}\t{{.Size}}")
        log_info "\n统计：总镜像数 ${image_count} | 总占用空间约 ${total_size_mb} MB"
    fi
    ;;

  rm-image)
    log_info "===== 删除镜像 ${IMAGE_NAME}:${TAG} ====="
    check_image_exists "${IMAGE_NAME}" "${TAG}"
    
    dependent_containers=$(docker ps -aq --filter "ancestor=${IMAGE_NAME}:${TAG}")
    if [ -n "${dependent_containers}" ]; then
        log_warn "发现依赖该镜像的容器，先删除..."
        docker rm -f ${dependent_containers} >/dev/null 2>&1
    fi
    
    # 同时删除远程标签镜像
    if docker images -q "${REMOTE_IMAGE_TAG}" &> /dev/null; then
        docker rmi "${REMOTE_IMAGE_TAG}" >/dev/null 2>&1
    fi
    docker rmi "${IMAGE_NAME}:${TAG}"
    log_success "镜像 ${IMAGE_NAME}:${TAG} 已删除"
    ;;

  clean)
    log_info "===== 清理脚本临时文件 ====="
    temp_files=(
      "${DOCKERFILE_TEMP}"
      "${REQUIREMENTS_FILE}.tmp"
    )
  
    deleted_count=0
    for file in "${temp_files[@]}"; do
      if [ -f "${file}" ]; then
        rm -f "${file}"
        log_success "已删除临时文件：${file}"
        deleted_count=$((deleted_count + 1))
      fi
    done
  
    if [ ${deleted_count} -eq 0 ]; then
        log_warn "当前无需要清理的临时文件"
    else
        log_success "共清理 ${deleted_count} 个临时文件"
    fi
    ;;

  info)
    show_usage_guide
    ;;

  # 新增命令
  push)
    # 推送镜像到远程仓库
    push_image
    ;;

  pull)
    # 从远程仓库拉取镜像
    pull_image
    ;;

  update-container)
    # 更新容器（拉新镜像+重启+清旧镜像）
    update_container
    ;;

  batch-load-images)
    # 批量加载镜像（--dir 指定目录）
    batch_load_images "${BATCH_DIR}"
    ;;

  batch-save-images)
    # 批量导出镜像（--dir 指定导出目录，--list-file 指定镜像列表）
    batch_save_images "${BATCH_DIR}" "${BATCH_LIST_FILE}"
    ;;
esac

exit 0