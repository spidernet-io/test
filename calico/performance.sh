#!/bin/bash

set -e
set -o

source config

[ -z "${PhysicalInterface}" ] && echo "err: PhysicalInterface can't be empty" && exit 1
echo "PhysicalInterface: ${PhysicalInterface}"

# tuning NIC queue
PRE_SET_RX=`ethtool -g ${PhysicalInterface} | sed -n '3p' | egrep -o  '[0-9]*$' `
PRE_SET_TX=`ethtool -g ${PhysicalInterface} | sed -n '6p' | egrep -o  '[0-9]*$'`
CURRENT_RX=`ethtool -g ${PhysicalInterface} | sed -n '8p' | egrep -o  '[0-9]*$'`
CURRENT_TX=`ethtool -g ${PhysicalInterface} | sed -n '11p' | egrep -o  '[0-9]*$'`

echo "PRE_SET_RX: ${PRE_SET_RX}"
echo "PRE_SET_TX: ${PRE_SET_TX}"
echo "CURRENT_RX: ${CURRENT_RX}"
echo "CURRENT_TX: ${CURRENT_TX}"

if [ "${CURRENT_RX}" -le "${PRE_SET_RX}" ]; then
  ethtool -G ${PhysicalInterface} rx ${PRE_SET_RX}
fi

if [ "${CURRENT_TX}" -le "${PRE_SET_TX}" ]; then
  ethtool -G ${PhysicalInterface} tx ${PRE_SET_TX}
fi

# tuned
tuned-adm profile network-latency
tuned-adm profile network-throughput
cpupower frequency-set -g performance

