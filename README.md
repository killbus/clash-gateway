# clash-gateway

```
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
    --network dMACvLAN --ip 10.1.1.238 \
    --privileged \
    --restart unless-stopped \
    -v $HOME/.docker/clash-gateway:/etc/clash-gateway \
    lisaac/clash-gateway:`uname -m`
```