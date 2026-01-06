#!/bin/bash
## ===================== 基础环境检测与依赖安装 =====================
# 自动安装bc工具（跨平台兼容）
install_bc() {
    if ! command -v bc &> /dev/null; then
        log_info "未检测到bc工具，开始自动安装..."
        # 区分Linux（apt/yum）和macOS（brew）
        if [ "$(uname -s)" = "Darwin" ]; then
            # macOS：使用brew安装
            if ! command -v brew &> /dev/null; then
                log_error "macOS需先安装Homebrew（https://brew.sh/），再执行脚本"
            fi
            brew install bc
        else
            # Linux：优先apt，其次yum
            if command -v apt &> /dev/null; then
                sudo apt update && sudo apt install -y bc
            elif command -v yum &> /dev/null; then
                sudo yum install -y bc
            else
                log_error "不支持的Linux包管理器，需手动安装bc工具"
            fi
        fi
        if command -v bc &> /dev/null; then
            log_success "bc工具安装完成"
        else
            log_error "bc工具安装失败，请手动安装"
        fi
    fi
}

# 自动安装nc命令（用于仓库端口检测，跨平台兼容）
install_nc() {
    if ! command -v nc &> /dev/null; then
        log_info "未检测到nc命令，开始自动安装..."
        if [ "$(uname -s)" = "Darwin" ]; then
            # macOS：brew安装netcat（nc命令）
            if ! command -v brew &> /dev/null; then
                log_error "macOS需先安装Homebrew（https://brew.sh/），再执行脚本"
            fi
            brew install netcat
        else
            # Linux：apt安装netcat，yum安装nc
            if command -v apt &> /dev/null; then
                sudo apt update && sudo apt install -y netcat
            elif command -v yum &> /dev/null; then
                sudo yum install -y nc
            else
                log_error "不支持的Linux包管理器，需手动安装nc工具"
            fi
        fi
        if ! command -v nc &> /dev/null; then
            log_error "nc命令安装失败，无法检测仓库端口"
        fi
    fi
}

# 跨平台sed命令封装（解决macOS sed -i 兼容性）
sed_inplace() {
    local sed_cmd
    if [ "$(uname -s)" = "Darwin" ]; then
        # macOS：sed -i 需要备份文件，备份后删除
        sed_cmd="sed -i.bak"
    else
        # Linux：直接使用sed -i
        sed_cmd="sed -i"
    fi
    # 执行sed命令
    $sed_cmd "$@"
    # 删除macOS生成的备份文件
    if [ "$(uname -s)" = "Darwin" ] && [ -f "${3}.bak" ]; then
        rm -f "${3}.bak"
    fi
}

## ===================== 终端颜色配置 =====================
RED='\033[0;31m'    # 错误提示色
GREEN='\033[0;32m'  # 成功提示色
YELLOW='\033[1;33m' # 警告提示色
BLUE='\033[0;34m'   # 信息提示色
NC='\033[0m'        # 重置颜色

## ===================== 日志函数 =====================
# 打印信息级日志（蓝色）
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# 打印成功级日志（绿色）
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 打印警告级日志（黄色）
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 打印错误级日志（红色）并退出
log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

## ===================== 检查函数 =====================
# 检查指定命令是否存在
# 参数：$1 - 要检查的命令名称
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "缺少必要命令: $1，请先安装"
    fi
}

# 验证指定镜像是否存在
# 参数：$1 - 镜像名称，$2 - 镜像标签（默认latest）
check_image_exists() {
    local img_name=$1
    local img_tag=${2:-latest}
    if ! docker images -q "${img_name}:${img_tag}" &> /dev/null; then
        log_error "镜像 ${img_name}:${img_tag} 不存在！"
    fi
}

# 验证指定容器是否存在
# 参数：$1 - 容器名称
check_container_exists() {
    local container_name=$1
    if [ -z "$(docker ps -aq -f name=${container_name})" ]; then
        log_error "容器 ${container_name} 不存在！"
    fi
}

