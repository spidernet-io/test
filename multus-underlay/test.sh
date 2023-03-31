#!/bin/bash
set -o errexit
set -o nounset
#set -o pipefail
#set -o xtrace

. ./test.config

function fun_info() {
    echo -e "\033[35m$1 \033[0m"
}
function fun_fail() {
    echo -e "\033[31m$1 \033[0m"
}
function fun_succ() {
    echo -e "\033[32m$1 \033[0m"
}

# single or multi cluster
isSingle="true"
if [[ -z ${KUBE_CONFIG_ONE} ]]; then fun_fail "KUBE_CONFIG_ONE needed"; exit 1; fi
#if [[ -z ${KUBE_CONFIG_TWO} && -n ${KUBE_CONFIG_ONE} ]]; then fun_info "single-cluster"; fi
#if [[ -n ${KUBE_CONFIG_TWO} && -n ${KUBE_CONFIG_ONE} ]]; then fun_info "multi-cluster"; isSingle="false"; fi

KUBE_CONFIG_TWO=${KUBE_CONFIG_TWO:-$KUBE_CONFIG_ONE}


# tmp file
TMP_FILE=`mktemp /tmp/result.XXX`

# apply node1 pod
for i in {1..2}; do
  cp ./yaml/template-node"${i}"-pod.yaml $TMP_FILE

  sed -i "s?<NODE1>?${NODE_ONE}?g" $TMP_FILE
  sed -i "s?<NODE2>?${NODE_TWO}?g" $TMP_FILE
  sed -i "s?<POD_NAME_PREFIX>?$POD_NAME_PREFIX?g" $TMP_FILE
  for anno in "${POD_ANNO[@]}"; do sed -i "/# <POD_ANNO>/a\        $anno" $TMP_FILE; done
  for req in "${POD_RESOURCES_REQUESTS[@]}"; do sed -i "/# <POD_RESOURCES_REQUESTS>/a\              $req" $TMP_FILE; done
  for lim in "${POD_RESOURCES_LIMITS[@]}"; do sed -i "/# <POD_RESOURCES_LIMITS>/a\              $lim" $TMP_FILE; done

  DURATION=${DURATION:-"10"}

  export kubeConfig=""
  export podNum=""
  if [[ $i -eq 1 ]]; then kubeConfig=$KUBE_CONFIG_ONE; podNum=3; fi
  if [[ $i -eq 2 ]]; then
    kubeConfig=$KUBE_CONFIG_TWO
    if [[ $isSingle = "true" ]]; then
      podNum=5
    else
      podNum=2
    fi
  fi

  # apply pod
  kubectl --kubeconfig=$kubeConfig apply -f $TMP_FILE

  # wait deploy ready
  ready="bad"
  for i in {0..30}; do
    if [[ `kubectl --kubeconfig=$kubeConfig get po | grep t-$POD_NAME_PREFIX | grep Running | wc -l` -ne $podNum ]]; then
      fun_info "$i, some pod not ready, wait..."
      sleep 2s
    else
      fun_info "all pod running..."
      ready="ok"
      break
    fi
  done

  if [[ $ready = "bad" ]]; then
    fun_fail "timeout to wait pod ready"
    exit 1
  fi

done

# test
fun_info "start test..."

kc1="kubectl --kubeconfig=$KUBE_CONFIG_ONE"
kc2="kubectl --kubeconfig=$KUBE_CONFIG_TWO"


