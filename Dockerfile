# 115 Linux browser + KasmVNC web desktop
# Port of github.com/dream10201/115Docker: TigerVNC+noVNC -> KasmVNC 1.5.0.
# amd64 only (the 115 Linux .deb ships amd64).
FROM docker.io/library/ubuntu:24.04

ARG VERSION=""
ARG KASM_VERSION=1.5.0
ARG KASM_DIST=noble

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/root \
    DISPLAY=:99 \
    WEB_PORT=2250 \
    LD_LIBRARY_PATH=/usr/local/115Browser \
    DISPLAY_WIDTH=1920 \
    DISPLAY_HEIGHT=1080 \
    AUTO_START=false \
    VNC_ENABLED=true \
    VNC_USER=kasm \
    PASSWORD=123456 \
    TINT2_CONF=/etc/115-kasm/tint2rc \
    TZ=Asia/Shanghai \
    LC_ALL=zh_CN.UTF-8 \
    LANG=zh_CN.UTF-8

# ------------------------------------------------ KasmVNC server + X desktop
RUN set -eux; \
    apt-get -qq update; \
    apt-get -qq install -y --no-install-recommends \
        ca-certificates curl wget unzip xz-utils openssl procps jq \
        locales tzdata; \
    curl -fsSL -o /tmp/kasmvnc.deb \
        "https://github.com/kasmtech/KasmVNC/releases/download/v${KASM_VERSION}/kasmvncserver_${KASM_DIST}_${KASM_VERSION}_amd64.deb"; \
    apt-get -qq install -y /tmp/kasmvnc.deb; \
    rm -f /tmp/kasmvnc.deb; \
    apt-get -qq install -y --no-install-recommends \
        pcmanfm tint2 openbox xterm libasound2t64 \
        x11-xserver-utils x11-utils dbus-x11 at-spi2-core \
        fontconfig fonts-liberation fonts-noto-cjk fonts-wqy-zenhei; \
    localedef -i zh_CN -c -f UTF-8 -A /usr/share/locale/locale.alias zh_CN.UTF-8; \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------ 115 Linux browser
# Upstream Dockerfile used /client/lin/ which now 404s; the working path is
# /client/115pc/lin/ (matches the version API's version_url field).
RUN set -eux; \
    apt-get -qq update; \
    apt-get -qq install -y --no-install-recommends libnss3 libgbm1; \
    if [ -z "$VERSION" ]; then \
        VERSION=$(curl -k -s https://appversion.115.com/1/web/1.0/api/getMultiVer \
            | jq -r '.data["Linux-115chrome"].version_code'); \
    fi; \
    echo "installing 115browser v${VERSION}"; \
    wget -q --no-check-certificate \
        "https://down.115.com/client/115pc/lin/115br_v${VERSION}.deb" -O /tmp/115.deb; \
    apt-get -qq install -y /tmp/115.deb; \
    rm -f /tmp/115.deb; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

# ------------------------------------------------- 115Cookie auto-login ext
RUN set -eux; \
    wget -q https://github.com/dream10201/115Cookie/archive/refs/heads/master.zip -O /tmp/cookie.zip; \
    mkdir -p /usr/local/115Cookie; \
    unzip -q /tmp/cookie.zip -d /tmp/cookie; \
    cp -a /tmp/cookie/115Cookie-master/. /usr/local/115Cookie/; \
    rm -rf /tmp/cookie /tmp/cookie.zip

# --------------------------------------------------------- desktop layout
COPY kasm/tint2rc /etc/115-kasm/tint2rc
COPY kasm/skel-config /etc/115-kasm/skel-config
COPY 115.sh /usr/local/115Browser/115.sh
COPY run.sh /opt/run.sh
RUN set -eux; \
    chmod 755 /opt/run.sh /usr/local/115Browser/115.sh; \
    mkdir -p /opt/Desktop /etc/115; \
    cp /usr/share/applications/115Browser.desktop /opt/Desktop/; \
    cp /usr/share/applications/pcmanfm.desktop /opt/Desktop/ 2>/dev/null || true; \
    sed -i 's|^Exec=.*|Exec=/usr/local/115Browser/115.sh|' /opt/Desktop/115Browser.desktop; \
    ln -sfn /opt/Desktop /root/Desktop; \
    chmod -R 777 /opt /etc/115 /usr/local/115Cookie

EXPOSE 2250
CMD ["bash", "/opt/run.sh"]
