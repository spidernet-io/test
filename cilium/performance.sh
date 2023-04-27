#!/bin/bash

set -e
set -x

source config

function install_yq() {
  if ! which yq &>/dev/null ; then
    echo "yq no found, trying to install"
    url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
    if [ ! -z "$GITHUB_PROXY" ]; then url="$GITHUB_PROXY/$url"
      wget $url -O /usr/bin/yq && chmod +x /usr/bin/yq
    fi
  fi
}

function tuningNode() {

  [ -z "${DEVICE}" ] && echo "err: Device can't be empty" && exit 1
  echo "DEVICE: ${DEVICE}"

  # tuning NIC queue
  PRE_SET_RX=`ethtool -g ${DEVICE} | sed -n '3p' | egrep -o  '[0-9]*$' `
  PRE_SET_TX=`ethtool -g ${DEVICE} | sed -n '6p' | egrep -o  '[0-9]*$'`
  CURRENT_RX=`ethtool -g ${DEVICE} | sed -n '8p' | egrep -o  '[0-9]*$'`
  CURRENT_TX=`ethtool -g ${DEVICE} | sed -n '11p' | egrep -o  '[0-9]*$'`

  echo "PRE_SET_RX: ${PRE_SET_RX}"
  echo "PRE_SET_TX: ${PRE_SET_TX}"
  echo "CURRENT_RX: ${CURRENT_RX}"
  echo "CURRENT_TX: ${CURRENT_TX}"

  if [ "${CURRENT_RX}" -lt "${PRE_SET_RX}" ]; then
    ethtool -G ${DEVICE} rx ${PRE_SET_RX}
  fi

  if [ "${CURRENT_TX}" -lt "${PRE_SET_TX}" ]; then
    ethtool -G ${DEVICE} tx ${PRE_SET_TX}
  fi

  # 禁用 irqbalance
  killall irqbalance || "echo "ingorning irpbalance""

  # 设置CPU为性能模式
  if [ -e /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ] ; then
    for CPU in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
          echo performance > $CPU
    done
  fi

  # 将网卡中断绑定到特定的 CPU0 和 CPU1 上，减少中断带来的性能影响
  ./set_irp_affnity.sh ${DEVICE}
}

function tuningCilium() {

    install_yq
    ############
    #  enable-bpf-masquerade: "true" # 启用 bpf-masquerading，数据包离开主机时采用 ebpf 隐藏源 IP 而不是基于 iptables
    #  enable-host-legacy-routing: "false" # 关闭可以主机处理数据包时绕过其内核协议栈，加快数据转发。默认情况下打开，但如果主机内核不支持，则回退到传统行为
    #  ipv4-native-routing-cidr: <pod_ipv4_cidr> # Direct-routing 模式下，必配配置
    #  ipv6-native-routing-cidr: <pod_ipv6_cidr> # 如果是双栈模式，必须配置
    #  kube-proxy-replacement: strict  # 启用 kube-proxy replacement 功能，需要删除 kube-proxy 组件
    #  install-no-conntrack-iptables-rules: true # 为 pod 下发 no-ct 的iptables规则，提升性能
    #  tunnel: disabled # 关闭隧道模式
    #  enable-bandwidth-manager: "true" 打开bandwidth-manager，提高tcp、udp的性能
    #  enable-bbr: "true"  bbr网络阻塞控制，要求内核大于5.18
    #  auto-direct-node-routes: "true", 路由模式下必须设置为 True, 否则无法路由跨节点流量
    ############

    # CILIUM_CONFIG_DATA=$(kubectl get cm ${CILIUM_CONFIG_MAP_NAME} -n ${CILIUM_NAMESPACE} -o yaml | yq .data)
    kubectl get cm ${CILIUM_CONFIG_MAP_NAME} -n ${CILIUM_NAMESPACE} -o yaml > .tmp/cilium-conf.yaml

    CILIUM_IPV4_CIDR=$(yq '.data.cluster-pool-ipv4-cidr' .tmp/cilium-conf.yaml)
    if [ "$CILIUM_IPV4_CIDR" = "null" ]; then
      "cilium-conf: cluster-pool-ipv4-cidr no found, exit 1" && exit 1
    else
      export CILIUM_IPV4_CIDR=$(yq '.data.cluster-pool-ipv4-cidr' .tmp/cilium-conf.yaml)
    fi

    KUBE_PROXY_REPLACEMENT=$(yq '.data.kube-proxy-replacement' .tmp/cilium-conf.yaml)
    if [ "$KUBE_PROXY_REPLACEMENT" = "null" ]; then
      "cilium-conf: kube-proxy-replacement no found, exit 2" && exit 2
    fi

    TUNNEL=$(yq '.data.tunnel' .tmp/cilium-conf.yaml)
    if [ "$TUNNEL" = "null" ]; then
      "cilium-conf: tunnel no found, exit 3" && exit 3
    fi

    yq -i '
      .data.ipv4-native-routing-cidr=strenv(CILIUM_IPV4_CIDR) |
      .data.enable-bpf-masquerade = "true" |
      .data.tunnel="disabled" |
      .data.enable-host-legacy-routing="true" |
      .data.enable-bpf-masquerade="true" |
      .data.kube-proxy-replacement="strict" |
      .data.install-no-conntrack-iptables-rules="true" |
      .data.enable-bandwidth-manager="true" |
      .data.auto-direct-node-routes="true"
    ' .tmp/cilium-conf.yaml

    kubectl apply -f .tmp/cilium-conf.yaml

    # restart cilium
    kubectl delete po -n ${CILIUM_NAMESPACE} -l k8s-app=cilium

    # wait ready
    kubectl wait  pod --for=jsonpath='{.status.phase}'=Running --timeout=200s -n ${CILIUM_NAMESPACE} -l k8s-app=cilium

    # disable hubble
    cilium  hubble disable

    # delete kube-proxy, ignore error if possible
    kubectl delete ds -n kube-system kube-proxy 2> /dev/null
}

rm -rf .tmp
mkdir -p .tmp

tuningNode

if [ "$TUNING_CILIUM" = "true" ]; then
  tuningCilium
fi

// cleanup kube-proxy iptables rules
iptables-save | grep -v KUBE > .tmp/ipatbles.data
iptables-restore < .tmp/ipatbles.data








