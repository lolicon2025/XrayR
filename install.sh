#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

REPO="lolicon2025/XrayR"
BRANCH="master"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
INSTALL_SCRIPT_URL="${RAW_URL}/install.sh"
GITHUB_RELEASE_URL="https://github.com/${REPO}/releases/download"
GITHUB_API_URL="https://api.github.com/repos/${REPO}/releases/latest"

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif [[ -f /etc/issue ]] && cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif [[ -f /etc/issue ]] && cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif [[ -f /etc/issue ]] && cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif [[ -f /proc/version ]] && cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif [[ -f /proc/version ]] && cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif [[ -f /proc/version ]] && cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

detect_arch() {
    local sys_arch
    sys_arch=$(uname -m)

    case "${sys_arch}" in
        x86_64|amd64)
            echo "64"
            ;;
        i386|i686)
            echo "32"
            ;;
        aarch64|arm64)
            echo "arm64-v8a"
            ;;
        armv7l|armv7*)
            echo "arm32-v7a"
            ;;
        armv6l|armv6*)
            echo "arm32-v6"
            ;;
        armv5l|armv5*)
            echo "arm32-v5"
            ;;
        s390x)
            echo "s390x"
            ;;
        riscv64)
            echo "riscv64"
            ;;
        mips64le)
            echo "mips64le"
            ;;
        mips64)
            echo "mips64"
            ;;
        mipsle)
            echo "mips32le"
            ;;
        mips)
            echo "mips32"
            ;;
        ppc64le)
            echo "ppc64le"
            ;;
        *)
            echo -e "${red}检测架构失败，使用默认架构: 64${plain}" >&2
            echo "64"
            ;;
    esac
}

arch=$(detect_arch)

echo "架构: linux-${arch}"

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi

if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ -n "${os_version}" && ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ -n "${os_version}" && ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ -n "${os_version}" && ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat ca-certificates -y
    else
        apt update -y
        apt install wget curl unzip tar cron socat ca-certificates -y
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/XrayR.service ]]; then
        return 2
    fi

    if systemctl is-active --quiet XrayR; then
        return 0
    else
        return 1
    fi
}

create_service() {
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
WorkingDirectory=/usr/local/XrayR/
ExecStart=/usr/local/XrayR/XrayR --config /etc/XrayR/config.yml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

create_xrayr_command() {
    cat > /usr/bin/XrayR <<EOF
#!/bin/bash

red='\\033[0;31m'
green='\\033[0;32m'
yellow='\\033[0;33m'
plain='\\033[0m'

check_status() {
    if [[ ! -f /etc/systemd/system/XrayR.service ]]; then
        return 2
    fi

    if systemctl is-active --quiet XrayR; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    if systemctl is-enabled XrayR >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

check_install() {
    check_status
    if [[ \$? == 2 ]]; then
        echo -e "\${red}请先安装 XrayR\${plain}"
        return 1
    fi
    return 0
}

start() {
    systemctl start XrayR
    sleep 2
    check_status
    if [[ \$? == 0 ]]; then
        echo -e "\${green}XrayR 启动成功，请使用 XrayR log 查看运行日志\${plain}"
    else
        echo -e "\${red}XrayR 可能启动失败，请使用 XrayR log 查看日志信息\${plain}"
    fi
}

stop() {
    systemctl stop XrayR
    sleep 2
    check_status
    if [[ \$? == 1 ]]; then
        echo -e "\${green}XrayR 停止成功\${plain}"
    else
        echo -e "\${red}XrayR 停止失败，请查看日志信息\${plain}"
    fi
}

restart() {
    systemctl restart XrayR
    sleep 2
    check_status
    if [[ \$? == 0 ]]; then
        echo -e "\${green}XrayR 重启成功，请使用 XrayR log 查看运行日志\${plain}"
    else
        echo -e "\${red}XrayR 可能启动失败，请使用 XrayR log 查看日志信息\${plain}"
    fi
}

status() {
    systemctl status XrayR --no-pager -l
}

enable() {
    systemctl enable XrayR
    if [[ \$? == 0 ]]; then
        echo -e "\${green}XrayR 设置开机自启成功\${plain}"
    else
        echo -e "\${red}XrayR 设置开机自启失败\${plain}"
    fi
}

disable() {
    systemctl disable XrayR
    if [[ \$? == 0 ]]; then
        echo -e "\${green}XrayR 取消开机自启成功\${plain}"
    else
        echo -e "\${red}XrayR 取消开机自启失败\${plain}"
    fi
}

show_log() {
    journalctl -u XrayR.service -e --no-pager -f
}

config() {
    echo "XrayR 配置文件：/etc/XrayR/config.yml"
    \${EDITOR:-vi} /etc/XrayR/config.yml
}

update() {
    if [[ -n "\$2" ]]; then
        bash <(curl -Ls ${INSTALL_SCRIPT_URL}) "\$2"
    else
        bash <(curl -Ls ${INSTALL_SCRIPT_URL})
    fi
}

uninstall() {
    echo -e "\${yellow}正在卸载 XrayR...\${plain}"
    systemctl stop XrayR 2>/dev/null
    systemctl disable XrayR 2>/dev/null
    rm -f /etc/systemd/system/XrayR.service
    systemctl daemon-reload
    systemctl reset-failed
    rm -rf /usr/local/XrayR/
    rm -f /usr/bin/XrayR
    rm -f /usr/bin/xrayr
    echo -e "\${green}XrayR 已卸载。配置文件 /etc/XrayR/ 未删除，如需彻底删除请手动执行：rm -rf /etc/XrayR/\${plain}"
}

show_version() {
    /usr/local/XrayR/XrayR version
}

show_usage() {
    echo "XrayR 管理脚本使用方法:"
    echo "------------------------------------------"
    echo "XrayR start              - 启动 XrayR"
    echo "XrayR stop               - 停止 XrayR"
    echo "XrayR restart            - 重启 XrayR"
    echo "XrayR status             - 查看 XrayR 状态"
    echo "XrayR enable             - 设置 XrayR 开机自启"
    echo "XrayR disable            - 取消 XrayR 开机自启"
    echo "XrayR log                - 查看 XrayR 日志"
    echo "XrayR update             - 更新 XrayR"
    echo "XrayR update x.x.x       - 更新 XrayR 指定版本"
    echo "XrayR config             - 编辑配置文件"
    echo "XrayR uninstall          - 卸载 XrayR"
    echo "XrayR version            - 查看 XrayR 版本"
    echo "------------------------------------------"
}

show_status() {
    check_status
    case \$? in
        0)
            echo -e "XrayR 状态: \${green}已运行\${plain}"
            ;;
        1)
            echo -e "XrayR 状态: \${yellow}未运行\${plain}"
            ;;
        2)
            echo -e "XrayR 状态: \${red}未安装\${plain}"
            ;;
    esac

    check_enabled
    if [[ \$? == 0 ]]; then
        echo -e "是否开机自启: \${green}是\${plain}"
    else
        echo -e "是否开机自启: \${red}否\${plain}"
    fi
}