LOG_FILE=/tmp/$POD_NAME_PREFIX.log
SERVER_NODE_IP=`$kc1 get po -owide | grep t-$POD_NAME_PREFIX-host-same-node-server | awk '{print $6}'`
POD_SAME_NODE=`$kc1 get po | grep t-$POD_NAME_PREFIX-pod-same-node | awk '{print $1}'`
POD_DIFF_NODE=`$kc2 get po | grep t-$POD_NAME_PREFIX-pod-dif-node | awk '{print $1}'`
HOST_SAME_NODE=`$kc1 get po | grep t-$POD_NAME_PREFIX-host-same-node | awk '{print $1}'`
HOST_DIFF_NODE=`$kc2 get po | grep t-$POD_NAME_PREFIX-host-dif-node | awk '{print $1}'`
SERVER_POD_IP=`$kc1 get po  | grep t-$POD_NAME_PREFIX-server | awk '{print $1}' | xargs $kc1 get po -oyaml | grep  net1 -A 2 | egrep -o '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | uniq`
if [[ -z $SERVER_POD_IP ]]; then
  SERVER_POD_IP=`$kc1 get po -owide | grep t-$POD_NAME_PREFIX-server | awk '{print $6}'`
fi
SERVER_SVC_IP=`$kc1 get svc | grep t-$POD_NAME_PREFIX-host-server-svc | awk '{print $3}'`

#----------------
# Bandwidth
#----------------

# node-node
$kc2 exec ${HOST_DIFF_NODE} -- iperf3 -c ${SERVER_NODE_IP} -i 1 -t $DURATION | grep receiver | awk '{ printf "%s,%s,%s,%s\n","","Interval sec","Transfer GB","Bandwidth Gb/sec"; printf "%s,%s,%s,%s\n","node-node",$3,$5,$7}' > ${TMP_FILE}

# pod-pod same node
kubectl exec "${POD_SAME_NODE}" -- iperf3 -c ${SERVER_POD_IP} -i 1 -t $DURATION | grep receiver | awk '{ printf "%s,%s,%s,%s\n","pod-pod-sameNode",$3,$5,$7}' >> ${TMP_FILE}

# pod-pod diff node
$kc2 exec ${POD_DIFF_NODE} -- iperf3 -c ${SERVER_POD_IP} -i 1 -t $DURATION | grep receiver | awk '{ printf "%s,%s,%s,%s\n","pod-pod-diffNode",$3,$5,$7}' >> ${TMP_FILE}

# pod-node same node
kubectl exec ${HOST_SAME_NODE} -- iperf3 -c ${SERVER_POD_IP} -i 1 -t $DURATION | grep receiver | awk '{ printf "%s,%s,%s,%s\n","pod-node-sameNode",$3,$5,$7}' >> ${TMP_FILE}

## pod-node diff node
#$kc2 exec ${HOST_DIFF_NODE} -- iperf3 -c ${SERVER_POD_IP} -i 1 -t $DURATION | grep receiver | awk '{ printf "%s,%s,%s,%s\n","pod-node-diffNode",$3,$5,$7}' >> ${TMP_FILE}

# pod-svc same node
kubectl exec ${POD_SAME_NODE} -- iperf3 -c ${SERVER_SVC_IP} -i 1 -t $DURATION | grep receiver | awk '{ printf "%s,%s,%s,%s\n","pod-svc-sameNode",$3,$5,$7}' >> ${TMP_FILE}

# pod-svc diff node
$kc2 exec ${POD_DIFF_NODE} -- iperf3 -c ${SERVER_SVC_IP} -i 1 -t $DURATION | grep receiver | awk '{ printf "%s,%s,%s,%s\n","pod-svc-diffNode",$3,$5,$7}' >> ${TMP_FILE}

## node-svc same node
#kubectl exec ${HOST_SAME_NODE} -- iperf3 -c ${SERVER_SVC_IP} -i 1 -t $DURATION | grep receiver | awk '{ printf "%s,%s,%s,%s\n","node-svc-sameNode",$3,$5,$7}' >> ${TMP_FILE}
#
## node-svc diff node
#$kc2 exec ${HOST_DIFF_NODE} -- iperf3 -c ${SERVER_SVC_IP} -i 1 -t $DURATION | grep receiver | awk '{ printf "%s,%s,%s,%s\n","node-svc-diffNode",$3,$5,$7}' >> ${TMP_FILE}

column -t -s "," -o "    " -R 1 ${TMP_FILE} > ${LOG_FILE}