# 检查容器是否处于运行状态（精准判断）
# 参数：$1 - 容器名称
# 返回值：0=运行中，1=未运行/不存在
is_container_running() {
    local container_name=$1
    # 通过docker inspect获取运行状态，容错处理（容器不存在时返回false）
    local running_status=$(docker inspect -f '{{.State.Running}}' "${container_name}" 2>/dev/null || echo "false")
    if [ "${running_status}" = "true" ]; then
        return 0
    else
        return 1
    fi
}

## ===================== 配置加载函数 =====================
# 从配置文件加载指定环境的配置
# 参数：$1 - 环境名称（如 dev/prod），$2 - 配置文件路径
load_config() {
    local env_name=${1:-default}
    local config_file=${2:-./docker-manager.conf}
    
    # 检查配置文件是否存在
    if [ ! -f "${config_file}" ]; then
        log_error "配置文件不存在：${config_file}"
    fi

    # 使用 awk 解析 ini 配置文件，提取指定环境的配置
    local config_lines=$(awk -F '=' -v env="[$env_name]" '
        $0 == env { in_env=1; next }
        in_env && $0 ~ /^\[.*\]/ { in_env=0; exit }
        in_env && $1 ~ /^[a-zA-Z_]+/ { gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2); print $1 "=" $2 }
    ' "${config_file}")

    # 加载配置到环境变量
    while IFS='=' read -r key value; do
        # 替换环境变量（如 $HOME），跨平台兼容路径分隔符
        if [ "$(uname -s)" = "Darwin" ]; then
            # macOS：替换$HOME为实际路径（避免eval解析问题）
            value=$(echo "${value}" | sed "s|\$HOME|${HOME}|g")
        else
            # Linux：直接eval解析
            value=$(eval echo "${value}")
        fi
        export "${key}"="${value}"
    done <<< "${config_lines}"

    # 补充默认值（若配置文件中未定义）
    export IMAGE_NAME=${IMAGE_NAME:-python-demo}
    export TAG=${TAG:-latest}
    export CONTAINER_NAME=${CONTAINER_NAME:-python-app}
    export PORT_MAP=${PORT_MAP:-8080:5000}
    export APP_DIR=${APP_DIR:-./}
    # 跨平台兼容日志目录（统一使用$HOME，避免绝对路径差异）
    export HOST_LOG_DIR=${HOST_LOG_DIR:-$HOME/docker-demo/host-logs}
    export CONTAINER_LOG_DIR=${CONTAINER_LOG_DIR:-/app/logs}
    export ENV_VARS=${ENV_VARS:--e APP_NAME='MyAwesomeApp' -e PORT=5000}
    export REMOTE_REGISTRY=${REMOTE_REGISTRY:-localhost:5000}

    # 派生变量
    export REQUIREMENTS_FILE="${APP_DIR}/requirements.txt"
    export DOCKERFILE_TEMP="${APP_DIR}/Dockerfile.tmp"
    export VOLUME_MAP="${HOST_LOG_DIR}:${CONTAINER_LOG_DIR}"
    # 推送镜像的目标标签（远程仓库+镜像名+标签）
    export REMOTE_IMAGE_TAG="${REMOTE_REGISTRY}/${IMAGE_NAME}:${TAG}"

    log_info "已加载 ${env_name} 环境配置"
}

## ===================== 重试函数 =====================
# 带重试的命令执行
# 参数：$1 - 重试次数，后续参数 - 要执行的命令
retry() {
    local retries=$1
    shift
    local count=0
    until "$@"; do
        count=$((count + 1))
        if [ $count -ge $retries ]; then
            log_error "操作失败，已重试 $retries 次"
            return 1
        fi
        # 修复：用$((...))进行数值运算
        log_warn "操作失败，$((retries - count)) 次重试中..."
        sleep 2
    done
}

