# coredns performance test

## requirement
1. at least two node in cluster
2. coredns installed
3. nodelocaldns installed

## test tools
- dnsperf

## test indicators
- Latency
- QueriesLost
- QueriesPerSecond

## service
- coredns
- nodelocaldns
- cluster ip (for coredns)

## usage
1. copy the directory "coredns-performance-test" of the project to one of your cluster master node
2. edit the kube.config document and fill in the kube.config related parameters of the tested work cluster
3. edit the parameter file and configure the request cpu and mem quantity of the coredns component; Query the domain name file; Server IP; limit the number of queries per second; run for at most this many seconds and mode
4. run ./script/install.sh to install the workload and dnsperf test tool,the installation process uses yaml files
5. run ./script/run-dnsperf.sh to auto test,the comparison results will be displayed on the screen
6. this shell script will output comparison result and max_qps log files in log folder <br>