# Cilium 性能调优

## Requirements:

- k8s 版本大于 1.24，本次实验版本: v1.24.9
- Cilium 版本大于 1.12, 本次实验版本: v1.12.2
- Kernel version 大于 5.10, 推荐大于5.18, 本次实验版本: 5.19
- 依赖二进制工具: kubectl、cilium、yq


## 测试步骤及方法

- 配置 config 文件，配置 cilium 的 namespace 和 configMap 的名称、及主机网卡名称
- 执行脚本`./performance.sh`，调整cilium配置及主机性能优化。调整主机参数需要每个主机上执行，注意修改config 文件中 `TUNING_CILIUM` 为 false
- 如果测试时延场景，请在每个主机上设置: `tuned-adm profile network-latency`
- 如果测试吞吐场景，请在每个主机上设置: `tuned-adm profile network-throughput`
- 使用工具 qperf 进行测试，测试项包括 tcp、udp 两种协议的延时和吞吐
- 创建至少两个测试 Pod，分布在不同节点
- 进入到 Pod 的 net namespace 中，分别启动 qperf server 和 qperf client
- 测试命令为: `qperf -t <time_out> <qperf_server_ip> -ub -oo msg_size:1 -vu tcp_lat tcp_bw udp_lat udp_bw`


## Cilium 性能提升对比

实验环境为虚拟机，环境信息如下:

```shell
[root@worker1 cilium]# uname -a
Linux worker1 5.9.8-1.el8.elrepo.x86_64 #1 SMP Wed Nov 11 09:27:50 EST 2020 x86_64 x86_64 x86_64 GNU/Linux
[root@controller1 cilium-performance]# kubectl version --short
Flag --short has been deprecated, and will be removed in the future. The --short output will become the default.
Client Version: v1.25.5
Kustomize Version: v4.5.7
Server Version: v1.25.5
```

测试步骤:

1. 在每个节点执行 `preformance.sh` 脚本之前，需要配置 config 文件：

    - DEVICE: 物理网卡名称，必须存在于节点
    - TUNING_CILIUM: 只需在其中一台master节点上设置为 true,其余设置为 false
    
2. 创建 Pod，使其分布在不同节点。测试其连通性是否正常。
3. 进入到 Pod 的 Network Namespace 中，分别启动Server 和 Client:

server 端:

```shell
nsenter -t <POD1_PID1> -n
qperf
```

client端:

```shell
nsenter -t <POD2_PID> -n
qperf -t 20 <POD1_IP> -ub -oo msg_size:1 -vu tcp_lat tcp_bw udp_lat udp_bw
```

测试3次，取平均值:

| type | tcp_lat(us) | tcp_bw | udp_lat(us) | udp_bw |
| --- | --- | --- | --- | --- |
| Host Network | 167 | 9.7Mb/sec | 157 | 1.6Mb/sec |
| Host Network | 147 | 9.6 Mb/sec | 172| 1.6 Mb/sec |
| Host Network | 198 | 9.6 Mb/sec | 170 | 1.49 Mb/sec |
|avg|170|9.63| 166|1.56 Mb/sec|

| type | tcp_lat(us) | tcp_bw | udp_lat(us) | udp_bw |
| --- | --- | --- | --- | --- |
| Cilium 优化前| 185 | 8.49 Mb/sec | 170 | 904 Kb/sec |
| Cilium 优化前| 179 | 8.59 Mb/sec | 193 | 925 Kb/sec |
| Cilium 优化前| 204 | 9.23 Mb/sec | 198 | 842 Kb/sec |
|avg|189.3|8.77 Mb/sec|187|890 Kb/sec|

| type | tcp_lat(us) | tcp_bw | udp_lat(us) | udp_bw |
| --- | --- | --- | --- | --- |
| Cilium  优化后| 183 | 9.8 Mb/sec  | 164 | 955 Kb/sec |
| Cilium  优化后| 171 | 9.8 Mb/sec  | 185 | 967 Kb/sec |
| Cilium  优化后| 170 | 10.3 Mb/sec  | 177 | 937 Kb/sec |
|avg|174.7|9.97 Mb/sec|175|953 Kb/sec |

从结果看: 时延减少 7%，吞吐增加 10% 左右