#!/bin/bash

CONFIG_PATH='/etc/clash-gateway'

if [ -f "${CONFIG_PATH}/cg.conf" ]; then
  source "${CONFIG_PATH}/cg.conf"
else
  echo "[ERR] No clash gateway config: ${CONFIG_PATH}/cg.conf"  1>&2; \
  exit 1;
fi; \

function check_env {
  if [ ! -f /clash-o ! -f /sample_config/cg.conf -o ! -f /sample_config/config.yml ]; then
    /update.sh || echo "[ERR] Can't update, please check networking or update the container. "
  fi; \
  return 0
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
  return 0
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
done

iptables -t nat -A CLASH_TCP -d 0.0.0.0/8 -j RETURN
iptables -t nat -A CLASH_TCP -d 127.0.0.0/8 -j RETURN
iptables -t nat -A CLASH_TCP -d 10.0.0.0/8 -j RETURN
iptables -t nat -A CLASH_TCP -d 169.254.0.0/16 -j RETURN
iptables -t nat -A CLASH_TCP -d 172.16.0.0/12 -j RETURN
iptables -t nat -A CLASH_TCP -d 192.168.0.0/16 -j RETURN
iptables -t nat -A CLASH_TCP -d 224.0.0.0/4 -j RETURN
iptables -t nat -A CLASH_TCP -d 240.0.0.0/4 -j RETURN

for server in "${server_addrs[@]}"; do
  iptables -t nat -A CLASH_TCP -d $server -j RETURN
done

iptables -t nat -A CLASH_TCP -p tcp -j REDIRECT --to-ports $proxy_tcport

# iptables -t nat -A OUTPUT -p tcp -j CLASH_TCP
# iptables -t nat -I OUTPUT -m owner --uid-owner 0 -j RETURN
echo "$(date +%Y-%m-%d\ %T) Starting clash.."
/clash -d /etc/clash-gateway/ &> /var/log/clash.log &
}

function stop {
  echo "$(date +%Y-%m-%d\ %T) Clear iptables.."
  for intranet in "${ipts_intranet[@]}"; do
    iptables -t nat -D PREROUTING -s $intranet -p tcp -j CLASH_TCP &>/dev/null
  done
  # iptables -t nat -D OUTPUT  -p tcp -j CLASH_TCP &>/dev/null
  iptables -t nat -F CLASH_TCP
  iptables -t nat -X CLASH_TCP
  echo "$(date +%Y-%m-%d\ %T) Stoping clash.."
  killall clash &>/dev/null
}

for server in "${proxy_server[@]}"; do
    if [ $(grep -Ec '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' <<< "$server") -eq 0 ]; then
        server_addrs+="$(ping -nq -c1 -t1 -W1 $server | head -n1 | awk -F'[()]' '{print $2}') "
    fi
done; \

case $1 in
    start)              check_env; check_config && start;;
    stop)               stop;;
    daemon)             stop; check_env; check_config && start; tail -f /var/log/clash.log;;
    *)                  stop; check_env; check_config && start;;
esac