show_menu() {
    echo -e "
\${green}XrayR 后端管理脚本\${plain} --- https://github.com/${REPO}

\${green}0.\${plain} 修改配置
\${green}1.\${plain} 启动 XrayR
\${green}2.\${plain} 停止 XrayR
\${green}3.\${plain} 重启 XrayR
\${green}4.\${plain} 查看 XrayR 状态
\${green}5.\${plain} 查看 XrayR 日志
\${green}6.\${plain} 设置开机自启
\${green}7.\${plain} 取消开机自启
\${green}8.\${plain} 更新 XrayR
\${green}9.\${plain} 查看 XrayR 版本
\${green}10.\${plain} 卸载 XrayR
"
    show_status
    echo
    read -p "请输入选择 [0-10]: " num

    case "\${num}" in
        0) check_install && config ;;
        1) check_install && start ;;
        2) check_install && stop ;;
        3) check_install && restart ;;
        4) check_install && status ;;
        5) check_install && show_log ;;
        6) check_install && enable ;;
        7) check_install && disable ;;
        8) check_install && update ;;
        9) check_install && show_version ;;
        10) check_install && uninstall ;;
        *) echo -e "\${red}请输入正确的数字 [0-10]\${plain}" ;;
    esac
}

if [[ \$# > 0 ]]; then
    case "\$1" in
        start)
            check_install && start
            ;;
        stop)
            check_install && stop
            ;;
        restart)
            check_install && restart
            ;;
        status)
            check_install && status
            ;;
        enable)
            check_install && enable
            ;;
        disable)
            check_install && disable
            ;;
        log)
            check_install && show_log
            ;;
        update)
            check_install && update "\$@"
            ;;
        config)
            check_install && config
            ;;
        uninstall)
            check_install && uninstall
            ;;
        version)
            check_install && show_version
            ;;
        *)
            show_usage
            ;;
    esac
else
    show_menu
fi
EOF

    chmod +x /usr/bin/XrayR
    ln -sf /usr/bin/XrayR /usr/bin/xrayr
}

download_xrayr() {
    local version="$1"
    local url="${GITHUB_RELEASE_URL}/${version}/XrayR-linux-${arch}.zip"

    echo -e "下载地址：${url}"

    wget -q -N --no-check-certificate -O /usr/local/XrayR/XrayR-linux.zip "${url}"
    return $?
}

