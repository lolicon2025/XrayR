#!/bin/sh

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

REPO="lolicon2025/XrayR"
BRANCH="master"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
INSTALL_SCRIPT_URL="${RAW_URL}/install-all.sh"
GITHUB_API_URL="https://api.github.com/repos/${REPO}/releases/latest"
GITHUB_RELEASE_URL="https://github.com/${REPO}/releases/download"

INSTALL_DIR="/usr/local/XrayR"
CONFIG_DIR="/etc/XrayR"

# 1. 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo -e "${red}错误：${plain} 必须使用 root 用户运行此脚本！\n"
    exit 1
fi

# 2. 系统检测
if [ -f /etc/os-release ]; then
    . /etc/os-release
    release="$ID"
elif [ -f /etc/redhat-release ]; then
    release="centos"
elif grep -Eqi "debian" /etc/issue 2>/dev/null; then
    release="debian"
elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null; then
    release="ubuntu"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n"
    exit 1
fi

case "$release" in
    ubuntu|debian|alpine|centos)
        ;;
    rocky|alma|rhel|fedora)
        release="centos"
        ;;
    *)
        echo -e "${red}暂不支持您的系统: ${release}${plain}\n"
        exit 1
        ;;
esac

# 3. 架构检测
sys_arch=$(uname -m)

case "$sys_arch" in
    x86_64|amd64)
        arch="64"
        ;;
    i386|i686)
        arch="32"
        ;;
    aarch64|arm64)
        arch="arm64-v8a"
        ;;
    armv7l|armv7*)
        arch="arm32-v7a"
        ;;
    armv6l|armv6*)
        arch="arm32-v6"
        ;;
    armv5l|armv5*)
        arch="arm32-v5"
        ;;
    s390x)
        arch="s390x"
        ;;
    riscv64)
        arch="riscv64"
        ;;
    mips64le)
        arch="mips64le"
        ;;
    mips64)
        arch="mips64"
        ;;
    mipsle)
        arch="mips32le"
        ;;
    mips)
        arch="mips32"
        ;;
    ppc64le)
        arch="ppc64le"
        ;;
    *)
        echo -e "${red}暂不支持此系统架构: ${sys_arch}${plain}"
        exit 1
        ;;
esac

echo -e "${green}检测到系统：${release}${plain}"
echo -e "${green}检测到架构：linux-${arch}${plain}"

# 4. 系统版本检查
os_version=""

if [ -n "$VERSION_ID" ]; then
    os_version=$(echo "$VERSION_ID" | awk -F. '{print $1}')
fi

if [ "$release" = "centos" ]; then
    if [ -n "$os_version" ] && [ "$os_version" -le 6 ]; then
        echo -e "${red}请使用 CentOS 7 / Rocky / AlmaLinux / RHEL 7 或更高版本！${plain}\n"
        exit 1
    fi
elif [ "$release" = "ubuntu" ]; then
    if [ -n "$os_version" ] && [ "$os_version" -lt 16 ]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本！${plain}\n"
        exit 1
    fi
elif [ "$release" = "debian" ]; then
    if [ -n "$os_version" ] && [ "$os_version" -lt 8 ]; then
        echo -e "${red}请使用 Debian 8 或更高版本！${plain}\n"
        exit 1
    fi
fi

install_base() {
    echo -e "${green}开始安装基础依赖...${plain}"

    if [ "$release" = "centos" ]; then
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y epel-release >/dev/null 2>&1 || true
            dnf install -y wget curl unzip tar cronie socat ca-certificates
        else
            yum install -y epel-release >/dev/null 2>&1 || true
            yum install -y wget curl unzip tar cronie socat ca-certificates
        fi
    elif [ "$release" = "alpine" ]; then
        apk update
        apk add --no-cache wget curl unzip tar socat ca-certificates openrc dcron
        rc-update add dcron default >/dev/null 2>&1 || true
        rc-service dcron start >/dev/null 2>&1 || rc-service cron start >/dev/null 2>&1 || true
    else
        apt update -y
        apt install -y wget curl unzip tar cron socat ca-certificates
    fi
}

check_status() {
    if [ "$release" = "alpine" ]; then
        if [ ! -f /etc/init.d/XrayR ]; then
            return 2
        fi

        if rc-service XrayR status 2>&1 | grep -q "started"; then
            return 0
        else
            return 1
        fi
    else
        if [ ! -f /etc/systemd/system/XrayR.service ]; then
            return 2
        fi

        if systemctl is-active --quiet XrayR; then
            return 0
        else
            return 1
        fi
    fi
}

get_latest_version() {
    curl -Ls "$GITHUB_API_URL" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | head -n 1
}

create_systemd_service() {
    echo -e "${yellow}检测到 systemd 系统，正在创建 systemd 服务...${plain}"

    rm -f /etc/systemd/system/XrayR.service

    cat > /etc/systemd/system/XrayR.service <<EOF
[Unit]
Description=XrayR Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/XrayR --config ${CONFIG_DIR}/config.yml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl stop XrayR >/dev/null 2>&1 || true
    systemctl enable XrayR
}

