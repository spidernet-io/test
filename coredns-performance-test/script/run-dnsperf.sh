#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail


KUBE_CONFIG=../kube_config/kube.config
echo -e "\033[32m we begin to coredns performance test\033[0m"
source ../config/parameter

#read parameters
echo "cpu,mem is ${COREDNS_CPU[@]}"
echo "Quests is ${Quests[@]}"
echo "queries is ${QUERY_FILE[*]}"

#cpu,mem different values {0.1,70；1,250；2,500；3,1000}

for i in ${COREDNS_CPU[*]}
  do
    CPU=$(echo $i|awk -F : '{print $1}')
    MEM=$(echo $i|awk -F : '{print $2}')
    echo "coredns components cpu is $CPU,mem is $MEM"
    # set coredns components cpu and mem
    kubectl --kubeconfig=${KUBE_CONFIG} set resources --requests="cpu=$CPU,memory=$MEM" deploy coredns -n kube-system
    kubectl --kubeconfig=${KUBE_CONFIG} set resources --requests="cpu=$CPU,memory=$MEM" ds nodelocaldns -n kube-system
    sleep 30
    kubectl --kubeconfig=${KUBE_CONFIG} get pod -A|grep coredns
    kubectl --kubeconfig=${KUBE_CONFIG} get pod -A|grep nodelocaldns
    
    # check coredns components start ok
    for i in {1..30}
    do
      RUN=$(kubectl --kubeconfig=${KUBE_CONFIG} get pod -A|grep nodelocaldns |awk '{print$4}'|sed -n '1,2p')
      RUN2=$(kubectl --kubeconfig=${KUBE_CONFIG} get pod -A|grep coredns |awk '{print$4}'|sed -n '1,2p')
      Status="Running"
      if [[ $RUN=$Status ]] && [[ $RUN2=$Status ]]
      then
        echo "status is $RUN"
        break
      else
       echo "not running"
       sleep 2
      fi
    done
    # prepare to copy the domain name file to the container
    DNSPERFPODNAME=$(kubectl --kubeconfig=${KUBE_CONFIG} get pod -A -o wide|grep dnstools|sed -n '/master1/p' |awk '{print $2}')
    kubectl --kubeconfig=${KUBE_CONFIG} cp ../query_file/queries.txt $DNSPERFPODNAME:/
    kubectl --kubeconfig=${KUBE_CONFIG} cp ../query_file/dnstest.txt $DNSPERFPODNAME:/
    kubectl --kubeconfig=${KUBE_CONFIG} cp ../query_file/podip.txt $DNSPERFPODNAME:/

   # import different domain name files
   for k in ${QUERY_FILE[*]}
     do
        # different requests
      for j in ${Quests[*]}
        do
        printf "\e[31m Q=$j Latency QueriesLost QueriesPerSecond \e[0m\n" > ../log/compare$j$k$CPU.log
          # different server ip
          for l in ${MODE_IP[*]}
           do
            # begin dnsperf tool test
            echo -e "\033[32m begin dnsperf tool test in $CPU $MEM \033[0m"

            kubectl --kubeconfig=${KUBE_CONFIG} exec -it $DNSPERFPODNAME sh -- dnsperf -d $QUERY_FILE -s $l -p 53 -l $MOSTTIME -Q $j |grep -E 'Average Latency|Queries per second|Queries lost' > ../log/${CPU}$k$j
            QpsValue=$(cat ../log/${CPU}$k$j |grep "Queries per second" | awk '{printf "%s\n",$4}')
            LatencyValue=$(cat ../log/${CPU}$k$j |grep "Average Latency" | awk '{printf "%s\n",$4}')
            LostValue=$(cat ../log/${CPU}$k$j |grep "Queries lost" | awk '{printf "%s\n",$3}')
            LostPresent=$(cat ../log/${CPU}$k$j|grep "Queries lost" | awk '{printf "%s\n",$4}'|awk '{gsub("^\\(",""); gsub(/\)/,""); print $0}')
            
            echo "QpsValue is $QpsValue"
            echo "Latency is $LatencyValue"
            echo "LostValue is $LostValue"
            echo "LostPresent is $LostPresent"

            # get MODE value
            case $l in
            ${MODE_IP[0]})
                MODE="coredns"
                echo ${MODE_IP[0]}
                echo $MODE
            ;;
            ${MODE_IP[1]})
                MODE="localdns"
                echo ${MODE_IP[1]}
                echo $MODE
            ;;
            ${MODE_IP[2]})
                MODE="clusterip"
                echo ${MODE_IP[2]}
                echo $MODE
            ;;
            esac

            # Print comparison results
            printf "\e[32m %s %12s %f %s \e[0m\n" $MODE $LatencyValue $LostValue $QpsValue >> ../log/compare$j$k$CPU.log
            # Column alignment
            awk '{for(i = 1; i <= NF; i++) {printf("%+18s", $i)} {printf("\n")}}' ../log/compare$j$k$CPU.log

            #get max_qps
            if [ $LostValue = 0 ]
            then
              echo "Queries lost: is 0 "
            else
              echo "Queries lost: is not 0 "
              echo "when Queries lost is not 0, QPS is $QpsValue in quests is $j;cpu is $CPU;mode is $MODE; testfile is $k"
              echo "when Queries lost is not 0, QPS is $QpsValue in quests is $j;cpu is $CPU;mode is $MODE; testfile is $k" >> ../log/max_qps.log
            
            fi

          #check Queries lost Present
          value="0.00%"
          if [ $LostPresent=$value ]
            then
              echo "Queries lost Present: is 0.00% "
            else
              echo "Queries lost: is $LostPresent"
              echo "when Queries lost is not 0, QPS is $LostPresent in quests is $j;cpu is $CPU;mode is $MODE; testfile is $k"
              echo "when Queries lost is not 0, QPS is $LostPresent in quests is $j;cpu is $CPU;mode is $MODE; testfile is $k" >> ../log/max_qps_present.log
              
          fi

            sleep 1
            
           done
 
        done
      done
  done