# 引入多个第三方依赖，测试脚本的依赖提取能力
from flask import Flask, jsonify, request
import requests  # 第三方HTTP库
from dotenv import load_dotenv  # 第三方环境变量库
import logging
import os
import datetime  # Python内置库（脚本会自动过滤）

# 初始化Flask应用
app = Flask(__name__)

# 加载.env文件（可选，测试环境变量功能）
load_dotenv()

# ===================== 日志配置（验证日志挂载） =====================
# 确保日志目录存在（容器内路径）
LOG_DIR = "/app/logs"
os.makedirs(LOG_DIR, exist_ok=True)

# 配置日志（同时输出到文件和控制台）
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.join(LOG_DIR, 'app.log')),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# ===================== 测试接口（验证功能） =====================
# 首页接口
@app.route('/')
def index():
    app_name = os.getenv('APP_NAME', 'FlaskDemo')
    current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    logger.info(f"首页访问 - 应用名称: {app_name}, 访问时间: {current_time}")
    return jsonify({
        "message": f"Updated: Updated: Hello from to {app_name}! 🚀",
        "time": current_time,
        "status": "success"
    })

# 测试第三方依赖（requests）的接口
@app.route('/api/test-request')
def test_request():
    """调用外部API，测试requests库是否正常"""
    try:
        # 调用公共测试API
        response = requests.get("https://httpbin.org/get", timeout=5)
        logger.info("成功调用外部API，状态码: {}".format(response.status_code))
        return jsonify({
            "status": "success",
            "data": response.json(),
            "timestamp": datetime.datetime.now().isoformat()
        })
    except Exception as e:
        logger.error(f"调用外部API失败: {str(e)}")
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

# 获取容器信息的接口
@app.route('/api/info')
def get_info():
    """返回容器运行信息"""
    return jsonify({
        "python_version": os.sys.version,
        "flask_version": Flask.__version__,
        "port": os.getenv('PORT', 5000),
        "host_log_dir": os.getenv('HOST_LOG_DIR', 'unknown'),
        "container_id": os.uname().nodename  # 容器ID
    })

# ===================== 启动应用 =====================
if __name__ == '__main__':
    # 从环境变量读取配置
    host = '0.0.0.0'
    port = int(os.getenv('PORT', 5000))
    debug = os.getenv('FLASK_DEBUG', 'False').lower() == 'true'
    
    logger.info(f"启动Flask应用 - 地址: {host}:{port}, 调试模式: {debug}")
    app.run(host=host, port=port, debug=debug)