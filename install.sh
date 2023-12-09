imageName="zerotier-planet"

function install(){
    ZT_PORT=9994
    API_PORT=3443
    FILE_PORT=3000

    read -p "请输入zerotier-planet要使用的端口号,例如9994: " ZT_PORT
    #port必须是数字
    while [[ ! "$ZT_PORT" =~ ^[0-9]+$ ]]; do
        read -p "端口号必须是数字，请重新输入: " ZT_PORT
    done

    read -p "请输入zerotier-planet的API端口号,例如3443: " API_PORT
    #port必须是数字
    while [[ ! "$API_PORT" =~ ^[0-9]+$ ]]; do
        read -p "端口号必须是数字，请重新输入: " API_PORT
    done

    read -p "请输入zerotier-planet的FILE端口号,例如3000: " FILE_PORT
    #port必须是数字
    while [[ ! "$FILE_PORT" =~ ^[0-9]+$ ]]; do
        read -p "端口号必须是数字，请重新输入: " FILE_PORT
    done

    read -p "是否自动获取公网IP地址?(y/n)" use_auto_ip
    use_auto_ip=${use_auto_ip:-y}
    if [[ "$use_auto_ip" =~ ^[Yy]$ ]]; then
        ipv4=$(curl -s https://ipv4.icanhazip.com/)
        ipv6=$(curl -s https://ipv6.icanhazip.com/)
        echo "获取到的IPv4地址为: $ipv4"
        echo "获取到的IPv6地址为: $ipv6"

        read -p "是否使用上面获取到的IP地址?(y/n)" use_auto_ip_result
        use_auto_ip_result=${use_auto_ip_result:-y}
        if [[ "$use_auto_ip_result" =~ ^[Nn]$ ]]; then
        read -p "请输入IPv4地址: " ipv4
        read -p "请输入IPv6地址(可留空): " ipv6
        fi
    else
        # 要求用户手动输入IP地址
        read -p "请输入IPv4地址: " ipv4
        read -p "请输入IPv6地址(可留空): " ipv6
    fi

}