## ===================== Docker镜像源配置函数 =====================
# 配置Docker镜像源（仅首次询问，后续跳过）
configure_docker_mirror() {
    log_info "===== Docker镜像源配置检测 ====="
    # 定义标记文件路径（存放在Docker配置目录，仅管理员可修改，避免误删）
    local mirror_flag="/etc/docker/mirror-configured.flag"
    
    # 第一步：检测标记文件，存在则直接跳过询问
    if [ -f "${mirror_flag}" ]; then
        # 读取标记文件内容，区分“已配置”和“已跳过”状态
        local flag_content=$(sudo cat "${mirror_flag}" 2>/dev/null)
        if [ "${flag_content}" = "configured" ]; then
            log_info "镜像源已配置（检测到标记文件：${mirror_flag}），跳过配置流程"
        else
            log_info "镜像源已跳过配置（检测到标记文件：${mirror_flag}），跳过配置流程"
        fi
        return 0
    fi

    # 第二步：无标记文件，执行交互式配置流程
    read -p "是否需要配置Docker镜像源（推荐国内源，提升拉取速度）？[y/N] " choice
    # 统一转为小写，处理用户输入（y/Y为是，其他为否）
    choice=$(echo "${choice}" | tr '[:upper:]' '[:lower:]')
    
    if [ "${choice}" != "y" ]; then
        log_warn "用户选择跳过Docker镜像源配置"
        # 创建标记文件，标记为“已跳过”（避免后续重复询问）
        sudo mkdir -p /etc/docker
        sudo touch "${mirror_flag}"
        echo "skipped" | sudo tee "${mirror_flag}" >/dev/null 2>&1
        return 0
    fi

    # 1. 定义要配置的国内镜像源列表（包含阿里云、腾讯云等稳定源）
    local mirror_config='{
    "registry-mirrors": [
        "https://docker.m.daocloud.io",
        "https://docker.1panel.live",
        "https://hub.rat.dev",
        "https://mirror.ccs.tencentyun.com"
    ]
}'

    # 2. 检查并创建Docker配置目录（确保目录存在）
    local docker_config_dir="/etc/docker"
    if [ ! -d "${docker_config_dir}" ]; then
        log_info "创建Docker配置目录：${docker_config_dir}"
        sudo mkdir -p "${docker_config_dir}"
    fi

    # 3. 备份原有配置文件（若存在），避免覆盖丢失
    local daemon_file="${docker_config_dir}/daemon.json"
    if [ -f "${daemon_file}" ]; then
        local backup_file="${daemon_file}.$(date +%Y%m%d%H%M%S).bak"
        log_info "备份原有配置文件至：${backup_file}"
        sudo cp "${daemon_file}" "${backup_file}"
    fi

    # 4. 写入新的镜像源配置（使用tee确保sudo权限）
    log_info "写入Docker镜像源配置：${daemon_file}"
    echo "${mirror_config}" | sudo tee "${daemon_file}" >/dev/null 2>&1

    # 5. 重启Docker服务使配置生效（兼容不同系统服务管理器）
    log_info "重启Docker服务以应用配置..."
    if command -v systemctl &> /dev/null; then
        # systemd系统（Ubuntu 16.04+/CentOS 7+）
        sudo systemctl daemon-reload
        sudo systemctl restart docker
    elif command -v service &> /dev/null; then
        # sysvinit系统（老旧系统）
        sudo service docker restart
    else
        log_error "无法识别的系统服务管理器，需手动重启Docker：sudo systemctl restart docker"
        return 1
    fi

    # 6. 创建标记文件，标记为“已配置”（后续执行不再询问）
    sudo touch "${mirror_flag}"
    echo "configured" | sudo tee "${mirror_flag}" >/dev/null 2>&1

    log_success "Docker镜像源配置完成！当前镜像源："
    # 打印配置结果，验证生效
    sudo cat "${daemon_file}" | grep -A 5 "registry-mirrors"
}