install_XrayR() {
    if [[ -e /usr/local/XrayR/ ]]; then
        rm -rf /usr/local/XrayR/
    fi

    mkdir -p /usr/local/XrayR/
    cd /usr/local/XrayR/ || exit 1

    if [[ $# == 0 ]]; then
        last_version=$(curl -Ls "${GITHUB_API_URL}" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 XrayR 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 XrayR 版本安装${plain}"
            exit 1
        fi

        echo -e "检测到 XrayR 最新版本：${last_version}，开始安装"
    else
        # 这里使用你输入的版本号，不自动补 v。
        # 因为你的 release tag 是 0.9.8，不是 v0.9.8。
        last_version="$1"
        echo -e "开始安装 XrayR ${last_version}"
    fi

    download_xrayr "${last_version}"

    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载 XrayR ${last_version} 失败。${plain}"
        echo -e "${yellow}请确认 Release 中存在文件：XrayR-linux-${arch}.zip${plain}"
        echo -e "${yellow}当前尝试下载的版本标签：${last_version}${plain}"
        exit 1
    fi

    unzip -o XrayR-linux.zip
    rm -f XrayR-linux.zip

    if [[ ! -f /usr/local/XrayR/XrayR ]]; then
        echo -e "${red}安装失败：压缩包内没有找到 XrayR 可执行文件${plain}"
        exit 1
    fi

    chmod +x /usr/local/XrayR/XrayR

    mkdir -p /etc/XrayR/

    # 复制默认配置和资源文件；已有配置不覆盖
    if [[ ! -f /etc/XrayR/config.yml ]]; then
        if [[ -f /usr/local/XrayR/config.yml ]]; then
            cp /usr/local/XrayR/config.yml /etc/XrayR/config.yml
        fi
    fi

    if [[ -f /usr/local/XrayR/geoip.dat ]]; then
        cp /usr/local/XrayR/geoip.dat /etc/XrayR/
    fi

    if [[ -f /usr/local/XrayR/geosite.dat ]]; then
        cp /usr/local/XrayR/geosite.dat /etc/XrayR/
    fi

    if [[ ! -f /etc/XrayR/dns.json && -f /usr/local/XrayR/dns.json ]]; then
        cp /usr/local/XrayR/dns.json /etc/XrayR/
    fi

    if [[ ! -f /etc/XrayR/route.json && -f /usr/local/XrayR/route.json ]]; then
        cp /usr/local/XrayR/route.json /etc/XrayR/
    fi

    if [[ ! -f /etc/XrayR/custom_outbound.json && -f /usr/local/XrayR/custom_outbound.json ]]; then
        cp /usr/local/XrayR/custom_outbound.json /etc/XrayR/
    fi

    if [[ ! -f /etc/XrayR/custom_inbound.json && -f /usr/local/XrayR/custom_inbound.json ]]; then
        cp /usr/local/XrayR/custom_inbound.json /etc/XrayR/
    fi

    if [[ ! -f /etc/XrayR/rulelist && -f /usr/local/XrayR/rulelist ]]; then
        cp /usr/local/XrayR/rulelist /etc/XrayR/
    fi

    rm -f /etc/systemd/system/XrayR.service
    create_service

    systemctl daemon-reload
    systemctl stop XrayR 2>/dev/null
    systemctl enable XrayR

    create_xrayr_command

    echo -e "${green}XrayR ${last_version}${plain} 安装完成，已设置开机自启"

    if [[ ! -f /etc/XrayR/config.yml ]]; then
        echo -e ""
        echo -e "${red}未找到 /etc/XrayR/config.yml，请手动创建配置文件。${plain}"
        echo -e "项目地址：https://github.com/${REPO}"
    else
        echo -e ""
        echo -e "${yellow}配置文件路径：/etc/XrayR/config.yml${plain}"

        systemctl start XrayR
        sleep 2

        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}XrayR 启动成功${plain}"
        else
            echo -e "${red}XrayR 可能启动失败，请稍后使用 XrayR log 查看日志信息。${plain}"
        fi
    fi

    cd "$cur_dir" || exit 1

    echo -e ""
    echo "XrayR 管理脚本使用方法，兼容使用 xrayr 执行："
    echo "------------------------------------------"
    echo "XrayR                    - 显示管理菜单"
    echo "XrayR start              - 启动 XrayR"
    echo "XrayR stop               - 停止 XrayR"
    echo "XrayR restart            - 重启 XrayR"
    echo "XrayR status             - 查看 XrayR 状态"
    echo "XrayR enable             - 设置 XrayR 开机自启"
    echo "XrayR disable            - 取消 XrayR 开机自启"
    echo "XrayR log                - 查看 XrayR 日志"
    echo "XrayR update             - 更新 XrayR"
    echo "XrayR update x.x.x       - 更新 XrayR 指定版本"
    echo "XrayR config             - 编辑配置文件"
    echo "XrayR uninstall          - 卸载 XrayR"
    echo "XrayR version            - 查看 XrayR 版本"
    echo "------------------------------------------"
}

echo -e "${green}开始安装${plain}"
install_base
install_XrayR "$1"
