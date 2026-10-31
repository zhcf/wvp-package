# syntax=docker/dockerfile:1
# ==============================================================================
# WVP-PRO 3.0.0 镜像构建（多阶段，Linux 容器部署专用）
# ------------------------------------------------------------------------------
# 阶段 1: alpine/git             拉取源码（保留 .git，pom 中 git-commit-id 插件需要）
# 阶段 2: node:20                构建前端，产物输出到 src/main/resources/static
# 阶段 3: maven + temurin 21     打包后端，前端静态资源随 jar 一起发布（UI 内置）
# 阶段 4: eclipse-temurin:21-jre 运行时镜像
# ------------------------------------------------------------------------------
# 构建参数（由 docker-compose build.args 传入，默认值见 ../.env）：
#   WVP_GIT_URL  源码仓库地址（默认 gitee）
#   WVP_GIT_REF  分支或标签（默认 master）
# 说明：构建上下文为本目录（linux/online/），因此 COPY 路径相对于本目录
# ==============================================================================

# ------------------------------ 阶段 1：拉取源码 ------------------------------
FROM alpine/git:latest AS source
ARG WVP_GIT_URL=https://gitee.com/pan648540858/wvp-GB28181-pro.git
ARG WVP_GIT_REF=master
RUN git clone --depth 1 --branch "${WVP_GIT_REF}" "${WVP_GIT_URL}" /src

# ------------------------------ 阶段 2：构建前端 ------------------------------
# 使用 node 20（官方 CI 验证过的版本）；npm 走国内镜像加速
# 注：vue-cli 4.4.4 依赖 webpack 4.46（自带 wasm md4），Node20 下无需 openssl-legacy-provider；
#     若构建报 ERR_OSSL_EVP_UNSUPPORTED，将下行 ENV 中的注释去掉即可
FROM node:20-bookworm-slim AS web
ENV npm_config_registry=https://registry.npmmirror.com
# ENV NODE_OPTIONS=--openssl-legacy-provider
COPY --from=source /src /src
WORKDIR /src/web
RUN npm install --no-audit --no-fund \
    && npm run build:prod \
    && rm -rf node_modules

# ------------------------------ 阶段 3：Maven 打包 ------------------------------
# 此时 src/main/resources/static 已存在（前端产物），会被打进 jar
FROM maven:3.9-eclipse-temurin-21 AS build
COPY wvp-image/maven-settings.xml /root/.m2/settings.xml
COPY --from=web /src /src
WORKDIR /src
RUN mvn -B clean package -Dmaven.test.skip=true \
    && find /src/target -maxdepth 1 -name "wvp-pro-*.jar" ! -name "*sources*" ! -name "*javadoc*" -exec cp {} /tmp/wvp.jar \;

# ------------------------------ 阶段 4：运行时镜像 ------------------------------
FROM eclipse-temurin:21-jre-noble
LABEL org.opencontainers.image.title="wvp-pro" \
      org.opencontainers.image.description="WVP-PRO GB28181 platform (backend jar with built-in web UI)"
ENV TZ=Asia/Shanghai \
    JAVA_OPTS="-Xms512m -Xmx1024m -Duser.timezone=Asia/Shanghai"
WORKDIR /opt/wvp
# 应用 jar（已内置前端静态资源，启动即带 Web 页面）
COPY --from=build /tmp/wvp.jar /opt/wvp/wvp.jar
# 静态资源外部副本（兜底/可替换：如需更换前端，更新此目录后重启即可）
COPY --from=web /src/src/main/resources/static /opt/wvp/static
# 配置文件（经 --spring.config.location 全量替换加载，见 config/application.yml）
COPY config/application.yml /opt/wvp/config/application.yml
RUN mkdir -p /opt/wvp/logs
EXPOSE 18080 5060/tcp 5060/udp
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /opt/wvp/wvp.jar --spring.config.location=/opt/wvp/config/application.yml"]