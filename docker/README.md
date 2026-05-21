# Patent Hermes Agent · Docker 部署

## 快速启动

```bash
# 1. 填写环境变量
cd docker && cp .env.example .env
# 编辑 .env，填入 API Key 和飞书机器人配置

# 2. 启动
./start.sh
```

## 端口说明

| 端口 | 容器内 | 宿主机（默认） | 说明 |
|------|--------|---------------|------|
| 9119 | Dashboard | 9130 | Hermes Dashboard |
| 8765 | Gateway | 8790 | Gateway / 飞书 Webhook |
| 9131 | Output Server | 9131 | 输出文件 HTTP 服务 |

端口通过 `.env` 中的 `DASHBOARD_HOST_PORT` / `GATEWAY_HOST_PORT` / `OUTPUT_HOST_PORT` 配置。

## 常用命令

```bash
# 启动
./docker/start.sh

# 进入容器
docker exec -it patent-hermes-agent bash

# 查看日志
docker logs -f patent-hermes-agent

# 在容器内手动触发任务
docker exec -it patent-hermes-agent hermes -z "生成技术交底书..."

# 停止（容器内执行 scripts/stop.sh）
docker exec patent-hermes-agent bash /app/patent-hermes-agent/scripts/stop.sh
```

## 手动构建

如果 `start.sh` 自动构建失败，可手动执行：

```bash
DOCKER_BUILDKIT=0 docker compose -f docker/docker-compose.yml build
docker compose -f docker/docker-compose.yml up -d
```