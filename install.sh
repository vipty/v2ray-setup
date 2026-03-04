#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:$HOME/bin
export PATH

cd "$(
    cd "$(dirname "$0")" || exit
    pwd
)" || exit
#====================================================
#	System Request:Debian 9+/Ubuntu 18.04+/Centos 7+
#	Author:	wulabing
#	Dscription: V2ray ws+tls onekey Management
#	Version: 1.0
#	email:admin@wulabing.com
#	Official document: www.v2ray.com
#====================================================

#fonts color
Green="\033[32m"
Red="\033[31m"
# Yellow="\033[33m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

#notification information
# Info="${Green}[信息]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

# 版本
shell_version="1.1.9.0"
shell_mode="None"
github_branch="master"
# 自有仓库（主源，vipty/v2ray-setup）：减少对个人仓库的依赖，长期可用
self_repo="vipty/v2ray-setup"
self_repo_branch="main"
self_repo_raw="https://raw.githubusercontent.com/${self_repo}/${self_repo_branch}"
# wulabing 原始仓库（备用）
wulabing_repo="wulabing/V2Ray_ws-tls_bash_onekey"
version_cmp="/tmp/version_cmp.tmp"
v2ray_conf_dir="/usr/local/etc/v2ray"
nginx_conf_dir="/etc/nginx/conf/conf.d"
v2ray_conf="${v2ray_conf_dir}/config.json"
nginx_conf="${nginx_conf_dir}/v2ray.conf"
nginx_dir="/etc/nginx"
web_dir="/home/wwwroot"
nginx_openssl_src="/usr/local/src"
v2ray_bin_dir_old="/usr/bin/v2ray"
v2ray_bin_dir="/usr/local/bin/v2ray"
v2ctl_bin_dir="/usr/local/bin/v2ctl"
v2ray_info_file="$HOME/v2ray_info.inf"
v2ray_qr_config_file="/usr/local/vmess_qr.json"
nginx_systemd_file="/etc/systemd/system/nginx.service"
v2ray_systemd_file="/etc/systemd/system/v2ray.service"
v2ray_access_log="/var/log/v2ray/access.log"
v2ray_error_log="/var/log/v2ray/error.log"
acme_sh_file="/root/.acme.sh/acme.sh"
ssl_update_file="/usr/bin/ssl_update.sh"
nginx_version="1.20.1"
openssl_version="1.1.1k"
jemalloc_version="5.2.1"
# v2ray_plugin_version="$(wget -qO- "https://github.com/shadowsocks/v2ray-plugin/tags" | grep -E "/shadowsocks/v2ray-plugin/releases/tag/" | head -1 | sed -r 's/.*tag\/v(.+)\">.*/\1/')"

#移动旧版本配置信息 对小于 1.1.0 版本适配
[[ -f "/etc/v2ray/vmess_qr.json" ]] && mv /etc/v2ray/vmess_qr.json $v2ray_qr_config_file

#简易随机数
random_num=$((RANDOM%12+4))
#生成伪装路径
camouflage="/$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})/"

THREAD=$(grep 'processor' /proc/cpuinfo | sort -u | wc -l)

source '/etc/os-release'

#从VERSION中提取发行版系统的英文名称，为了在debian/ubuntu下添加相对应的Nginx apt源
VERSION=$(echo "${VERSION}" | awk -F "[()]" '{print $2}')

