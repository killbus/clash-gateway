#!/bin/bash

CONFIG_PATH='/etc/clash-gateway'

function check_env {
  if [ ! -f /clash -o ! -f /sample_config/cg.conf -o ! -f /sample_config/config.yml ]; then
    /update.sh || echo "[ERR] Can't update, please check networking or update the container. "
  fi; \
  return 0
}

function update_mmdb {
  echo "$(date +%Y-%m-%d\ %T) Updating MMDB.." && \
  wget http://geolite.maxmind.com/download/geoip/database/GeoLite2-Country.tar.gz -O /tmp/GeoLite2-Country.tar.gz && \
  tar zxvf /tmp/GeoLite2-Country.tar.gz -C /tmp && mkdir -p $CONFIG_PATH && \
  mv /tmp/GeoLite2-Country_*/GeoLite2-Country.mmdb ${CONFIG_PATH}/Country.mmdb && rm -fr /tmp/*
}

function check_config {
  NEED_EXIT="false"
  # 若没有配置文件，拷贝配置文件模版
  if [ ! -f "${CONFIG_PATH}/cg.conf" ]; then
    cp /sample_config/cg.conf "$CONFIG_PATH"
    echo "[ERR] No cg.conf, sample file copied, please configure it."
    NEED_EXIT="true"
  fi; \
  if [ ! -f "${CONFIG_PATH}/config.yml" ]; then
    cp /sample_config/config.yml "$CONFIG_PATH"
    echo "[ERR] No config.yml, sample file copied, please configure it."
    NEED_EXIT="true"
  fi; \
  if [ "$NEED_EXIT" = "true" ]; then
    exit 1;
  fi; \
  if [ ! -f "${CONFIG_PATH}/Country.mmdb" ]; then
    update_mmdb
  fi
  source "${CONFIG_PATH}/cg.conf"
  return 0
}

function check_snat_rule {
  if [ "$ipts_non_snat" != 'true' ]; then
    if ! iptables -t nat -C POSTROUTING -s $intranet ! -d $intranet -j MASQUERADE &>/dev/null; then
        iptables -t nat -A POSTROUTING -s $intranet ! -d $intranet -j MASQUERADE
    fi
  fi
}

function start {
sysctl -w net.ipv4.ip_forward=1 &>/dev/null
for dir in $(ls /proc/sys/net/ipv4/conf); do
    sysctl -w net.ipv4.conf.$dir.send_redirects=0 &>/dev/null
done

echo "$(date +%Y-%m-%d\ %T) Setting iptables.."
iptables -t nat -N CLASH_TCP
for intranet in "${ipts_intranet[@]}"; do
  iptables -t nat -A PREROUTING -s $intranet -p tcp -j CLASH_TCP
  check_snat_rule
done

iptables -t nat -A CLASH_TCP -d 0.0.0.0/8 -j RETURN
iptables -t nat -A CLASH_TCP -d 127.0.0.0/8 -j RETURN
iptables -t nat -A CLASH_TCP -d 10.0.0.0/8 -j RETURN
iptables -t nat -A CLASH_TCP -d 169.254.0.0/16 -j RETURN
iptables -t nat -A CLASH_TCP -d 172.16.0.0/12 -j RETURN
iptables -t nat -A CLASH_TCP -d 192.168.0.0/16 -j RETURN
iptables -t nat -A CLASH_TCP -d 224.0.0.0/4 -j RETURN
iptables -t nat -A CLASH_TCP -d 240.0.0.0/4 -j RETURN

# 过滤 VPS ip地址
unset server_addrs && \
for server in "${proxy_server[@]}"; do
  if [ $(grep -Ec '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' <<< "$server") -eq 0 ]; then
    server_addr="$(getent hosts $server | cut -d' ' -f1)"
    server_addrs+=($server_addr)
    if [ -n "$(cat /etc/hosts | grep $server)" ];then 
      echo "$(sed "/${server}/d" /etc/hosts)" > /etc/hosts
    fi
    echo "${server_addr} ${server}" >> /etc/hosts
  fi
done; \
for server in "${proxy_server[@]}"; do
  iptables -t nat -A CLASH_TCP -d $server -j RETURN
done; \

iptables -t nat -A CLASH_TCP -p tcp -j REDIRECT --to-ports $proxy_tcport

# iptables -t nat -A OUTPUT -p tcp -j CLASH_TCP
# iptables -t nat -I OUTPUT -m owner --uid-owner 0 -j RETURN

echo "nameserver 127.0.0.1" > /etc/resolv.conf

echo "$(date +%Y-%m-%d\ %T) Starting clash.."
/clash -d /etc/clash-gateway/ &> /var/log/clash.log &

echo -e "IPv4 gateway & dns server: \n`ip addr show eth0 |grep 'inet ' | awk '{print $2}' |sed 's/\/.*//g'`" && \
echo -e "IPv6 dns server: \n`ip addr show eth0 |grep 'inet6 ' | awk '{print $2}' |sed 's/\/.*//g'`" 
}

function stop {
  echo "nameserver 114.114.114.114" > /etc/resolv.conf
  # 清理 /etc/hosts
  unset server_addrs && \
  for server in "${proxy_server[@]}"; do
    if [ $(grep -Ec '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' <<< "$server") -eq 0 ]; then
      if [ -n "$(cat /etc/hosts | grep $server)" ];then 
        echo "$(sed "/${server}/d" /etc/hosts)" > /etc/hosts
      fi
    fi
  done; \
  echo "$(date +%Y-%m-%d\ %T) Clear iptables.."
  for intranet in "${ipts_intranet[@]}"; do
    iptables -t nat -D PREROUTING -s $intranet -p tcp -j CLASH_TCP &>/dev/null
  done
  # iptables -t nat -D OUTPUT  -p tcp -j CLASH_TCP &>/dev/null
  iptables -t nat -F CLASH_TCP
  iptables -t nat -X CLASH_TCP

  echo "$(date +%Y-%m-%d\ %T) Stoping clash.."
  killall clash &>/dev/null; \
  return 0
}

check_env && check_config && \
case $1 in
    start)         start;;
    stop)          stop;;
    daemon)        start && tail -f /var/log/clash.log;;
    update-mmdb)   update;;
    *)             stop && start;;
esac