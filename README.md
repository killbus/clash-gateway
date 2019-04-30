# clash-gateway
# 说明
基于 [clash 项目](https://github.com/Dreamacro/clash)，实现docker中的透明网关，目前有`x86_64`及`aarch64`两个版本。

群晖上由于内核模块缺失，导致`iptables`及`ipset`部分功能无法使用，所以无法使用 [tproxy-gateway](https://hub.docker.com/r/lisaac/tproxy-gateway)，所以才有了这个镜像，若运行在群晖上，请将群晖设为静态IP。

# 快速开始

```bash
mkdir -p ~/.docker/clash-gateway

# 下载 clash 配置文件模版
wget https://raw.githubusercontent.com/lisaac/clash-gateway/master/config.yml -O ~/.docker/clash-gateway/config.yml

# 下载 cg.conf
wget https://raw.githubusercontent.com/lisaac/clash-gateway/master/cg.conf -O ~/.docker/clash-gateway/cg.conf 

################## 配置 clash ##################
vi ~/.docker/clash-gateway/config.yml

################## 配置 cg.conf ##################
vi ~/.docker/clash-gateway/cg.conf

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
docker run -d --name clash-gateway \
    --network dMACvLAN --ip 10.1.1.244 \
    --privileged \
    --restart unless-stopped \
    -v $HOME/.docker/clash-gateway:/etc/clash-gateway \
    lisaac/clash-gateway:`uname -m`

# 查看网关运行情况
docker logs clash-gateway
```
配置客户端网关及DNS

# 配置文件
配置文件放至`/to/path/config`，并挂载至容器，主要配置文件为：
```bash
/to/ptah/config
  |- cg.conf：clash-gateway 配置文件
  |- config.yaml: clash 配置文件
```

# koolproxy
镜像中包含 `koolproxy`，需要在 `cg.conf` 设置 `ad_filter='kp'`

#### Koolproxy 开启 HTTPS 过滤
默认没有启用 `https` 过滤，如需要启用 `https` 过滤，需要运行:
```bash
docker exec clash-gateway /koolproxy/koolproxy --cert -b /etc/ss-proxy/koolproxydata
```
并重启容器，证书文件在宿主机的`/to/path/config/koolproxydata/cert`目录下。

## 配置不走代理及广告过滤的内网ip地址
有时候希望内网某些机器不走代理，配置 `cg.conf` 中 `ipts_non_proxy`，多个`ip`请用空格隔开

# 运行 clash-gateway 容器
新建`docker macvlan`网络，配置网络地址为内网`lan`地址及默认网关:
```bash
docker network create -d macvlan \
  --subnet=10.1.1.0/24 --gateway=10.1.1.1 \
  --ipv6 --subnet=fe80::/10 --gateway=fe80::1 \
  -o parent=eth0 \
  -o macvlan_mode=bridge \
  dMACvLAN
```
 - `--subnet=10.1.1.0/24` 指定 ipv4 内网网段
 - `--gateway=10.1.1.1` 指定 ipv4 内网网关
 - `-o parent=eth0` 指定网卡

运行容器:
```bash
docker run -d --name clash-gateway \
  -e TZ=Asia/Shanghai \
  --network dMACvLAN --ip 10.1.1.244 \
  --privileged \
  --restart unless-stopped \
  -v /to/path/config:/etc/clash-gateway \
  lisaac/clash-gateway:`uname -m`
```
 - `--ip 10.1.1.244` 指定容器`ipv4`地址
 - `--ip6 fe80::fe80 ` 指定容器`ipv6`地址，如不指定自动分配，建议自动分配。若指定，容器重启后会提示ip地址被占用，只能重启`docker`服务才能启动，原因未知。
 - `-v /to/path/config:/etc/clash-gateway` 指定配置文件目录，至少需要`cg.conf`及`config.yaml`

启动后会自动更新规则，根据网络情况，启动可能有所滞后，可以使用`docker logs clash-gateway`查看容器情况。

# 热更新容器
容器中内置 update.sh, 用于热更新 `clash/koolproxy`等二进制文件。
```
# 更新
docker exec clash-gateway /update.sh
# 重启
docker exec clash-gateway /init.sh
```

# 设置客户端
设置客户端(或设置路由器`DHCP`)默认网关及`DNS`服务器为容器`IP:10.1.1.244`

以openwrt为例，在`/etc/config/dhcp`中`config dhcp 'lan'`段加入：

```
  list dhcp_option '6,10.1.1.244'
  list dhcp_option '3,10.1.1.244'
```
# 关于IPv6 DNS
使用过程中发现，若启用了 `IPv6`，某些客户端(`Android`)会自动将`DNS`服务器地址指向默认网关(路由器)的`IPv6`地址，导致客户端不走`docker`中的`dns`服务器。

解决方案是修改路由器中`IPv6`的`通告dns服务器`为容器ipv6地址。

以openwrt为例，在`/etc/config/dhcp`中`config dhcp 'lan'`段加入：
```
  list dns 'fe80::fe80'
```

# 关于宿主机出口
由于`docker`网络采用`macvlan`的`bridge`模式，宿主机虽然与容器在同一网段，但是相互之间是无法通信的，所以无法通过`clash-gateway`透明代理。

解决方案 1 是让宿主机（群晖）直接走主路由，不经过代理网关，直接设置静态IP地址：
```bash
ip route add default via 10.1.1.1 dev eth0 # 设置静态路由
echo "nameserver 10.1.1.1" > /etc/resolv.conf # 设置静态dns服务器
```
解决方案 2 是利用多个`macvlan`接口之间是互通的原理，新建一个`macvlan`虚拟接口，并设置静态IP地址：
```bash
ip link add link eth0 mac0 type macvlan mode bridge # 在eth0接口下添加一个macvlan虚拟接口
ip addr add 10.1.1.250/24 brd + dev mac0 # 为mac0 分配ip地址
ip link set mac0 up
ip route del default #删除默认路由
ip route add default via 10.1.1.244 dev mac0 # 设置静态路由
echo "nameserver 10.1.1.244" > /etc/resolv.conf # 设置静态dns服务器
```

# Docker Hub
[https://hub.docker.com/r/lisaac/clash-gateway](https://hub.docker.com/r/lisaac/clash-gateway)

ENJOY