## ===================== 依赖/镜像生成函数 =====================
# 从app.py提取第三方依赖，生成requirements.txt文件
generate_requirements() {
    log_info "开始分析app.py依赖并生成requirements.txt..."
    
    # 检查app.py文件是否存在
    if [ ! -f "${APP_DIR}/app.py" ]; then
        log_error "未找到app.py文件，请确认文件路径: ${APP_DIR}/app.py"
    fi

    # 提取import语句并去重（支持import xxx 和 from xxx import xxx两种格式）
    grep -E '^import |^from ' "${APP_DIR}/app.py" | \
        sed -E 's/^import ([a-zA-Z0-9_-]+).*/\1/' | \
        sed -E 's/^from ([a-zA-Z0-9_-]+).*/\1/' | \
        sort | uniq > "${REQUIREMENTS_FILE}.tmp"

    # 过滤Python内置库（避免将系统库写入依赖清单），使用跨平台sed
    BUILTIN_MODULES="os sys json re datetime time collections pathlib logging"
    for MODULE in $BUILTIN_MODULES; do
        sed_inplace "/^${MODULE}$/d" "${REQUIREMENTS_FILE}.tmp"
    done

    # 生成最终的requirements.txt文件
    mv "${REQUIREMENTS_FILE}.tmp" "${REQUIREMENTS_FILE}"
    
    # 检查依赖文件是否为空
    if [ ! -s "${REQUIREMENTS_FILE}" ]; then
        log_warn "未检测到第三方依赖，requirements.txt为空"
    else
        log_success "依赖文件生成完成！路径: ${REQUIREMENTS_FILE}"
        log_info "检测到的依赖列表："
        cat "${REQUIREMENTS_FILE}"
    fi
}

# 生成多阶段构建的Dockerfile（瘦身镜像，跨平台兼容）
generate_dockerfile() {
    log_info "生成多阶段构建Dockerfile（目标：精简Python镜像）..."
    
    # 写入临时Dockerfile文件，新增--platform参数确保跨架构兼容
    cat > "${DOCKERFILE_TEMP}" << EOF
# 阶段1：构建依赖（builder阶段，仅用于安装依赖）
FROM --platform=linux/amd64 python:3.11-slim AS builder

# 设置工作目录
WORKDIR /app

# 复制依赖清单文件
COPY requirements.txt .

# 安装依赖到临时目录（--target指定安装路径）
RUN pip install --no-cache-dir --target=/app/deps -r requirements.txt

# 阶段2：运行镜像（最终镜像，仅包含运行时依赖）
FROM --platform=linux/amd64 python:3.11-alpine

# 设置工作目录
WORKDIR /app

# 从builder阶段复制依赖文件
COPY --from=builder /app/deps /app/deps

# 将依赖目录加入Python路径
ENV PYTHONPATH=/app/deps

# 创建日志目录并赋予权限
RUN mkdir -p /app/logs && chmod 777 /app/logs

# 复制应用代码
COPY app.py .

# 暴露容器端口
EXPOSE 5000

# 启动命令
CMD ["python", "app.py"]
EOF

    log_success "多阶段构建Dockerfile生成完成！路径: ${DOCKERFILE_TEMP}"
}