# title
TITLE=`fun_info "=== $POD_NAME_PREFIX Bandwidth ==="`
sed -i "1i${TITLE}" ${LOG_FILE}

#----------------
# Throughput
#----------------

# node-node
$kc2 exec ${HOST_DIFF_NODE} -- netperf -H ${SERVER_NODE_IP} -l $DURATION | tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s\n","","Recv Socket Size bytes","Send Socket Size bytes","Send Message Size bytes","Elapsed Time secs","Throughput 10^6bits/sec"; printf "%s,%s,%s,%s,%s,%s\n","node-node",$1,$2,$3,$4,$5}' > ${TMP_FILE}

# pod-pod same node
kubectl exec "${POD_SAME_NODE}" -- netperf -H ${SERVER_POD_IP} -l $DURATION | tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s\n","pod-pod-sameNode",$1,$2,$3,$4,$5}' >> ${TMP_FILE}

# pod-pod diff node
$kc2 exec ${POD_DIFF_NODE} -- netperf -H ${SERVER_POD_IP} -l $DURATION | tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s\n","pod-pod-diffNode",$1,$2,$3,$4,$5}' >> ${TMP_FILE}

# pod-node same node
kubectl exec ${HOST_SAME_NODE} -- netperf -H ${SERVER_POD_IP} -l $DURATION | tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s\n","pod-node-sameNode",$1,$2,$3,$4,$5}' >> ${TMP_FILE}

## pod-node diff node
#$kc2 exec ${HOST_DIFF_NODE} -- netperf -H ${SERVER_POD_IP} -l $DURATION | tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s\n","pod-node-diffNode",$1,$2,$3,$4,$5}' >> ${TMP_FILE}

# title
TITLE=`fun_info "=== $POD_NAME_PREFIX Throughput ==="`
echo $TITLE >> ${LOG_FILE}

column -t -s "," -o "    " -R 1 ${TMP_FILE} >> ${LOG_FILE}

#----------------
# Latency Long Connection
#----------------

# node-node
$kc2 exec ${HOST_DIFF_NODE} -- netperf -t TCP_RR -H ${SERVER_NODE_IP} -l $DURATION  -- -O "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY,MEAN_LATENCY" | tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s,%s\n","","Minimum Latency Micro","Maximum Latency Micro","50th Percentile Latency Micro","90th Percentile Latency Micro","99th Percentile Latency Micro","Mean Latency Micro"; printf "%s,%s,%s,%s,%s,%s,%s\n","node-node",$1,$2,$3,$4,$5,$6}' > ${TMP_FILE}

# pod-pod same node
kubectl exec "${POD_SAME_NODE}" -- netperf -t TCP_RR -H ${SERVER_POD_IP} -l $DURATION  -- -O "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY,MEAN_LATENCY" |  tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s,%s\n","pod-pod-sameNode",$1,$2,$3,$4,$5,$6}' >> ${TMP_FILE}

# pod-pod diff node
$kc2 exec ${POD_DIFF_NODE} -- netperf -t TCP_RR -H ${SERVER_POD_IP} -l $DURATION  -- -O "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY,MEAN_LATENCY" |  tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s,%s\n","pod-pod-diffNode",$1,$2,$3,$4,$5,$6}' >> ${TMP_FILE}

# pod-node same node
kubectl exec ${HOST_SAME_NODE} -- netperf -t TCP_RR -H ${SERVER_POD_IP} -l $DURATION  -- -O "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY,MEAN_LATENCY" |  tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s,%s\n","pod-node-sameNode",$1,$2,$3,$4,$5,$6}' >> ${TMP_FILE}

## pod-node diff node
#$kc2 exec ${HOST_DIFF_NODE} -- netperf -t TCP_RR -H ${SERVER_POD_IP} -l $DURATION  -- -O "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY,MEAN_LATENCY" |  tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s,%s\n","pod-node-diffNode",$1,$2,$3,$4,$5,$6}' >> ${TMP_FILE}

