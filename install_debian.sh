#!/bin/bash
#
# 提供: sockd.info (Lozy)
#

VERSION="1.4.3"  # 版本号
INSTALL_FROM="compile"  # 安装方式，默认从源码编译安装
DEFAULT_PORT="2024"  # 默认端口
DEFAULT_USER=""  # 默认用户名
DEFAULT_PAWD=""  # 默认密码
WHITE_LIST_NET=""  # 允许访问的网络列表
WHITE_LIST=""  # 允许访问的 IP 列表
SCRIPT_HOST="https://public.sockd.info"  # 脚本下载地址
PACKAGE_NAME="dante_1.3.2-1_$(uname -m).deb"  # 软件包名称
COLOR_PATH="/etc/default/color"  # 颜色配置文件路径

BIN_DIR="/etc/danted"  # 二进制文件目录
BIN_PATH="/etc/danted/sbin/sockd"  # 可执行文件路径
CONFIG_PATH="/etc/danted/sockd.conf"  # 配置文件路径
BIN_SCRIPT="/etc/init.d/sockd"  # 服务启动脚本

# 获取默认 IP 地址，排除本地回环地址（127.0.0.1）和私有地址（192.168.x.x）
DEFAULT_IPADDR=$(ip addr | grep 'inet ' | grep -Ev 'inet 127|inet 192\.168' | \
            sed "s/[[:space:]]*inet \([0-9.]*\)\/.*/\1/")
RUN_OPTS=$*

##################------------函数定义---------#####################################

# 删除已安装的 Dante
remove_install(){
    [ -s "${BIN_SCRIPT}" ] && ${BIN_SCRIPT} stop > /dev/null 2>&1  # 停止服务
    [ -f "${BIN_SCRIPT}" ] && rm "${BIN_SCRIPT}"  # 删除服务脚本
    [ -n "$BIN_DIR" ] && rm -r "$BIN_DIR"  # 删除程序目录
}

# 检测是否已安装 Dante
detect_install(){
    if [ -s "${BIN_PATH}" ];then
        echo "Dante socks5 已安装"
        ${BIN_PATH} -v
    fi
}

# 生成配置文件的 IP 地址部分
generate_config_ip(){
    local ipaddr="$1"
    local port="$2"

    cat <<EOF
# 生成接口 ${ipaddr}
internal: ${ipaddr}  port = ${port}
external: ${ipaddr}

EOF
}

# 生成多个 IP 地址的配置
generate_config_iplist(){
    local ipaddr_list="$1"
    local port="$2"

    [ -z "${ipaddr_list}" ] && return 1
    [ -z "${port}" ] && return 2

    for ipaddr in ${ipaddr_list};do
        generate_config_ip "${ipaddr}" "${port}" >> ${CONFIG_PATH}
    done

    ipaddr_array=("$ipaddr_list")

    if [ ${#ipaddr_array[@]} -gt 1 ];then
        echo "external.rotation: same-same" >> ${CONFIG_PATH}
    fi
}

# 生成静态配置
generate_config_static(){
    if [ "$VERSION" == "1.4.3" ];then
    cat <<EOF
method: pam none
clientmethod: none
user.privileged: root
user.notprivileged: sockd
logoutput: /var/log/sockd.log

client pass {
        from: 0.0.0.0/0  to: 0.0.0.0/0
}
client block {
        from: 0.0.0.0/0 to: 0.0.0.0/0
}
EOF
    else
    cat <<EOF
clientmethod: none
socksmethod: pam.username none

user.privileged: root
user.notprivileged: sockd

logoutput: /var/log/sockd.log

client pass {
    from: 0/0  to: 0/0
    log: connect disconnect
}
client block {
    from: 0/0 to: 0/0
    log: connect error
}
EOF
    fi
}

# 生成白名单 IP 规则
generate_config_white(){
    local white_ipaddr="$1"

    [ -z "${white_ipaddr}" ] && return 1

    for ipaddr_range in ${white_ipaddr};do
        cat <<EOF
#------------ 受信任的网络: ${ipaddr_range} ---------------
pass {
        from: ${ipaddr_range} to: 0.0.0.0/0
        method: none
}

EOF
    done
}

# 从在线地址获取白名单 IP 并生成规则
generate_config_whitelist(){
    local whitelist_url="$1"

    if [ -n "${whitelist_url}" ];then
        ipaddr_list=$(curl -s --insecure -A "Mozilla Server Init" "${whitelist_url}")
        generate_config_white "${ipaddr_list}"
    fi
}

# 生成底部配置（访问控制规则）
generate_config_bottom(){
    if [ "$VERSION" == "1.4.3" ];then
    cat <<EOF
pass {
        from: 0.0.0.0/0 to: 0.0.0.0/0
        protocol: tcp udp
        method: pam
        log: connect disconnect
}
block {
        from: 0.0.0.0/0 to: 0.0.0.0/0
        log: connect error
}

EOF
    else
    cat <<EOF
socks pass {
    from: 0/0 to: 0/0
    socksmethod: pam.username
    log: connect disconnect
}
socks block {
    from: 0/0 to: 0/0
    log: connect error
}

EOF
    fi
}

# 生成完整的配置文件
generate_config(){
    local ipaddr_list="$1"
    local whitelist_url="$2"
    local whitelist_ip="$3"

    mkdir -p ${BIN_DIR}

    echo "# 由 sockd.info 生成" > ${CONFIG_PATH}

    generate_config_iplist "${ipaddr_list}" "${DEFAULT_PORT}" >> ${CONFIG_PATH}

    generate_config_static >> ${CONFIG_PATH}
    generate_config_white "${whitelist_ip}" >> ${CONFIG_PATH}
    generate_config_whitelist "${whitelist_url}" >> ${CONFIG_PATH}
    generate_config_bottom  >> ${CONFIG_PATH}
}

# 下载文件
download_file(){
    local path="$1"
    local filename="$2"
    local execute="$3"

    [ -z "${filename}" ] && filename="$path"

    [ -n "$path" ] && \
        wget -q --no-check-certificate ${SCRIPT_HOST}/"${path}" -O "${filename}"

    [ -f "${filename}" ] && [ -n "${execute}" ] && chmod +x "${filename}"
}

##################------------菜单选项---------#####################################

# 解析运行参数
for _PARAMETER in $RUN_OPTS
do
    case "${_PARAMETER}" in
      --version=*)
        VERSION="${_PARAMETER#--version=}"
      ;;
      --ip=*)
        ipaddr_list=$(echo "${_PARAMETER#--ip=}" | sed 's/:/\n/g' | sed '/^$/d')
      ;;
      --port=*)
        port="${_PARAMETER#--port=}"
      ;;
      --user=*)
        user="${_PARAMETER#--user=}"
      ;;
      --passwd=*)
        passwd="${_PARAMETER#--passwd=}"
      ;;
      --whitelist=*)
        whitelist_ipaddrs=$(echo "${_PARAMETER#--whitelist=}" | sed 's/:/\n/g' | sed '/^$/d')
      ;;
      --help|-h)
        echo "显示帮助信息"
        exit 1
      ;;
      *)
        echo "不支持的选项: ${_PARAMETER}"
        exit 1
      ;;
    esac
done

# 设置默认值
[ -n "${port}" ] && DEFAULT_PORT="${port}"
[ -n "${ipaddr_list}" ] && DEFAULT_IPADDR="${ipaddr_list}"

# 生成配置文件
generate_config "${DEFAULT_IPADDR}" "${WHITE_LIST}" "${WHITE_LIST_NET}"

# 重新启动服务
service sockd restart

echo "Dante Socks5 安装完成！"
exit 0

