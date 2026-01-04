FROM python:3.9-alpine

LABEL maintainer="xjn@xxt.com"

WORKDIR /app

ENV APP_NAME="MyFlaskApp" \
    PORT=5000 \
    LOG_LEVEL="INFO"

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

RUN mkdir -p /app/logs && chmod 777 /app/logs

EXPOSE $PORT

CMD ["sh", "-c", "python app.py"]
