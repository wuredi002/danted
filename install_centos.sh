#!/bin/bash
#
# 提供服务: sockd.info (Lozy)
#

VERSION="1.4.2"  # 版本号
INSTALL_FROM="compile"  # 安装方式（编译）
DEFAULT_PORT="2016"  # 默认端口
DEFAULT_USER=""  # 默认用户名
DEFAULT_PAWD=""  # 默认密码
WHITE_LIST_NET=""  # IP 白名单网络
WHITE_LIST=""  # 白名单
SCRIPT_HOST="https://public.sockd.info"  # 脚本服务器地址
PACKAGE_NAME="dante_1.3.2-1_$(uname -m).deb"  # 安装包名称
COLOR_PATH="/etc/default/color"  # 颜色配置路径

BIN_DIR="/etc/danted"  # 二进制文件存放目录
BIN_PATH="/etc/danted/sbin/sockd"  # 二进制可执行文件路径
CONFIG_PATH="/etc/danted/sockd.conf"  # 配置文件路径
BIN_SCRIPT="/etc/init.d/sockd"  # 启动脚本路径

# 获取服务器的外部 IP 地址（排除本地回环地址和私有地址）
DEFAULT_IPADDR=$(ip addr | grep 'inet ' | grep -Ev 'inet 127|inet 192\.168' | sed "s/[[:space:]]*inet \([0-9.]*\)\/.*/\1/")
RUN_PATH=$(cd `dirname $0`;pwd )  # 运行脚本所在路径
RUN_OPTS=$*  # 运行时传入的参数

##################------------函数定义---------#####################################
# 移除已安装的 Dante 服务
remove_install(){
    [ -s "${BIN_SCRIPT}" ] && ${BIN_SCRIPT} stop > /dev/null 2>&1
    [ -f "${BIN_SCRIPT}" ] && rm "${BIN_SCRIPT}"
    [ -n "$BIN_DIR" ] && rm -r "$BIN_DIR"
}

# 检测是否已安装 Dante
detect_install(){
    if [ -s "${BIN_PATH}" ];then
        echo "Dante Socks5 已安装"
        ${BIN_PATH} -v
    fi
}

# 生成配置文件（单个 IP）
generate_config_ip(){
    local ipaddr="$1"
    local port="$2"

    cat <<EOF
# 生成接口 ${ipaddr}
internal: ${ipaddr}  port = ${port}
external: ${ipaddr}

EOF
}

# 生成配置文件（多个 IP）
generate_config_iplist(){
    local ipaddr_list="$1"
    local port="$2"

    [ -z "${ipaddr_list}" ] && return 1
    [ -z "${port}" ] && return 2

    for ipaddr in ${ipaddr_list};do
        generate_config_ip ${ipaddr} ${port} >> ${CONFIG_PATH}
    done

    ipaddr_array=($ipaddr_list)

    if [ ${#ipaddr_array[@]} -gt 1 ];then
        echo "external.rotation: same-same" >> ${CONFIG_PATH}
    fi
}

# 生成静态配置
generate_config_static(){
    if [ "$VERSION" == "1.4.2" ];then
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
#------------ 信任的网络: ${ipaddr_range} ---------------
pass {
        from: ${ipaddr_range} to: 0.0.0.0/0
        method: none
}

EOF
    done
}

# 从 URL 获取白名单 IP
generate_config_whitelist(){
    local whitelist_url="$1"

    if [ -n "${whitelist_url}" ];then
        ipaddr_list=$(curl -s --insecure -A "Mozilla Server Init" ${whitelist_url})
        generate_config_white "${ipaddr_list}"
    fi
}

# 生成配置文件底部
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

# 生成最终配置文件
generate_config(){
    local ipaddr_list="$1"
    local whitelist_url="$2"
    local whitelist_ip="$3"

    mkdir -p ${BIN_DIR}

    echo "# 由 sockd.info 生成" > ${CONFIG_PATH}

    generate_config_iplist "${ipaddr_list}" ${DEFAULT_PORT} >> ${CONFIG_PATH}

    generate_config_static >> ${CONFIG_PATH}
    generate_config_white ${whitelist_ip} >> ${CONFIG_PATH}
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
        wget -q --no-check-certificate ${SCRIPT_HOST}/${path} -O ${filename}

    [ -f "${filename}" ] && [ -n "${execute}" ] && chmod +x ${filename}
}

# 安装 Dante Socks5
yum install gcc g++ make vim pam-devel tcp_wrappers-devel unzip httpd-tools -y

mkdir -p /tmp/danted && rm /tmp/danted/* -rf && cd /tmp/danted

id sockd > /dev/null 2>&1 || useradd sockd -s /bin/false

if [ "$INSTALL_FROM" == "compile" ];then
    yum install gcc g++ make libpam-dev libwrap0-dev -y
    download_file "source/dante-${VERSION}.tar.gz" "dante-${VERSION}.tar.gz"

    if [ -f "dante-${VERSION}.tar.gz" ];then
        tar xzf dante-${VERSION}.tar.gz --strip 1
        ./configure --with-sockd-conf=${CONFIG_PATH} --prefix=${BIN_DIR}
        make -j && make install
    fi
fi

cat > /etc/pam.d/sockd  <<EOF
auth required pam_pwdfile.so pwdfile ${BIN_DIR}/sockd.passwd
account required pam_permit.so
EOF

service sockd restart
clear

if [ -n "$(ss -ln | grep "$DEFAULT_PORT")" ];then
    echo "Dante Socks5 安装成功"
else
    echo "Dante Socks5 安装失败"
fi

exit 0
