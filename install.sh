#!/bin/bash
#
#   Dante Socks5 服务器自动安装
#   -- 所有者:       https://www.inet.no/dante
#   -- 提供者:      https://sockd.info
#   -- 作者:        Lozy
#

# 检查是否是 root 用户
if [ $(id -u) != "0" ]; then
    echo "错误: 必须使用 root 用户运行此脚本，请使用 root 用户安装"
    exit 1
fi

REQUEST_SERVER="https://raw.github.com/Lozy/danted/master"
SCRIPT_SERVER="https://public.sockd.info"
SYSTEM_RECOGNIZE=""

[ "$1" == "--no-github" ] && REQUEST_SERVER=${SCRIPT_SERVER}

# 判断操作系统类型
if [ -s "/etc/os-release" ];then
    os_name=$(sed -n 's/PRETTY_NAME="\(.*\)"/\1/p' /etc/os-release)

    if [ -n "$(echo ${os_name} | grep -Ei 'Debian|Ubuntu' )" ];then
        printf "当前操作系统: %s\n" "${os_name}"
        SYSTEM_RECOGNIZE="debian"

    elif [ -n "$(echo ${os_name} | grep -Ei 'CentOS')" ];then
        printf "当前操作系统: %s\n" "${os_name}"
        SYSTEM_RECOGNIZE="centos"
    else
        printf "当前操作系统: %s 不支持.\n" "${os_name}"
    fi
elif [ -s "/etc/issue" ];then
    if [ -n "$(grep -Ei 'CentOS' /etc/issue)" ];then
        printf "当前操作系统: %s\n" "$(grep -Ei 'CentOS' /etc/issue)"
        SYSTEM_RECOGNIZE="centos"
    else
        printf "+++++++++++++++++++++++\n"
        cat /etc/issue
        printf "+++++++++++++++++++++++\n"
        printf "[错误] 当前操作系统: 不支持.\n"
    fi
else
    printf "[错误] (/etc/os-release) 或 (/etc/issue) 文件不存在！\n"
    printf "[错误] 当前操作系统: 不支持.\n"
fi

# 如果系统支持，下载并执行安装脚本
if [ -n "$SYSTEM_RECOGNIZE" ];then
    wget -qO- --no-check-certificate ${REQUEST_SERVER}/install_${SYSTEM_RECOGNIZE}.sh | \
        bash -s -- $*  | tee /tmp/danted_install.log
else
    printf "[错误] 安装终止\n"
    exit 1
fi

exit 0