create_openrc_service() {
    echo -e "${yellow}检测到 Alpine/OpenRC 系统，正在创建 OpenRC 服务...${plain}"

    rm -f /etc/init.d/XrayR

    cat > /etc/init.d/XrayR <<EOF
#!/sbin/openrc-run

name="XrayR"
description="XrayR Service"

supervisor="supervise-daemon"
command="${INSTALL_DIR}/XrayR"
command_args="--config ${CONFIG_DIR}/config.yml"
command_user="root"
directory="${INSTALL_DIR}"

required_files="${CONFIG_DIR}/config.yml"

respawn_delay=5
respawn_max=0

output_log="/var/log/XrayR/XrayR.log"
error_log="/var/log/XrayR/XrayR.err"

depend() {
    need net
    use dns
}

start_pre() {
    checkpath --directory --mode 0755 /var/log/XrayR
    checkpath --file --mode 0644 /var/log/XrayR/XrayR.log
    checkpath --file --mode 0644 /var/log/XrayR/XrayR.err
}
EOF

    chmod +x /etc/init.d/XrayR
    rc-service XrayR stop >/dev/null 2>&1 || true
    rc-update add XrayR default
}

create_manage_command() {
    cat > /usr/bin/XrayR <<EOF
#!/bin/sh

red='\\033[0;31m'
green='\\033[0;32m'
yellow='\\033[0;33m'
plain='\\033[0m'

is_openrc() {
    [ -f /etc/init.d/XrayR ] && command -v rc-service >/dev/null 2>&1
}

is_systemd() {
    [ -f /etc/systemd/system/XrayR.service ] && command -v systemctl >/dev/null 2>&1
}

start_service() {
    if is_openrc; then
        rc-service XrayR start
    else
        systemctl start XrayR
    fi
}

stop_service() {
    if is_openrc; then
        rc-service XrayR stop
    else
        systemctl stop XrayR
    fi
}

restart_service() {
    if is_openrc; then
        rc-service XrayR restart
    else
        systemctl restart XrayR
    fi
}

status_service() {
    if is_openrc; then
        rc-service XrayR status
    else
        systemctl status XrayR --no-pager -l
    fi
}

enable_service() {
    if is_openrc; then
        rc-update add XrayR default
    else
        systemctl enable XrayR
    fi
}

disable_service() {
    if is_openrc; then
        rc-update del XrayR default
    else
        systemctl disable XrayR
    fi
}

log_service() {
    if is_openrc; then
        echo "标准日志：/var/log/XrayR/XrayR.log"
        echo "错误日志：/var/log/XrayR/XrayR.err"
        tail -f /var/log/XrayR/XrayR.log /var/log/XrayR/XrayR.err
    else
        journalctl -u XrayR.service -e --no-pager -f
    fi
}

config_service() {
    \${EDITOR:-vi} /etc/XrayR/config.yml
}

update_service() {
    if [ -n "\$2" ]; then
        curl -fsSL "${INSTALL_SCRIPT_URL}" | sh -s -- "\$2"
    else
        curl -fsSL "${INSTALL_SCRIPT_URL}" | sh
    fi
}

uninstall_service() {
    echo -e "\${yellow}正在卸载 XrayR...\${plain}"

    if is_openrc; then
        rc-service XrayR stop >/dev/null 2>&1 || true
        rc-update del XrayR default >/dev/null 2>&1 || true
        rm -f /etc/init.d/XrayR
    elif is_systemd; then
        systemctl stop XrayR >/dev/null 2>&1 || true
        systemctl disable XrayR >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/XrayR.service
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl reset-failed >/dev/null 2>&1 || true
    fi

    rm -rf /usr/local/XrayR
    rm -f /usr/bin/XrayR /usr/bin/xrayr

    echo -e "\${green}XrayR 已卸载。配置文件 /etc/XrayR 未删除。${plain}"
}

version_service() {
    /usr/local/XrayR/XrayR version
}

show_usage() {
    echo "XrayR 管理脚本使用方法："
    echo "------------------------------------------"
    echo "XrayR start              - 启动 XrayR"
    echo "XrayR stop               - 停止 XrayR"
    echo "XrayR restart            - 重启 XrayR"
    echo "XrayR status             - 查看 XrayR 状态"
    echo "XrayR enable             - 设置开机自启"
    echo "XrayR disable            - 取消开机自启"
    echo "XrayR log                - 查看日志"
    echo "XrayR update             - 更新最新版"
    echo "XrayR update x.x.x       - 更新指定版本"
    echo "XrayR config             - 编辑配置文件"
    echo "XrayR version            - 查看版本"
    echo "XrayR uninstall          - 卸载 XrayR"
    echo "------------------------------------------"
}

case "\$1" in
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    status)
        status_service
        ;;
    enable)
        enable_service
        ;;
    disable)
        disable_service
        ;;
    log)
        log_service
        ;;
    update)
        update_service "\$@"
        ;;
    config)
        config_service
        ;;
    version)
        version_service
        ;;
    uninstall)
        uninstall_service
        ;;
    *)
        show_usage
        ;;