## ===================== 新增功能函数 =====================
# 推送镜像到远程仓库（支持本地仓库）
push_image() {
    log_info "===== 推送镜像到仓库：${REMOTE_REGISTRY} ====="
    check_image_exists "${IMAGE_NAME}" "${TAG}"

    # 自动安装nc命令（用于端口检测）
    install_nc

    # 解析仓库地址（默认localhost:5000）
    local registry_host=$(echo "${REMOTE_REGISTRY}" | cut -d: -f1)
    local registry_port=$(echo "${REMOTE_REGISTRY}" | cut -d: -f2)

    # 核心逻辑：分层检查registry镜像/容器状态
    if ! nc -z "${registry_host}" "${registry_port}" &> /dev/null; then
        log_warn "远程仓库 ${REMOTE_REGISTRY} 端口不可达，开始检查本地仓库状态..."
        
        # 第一步：检查registry:2镜像是否存在
        if ! docker images -q registry:2 &> /dev/null; then
            log_info "未检测到registry:2镜像，开始拉取..."
            # 拉取镜像（带重试，确保网络波动时也能成功）
            retry 3 docker pull registry:2 || log_error "registry:2镜像拉取失败，请检查网络"
            log_success "registry:2镜像拉取完成"
        else
            log_info "本地已存在registry:2镜像，跳过拉取"
        fi

        # 第二步：检查registry容器是否存在（精准匹配容器名）
        if [ -z "$(docker ps -aq -f name=^/registry$)" ]; then
            log_info "未检测到registry容器，创建并启动..."
            # 创建并启动容器（指定端口+自动重启，确保稳定性）
            docker run -d -p 5000:5000 --restart=always --name registry registry:2 || log_error "registry容器创建失败"
            log_success "registry容器创建并启动成功"
            sleep 5  # 等待仓库服务初始化（避免立即推送失败）
        else
            # 第三步：容器存在，检查是否运行
            if ! is_container_running "registry"; then
                log_info "registry容器已存在但未运行，启动容器..."
                docker start registry || log_error "registry容器启动失败"
                log_success "registry容器启动成功"
                sleep 3  # 短等待，确保服务就绪
            else
                log_info "registry容器已正常运行，无需操作"
            fi
        fi

        # 最终验证仓库是否可用（二次确认端口）
        if ! nc -z "${registry_host}" "${registry_port}" &> /dev/null; then
            log_error "本地仓库启动后端口仍不可达，请检查容器日志：docker logs registry"
        fi
    fi

    # 1. 为镜像打远程标签（关联本地镜像与远程仓库）
    log_info "为镜像打远程标签：${IMAGE_NAME}:${TAG} → ${REMOTE_IMAGE_TAG}"
    docker tag "${IMAGE_NAME}:${TAG}" "${REMOTE_IMAGE_TAG}"

    # 2. 推送镜像到远程仓库（带重试，应对网络波动）
    log_info "开始推送镜像：${REMOTE_IMAGE_TAG}"
    retry 3 docker push "${REMOTE_IMAGE_TAG}"

    log_success "镜像推送完成！远程地址：${REMOTE_IMAGE_TAG}"
}

# 从远程仓库拉取镜像
pull_image() {
    log_info "===== 从仓库拉取镜像：${REMOTE_REGISTRY} ====="
    log_info "拉取镜像：${REMOTE_IMAGE_TAG}"
    retry 3 docker pull "${REMOTE_IMAGE_TAG}"

    # 为拉取的镜像打本地标签（便于后续使用）
    docker tag "${REMOTE_IMAGE_TAG}" "${IMAGE_NAME}:${TAG}"
    log_success "镜像拉取完成！本地标签：${IMAGE_NAME}:${TAG}"
}

# 批量加载镜像（从.tar文件）
# 参数：$1 - 镜像文件目录（默认当前目录）
batch_load_images() {
    local img_dir=${1:-./}
    log_info "===== 批量加载 ${img_dir} 目录下的.tar镜像 ====="

    # 检查目录是否存在
    if [ ! -d "${img_dir}" ]; then
        log_error "镜像目录不存在：${img_dir}"
    fi

    # 统计.tar文件数量（仅一级目录，避免递归）
    local img_files=$(find "${img_dir}" -maxdepth 1 -type f -name "*.tar")
    if [ -z "${img_files}" ]; then
        log_warn "目录 ${img_dir} 下无.tar镜像文件"
        return 0
    fi

    # 批量加载镜像
    local loaded_count=0
    for img_file in ${img_files}; do
        log_info "正在加载镜像：${img_file}"
        if docker load -i "${img_file}" &> /dev/null; then
            log_success "加载成功：$(basename "${img_file}")"
            loaded_count=$((loaded_count + 1))
        else
            log_warn "加载失败：$(basename "${img_file}")"
        fi
    done

    log_info "\n批量加载完成！成功 ${loaded_count} 个，失败 $(( $(echo "${img_files}" | wc -w) - loaded_count )) 个"
}