check_system() {
    if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Centos ${VERSION_ID} ${VERSION} ${Font}"
        INS="yum"
    elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 8 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Debian ${VERSION_ID} ${VERSION} ${Font}"
        INS="apt"
        $INS update
        ## 添加 Nginx apt源
    elif [[ "${ID}" == "ubuntu" && $(echo "${VERSION_ID}" | cut -d '.' -f1) -ge 16 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Ubuntu ${VERSION_ID} ${UBUNTU_CODENAME} ${Font}"
        INS="apt"
        rm -f /var/lib/dpkg/lock
        dpkg --configure -a
        rm -f /var/lib/apt/lists/lock
        rm -f /var/cache/apt/archives/lock
        $INS update
    else
        echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font}"
        exit 1
    fi

    $INS install dbus

    systemctl stop firewalld
    systemctl disable firewalld
    echo -e "${OK} ${GreenBG} firewalld 已关闭 ${Font}"

    systemctl stop ufw
    systemctl disable ufw
    echo -e "${OK} ${GreenBG} ufw 已关闭 ${Font}"
}

is_root() {
    if [ 0 == $UID ]; then
        echo -e "${OK} ${GreenBG} 当前用户是root用户，进入安装流程 ${Font}"
        sleep 3
    else
        echo -e "${Error} ${RedBG} 当前用户不是root用户，请切换到root用户后重新执行脚本 ${Font}"
        exit 1
    fi
}
judge() {
    if [[ 0 -eq $? ]]; then
        echo -e "${OK} ${GreenBG} $1 完成 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} $1 失败${Font}"
        exit 1
    fi
}
chrony_install() {
    ${INS} -y install chrony
    judge "安装 chrony 时间同步服务 "

    timedatectl set-ntp true

    if [[ "${ID}" == "centos" ]]; then
        systemctl enable chronyd && systemctl restart chronyd
    else
        systemctl enable chrony && systemctl restart chrony
    fi

    judge "chronyd 启动 "

    timedatectl set-timezone Asia/Shanghai

    echo -e "${OK} ${GreenBG} 等待时间同步 ${Font}"
    sleep 10

    chronyc sourcestats -v
    chronyc tracking -v
    date
    echo -e "${OK} ${GreenBG} 时间同步完成，自动继续安装 ${Font}"
    echo -e "${OK} ${GreenBG} 提示：若后续 SSL 证书申请失败，请检查服务器时间是否准确（误差不超过3分钟）${Font}"
    sleep 2
}

dependency_install() {
    ${INS} install wget git lsof -y

    if [[ "${ID}" == "centos" ]]; then
        ${INS} -y install crontabs
    else
        ${INS} -y install cron
    fi
    judge "安装 crontab"

    if [[ "${ID}" == "centos" ]]; then
        touch /var/spool/cron/root && chmod 600 /var/spool/cron/root
        systemctl start crond && systemctl enable crond
    else
        touch /var/spool/cron/crontabs/root && chmod 600 /var/spool/cron/crontabs/root
        systemctl start cron && systemctl enable cron

    fi
    judge "crontab 自启动配置 "

    ${INS} -y install bc
    judge "安装 bc"

    ${INS} -y install unzip
    judge "安装 unzip"

    ${INS} -y install qrencode
    judge "安装 qrencode"

    ${INS} -y install curl
    judge "安装 curl"

    if [[ "${ID}" == "centos" ]]; then
        ${INS} -y groupinstall "Development tools"
    else
        ${INS} -y install build-essential
    fi
    judge "编译工具包 安装"

    if [[ "${ID}" == "centos" ]]; then
        ${INS} -y install pcre pcre-devel zlib-devel epel-release
    else
        ${INS} -y install libpcre3 libpcre3-dev zlib1g-dev dbus
    fi

    #    ${INS} -y install rng-tools
    #    judge "rng-tools 安装"

    ${INS} -y install haveged
    #    judge "haveged 安装"

    #    sed -i -r '/^HRNGDEVICE/d;/#HRNGDEVICE=\/dev\/null/a HRNGDEVICE=/dev/urandom' /etc/default/rng-tools

    systemctl start haveged && systemctl enable haveged

    mkdir -p /usr/local/bin >/dev/null 2>&1
}
basic_optimization() {
    # 最大文件打开数
    sed -i '/^\*\ *soft\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
    sed -i '/^\*\ *hard\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
    echo '* soft nofile 65536' >>/etc/security/limits.conf
    echo '* hard nofile 65536' >>/etc/security/limits.conf

    # 关闭 Selinux
    if [[ "${ID}" == "centos" ]]; then
        sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
        setenforce 0
    fi

}
port_alterid_set() {
    # 端口默认 443：标准 HTTPS 端口，防火墙/运营商拦截概率最低，伪装性最强
    [[ -z ${port} ]] && port="443"
    # alterID 默认 0：启用 VMessAEAD 加密模式，安全性更高，新版客户端均支持
    [[ -z ${alterID} ]] && alterID="0"
    echo -e "${OK} ${GreenBG} 连接端口: ${port}（推荐：标准HTTPS端口，穿透性最佳）${Font}"
    echo -e "${OK} ${GreenBG} alterID: ${alterID}（推荐：启用VMessAEAD加密，安全性更强）${Font}"
}
modify_path() {
    sed -i "/\"path\"/c \\\t  \"path\":\"${camouflage}\"" ${v2ray_conf}
    judge "V2ray 伪装路径 修改"
}
modify_alterid() {
    sed -i "/\"alterId\"/c \\\t  \"alterId\":${alterID}" ${v2ray_conf}
    judge "V2ray alterid 修改"
    [ -f ${v2ray_qr_config_file} ] && sed -i "/\"aid\"/c \\  \"aid\": \"${alterID}\"," ${v2ray_qr_config_file}
    echo -e "${OK} ${GreenBG} alterID:${alterID} ${Font}"
}
modify_inbound_port() {
    if [[ "$shell_mode" != "h2" ]]; then
        PORT=$((RANDOM + 10000))
        sed -i "/\"port\"/c  \    \"port\":${PORT}," ${v2ray_conf}
    else
        sed -i "/\"port\"/c  \    \"port\":${port}," ${v2ray_conf}
    fi
    judge "V2ray inbound_port 修改"
}
modify_UUID() {
    [ -z "$UUID" ] && UUID=$(cat /proc/sys/kernel/random/uuid)
    sed -i "/\"id\"/c \\\t  \"id\":\"${UUID}\"," ${v2ray_conf}
    judge "V2ray UUID 修改"
    [ -f ${v2ray_qr_config_file} ] && sed -i "/\"id\"/c \\  \"id\": \"${UUID}\"," ${v2ray_qr_config_file}
    echo -e "${OK} ${GreenBG} UUID:${UUID} ${Font}"
}
modify_nginx_port() {
    sed -i "/ssl http2;$/c \\\tlisten ${port} ssl http2;" ${nginx_conf}
    sed -i "3c \\\tlisten [::]:${port} http2;" ${nginx_conf}
    judge "V2ray port 修改"
    [ -f ${v2ray_qr_config_file} ] && sed -i "/\"port\"/c \\  \"port\": \"${port}\"," ${v2ray_qr_config_file}
    echo -e "${OK} ${GreenBG} 端口号:${port} ${Font}"
}
modify_nginx_other() {
    sed -i "/server_name/c \\\tserver_name ${domain};" ${nginx_conf}
    sed -i "/location/c \\\tlocation ${camouflage}" ${nginx_conf}
    sed -i "/proxy_pass/c \\\tproxy_pass http://127.0.0.1:${PORT};" ${nginx_conf}
    sed -i "/return/c \\\treturn 301 https://${domain}\$request_uri;" ${nginx_conf}
    #sed -i "27i \\\tproxy_intercept_errors on;"  ${nginx_dir}/conf/nginx.conf
}
web_camouflage() {
    ##请注意 这里和LNMP脚本的默认路径冲突，千万不要在安装了LNMP的环境下使用本脚本，否则后果自负
    rm -rf /home/wwwroot
    mkdir -p /home/wwwroot/3DCEList
    cd /home/wwwroot || exit
    # 主源：wulabing 的伪装站点仓库（个人维护，有停止风险）
    if git clone https://github.com/wulabing/3DCEList.git 2>/dev/null; then
        echo -e "${OK} ${GreenBG} web 站点伪装 完成 ${Font}"
    else
        # 备用：内置最简伪装页，不依赖任何外部仓库
        echo -e "${Error} ${RedBG} 伪装站点拉取失败，使用内置页面作为备用伪装 ${Font}"
        cat >/home/wwwroot/3DCEList/index.html <<'HTMLEOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Welcome</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{display:flex;justify-content:center;align-items:center;min-height:100vh;
       background:#f0f2f5;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
  .card{background:#fff;border-radius:12px;padding:48px 64px;text-align:center;
        box-shadow:0 4px 24px rgba(0,0,0,.08)}
  h1{font-size:2rem;color:#1a1a2e;margin-bottom:12px}
  p{color:#6b7280;font-size:1rem}
</style>
</head>
<body>
  <div class="card">
    <h1>Welcome</h1>
    <p>Service is running normally.</p>
  </div>
</body>
</html>
HTMLEOF
        echo -e "${OK} ${GreenBG} 内置伪装页面已生成 ${Font}"
    fi
}
v2ray_install() {
    if [[ -d /root/v2ray ]]; then
        rm -rf /root/v2ray
    fi
    if [[ -d /etc/v2ray ]]; then
        rm -rf /etc/v2ray
    fi
    # 备份旧服务文件：v2fly 安装器在"已是最新版"时会跳过，不会重建服务文件
    [[ -f "$v2ray_systemd_file" ]] && cp "$v2ray_systemd_file" "${v2ray_systemd_file}.bak"
    rm -rf $v2ray_systemd_file
    systemctl daemon-reload

    # 主安装源：v2fly 官方安装脚本（官方维护，长期稳定）
    if bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh); then
        # 安装器跳过时服务文件不会重建，从备份恢复
        if [[ ! -f "$v2ray_systemd_file" && -f "${v2ray_systemd_file}.bak" ]]; then
            cp "${v2ray_systemd_file}.bak" "$v2ray_systemd_file"
            systemctl daemon-reload
            echo -e "${OK} ${GreenBG} 已是最新版，从备份恢复服务文件 ${Font}"
        fi
        judge "安装 V2ray (v2fly 官方)"
    else
        # 备用安装源：wulabing 脚本
        echo -e "${Error} ${RedBG} v2fly 官方安装源失败，切换至备用安装源 ${Font}"
        mkdir -p /root/v2ray && cd /root/v2ray || exit
        wget -q -N --no-check-certificate https://raw.githubusercontent.com/wulabing/V2Ray_ws-tls_bash_onekey/${github_branch}/v2ray.sh
        if [[ -f v2ray.sh ]]; then
            bash v2ray.sh --force
            judge "安装 V2ray (备用)"
        else
            echo -e "${Error} ${RedBG} V2ray 安装失败，请检查网络连接或手动安装 ${Font}"
            exit 4
        fi
    fi
    # 清除临时文件
    rm -rf /root/v2ray
}
nginx_exist_check() {
    if [[ -f "/etc/nginx/sbin/nginx" ]]; then
        echo -e "${OK} ${GreenBG} Nginx已存在，跳过编译安装过程 ${Font}"
        sleep 2
    elif [[ -d "/usr/local/nginx/" ]]; then
        echo -e "${OK} ${GreenBG} 检测到其他套件安装的Nginx，继续安装会造成冲突，请处理后安装${Font}"
        exit 1
    else
        nginx_install
    fi
}
nginx_install() {
    #    if [[ -d "/etc/nginx" ]];then
    #        rm -rf /etc/nginx
    #    fi

    wget -nc --no-check-certificate http://nginx.org/download/nginx-${nginx_version}.tar.gz -P ${nginx_openssl_src}
    judge "Nginx 下载"
    wget -nc --no-check-certificate https://www.openssl.org/source/openssl-${openssl_version}.tar.gz -P ${nginx_openssl_src}
    judge "openssl 下载"
    wget -nc --no-check-certificate https://github.com/jemalloc/jemalloc/releases/download/${jemalloc_version}/jemalloc-${jemalloc_version}.tar.bz2 -P ${nginx_openssl_src}
    judge "jemalloc 下载"

    cd ${nginx_openssl_src} || exit

    [[ -d nginx-"$nginx_version" ]] && rm -rf nginx-"$nginx_version"
    tar -zxvf nginx-"$nginx_version".tar.gz

    [[ -d openssl-"$openssl_version" ]] && rm -rf openssl-"$openssl_version"
    tar -zxvf openssl-"$openssl_version".tar.gz

    [[ -d jemalloc-"${jemalloc_version}" ]] && rm -rf jemalloc-"${jemalloc_version}"
    tar -xvf jemalloc-"${jemalloc_version}".tar.bz2

    [[ -d "$nginx_dir" ]] && rm -rf ${nginx_dir}

    echo -e "${OK} ${GreenBG} 即将开始编译安装 jemalloc ${Font}"
    sleep 2

    cd jemalloc-${jemalloc_version} || exit
    ./configure
    judge "编译检查"
    make -j "${THREAD}" && make install
    judge "jemalloc 编译安装"
    echo '/usr/local/lib' >/etc/ld.so.conf.d/local.conf
    ldconfig

    echo -e "${OK} ${GreenBG} 即将开始编译安装 Nginx, 过程稍久，请耐心等待 ${Font}"
    sleep 4

    cd ../nginx-${nginx_version} || exit

    ./configure --prefix="${nginx_dir}" \
        --with-http_ssl_module \
        --with-http_sub_module \
        --with-http_gzip_static_module \
        --with-http_stub_status_module \
        --with-pcre \
        --with-http_realip_module \
        --with-http_flv_module \
        --with-http_mp4_module \
        --with-http_secure_link_module \
        --with-http_v2_module \
        --with-cc-opt='-O3' \
        --with-ld-opt="-ljemalloc" \
        --with-openssl=../openssl-"$openssl_version"
    judge "编译检查"
    make -j "${THREAD}" && make install
    judge "Nginx 编译安装"

    # 修改基本配置
    sed -i 's/#user  nobody;/user  root;/' ${nginx_dir}/conf/nginx.conf
    sed -i "s/worker_processes  1;/worker_processes  ${THREAD};/" ${nginx_dir}/conf/nginx.conf
    sed -i 's/    worker_connections  1024;/    worker_connections  4096;/' ${nginx_dir}/conf/nginx.conf
    sed -i '$i include conf.d/*.conf;' ${nginx_dir}/conf/nginx.conf

    # 删除临时文件
    rm -rf ../nginx-"${nginx_version}"
    rm -rf ../openssl-"${openssl_version}"
    rm -rf ../nginx-"${nginx_version}".tar.gz
    rm -rf ../openssl-"${openssl_version}".tar.gz

    # 添加配置文件夹，适配旧版脚本
    mkdir ${nginx_dir}/conf/conf.d
}
ssl_install() {
    if [[ "${ID}" == "centos" ]]; then
        ${INS} install socat nc -y
    else
        ${INS} install socat netcat-openbsd -y
    fi
    judge "安装 SSL 证书生成脚本依赖"

    curl https://get.acme.sh | sh
    judge "安装 SSL 证书生成脚本"
}
get_public_ip() {
    local ip
    # 依次尝试多个公网IP查询服务，任一成功即返回
    for api in "https://api-ipv4.ip.sb/ip" "https://api4.ipify.org" "https://ipv4.icanhazip.com" "https://ifconfig.me/ip"; do
        ip=$(curl -s --connect-timeout 5 "$api" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return
        fi
    done
    echo ""
}
resolve_domain_ip() {
    local d="$1"
    local ip
    # 优先用 dig，其次 nslookup，最后 ping（兼容性兜底）
    if command -v dig &>/dev/null; then
        ip=$(dig +short "$d" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    fi
    if [[ -z "$ip" ]] && command -v nslookup &>/dev/null; then
        ip=$(nslookup "$d" 2>/dev/null | awk '/^Address:/{ip=$2} END{print ip}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    fi
    if [[ -z "$ip" ]]; then
        ip=$(ping -c1 -W2 "$d" 2>/dev/null | sed -n 's/.*(\([0-9.]*\)).*/\1/p' | head -1)
    fi
    echo "$ip"
}
domain_check() {
    if [[ -z "${domain}" ]]; then
        read -rp "请输入你的域名信息(eg:www.wulabing.com):" domain
    else
        echo -e "${OK} ${GreenBG} 使用指定域名: ${domain} ${Font}"
    fi
    domain_ip=$(resolve_domain_ip "${domain}")
    echo -e "${OK} ${GreenBG} 正在获取 公网ip 信息，请耐心等待 ${Font}"
    local_ip=$(get_public_ip)
    if [[ -z "$local_ip" ]]; then
        echo -e "${Error} ${RedBG} 无法获取公网IP（所有查询服务均失败），跳过IP匹配检查 ${Font}"
        sleep 2
        return
    fi
    echo -e "域名dns解析IP：${domain_ip}"
    echo -e "本机IP: ${local_ip}"
    sleep 2
    if [[ "${local_ip}" == "${domain_ip}" ]]; then
        echo -e "${OK} ${GreenBG} 域名dns解析IP 与 本机IP 匹配 ${Font}"
        sleep 2
    else
        echo -e "${Error} ${RedBG} 请确保域名添加了正确的 A 记录，否则将无法正常使用 V2ray ${Font}"
        echo -e "${Error} ${RedBG} 域名dns解析IP 与 本机IP 不匹配，自动继续安装，如遇证书申请失败请检查 DNS 解析 ${Font}"
        sleep 3
    fi
}

port_exist_check() {
    if [[ 0 -eq $(lsof -i:"$1" | grep -i -c "listen") ]]; then
        echo -e "${OK} ${GreenBG} $1 端口未被占用 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} 检测到 $1 端口被占用，以下为 $1 端口占用信息 ${Font}"
        lsof -i:"$1"
        echo -e "${OK} ${GreenBG} 5s 后将尝试自动 kill 占用进程 ${Font}"
        sleep 5
        lsof -i:"$1" | awk '{print $2}' | grep -v "PID" | xargs kill -9
        echo -e "${OK} ${GreenBG} kill 完成 ${Font}"
        sleep 1
    fi
}
acme() {
    "$HOME"/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    if "$HOME"/.acme.sh/acme.sh --issue --insecure -d "${domain}" --standalone -k ec-256 --force --test; then
        echo -e "${OK} ${GreenBG} SSL 证书测试签发成功，开始正式签发 ${Font}"
        rm -rf "$HOME/.acme.sh/${domain}_ecc"
        sleep 2
    else
        echo -e "${Error} ${RedBG} SSL 证书测试签发失败 ${Font}"
        echo -e "${Error} ${RedBG} 排查建议：1) 检查服务器时间是否准确（误差不超过3分钟，运行 date 查看）${Font}"
        echo -e "${Error} ${RedBG}           2) 检查域名 DNS 解析是否已指向本机 IP ${Font}"
        echo -e "${Error} ${RedBG}           3) 检查 80 端口是否被占用或防火墙拦截 ${Font}"
        rm -rf "$HOME/.acme.sh/${domain}_ecc"
        exit 1
    fi

    if "$HOME"/.acme.sh/acme.sh --issue --insecure -d "${domain}" --standalone -k ec-256 --force; then
        echo -e "${OK} ${GreenBG} SSL 证书生成成功 ${Font}"
        sleep 2
        mkdir -p /data
        if "$HOME"/.acme.sh/acme.sh --installcert -d "${domain}" --fullchainpath /data/v2ray.crt --keypath /data/v2ray.key --ecc --force; then
            echo -e "${OK} ${GreenBG} 证书配置成功 ${Font}"
            sleep 2
        fi
    else
        echo -e "${Error} ${RedBG} SSL 证书生成失败 ${Font}"
        echo -e "${Error} ${RedBG} 排查建议：1) 检查服务器时间是否准确（误差不超过3分钟，运行 date 查看）${Font}"
        echo -e "${Error} ${RedBG}           2) 检查域名 DNS 解析是否已指向本机 IP ${Font}"
        echo -e "${Error} ${RedBG}           3) 检查 80 端口是否被占用或防火墙拦截 ${Font}"
        rm -rf "$HOME/.acme.sh/${domain}_ecc"
        exit 1
    fi
}
v2ray_conf_add() {
    local mode="$1"
    cd "$v2ray_conf_dir" || exit
    # 主源：自有仓库（vipty/v2ray-setup），长期可用
    if ! wget -q --no-check-certificate "${self_repo_raw}/${mode}/config.json" -O config.json 2>/dev/null; then
        # 备用：wulabing 原始仓库
        echo -e "${Error} ${RedBG} 主源配置下载失败，切换至备用源 ${Font}"
        wget --no-check-certificate "https://raw.githubusercontent.com/${wulabing_repo}/${github_branch}/${mode}/config.json" -O config.json
    fi
    modify_path
    modify_alterid
    modify_inbound_port
    modify_UUID
}
v2ray_conf_add_tls() { v2ray_conf_add "tls"; }
v2ray_conf_add_h2()  { v2ray_conf_add "http2"; }
old_config_exist_check() {
    if [[ -f $v2ray_qr_config_file ]]; then
        # 默认使用全新配置：重新安装时生成新UUID和路径更安全，避免旧配置泄露风险
        rm -rf $v2ray_qr_config_file
        echo -e "${OK} ${GreenBG} 检测到旧配置文件，自动使用全新配置（推荐：更安全）${Font}"
    fi
}
nginx_conf_add() {
    touch ${nginx_conf_dir}/v2ray.conf
    cat >${nginx_conf_dir}/v2ray.conf <<EOF
    server {
        listen 443 ssl http2;
        listen [::]:443 http2;
        ssl_certificate       /data/v2ray.crt;
        ssl_certificate_key   /data/v2ray.key;
        ssl_protocols         TLSv1.3;
        ssl_ciphers           TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256:TLS13-AES-128-CCM-SHA256:EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5;
        server_name           serveraddr.com;
        index index.html index.htm;
        root  /home/wwwroot/3DCEList;
        error_page 400 = /400.html;

        # Config for 0-RTT in TLSv1.3
        ssl_early_data on;
        ssl_stapling on;
        ssl_stapling_verify on;
        add_header Strict-Transport-Security "max-age=31536000";

        location /ray/
        {
        proxy_redirect off;
        proxy_read_timeout 1200s;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;

        # Config for 0-RTT in TLSv1.3
        proxy_set_header Early-Data \$ssl_early_data;
        }
}
    server {
        listen 80;
        listen [::]:80;
        server_name serveraddr.com;
        return 301 https://use.shadowsocksr.win\$request_uri;
    }
EOF

    modify_nginx_port
    modify_nginx_other
    judge "Nginx 配置修改"

}

start_process_systemd() {
    systemctl daemon-reload
    # v2fly FHS 安装的服务以 nobody 用户运行，日志目录需对应权限
    mkdir -p /var/log/v2ray
    chown -R nobody:nogroup /var/log/v2ray/
    if [[ "$shell_mode" != "h2" ]]; then
        systemctl restart nginx
        judge "Nginx 启动"
    fi
    systemctl restart v2ray
    judge "V2ray 启动"
}

enable_process_systemd() {
    systemctl enable v2ray
    judge "设置 v2ray 开机自启"
    if [[ "$shell_mode" != "h2" ]]; then
        systemctl enable nginx
        judge "设置 Nginx 开机自启"
    fi

}

stop_process_systemd() {
    if [[ "$shell_mode" != "h2" ]]; then
        systemctl stop nginx
    fi
    systemctl stop v2ray
}
nginx_process_disabled() {
    [ -f $nginx_systemd_file ] && systemctl stop nginx && systemctl disable nginx
}

#debian 系 9 10 适配
#rc_local_initialization(){
#    if [[ -f /etc/rc.local ]];then
#        chmod +x /etc/rc.local
#    else
#        touch /etc/rc.local && chmod +x /etc/rc.local
#        echo "#!/bin/bash" >> /etc/rc.local
#        systemctl start rc-local
#    fi
#
#    judge "rc.local 配置"
#}
acme_cron_update() {
    # 本地生成证书续签脚本，不依赖 wulabing 个人仓库的 ssl_update.sh
    cat >${ssl_update_file} <<'SSLEOF'
#!/bin/bash
domain=$(grep '"add"' /usr/local/vmess_qr.json 2>/dev/null | awk -F '"' '{print $4}')
[[ -z "$domain" ]] && exit 0
"$HOME/.acme.sh"/acme.sh --cron --home "$HOME/.acme.sh" >/dev/null 2>&1
"$HOME/.acme.sh"/acme.sh --installcert -d "$domain" \
    --fullchainpath /data/v2ray.crt --keypath /data/v2ray.key --ecc >/dev/null 2>&1
systemctl is-active --quiet nginx && systemctl restart nginx
systemctl is-active --quiet v2ray && systemctl restart v2ray
SSLEOF
    chmod +x ${ssl_update_file}

    local cron_file
    [[ "${ID}" == "centos" ]] && cron_file="/var/spool/cron/root" || cron_file="/var/spool/cron/crontabs/root"
    if grep -q "ssl_update.sh" "$cron_file" 2>/dev/null; then
        sed -i "/ssl_update.sh/c 0 3 * * 0 bash ${ssl_update_file}" "$cron_file"
    else
        echo "0 3 * * 0 bash ${ssl_update_file}" >>"$cron_file"
    fi
    judge "cron 计划任务更新"
}

vmess_qr_config_tls_ws() {
    cat >$v2ray_qr_config_file <<-EOF
{
  "v": "2",
  "ps": "wulabing_${domain}",
  "add": "${domain}",
  "port": "${port}",
  "id": "${UUID}",
  "aid": "${alterID}",
  "net": "ws",
  "type": "none",
  "host": "${domain}",
  "path": "${camouflage}",
  "tls": "tls"
}
EOF
}

vmess_qr_config_h2() {
    cat >$v2ray_qr_config_file <<-EOF
{
  "v": "2",
  "ps": "wulabing_${domain}",
  "add": "${domain}",
  "port": "${port}",
  "id": "${UUID}",
  "aid": "${alterID}",
  "net": "h2",
  "type": "none",
  "path": "${camouflage}",
  "tls": "tls"
}
EOF
}

vmess_qr_link_image() {
    vmess_link="vmess://$(base64 -w 0 $v2ray_qr_config_file)"
    {
        echo -e "$Red 二维码: $Font"
        echo -n "${vmess_link}" | qrencode -o - -t utf8
        echo -e "${Red} URL导入链接:${vmess_link} ${Font}"
    } >>"${v2ray_info_file}"
}

vmess_quan_link_image() {
    echo "$(info_extraction '\"ps\"') = vmess, $(info_extraction '\"add\"'), \
    $(info_extraction '\"port\"'), chacha20-ietf-poly1305, "\"$(info_extraction '\"id\"')\"", over-tls=true, \
    certificate=1, obfs=ws, obfs-path="\"$(info_extraction '\"path\"')\"", " > /tmp/vmess_quan.tmp
    vmess_link="vmess://$(base64 -w 0 /tmp/vmess_quan.tmp)"
    {
        echo -e "$Red 二维码: $Font"
        echo -n "${vmess_link}" | qrencode -o - -t utf8
        echo -e "${Red} URL导入链接:${vmess_link} ${Font}"
    } >>"${v2ray_info_file}"
}

vmess_link_image_choice() {
        # 默认生成 V2RayNG/V2RayN 格式链接：兼容性最广，支持 Android/Windows/iOS 全平台主流客户端
        echo -e "${OK} ${GreenBG} 自动生成 V2RayNG/V2RayN 格式链接（推荐：兼容性最广）${Font}"
        vmess_qr_link_image
}
info_extraction() {
    grep "$1" $v2ray_qr_config_file | awk -F '"' '{print $4}'
}
basic_information() {
    {
        echo -e "${OK} ${GreenBG} V2ray+ws+tls 安装成功"
        echo -e "${Red} V2ray 配置信息 ${Font}"
        echo -e "${Red} 地址（address）:${Font} $(info_extraction '\"add\"') "
        echo -e "${Red} 端口（port）：${Font} $(info_extraction '\"port\"') "
        echo -e "${Red} 用户id（UUID）：${Font} $(info_extraction '\"id\"')"
        echo -e "${Red} 额外id（alterId）：${Font} $(info_extraction '\"aid\"')"
        echo -e "${Red} 加密方式（security）：${Font} 自适应 "
        echo -e "${Red} 传输协议（network）：${Font} $(info_extraction '\"net\"') "
        echo -e "${Red} 伪装类型（type）：${Font} none "
        echo -e "${Red} 路径（不要落下/）：${Font} $(info_extraction '\"path\"') "
        echo -e "${Red} 底层传输安全：${Font} tls "
    } >"${v2ray_info_file}"
}
show_information() {
    cat "${v2ray_info_file}"
}
ssl_judge_and_install() {
    if [[ -f "/data/v2ray.key" || -f "/data/v2ray.crt" ]]; then
        # 默认删除旧证书重新申请：避免证书过期或域名变更导致的问题
        echo -e "${OK} ${GreenBG} 检测到旧证书，自动删除并重新申请（推荐：确保证书与当前域名匹配）${Font}"
        rm -rf /data/*
    fi

    if [[ -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" ]]; then
        echo -e "${OK} ${GreenBG} 检测到 acme.sh 缓存证书，直接安装 ${Font}"
        "$HOME"/.acme.sh/acme.sh --installcert -d "${domain}" --fullchainpath /data/v2ray.crt --keypath /data/v2ray.key --ecc
        judge "证书应用"
    else
        ssl_install
        acme
    fi
}

nginx_systemd() {
    cat >$nginx_systemd_file <<EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/etc/nginx/logs/nginx.pid
ExecStartPre=/etc/nginx/sbin/nginx -t
ExecStart=/etc/nginx/sbin/nginx -c ${nginx_dir}/conf/nginx.conf
ExecReload=/etc/nginx/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT \$MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    judge "Nginx systemd ServerFile 添加"
    systemctl daemon-reload
}

tls_type() {
    if [[ -f "/etc/nginx/sbin/nginx" ]] && [[ -f "$nginx_conf" ]] && [[ "$shell_mode" == "ws" ]]; then
        echo "请选择支持的 TLS 版本（default:3）:"
        echo "请注意,如果你使用 Quantaumlt X / 路由器 / 旧版 Shadowrocket / 低于 4.18.1 版本的 V2ray core 请选择 兼容模式"
        echo "1: TLS1.1 TLS1.2 and TLS1.3（兼容模式）"
        echo "2: TLS1.2 and TLS1.3 (兼容模式)"
        echo "3: TLS1.3 only"
        read -rp "请输入：" tls_version
        [[ -z ${tls_version} ]] && tls_version=3
        if [[ $tls_version == 3 ]]; then
            sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.3;/' $nginx_conf
            echo -e "${OK} ${GreenBG} 已切换至 TLS1.3 only ${Font}"
        elif [[ $tls_version == 1 ]]; then
            sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.1 TLSv1.2 TLSv1.3;/' $nginx_conf
            echo -e "${OK} ${GreenBG} 已切换至 TLS1.1 TLS1.2 and TLS1.3 ${Font}"
        else
            sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.2 TLSv1.3;/' $nginx_conf
            echo -e "${OK} ${GreenBG} 已切换至 TLS1.2 and TLS1.3 ${Font}"
        fi
        systemctl restart nginx
        judge "Nginx 重启"
    else
        echo -e "${Error} ${RedBG} Nginx 或 配置文件不存在 或当前安装版本为 h2 ，请正确安装脚本后执行${Font}"
    fi
}
show_access_log() {
    [ -f ${v2ray_access_log} ] && tail -f ${v2ray_access_log} || echo -e "${RedBG}log文件不存在${Font}"
}
show_error_log() {
    [ -f ${v2ray_error_log} ] && tail -f ${v2ray_error_log} || echo -e "${RedBG}log文件不存在${Font}"
}
ssl_update_manuel() {
    if [[ ! -f "$HOME/.acme.sh/acme.sh" ]]; then
        echo -e "${RedBG}证书签发工具不存在，请确认你是否使用了自己的证书${Font}"
        return 1
    fi
    "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh"
    domain="$(info_extraction '\"add\"')"
    "$HOME/.acme.sh/acme.sh" --installcert -d "${domain}" --fullchainpath /data/v2ray.crt --keypath /data/v2ray.key --ecc
}
bbr_boost_sh() {
    local tcp_script="/tmp/tcp.sh"
    rm -f "$tcp_script"
    # 主源：ylx2016 的网络加速脚本（第三方）
    if ! wget -q -O "$tcp_script" --no-check-certificate "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" 2>/dev/null; then
        # 备用：自有仓库镜像
        wget -O "$tcp_script" --no-check-certificate "${self_repo_raw}/tools/tcp.sh"
    fi
    [[ -f "$tcp_script" ]] && chmod +x "$tcp_script" && bash "$tcp_script"
}
mtproxy_sh() {
    echo -e "${Error} ${RedBG} 功能维护，暂不可用 ${Font}"
}

uninstall_all() {
    stop_process_systemd
    [[ -f $v2ray_systemd_file ]] && rm -f $v2ray_systemd_file
    [[ -f $v2ray_bin_dir ]] && rm -f $v2ray_bin_dir
    [[ -f $v2ctl_bin_dir ]] && rm -f $v2ctl_bin_dir
    [[ -d $v2ray_bin_dir_old ]] && rm -rf $v2ray_bin_dir_old
    if [[ -d $nginx_dir ]]; then
        echo -e "${OK} ${Green} 是否卸载 Nginx [Y/N]? ${Font}"
        read -r uninstall_nginx
        case $uninstall_nginx in
        [yY][eE][sS] | [yY])
            rm -rf $nginx_dir
            rm -rf $nginx_systemd_file
            echo -e "${OK} ${Green} 已卸载 Nginx ${Font}"
            ;;
        *) ;;

        esac
    fi
    [[ -d $v2ray_conf_dir ]] && rm -rf $v2ray_conf_dir
    [[ -d $web_dir ]] && rm -rf $web_dir
    echo -e "${OK} ${Green} 是否卸载acme.sh及证书 [Y/N]? ${Font}"
    read -r uninstall_acme
    case $uninstall_acme in
    [yY][eE][sS] | [yY])
      /root/.acme.sh/acme.sh --uninstall
      rm -rf /root/.acme.sh
      rm -rf /data/*
      ;;
    *) ;;
    esac
    systemctl daemon-reload
    echo -e "${OK} ${GreenBG} 已卸载 ${Font}"
}
delete_tls_key_and_crt() {
    [[ -f $HOME/.acme.sh/acme.sh ]] && /root/.acme.sh/acme.sh uninstall >/dev/null 2>&1
    [[ -d $HOME/.acme.sh ]] && rm -rf "$HOME/.acme.sh"
    echo -e "${OK} ${GreenBG} 已清空证书遗留文件 ${Font}"
}
judge_mode() {
    if [ -f $v2ray_bin_dir ] || [ -f $v2ray_bin_dir_old/v2ray ]; then
        if [[ -f "$v2ray_qr_config_file" ]]; then
            if grep -q "ws" $v2ray_qr_config_file; then
                shell_mode="ws"
            elif grep -q "h2" $v2ray_qr_config_file; then
                shell_mode="h2"
            fi
        fi
    fi
}
enable_bbr() {
    modprobe tcp_bbr 2>/dev/null
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc=fq" >>/etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    if sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
        echo -e "${OK} ${GreenBG} BBR 加速启用成功（立即生效，无需重启）${Font}"
    else
        echo -e "${Error} ${RedBG} BBR 启用失败，内核可能不支持，建议通过菜单选项11安装加速脚本 ${Font}"
    fi
}
check_kernel_and_recommend_bbr() {
    local kver major minor current_cc
    kver=$(uname -r | sed 's/[-+].*//')
    major=$(echo "$kver" | cut -d'.' -f1)
    minor=$(echo "$kver" | cut -d'.' -f2)
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)

    echo -e ""
    echo -e "—————————————— 内核与加速分析 ——————————————"
    echo -e "${OK} ${GreenBG} 内核版本: $(uname -r) ${Font}"
    echo -e "${OK} ${GreenBG} 当前拥塞控制: ${current_cc:-未知} ${Font}"

    if [[ "$current_cc" == "bbr" ]]; then
        echo -e "${OK} ${GreenBG} BBR 已启用，无需重复配置 ${Font}"
        echo -e "—————————————————————————————————————————"
        return 0
    fi

    if [[ $major -gt 4 ]] || [[ $major -eq 4 && $minor -ge 9 ]]; then
        echo -e "${OK} ${GreenBG} 推荐: 原生 BBR（Google研发，内核已内置，无第三方依赖，最稳定可靠）${Font}"
        if [[ $major -ge 5 ]]; then
            echo -e "${OK} ${GreenBG} 内核 ≥ 5.x，BBR 支持更完善，强烈推荐启用 ${Font}"
        fi
        read -rp "$(echo -e "${GreenBG} 是否立即一键启用 BBR？(Y/n): ${Font}")" bbr_yn
        [[ -z "$bbr_yn" ]] && bbr_yn="Y"
        case $bbr_yn in
        [yY][eE][sS] | [yY])
            enable_bbr
            ;;
        *)
            echo -e "${OK} ${GreenBG} 跳过 BBR 配置，可后续从菜单选项11安装加速脚本 ${Font}"
            ;;
        esac
    else
        echo -e "${Error} ${RedBG} 内核 ${kver} < 4.9，不支持原生 BBR ${Font}"
        echo -e "${Error} ${RedBG} 推荐：菜单选项11安装 BBR Plus/锐速，或先升级内核到 4.9+ ${Font}"
    fi
    echo -e "—————————————————————————————————————————"
    sleep 2
}
install_v2ray_ws_tls() {
    is_root
    check_kernel_and_recommend_bbr
    check_system
    chrony_install
    dependency_install
    basic_optimization
    domain_check
    old_config_exist_check
    port_alterid_set
    v2ray_install
    port_exist_check 80
    port_exist_check "${port}"
    nginx_exist_check
    v2ray_conf_add_tls
    nginx_conf_add
    web_camouflage
    ssl_judge_and_install
    nginx_systemd
    vmess_qr_config_tls_ws
    basic_information
    vmess_link_image_choice
    # TLS 版本：安装时固定使用 TLS1.3（最安全，现代客户端均支持；如需兼容旧客户端可安装后从菜单选项7调整）
    echo -e "${OK} ${GreenBG} TLS 版本: TLS1.3 only（推荐：最高安全性，Shadowrocket/V2RayNG/Clash 均支持）${Font}"
    show_information
    start_process_systemd
    enable_process_systemd
    acme_cron_update
}
install_v2_h2() {
    is_root
    check_kernel_and_recommend_bbr
    check_system
    chrony_install
    dependency_install
    basic_optimization
    domain_check
    old_config_exist_check
    port_alterid_set
    v2ray_install
    port_exist_check 80
    port_exist_check "${port}"
    v2ray_conf_add_h2
    ssl_judge_and_install
    vmess_qr_config_h2
    basic_information
    vmess_qr_link_image
    show_information
    start_process_systemd
    enable_process_systemd

}
update_sh() {
    # 主源：自有仓库（vipty/v2ray-setup）
    ol_version=$(curl -L -s "${self_repo_raw}/install.sh" 2>/dev/null | grep "shell_version=" | head -1 | awk -F '=|"' '{print $3}')
    if [[ -z "$ol_version" ]]; then
        # 备用：wulabing 原始仓库
        ol_version=$(curl -L -s "https://raw.githubusercontent.com/${wulabing_repo}/${github_branch}/install.sh" | grep "shell_version=" | head -1 | awk -F '=|"' '{print $3}')
    fi
    echo "$ol_version" >$version_cmp
    echo "$shell_version" >>$version_cmp
    if [[ "$shell_version" < "$(sort -rV $version_cmp | head -1)" ]]; then
        echo -e "${OK} ${GreenBG} 存在新版本，是否更新 [Y/N]? ${Font}"
        read -r update_confirm
        case $update_confirm in
        [yY][eE][sS] | [yY])
            wget -N --no-check-certificate "${self_repo_raw}/install.sh"
            echo -e "${OK} ${GreenBG} 更新完成 ${Font}"
            exit 0
            ;;
        *) ;;

        esac
    else
        echo -e "${OK} ${GreenBG} 当前版本为最新版本 ${Font}"
    fi

}
maintain() {
    echo -e "${RedBG}该选项暂时无法使用${Font}"
    echo -e "${RedBG}$1${Font}"
    exit 0
}
list() {
    case $1 in
    tls_modify)
        tls_type
        ;;
    uninstall)
        uninstall_all
        ;;
    crontab_modify)
        acme_cron_update
        ;;
    boost)
        bbr_boost_sh
        ;;
    *)
        menu
        ;;
    esac
}
modify_camouflage_path() {
    [[ -z ${camouflage_path} ]] && camouflage_path=1
    sed -i "/location/c \\\tlocation \/${camouflage_path}\/" ${nginx_conf}          #Modify the camouflage path of the nginx configuration file
    sed -i "/\"path\"/c \\\t  \"path\":\"\/${camouflage_path}\/\"" ${v2ray_conf}    #Modify the camouflage path of the v2ray configuration file
    judge "V2ray camouflage path modified"
}

