#!/bin/bash


# --- 配置区 ---
# 镜像和容器名称
IMAGE_NAME="flask-demo"
TAG_ORIG="v1.0"
TAG_SLIM="slim"
CONTAINER_NAME="flask-app"

# 端口映射 (主机端口:容器端口)
PORT_MAP="8080:5000"

# 卷挂载 (主机目录:容器目录)
# 确保主机目录存在
HOST_LOG_DIR="$HOME/docker-demo/host-logs"
CONTAINER_LOG_DIR="/app/logs"
VOLUME_MAP="${HOST_LOG_DIR}:${CONTAINER_LOG_DIR}"

# 环境变量
ENV_VARS="-e APP_NAME='MyAwesomeApp' -e PORT=5000"

# --- 脚本主逻辑 ---
case "$1" in
  build)
    echo "===== 开始构建原始镜像: ${IMAGE_NAME}:${TAG_ORIG} ====="
    docker build -t "${IMAGE_NAME}:${TAG_ORIG}" .

    echo -e "\n===== 开始构建瘦身镜像: ${IMAGE_NAME}:${TAG_SLIM} ====="
    if [ -f "Dockerfile.slim" ]; then
      docker build -f "Dockerfile.slim" -t "${IMAGE_NAME}:${TAG_SLIM}" .
      
      echo -e "\n===== 镜像体积对比 ====="
      ORIG_SIZE=$(docker inspect -f '{{.Size}}' "${IMAGE_NAME}:${TAG_ORIG}" 2>/dev/null || echo 0)
      SLIM_SIZE=$(docker inspect -f '{{.Size}}' "${IMAGE_NAME}:${TAG_SLIM}" 2>/dev/null || echo 0)
      
      if [ "$ORIG_SIZE" != "0" ] && [ "$SLIM_SIZE" != "0" ]; then
        ORIG_MB=$(echo "scale=2; $ORIG_SIZE/1024/1024" | bc)
        SLIM_MB=$(echo "scale=2; $SLIM_SIZE/1024/1024" | bc)
        REDUCE_MB=$(echo "scale=2; $ORIG_MB - $SLIM_MB" | bc)
        REDUCE_PERCENT=$(echo "scale=2; ($REDUCE_MB/$ORIG_MB)*100" | bc)
        
        echo "原始镜像体积: ${ORIG_MB} MB"
        echo "瘦身镜像体积: ${SLIM_MB} MB"
        echo "体积减少:    ${REDUCE_MB} MB (${REDUCE_PERCENT}%)"
      else
        echo "无法计算体积，可能有镜像未成功构建。"
      fi
    else
      echo "错误: 未找到 'Dockerfile.slim' 文件，跳过瘦身镜像构建。"
    fi
    ;;

  start)
    # 检查容器是否已存在，存在则先删除
    if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
      echo "容器 ${CONTAINER_NAME} 已存在，正在删除..."
      docker rm -f "${CONTAINER_NAME}"
    fi

    # 确保主机日志目录存在
    mkdir -p "${HOST_LOG_DIR}"

    echo "===== 启动容器: ${CONTAINER_NAME} ====="
    echo "  - 镜像: ${IMAGE_NAME}:${TAG_SLIM}"
    echo "  - 端口: ${PORT_MAP}"
    echo "  - 卷挂载: ${VOLUME_MAP}"
    echo "  - 环境变量: ${ENV_VARS}"
    
    # 使用 eval 来正确处理包含空格的环境变量
    eval "docker run -d \
      --name ${CONTAINER_NAME} \
      -p ${PORT_MAP} \
      -v ${VOLUME_MAP} \
      ${ENV_VARS} \
      ${IMAGE_NAME}:${TAG_SLIM}"
    
    echo -e "\n容器已启动！"
    echo "访问地址: http://localhost:${PORT_MAP%:*}"
    echo "查看日志: ./manage-flask.sh logs"
    ;;

  stop)
    echo "===== 停止并删除容器: ${CONTAINER_NAME} ====="
    docker stop "${CONTAINER_NAME}"
    docker rm "${CONTAINER_NAME}"
    echo "操作完成。"
    ;;

  logs)
    echo "===== 实时查看容器日志 (按 Ctrl+C 退出) ====="
    docker logs -f "${CONTAINER_NAME}"
    ;;
    
  status)
    echo "===== 容器 ${CONTAINER_NAME} 状态 ====="
    docker ps -a --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    ;;

  *)
    echo "使用方法: $0 {build|start|stop|logs|status}"
    echo "  build   - 构建原始和瘦身镜像，并对比体积"
    echo "  start   - 启动容器 (使用瘦身镜像)"
    echo "  stop    - 停止并删除容器"
    echo "  logs    - 实时查看容器日志"
    echo "  status  - 查看容器状态"
    exit 1
    ;;
esac

exit 0