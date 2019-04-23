#!/bin/bash

CONFIG_PATH='/etc/clash-gateway'

function check_env {
  if [ ! -f /clash -o ! -f /sample_config/cg.conf -o ! -f /sample_config/config.yml ]; then
    /update.sh  && { exec $0 "$@"; exit 0; } ||{ echo "[ERR] Can't update, please check networking or update the container. "; return 1; }
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
    if ! iptables -t nat -C S_NAT -s $intranet ! -d $intranet -j MASQUERADE &>/dev/null; then
      iptables -t nat -A S_NAT -s $intranet ! -d $intranet -j MASQUERADE
    fi
  fi
}

function flush_iptables {
  echo "$(date +%Y-%m-%d\ %T) flush iptables.."
  iptables -t nat -D PREROUTING -j CLASH &>/dev/null
  iptables -t nat -D PREROUTING -j HANDLE_DNS &>/dev/null
  iptables -t nat -D PREROUTING -j NEED_ACCEPT &>/dev/null
  iptables -t nat -D POSTROUTING -j S_NAT &>/dev/null

  iptables -t nat -F CLASH &>/dev/null
  iptables -t nat -X CLASH &>/dev/null
  iptables -t nat -F HANDLE_DNS &>/dev/null
  iptables -t nat -X HANDLE_DNS &>/dev/null
  iptables -t nat -F NEED_ACCEPT &>/dev/null
  iptables -t nat -X NEED_ACCEPT &>/dev/null
  iptables -t nat -F S_NAT &>/dev/null
  iptables -t nat -X S_NAT &>/dev/null

  iptables -t raw -F
  iptables -t raw -X
  iptables -t mangle -F
  iptables -t mangle -X
  iptables -t nat -F
  iptables -t nat -X
  iptables -t filter -F
  iptables -t filter -X
}

function cdr2mask {
   # Number of args to shift, 255..255, first non-255 byte, zeroes
   set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
   [ $1 -gt 1 ] && shift $1 || shift
   echo $(printf %02x ${1-0})$(printf %02x ${2-0})$(printf %02x ${3-0})$(printf %02x ${4-0})
}

function start_iptables {
  echo "$(date +%Y-%m-%d\ %T) Setting iptables.."
  # 建立自定义chian
  iptables -t nat -N HANDLE_DNS
  iptables -t nat -N NEED_ACCEPT
  iptables -t nat -N CLASH
  iptables -t nat -N S_NAT

  # 解析 server 地址
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
  # 过滤 VPS ip地址
  for server in "${proxy_server[@]}"; do
    iptables -t nat -A NEED_ACCEPT -d $server -j ACCEPT
  done; \

  # 转发至 clash
  iptables -t nat -A CLASH -p tcp -j REDIRECT --to-ports $proxy_tcport

  for intranet in "${ipts_intranet[@]}"; do
    # handle dns
    iptables -t nat -A HANDLE_DNS -p udp -s $intranet --dport 53 -j REDIRECT --to-ports 60053
    # 内网地址 return
    iptables -t nat -A NEED_ACCEPT -d $intranet -j ACCEPT
    check_snat_rule
  done

  # 包转入自定义 chian
    iptables -t nat -A PREROUTING -j HANDLE_DNS
    iptables -t nat -A PREROUTING -j NEED_ACCEPT
    iptables -t nat -A PREROUTING -j CLASH

    iptables -t nat -A POSTROUTING -j S_NAT
}

function start_koolproxy {
  echo  "$(date +%Y-%m-%d\ %T) Starting koolproxy.."
  if [ "$ad_filter" = 'kp' ]; then
    mkdir -p ${CONFIG_PATH}/koolproxydata
    chown -R daemon:daemon ${CONFIG_PATH}/koolproxydata
    #su -s/bin/sh -c'/koolproxy/koolproxy -d -l2 -p65080 -b'${CONFIG_PATH}'/koolproxydata' daemon
    /koolproxy/koolproxy -d -l2 --mark -p65080 -b${CONFIG_PATH}/koolproxydata

    iptables -t nat -N KOOLPROXY
    iptables -t nat -N KP_OUT

    iptables -t nat -I PREROUTING 3 -p tcp -j KOOLPROXY
    iptables -t nat -I OUTPUT -p tcp -j KP_OUT

    for intranet in "${ipts_intranet[@]}"; do
      # https://github.com/openwrt-develop/luci-app-koolproxy/blob/master/koolproxy.txt
      iptables -t nat -A KOOLPROXY -s $intranet ! -d $intranet -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 65080
      kp_mark_mask=$(cdr2mask $(echo $intranet | awk -F "[./]" '{printf ($5)}'))
      kp_mark=$(echo $intranet | awk -F "[./]" '{printf ("0x%02x", $1)} {printf ("%02x", $2)} {printf ("%02x", $3)} {printf ("%02x", $4)} {printf ("/0x'$kp_mark_mask'\n")}')
      iptables -t nat -A KP_OUT -p tcp -m mark --mark $kp_mark -j CLASH
      # iptables -t nat -A KP_OUT -p tcp -m mark ! --mark $kp_mark -j KOOLPROXY
    done
    
  fi
}

function stop_koolproxy {
  echo  "$(date +%Y-%m-%d\ %T) Stoping koolproxy.."
  iptables -t nat -D PREROUTING -p tcp -j KOOLPROXY &>/dev/null
  iptables -t nat -D PREROUTING -p tcp -j KP_OUT &>/dev/null
  iptables -t nat -F KOOLPROXY &>/dev/null
  iptables -t nat -X KOOLPROXY &>/dev/null
  iptables -t nat -F KP_OUT &>/dev/null
  iptables -t nat -X KP_OUT &>/dev/null
  killall koolproxy &>/dev/null
}

function start {
  sysctl -w net.ipv4.ip_forward=1 &>/dev/null
  for dir in $(ls /proc/sys/net/ipv4/conf); do
      sysctl -w net.ipv4.conf.$dir.send_redirects=0 &>/dev/null
  done

  start_iptables

  echo "nameserver 127.0.0.1" > /etc/resolv.conf
  echo "$(date +%Y-%m-%d\ %T) Starting clash.."
  /clash -d /etc/clash-gateway/ &> /var/log/clash.log &

  [ "$ad_filter" = 'kp' ] && start_koolproxy

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

  stop_koolproxy
  flush_iptables

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