menu() {
    update_sh
    echo -e "\t V2ray 安装管理脚本 ${Red}[${shell_version}]${Font}"
    echo -e "\t---authored by wulabing---"
    echo -e "\thttps://github.com/wulabing\n"
    echo -e "当前已安装版本:${shell_mode}\n"

    echo -e "—————————————— 安装向导 ——————————————"""
    echo -e "${Green}0.${Font}  升级 脚本"
    echo -e "${Green}1.${Font}  安装 V2Ray (Nginx+ws+tls)"
    echo -e "${Green}2.${Font}  安装 V2Ray (http/2)"
    echo -e "${Green}3.${Font}  升级 V2Ray core"
    echo -e "—————————————— 配置变更 ——————————————"
    echo -e "${Green}4.${Font}  变更 UUID"
    echo -e "${Green}5.${Font}  变更 alterid"
    echo -e "${Green}6.${Font}  变更 port"
    echo -e "${Green}7.${Font}  变更 TLS 版本(仅ws+tls有效)"
    echo -e "${Green}18.${Font}  变更伪装路径"
    echo -e "—————————————— 查看信息 ——————————————"
    echo -e "${Green}8.${Font}  查看 实时访问日志"
    echo -e "${Green}9.${Font}  查看 实时错误日志"
    echo -e "${Green}10.${Font} 查看 V2Ray 配置信息"
    echo -e "—————————————— 其他选项 ——————————————"
    echo -e "${Green}11.${Font} 安装 4合1 bbr 锐速安装脚本（第三方脚本）"
    echo -e "${Green}12.${Font} 安装 MTproxy(支持TLS混淆)"
    echo -e "${Green}13.${Font} 证书 有效期更新"
    echo -e "${Green}14.${Font} 卸载 V2Ray"
    echo -e "${Green}15.${Font} 更新 证书crontab计划任务"
    echo -e "${Green}16.${Font} 清空 证书遗留文件"
    echo -e "${Green}17.${Font} 退出"
    echo -e "${Green}19.${Font} 内核分析 & 一键启用 BBR 加速 \n"

    read -rp "请输入数字：" menu_num
    case $menu_num in
    0)
        update_sh
        ;;
    1)
        shell_mode="ws"
        install_v2ray_ws_tls
        ;;
    2)
        shell_mode="h2"
        install_v2_h2
        ;;
    3)
        bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
        ;;
    4)
        read -rp "请输入UUID:" UUID
        modify_UUID
        start_process_systemd
        ;;
    5)
        read -rp "请输入alterID:" alterID
        modify_alterid
        start_process_systemd
        ;;
    6)
        read -rp "请输入连接端口:" port
        if grep -q "ws" $v2ray_qr_config_file; then
            modify_nginx_port
        elif grep -q "h2" $v2ray_qr_config_file; then
            modify_inbound_port
        fi
        start_process_systemd
        ;;
    7)
        tls_type
        ;;
    8)
        show_access_log
        ;;
    9)
        show_error_log
        ;;
    10)
        basic_information
        if [[ $shell_mode == "ws" ]]; then
            vmess_link_image_choice
        else
            vmess_qr_link_image
        fi
        show_information
        ;;
    11)
        bbr_boost_sh
        ;;
    12)
        mtproxy_sh
        ;;
    13)
        stop_process_systemd
        ssl_update_manuel
        start_process_systemd
        ;;
    14)
        source '/etc/os-release'
        uninstall_all
        ;;
    15)
        acme_cron_update
        ;;
    16)
        delete_tls_key_and_crt
        ;;
    17)
        exit 0
        ;;
    18)
        read -rp "请输入伪装路径(注意！不需要加斜杠 eg:ray):" camouflage_path
        modify_camouflage_path
        start_process_systemd
        ;;
    19)
        check_kernel_and_recommend_bbr
        ;;
    *)
        echo -e "${RedBG}请输入正确的数字${Font}"
        ;;
    esac
}

# 解析命令行参数
# 支持 --host <domain> 指定域名，跳过交互式输入
# 支持 --mode <ws|h2> 直接启动安装，跳过菜单
SUBCMD=""
install_mode=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            domain="$2"
            shift 2
            ;;
        --mode)
            install_mode="$2"
            shift 2
            ;;
        *)
            SUBCMD="$1"
            shift
            ;;
    esac
done

judge_mode

# 若指定了 --mode，直接执行对应安装流程（无需交互菜单）
if [[ -n "$install_mode" ]]; then
    case "$install_mode" in
        ws)
            shell_mode="ws"
            install_v2ray_ws_tls
            ;;
        h2)
            shell_mode="h2"
            install_v2_h2
            ;;
        *)
            echo -e "${Error} ${RedBG} 未知 --mode 值：${install_mode}，可选：ws / h2 ${Font}"
            exit 1
            ;;
    esac
else
    list "${SUBCMD}"
fi