# 批量导出镜像（到.tar文件）
# 参数：$1 - 导出目录（默认当前目录），$2 - 镜像列表文件（每行一个镜像名:标签）
batch_save_images() {
    local export_dir=${1:-./}
    local img_list_file=${2:-./image-list.txt}
    log_info "===== 批量导出镜像到 ${export_dir} 目录 ====="

    # 检查目录和文件（确保导出目录存在，列表文件可读取）
    mkdir -p "${export_dir}"
    if [ ! -f "${img_list_file}" ]; then
        log_error "镜像列表文件不存在：${img_list_file}"
    fi

    # 批量导出镜像
    local saved_count=0
    while IFS= read -r img; do
        # 跳过空行和注释行（支持#开头的注释）
        if [ -z "${img}" ] || [[ "${img}" =~ ^# ]]; then
            continue
        fi
        # 生成导出文件名（替换:和/为-，避免路径问题）
        local img_file="${export_dir}/$(echo "${img}" | tr ':' '-' | tr '/' '-').tar"
        log_info "正在导出镜像：${img} → ${img_file}"
        if docker save -o "${img_file}" "${img}" &> /dev/null; then
            log_success "导出成功：${img}"
            saved_count=$((saved_count + 1))
        else
            log_warn "导出失败：${img}（镜像不存在或无权限）"
        fi
    done < "${img_list_file}"

    log_info "\n批量导出完成！成功 ${saved_count} 个，失败 $(( $(grep -v '^#\|^$' "${img_list_file}" | wc -l) - saved_count )) 个"
}

# 容器更新（基于新镜像重启，解决名称冲突）
update_container() {
    log_info "===== 更新容器 ${CONTAINER_NAME} ====="
    local old_image="${IMAGE_NAME}:${TAG}"

    # 1. 拉取最新镜像（从远程仓库，确保使用最新版本）
    pull_image

    # 2. 停止并删除旧容器（关键：删除容器避免名称冲突）
    if is_container_running "${CONTAINER_NAME}"; then
        log_info "停止旧容器：${CONTAINER_NAME}"
        docker stop "${CONTAINER_NAME}"
    fi
    # 精准匹配容器名，避免误删其他容器
    if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
        log_info "删除旧容器：${CONTAINER_NAME}"
        docker rm "${CONTAINER_NAME}"
    fi

    # 3. 启动新容器（复用原有配置，添加自动重启）
    log_info "启动新容器（基于最新镜像）"
    retry 3 eval "docker run -d \
        --name ${CONTAINER_NAME} \
        --restart=unless-stopped \
        -p ${PORT_MAP} \
        -v ${VOLUME_MAP} \
        ${ENV_VARS} \
        ${IMAGE_NAME}:${TAG}"

    # 4. 清理旧镜像（保留最新2个版本，避免镜像堆积）
    local old_img_ids=$(docker images -q "${IMAGE_NAME}" | tail -n +3)
    if [ -n "${old_img_ids}" ]; then
        log_info "清理旧镜像（保留最新2个版本）"
        docker rmi -f ${old_img_ids} &> /dev/null
    fi

    log_success "容器更新完成！新镜像：${IMAGE_NAME}:${TAG}"
}

## ===================== 使用指南函数 =====================
# 脚本完整使用指南
show_usage_guide() {
    echo -e "${BLUE}===== Python Docker 管理脚本（增强版）- 完整使用指南 =====${NC}"
    echo -e "\n${YELLOW}【脚本核心能力】${NC}"
    echo "1. Docker自动安装：检测到无Docker时，自动执行官方脚本安装最新版"
    echo "2. 镜像源智能配置：仅首次执行询问是否配置，后续通过标记文件跳过（路径：/etc/docker/mirror-configured.flag）"
    echo "3. 镜像推送/拉取：自动分层检查本地仓库（registry:2）状态，无镜像则拉取、无容器则创建、未运行则启动"
    echo "4. 容器自动更新：拉取最新镜像、停止删除旧容器、启动新容器、清理旧镜像（保留2个版本）一键完成"
    echo "5. 批量操作：批量加载（.tar文件）、批量导出镜像，支持指定目录和镜像列表"
    echo "6. 跨平台兼容：适配macOS/Linux，自动处理sed命令、bc/nc工具安装差异"
    echo "7. 精细化管理：容器启停/删除分离、资源统计、实时日志查看、临时文件清理"
    echo "8. 鲁棒性保障：核心操作3次重试、配置文件自动备份、权限自动适配"
    echo -e "\n${YELLOW}【前置条件】${NC}"
    echo "1. 拥有sudo权限（用于安装Docker、依赖工具、修改系统配置）"
    echo "2. 脚本同级目录存在app.py（Python业务代码）和docker-manager.conf（配置文件）"
    echo "3. macOS需提前安装Homebrew（https://brew.sh/），用于安装bc/nc等依赖工具"
    echo -e "\n${YELLOW}【基础命令（默认环境）】${NC}"
    echo "  ./python-docker-manager.sh init        # 初始化：生成requirements.txt+Dockerfile.tmp"
    echo "  ./python-docker-manager.sh build      # 构建默认镜像（python-demo:latest）"
    echo "  ./python-docker-manager.sh start      # 启动默认容器（python-app，8080端口）"
    echo "  ./python-docker-manager.sh stop-container  # 停止默认容器（不删除）"
    echo "  ./python-docker-manager.sh rm-container    # 删除默认容器（自动停止运行中容器）"
    echo "  ./python-docker-manager.sh logs       # 查看默认容器实时日志（按Ctrl+C退出）"
    echo "  ./python-docker-manager.sh status    # 查看默认镜像/容器/远程镜像状态"
    echo "  ./python-docker-manager.sh clean      # 清理脚本临时文件（Dockerfile.tmp等）"
    echo -e "\n${YELLOW}【核心命令示例】${NC}"
    echo "  # 1. 首次执行触发镜像源配置（后续执行自动跳过）"
    echo "  ./python-docker-manager.sh info"
    echo ""
    echo "  # 2. 使用dev环境启动容器（自动加载dev配置，8081端口）"
    echo "  ./python-docker-manager.sh --env dev start"
    echo ""
    echo "  # 3. 推送dev环境镜像到本地仓库（自动处理registry状态）"
    echo "  ./python-docker-manager.sh --env dev push"
    echo ""
    echo "  # 4. 从仓库拉取prod环境镜像"
    echo "  ./python-docker-manager.sh --env prod pull"
    echo ""
    echo "  # 5. 更新dev环境容器（拉新镜像+重启+清旧镜像）"
    echo "  ./python-docker-manager.sh --env dev update-container"
    echo ""
    echo "  # 6. 批量加载./images目录下的.tar镜像"
    echo "  ./python-docker-manager.sh batch-load-images --dir ./images"
    echo ""
    echo "  # 7. 批量导出镜像（基于image-list.txt，每行一个镜像名:标签）"
    echo "  # image-list.txt示例："
    echo "  # python-demo:latest"
    echo "  # python-demo-dev:dev-latest"
    echo "  ./python-docker-manager.sh batch-save-images --dir ./export --list-file ./image-list.txt"
    echo ""
    echo "  # 8. 自定义镜像名+标签启动容器（覆盖默认配置）"
    echo "  ./python-docker-manager.sh start --image my-app --tag v2.0 --container my-app-v2 --port 8084:5000"
    echo -e "\n${YELLOW}【常见问题排查】${NC}"
    echo "1. 权限错误：执行 sudo usermod -aG docker \$USER 后重新登录（免sudo使用Docker）"
    echo "2. 端口被占用：使用 --port 参数指定未占用端口（如8081:5000）"
    echo "3. 镜像拉取缓慢：首次执行时选择配置国内镜像源，或手动删除标记文件重新配置"
    echo "4. macOS依赖工具安装失败：确保Homebrew已安装且网络通畅（执行 brew update 修复）"
    echo "5. 镜像推送失败：检查registry容器日志（docker logs registry），或重启容器（docker restart registry）"
    echo "6. 重置镜像源配置：删除标记文件（sudo rm -f /etc/docker/mirror-configured.flag），重新执行脚本即可触发询问"
    echo "7. 容器名称冲突：执行 ./python-docker-manager.sh --env 环境名 rm-container 删除旧容器"
}