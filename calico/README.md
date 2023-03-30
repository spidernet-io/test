# Calico 性能调优

## 环境

- centos8: 4.18.0-448.el8.x86_64

## 结果

测试命令:

```shell
qperf -t 60 <Server_IP> -ub -oo msg_size:1k -vu tcp_lat tcp_bw udp_lat udp_bw
```

| type | tcp_lat(us) | tcp_bw | udp_lat(us) | udp_bw |
| --- | --- | --- | --- | --- |
| Host Network | 104 | 3.58 Gb/sec | 105 | 1.21 Gb/sec |
| Calico Vxlan | 166 | 684 Mb/sec | 135 | 462 Mb/sec |
| Calico IPIP  | 143 | 749 Mb/sec  | 133 | 480 Mb/sec |
| Calico NoEncap | 119 | 1.01 G/sec | 112 | 656 Mb/sec |

性能调优之后:

| type | tcp_lat(us) | tcp_bw | udp_lat(us) | udp_bw |
| --- | --- | --- | --- | --- |
| Calico Vxlan | 131 | 1.06 Gb/sec | 125 | 564 Mb/sec |
| Calico IPIP  | 134 | 1.1 GB/sec | 133 | 463 Mb/sec |
| Calico NoEncap | 118 | 1.34 Gb/sec | 114 | 642 Mb/sec |

从结果来看，整体性能可以提高 20% 以上。

## 调整步骤

### 在每个节点执行网卡性能调优脚本

```shell
./performance.sh
```

> 此步骤主要调整网卡队列参数
> 优化测试场景

### FastPath 模块

参考[kube-ovn fastpath](https://kubeovn.github.io/docs/v1.11.x/advance/fastpath/)，在此基础做了一些小的修改: 主要增加 Calico Vxlan 模式的场景，此 Module 
可绕过容器侧的网络协议栈，提高CPU的利用率,提升吞吐量，实测提高 20%-30%, 下面是手动编译安装过程:

针对 kernel 3.x 内核:

```shell
cd centos7.x
yum install -y kernel-devel-$(uname -r) gcc elfutils-libelf-devel
make all
```

针对 kernel 4.x 内核:

```shell
cd centos8.x
yum install -y kernel-devel-$(uname -r) gcc elfutils-libelf-devel
make all
```

将 ·`fastpath.ko` 拷贝到每个节点上，并执行 `insmod fastpath.ko`, 查看 `dmesg` 检查是否安装成功:

```shell
dmesg | grep init_module
[  196.678314] init_module,kube_ovn_fast_path
```

卸载模块:

```shell
cd centos8.x
make uninstall
```

性能调整主要参考 [kube-ovn性能调优](https://kubeovn.github.io/docs/v1.11.x/advance/performance-tuning/)