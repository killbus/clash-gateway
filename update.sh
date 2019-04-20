#!/bin/bash

function check_last_version {
  arch=`uname -m` && \
  clash_latest_ver="$(curl -H 'Cache-Control: no-cache' -s https://api.github.com/repos/Dreamacro/clash/releases | grep 'tag_name' | cut -d\" -f4 | head -n 1)" && \
  koolproxy_latest_ver="$(curl -H 'Cache-Control: no-cache' -s https://raw.githubusercontent.com/lisaac/tproxy-gateway/master/latest_version | grep 'koolproxy' | cut -d' ' -f2)" || { echo "[ERR] can NOT get the latest version of clash-gateway, please check the network"; exit 1; }
  if [ $arch = "x86_64" ]; then
    _arch="amd64"
    kp_url="https://koolproxy.com/downloads/x86_64"
    clash_url="https://github.com/Dreamacro/clash/releases/download/${clash_latest_ver}/clash-linux-${_arch}.tar.gz"
  elif [ $arch = "aarch64" ]; then
    _arch="armv8"
    kp_url="https://koolproxy.com/downloads/arm"
    clash_url="https://github.com/Dreamacro/clash/releases/download/${clash_latest_ver}/clash-linux-${_arch}.tar.gz"
  fi; \
}

function update_self {
  echo "$(date +%Y-%m-%d\ %T) Check new version of clash-gateway." && \
  clash_gateway_latest=$(curl -H 'Cache-Control: no-cache' -s "https://api.github.com/repos/lisaac/clash-gateway/commits/master" | grep '"date": ' | awk 'NR==1{print $2}' | sed 's/"//g; s/T/ /; s/Z//' | xargs -I{} date -u -d {} +%s) || { echo "[ERR] can NOT get the latest version of clash-gateway, please check the network"; exit 1; }
  [ -f $0 ] && update_sh_current=$(stat -c %Y $0) || update_sh_current=0
  if [ "$clash_gateway_latest" -gt "$update_sh_current" ]; then
    echo "$(date +%Y-%m-%d\ %T) updating update.sh."
    wget https://raw.githubusercontent.com/lisaac/clash-gateway/master/update.sh -O /tmp/update.sh && \
    install -c /tmp/update.sh $0 && \
    exec $0 "$@"
    exit 0
  fi
  [ -f /init.sh ] && init_sh_current=$(stat -c %Y /init.sh) || init_sh_current=0
  if [ "$clash_gateway_latest" -gt "$init_sh_current" ]; then
    echo "$(date +%Y-%m-%d\ %T) updating init.sh."
    wget https://raw.githubusercontent.com/lisaac/clash-gateway/master/init.sh -O /tmp/init.sh && \
    install -c /tmp/init.sh /init.sh
  fi
  echo "$(date +%Y-%m-%d\ %T) clash-gateway update to date."
}

function update_system {
  apk --no-cache --no-progress upgrade && \
  apk --no-cache --no-progress add iptables bash ca-certificates tzdata curl
}
# 更新 koolproxy
function update_koolproxy {
  echo "$(date +%Y-%m-%d\ %T) Updating koolproxy.." && \
  if [ -f /koolproxy/koolproxy ]; then
    koolproxy_current_ver="$(/koolproxy/koolproxy -v | cut -d' ' -f1)"
  fi; \

  if [ "$koolproxy_latest_ver" != "$koolproxy_current_ver" -o ! -f /koolproxy/koolproxy ]; then
    echo "Latest koolproxy version: ${koolproxy_latest_ver}, need to update" && \
    rm -fr /koolproxy && mkdir -p /koolproxy && cd /koolproxy && \
    wget "$kp_url" -O koolproxy && chmod +x /koolproxy/koolproxy
  else
    echo "Current koolproxy version: ${koolproxy_current_ver}, need NOT to update"
  fi
}
# update clash
function update_clash {
  echo "$(date +%Y-%m-%d\ %T) Updating clash.." && \

  
  if [ -f /clash ]; then
    clash_current_ver="$(/clash -v | cut -d' ' -f2 | cut -d- -f1)"; \
  fi; \
  if [ "$clash_latest_ver" != "$clash_current_ver" -o ! -f /clash ]; then
    echo "Latest clash version: ${clash_current_ver}, need to update" && \
    rm -fr /clash && \
    wget $clash_url -O /clash-linux.tar.gz && \
    tar zxf /clash-linux.tar.gz && rm -fr /clash-linux.tar.gz && \
    mv "/clash-linux-${_arch}" /clash && chmod +x /clash
  else
    echo "Current clash version: ${clash_current_ver}, need NOT to update"
  fi
}

function update_sample_file {
  echo "$(date +%Y-%m-%d\ %T) Updating sample files.." && \
  mkdir -p /sample_config && \
  wget https://raw.githubusercontent.com/lisaac/clash-gateway/master/cg.conf -O /sample_config/cg.conf && \
  wget https://raw.githubusercontent.com/lisaac/clash-gateway/master/config.yml -O /sample_config/config.yml
}

function check_version {
  rm -rf /tmp/* && \
  echo "Update time: $(date +%Y-%m-%d\ %T)" > /version && \
  echo "clash version: $(/clash -v | cut -d' ' -f2 | cut -d- -f1)" | tee -a /version && \
  echo "Update completed !!"
}

update_system && update_self && check_last_version && update_clash && update_koolproxy && update_sample_file && check_version || echo "Update failed!"