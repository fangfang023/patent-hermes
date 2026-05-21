# 基础镜像：python:3.11-slim
# start.sh 会自动从国内镜像源拉取，无需手动操作
# 手动构建时需加 DOCKER_BUILDKIT=0 避免远程验证超时：
#   DOCKER_BUILDKIT=0 docker compose build
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
   DEBIAN_FRONTEND=noninteractive \
   PIP_DISABLE_PIP_VERSION_CHECK=1 \
   PIP_NO_CACHE_DIR=1 \
   LANG=C.UTF-8 \
   LC_ALL=C.UTF-8

# pip 用清华源加速
RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple \
 && pip config set global.trusted-host pypi.tuna.tsinghua.edu.cn

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        git \
        ripgrep \
        ca-certificates \
        build-essential \
        procps \
        tini \
        less \
        jq \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip \
 && pip install hermes-agent pyyaml fastapi uvicorn websockets

RUN mkdir -p /app/patent-hermes-agent

WORKDIR /app/patent-hermes-agent

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["tail", "-f", "/dev/null"]