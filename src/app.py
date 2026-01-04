from flask import Flask
import os
import logging
from datetime import datetime

app = Flask(__name__)

APP_NAME = os.getenv("APP_NAME", "DefaultApp")
PORT = int(os.getenv("PORT", 5000))
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
LOG_DIR = "/app/logs"

logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(f"{LOG_DIR}/app_{datetime.now().strftime('%Y%m%d')}.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(APP_NAME)

@app.route("/")
def index():
    msg = f"Hello from {APP_NAME}! Running on port {PORT}"
    logger.info(msg)
    return msg

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