# title
TITLE=`fun_info "=== $POD_NAME_PREFIX Latency Long Connection ==="`
echo $TITLE >> ${LOG_FILE}

column -t -s "," -o "    " -R 1 ${TMP_FILE} >> ${LOG_FILE}

#----------------
# Latency Short Connection
#----------------

# node-node
$kc2 exec ${HOST_DIFF_NODE} -- netperf -t TCP_CRR -H ${SERVER_NODE_IP} -l $DURATION  -- -O "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY,MEAN_LATENCY" | tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s,%s\n","","Minimum Latency Micro","Maximum Latency Micro","50th Percentile Latency Micro","90th Percentile Latency Micro","99th Percentile Latency Micro","Mean Latency Micro"; printf "%s,%s,%s,%s,%s,%s,%s\n","node-node",$1,$2,$3,$4,$5,$6}' > ${TMP_FILE}

# pod-pod same node
kubectl exec "${POD_SAME_NODE}" -- netperf -t TCP_CRR -H ${SERVER_POD_IP} -l $DURATION  -- -O "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY,MEAN_LATENCY" |  tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s,%s\n","pod-pod-sameNode",$1,$2,$3,$4,$5,$6}' >> ${TMP_FILE}

# pod-pod diff node
$kc2 exec ${POD_DIFF_NODE} -- netperf -t TCP_CRR -H ${SERVER_POD_IP} -l $DURATION  -- -O "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY,MEAN_LATENCY" |  tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s,%s\n","pod-pod-diffNode",$1,$2,$3,$4,$5,$6}' >> ${TMP_FILE}

# pod-node same node
kubectl exec ${HOST_SAME_NODE} -- netperf -t TCP_CRR -H ${SERVER_POD_IP} -l $DURATION  -- -O "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY,MEAN_LATENCY" |  tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s,%s\n","pod-node-sameNode",$1,$2,$3,$4,$5,$6}' >> ${TMP_FILE}

## pod-node diff node
#$kc2 exec ${HOST_DIFF_NODE} -- netperf -t TCP_CRR -H ${SERVER_POD_IP} -l $DURATION  -- -O "MIN_LATENCY,MAX_LATENCY,P50_LATENCY,P90_LATENCY,P99_LATENCY,MEAN_LATENCY" |  tail -n 1 | awk '{ printf "%s,%s,%s,%s,%s,%s,%s\n","pod-node-diffNode",$1,$2,$3,$4,$5,$6}' >> ${TMP_FILE}

# title
TITLE=`fun_info "=== $POD_NAME_PREFIX Latency Short Connection ==="`
echo $TITLE >> ${LOG_FILE}

column -t -s "," -o "    " -R 1 ${TMP_FILE} >> ${LOG_FILE}

fun_succ "finished, you can see the log /tmp/$POD_NAME_PREFIX.log on the host"

# clean
fun_info "clean..."
rm -rf ${TMP_FILE}

# delete deploy and svc
$kc1 get deploy | grep t-$POD_NAME_PREFIX | awk '{print $1}' | xargs $kc1 delete deploy
$kc2 get deploy | grep t-$POD_NAME_PREFIX | awk '{print $1}' | xargs $kc2 delete deploy
$kc1 get svc | grep t-$POD_NAME_PREFIX | awk '{print $1}' | xargs $kc1 delete svc

# wait deploy svc deleted
export deleted="no"
for i in {0..30}; do
  if [[ `$kc1 get po | grep t-$POD_NAME_PREFIX | wc -l` -ne 0 ]]; then
    fun_info "$i, some pod not deleted, wait..."
    sleep 2s
  elif [[ `$kc2 get po | grep t-$POD_NAME_PREFIX | wc -l` -ne 0  ]]; then
     fun_info "$i, some pod not deleted, wait..."
     sleep 2s
  else
    fun_info "all pod deleted..."
    deleted="yes"
    break
  fi
done

if [[ $deleted = "no" ]]; then
  fun_fail "timeout to wait pod ready"
  exit 1
fi
