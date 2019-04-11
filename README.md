# clash-gateway
# 说明
基于 [clash 项目](https://github.com/Dreamacro/clash)，实现docker中的透明网关，目前有`x86_64`及`aarch64`两个版本。
# 快速开始

```bash
mkdir -p ~/.docker/clash-gateway

# 下载 clash 配置文件模版
wget -p ~/.docker/clash-gateway https://raw.githubusercontent.com/lisaac/clash-gateway/master/config.yml

# 下载 cg.conf
wget -p ~/.docker/clash-gateway https://raw.githubusercontent.com/lisaac/clash-gateway/master/cg.conf

################## 配置 clash.yml ##################
vi ~/.docker/clash-gateway/clash.yml

################## 配置 cg.conf ##################
vi ~/.docker/clash-gateway/clash.yml

# 创建docker network
docker network create -d macvlan \
    --subnet=10.1.1.0/24 --gateway=10.1.1.1 \
    --ipv6 --subnet=fe80::/10 --gateway=fe80::1 \
    -o parent=eth0 \
    -o macvlan_mode=bridge \
    dMACvLAN

# 拉取docker镜像
docker pull lisaac/clash-gateway:`uname -m`

# 运行容器
docker run -d --name clash-gatewayt \
    --network dMACvLAN --ip 10.1.1.244 \
    --privileged \
    --restart unless-stopped \
    -v $HOME/.docker/clash-gateway:/etc/clash-gateway \
    lisaac/clash-gateway:`uname -m`

# 查看网关运行情况
docker logs clash-gateway
```
配置客户端网关及DNS