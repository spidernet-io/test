#!/bin/sh
#
# setting up irq affinity according to /proc/interrupts
# 2008-11-25 Robert Olsson
# 2009-02-19 updated by Jesse Brandeburg
# 2010-09-15 Jesper Dangaard Brouer, change script for Debian ifup
#
# > Dave Miller:
# (To get consistent naming in /proc/interrups)
# I would suggest that people use something like:
#	char buf[IFNAMSIZ+6];
#
#	sprintf(buf, "%s-%s-%d",
#	        netdev->name,
#		(RX_INTERRUPT ? "rx" : "tx"),
#		queue->index);
#
#  Assuming a device with two RX and TX queues.
#  This script will assign:
#
#	eth0-rx-0  CPU0
#	eth0-rx-1  CPU1
#	eth0-tx-0  CPU0
#	eth0-tx-1  CPU1
#

export OUT=/tmp/ifup-set-irq-affinity-DEBUG
DEBUG=$VERBOSITY
DEBUG=1 #Force debugging on
info() {
  if [ -n "$DEBUG" -a "$DEBUG" -ne 0 ]; then
	  TS=`date +%Y%m%dT%H%M%S`
	  echo "$TS iface:$IFACE -- $@" >> $OUT
  fi
}

set_affinity()
{
    MASK=$((1<<$VEC))
    printf "%s mask=%X for /proc/irq/%d/smp_affinity\n" $DEV $MASK $IRQ >> $OUT
    printf "%X" $MASK > /proc/irq/$IRQ/smp_affinity
    #echo $DEV mask=$MASK for /proc/irq/$IRQ/smp_affinity
    #echo $MASK > /proc/irq/$IRQ/smp_affinity
}

IFACE=$1

if [ "$IFACE" = "" ] ; then
    echo "Description:"
    echo "    This script attempts to bind each queue of a multi-queue NIC"
    echo "    to the same numbered core, ie tx0|rx0 --> cpu0, tx1|rx1 --> cpu1"
    echo "Usage: "
    echo "    ./set_irp_affnity.sh "ens192"  "
fi
info "Start set_irq_affinity"

# check for irqbalance running
IRQBALANCE_ON=`ps ax | grep -v grep | grep -q irqbalance; echo $?`
if [ "$IRQBALANCE_ON" = "0" ] ; then
	echo " WARNING: irqbalance is running and will"
	echo "          likely override this script's affinitization."
	echo "          Please stop the irqbalance service and/or execute"
	echo "          'killall irqbalance'"
fi

#
# Set up the desired devices.
#

for DEV in $IFACE
do
  for DIR in rx tx TxRx
  do
     MAX=`grep $DEV-$DIR /proc/interrupts | wc -l`
     if [ "$MAX" = "0" ] ; then
       MAX=`egrep -i "$DEV:.*$DIR" /proc/interrupts | wc -l`
     fi
     if [ "$MAX" = "0" ] ; then
       info no $DIR vectors found on $DEV
       continue
       #exit 1
     fi
     for VEC in `seq 0 1 $MAX`
     do
        IRQ=`cat /proc/interrupts | grep -i $DEV-$DIR-$VEC"$"  | cut  -d:  -f1 | sed "s/ //g"`
        if [ -n  "$IRQ" ]; then
          set_affinity
        else
           IRQ=`cat /proc/interrupts | egrep -i $DEV:v$VEC-$DIR"$"  | cut  -d:  -f1 | sed "s/ //g"`
           if [ -n "$IRQ" ]; then
             set_affinity
           fi
        fi
     done
  done
done