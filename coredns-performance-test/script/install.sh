#!/bin/bash
KUBE_CONFIG=../kube_config/kube.config
# install dnsperf app and service of app
# dnstools部署在master节点上，与coredns不在同一个节点
kubectl --kubeconfig=${KUBE_CONFIG} apply -f ../yaml/dnsperf.yaml
kubectl --kubeconfig=${KUBE_CONFIG} apply -f ../yaml/daodns.yaml
kubectl --kubeconfig=${KUBE_CONFIG} apply -f ../yaml/daodns-service.yaml
