#!/bin/bash

function update_system {
  apk --no-cache --no-progress upgrade && \
  apk --no-cache --no-progress add iptables bash ca-certificates curl
}

# update clash
function update_clash {
  echo "$(date +%Y-%m-%d\ %T) Updating clash.." && \
  arch=`uname -m` && \
  clash_latest_ver="$(curl -H 'Cache-Control: no-cache' -s https://api.github.com/repos/Dreamacro/clash/releases | grep 'tag_name' | cut -d\" -f4 | head -n 1)" && \
  if [ $arch = "x86_64" ]; then
    arch="amd64"
  elif [ $arch = aarch64 ]; then
    arch="armv8"
  fi; \
  clash_url="https://github.com/Dreamacro/clash/releases/download/$clash_latest_ver/clash-linux-$arch.tar.gz" && \
  if [ -f /clash ]; then
    clash_current_ver="$(/clash -v | cut -d' ' -f2 | cut -d- -f1)"; \
  fi; \
  if [ "$clash_latest_ver" != "$clash_current_ver" -o ! -f /clash ]; then
    echo "Latest clash version: ${clash_current_ver}, need to update" && \
    rm -fr /clash && \
    wget $clash_url -O /clash-linux.tar.gz && \
    tar zxf /clash-linux.tar.gz && rm -fr /clash-linux.tar.gz && \
    mv "/clash-linux-${arch}" /clash && chmod +x /clash
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

update_system && update_clash && update_sample_file && check_version || echo "Update failed!"