esac
EOF

    chmod +x /usr/bin/XrayR
    ln -sf /usr/bin/XrayR /usr/bin/xrayr
}

copy_config_files() {
    mkdir -p "$CONFIG_DIR"

    if [ ! -f "${CONFIG_DIR}/config.yml" ] && [ -f "${INSTALL_DIR}/config.yml" ]; then
        cp "${INSTALL_DIR}/config.yml" "${CONFIG_DIR}/config.yml"
    fi

    for file in geoip.dat geosite.dat; do
        if [ -f "${INSTALL_DIR}/${file}" ]; then
            cp "${INSTALL_DIR}/${file}" "${CONFIG_DIR}/${file}"
        fi
    done

    for file in dns.json route.json custom_outbound.json custom_inbound.json rulelist; do
        if [ ! -f "${CONFIG_DIR}/${file}" ] && [ -f "${INSTALL_DIR}/${file}" ]; then
            cp "${INSTALL_DIR}/${file}" "${CONFIG_DIR}/${file}"
        fi
    done
}

download_xrayr() {
    version="$1"
    url="${GITHUB_RELEASE_URL}/${version}/XrayR-linux-${arch}.zip"

    echo -e "${green}下载地址：${url}${plain}"

    wget -q -N --no-check-certificate -O "${INSTALL_DIR}/XrayR-linux.zip" "$url"
}

install_XrayR() {
    if [ -e "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
    fi

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR" || exit 1

    if [ "$#" -eq 0 ] || [ -z "$1" ]; then
        last_version=$(get_latest_version)

        if [ -z "$last_version" ]; then
            echo -e "${red}检测 XrayR 版本失败，可能是 GitHub API 限制或网络问题。${plain}"
            echo -e "${yellow}你可以手动指定版本，例如：curl -fsSL ${INSTALL_SCRIPT_URL} | sh -s -- 0.9.8${plain}"
            exit 1
        fi

        echo -e "${green}检测到 XrayR 最新版本：${last_version}，开始安装${plain}"
    else
        # 不自动补 v，因为你的 Release tag 是 0.9.8，不是 v0.9.8
        last_version="$1"
        echo -e "${green}开始安装 XrayR ${last_version}${plain}"
    fi

    download_xrayr "$last_version"

    if [ "$?" -ne 0 ]; then
        echo -e "${red}下载 XrayR ${last_version} 失败。${plain}"
        echo -e "${yellow}请确认 Release 中存在文件：XrayR-linux-${arch}.zip${plain}"
        echo -e "${yellow}当前尝试下载的版本标签：${last_version}${plain}"
        exit 1
    fi

    unzip -o XrayR-linux.zip
    rm -f XrayR-linux.zip

    if [ ! -f "${INSTALL_DIR}/XrayR" ]; then
        echo -e "${red}安装失败：压缩包内没有找到 XrayR 可执行文件。${plain}"
        exit 1
    fi

    chmod +x "${INSTALL_DIR}/XrayR"

    copy_config_files

    if [ "$release" = "alpine" ]; then
        create_openrc_service
    else
        create_systemd_service
    fi

    create_manage_command

    echo -e "${green}XrayR ${last_version} 安装完成，已设置开机自启。${plain}"

    if [ ! -f "${CONFIG_DIR}/config.yml" ]; then
        echo -e ""
        echo -e "${yellow}全新安装，但未找到 ${CONFIG_DIR}/config.yml。${plain}"
        echo -e "${yellow}请先创建或上传配置文件，然后执行：XrayR start${plain}"
        echo -e "项目地址：https://github.com/${REPO}"
    else
        if [ "$release" = "alpine" ]; then
            rc-service XrayR start
        else
            systemctl start XrayR
        fi

        sleep 2

        check_status
        if [ "$?" -eq 0 ]; then
            echo -e "${green}XrayR 启动/重启成功。${plain}"
        else
            echo -e "${red}XrayR 可能启动失败，请使用 XrayR log 查看日志。${plain}"
        fi
    fi

    cd "$cur_dir" || exit 1

    echo -e ""
    echo "XrayR 管理脚本使用方法，兼容使用 xrayr 执行："
    echo "------------------------------------------"
    echo "XrayR start              - 启动 XrayR"
    echo "XrayR stop               - 停止 XrayR"
    echo "XrayR restart            - 重启 XrayR"
    echo "XrayR status             - 查看 XrayR 状态"
    echo "XrayR enable             - 设置 XrayR 开机自启"
    echo "XrayR disable            - 取消 XrayR 开机自启"
    echo "XrayR log                - 查看日志"
    echo "XrayR update             - 更新最新版"
    echo "XrayR update x.x.x       - 更新指定版本"
    echo "XrayR config             - 编辑配置文件"
    echo "XrayR uninstall          - 卸载 XrayR"
    echo "XrayR version            - 查看 XrayR 版本"
    echo "------------------------------------------"
}

echo -e "${green}开始安装流程...${plain}"
install_base
install_XrayR "$@"
