---
layout: post
title:  "如何临时或永久修改route table"
description: "如何修改route table，如何临时增加或删除路由条目，如何永久添加或删除路由条目"
date:   2023-06-30 08:34:50 +0800
categories: Technology notes
permalink: /posts/b9ec2c19/
tags: [writing, IT, Linux, route]
preview: "内容摘要： 如何修改route table，如何临时增加或删除路由条目，如何永久添加或删除路由条目。主要涉及route命令、nmcli命令、相关配置文件持久化位置等"
---


## 内容摘要
如何修改route table，如何临时增加或删除路由条目，如何永久添加或删除路由条目。主要涉及route命令、nmcli命令、相关配置文件持久化位置等

## 临时修改，重启后丢失

直接使用 route 命令可以进行临时修改，但是在系统重启或者是执行interface的重启后会丢失。

命令使用方式：

`route {add | delete} {-host | -net} {des_ip} [netmask {net mask}] [gw {gw}] [dev {device}]`

route add：命令关键字，表示增加路由，若要删除路由，则为route del；

-host | -net：表示路由目标是主机还是网段；

netmask：表示路由目标为网段时才会使用到，表示路由目标网段的子网掩码；

gw：命令关键字，后面跟下一跳网关；

dev：命令关键字，后面跟具体设备名，表示路由是从该设备出去。

metric：为路由指定所需跳数里的多个路由中选择与转发包中的目标地址最为匹配的路由。所选的路由具有最少的跳数。跳数能够反映途经节点的数量、路径的速度、路径可靠性、路径吞吐量以及管理属性。

示例：

添加路由：

`route add –host 192.168.168.110 dev eth0`

`route add –host 192.168.168.119 gw 192.168.168.1`

`route add -net 192.168.3.0/24 dev eth0`

`route add -net 192.168.2.0/24 gw 192.168.2.254`

`route add –net 180.200.0.0 netmask 255.255.0.0 gw 10.200.6.201 dev eth0 metric 1`

添加默认网关：

`route add default gw 99.12.11.253`

删除路由：

`route del –host 192.168.168.110 dev eth0`

## 通过 nmcli 修改

通过 nmcli 修改配置，可以永久保存，在系统重启后，该配置仍有效。

`nmcli connection show` 找到要添加的route的设备对应的connection名。

执行修改：

`nmcli connection modify “connection-name” +ipv4.routes “network address/prefix gateway”`

`nmcli connection up “connection-name”`

至此，就已经完成了 route 的添加，此时通过 `route -n` 可以查看到添加后的route 表。

注意 `+ipv4.routes` 中的 `+` 表示添加，如果没有 `+` 则表示覆盖，如果需要移除，则使用 `-` ,即 `-ipv4.routes`。

以上命令举报幂等性，可以重复执行。

其中 `nmcli connection modify “connection-name” +ipv4.routes “network address/prefix gateway”` 执行后，会在文件系统中将配置持久化。

持久化的位置可以通过 `nmcli -f NAME,DEVICE,FILENAME connection show` 查看：

```
NAME               DEVICE  FILENAME
bridge-br0         br0     /etc/sysconfig/network-scripts/ifcfg-bridge-br0
virbr0             virbr0  /run/NetworkManager/system-connections/virbr0.nmconnection
bridge-slave-eno1  eno1    /etc/sysconfig/network-scripts/ifcfg-bridge-slave-eno1
vnet1              vnet1   /run/NetworkManager/system-connections/vnet1.nmconnection
eno2               --      /etc/sysconfig/network-scripts/ifcfg-eno2
```

通过上述命令可能不能准确地找到每个 device 全部的配置文件，但是基本可以定位配置文件存放的目录。

如果通过`nmcli`修改的内容是添加 route 表，在红帽和ubuntu中配置文件存放的位置如下：

rhel 中，位于： `/etc/sysconfig/network-scripts/route-{name_of_connection}`

ubuntu 中，位于: `/etc/NetworkManager/system-connections/{name_of_connection}.nmconnection`

## 直接修改配置文件

知道了配置存储的位置，我们可以直接在通过添加、修改配置文件的方式，来实现永久添加route 的目的。

但是在不同的系统中，由于管理工具差异，配置文件有所不同。

以 rhel为例：

如果 network connection 是 `enp0s3`, 那么配置文件的名字应该是

`/etc/sysconfig/network-scripts/route-enp0s3`

可以通过以下格式添加：

```yaml
10.0.0.0/24 via 192.168.1.10

192.168.100.0/24 via 192.168.1.10

192.168.50.10/32 via 192.168.1.1
```

或者通过如下格式添加：

```yaml
ADDRESS0=10.0.0.0

NETMASK0=255.255.255.0

GATEWAY0=192.168.1.10

ADDRESS1=192.168.50.10

NETMASK1=255.255.255.255

GATEWAY1=192.168.1.1
```

最后通过 nmcli 命令使配置生效：

`nmcli connection reload`

`nmcli connection up enp0s3`

参考链接：

[https://www.cyberciti.biz/faq/linux-route-add/](https://www.cyberciti.biz/faq/linux-route-add/)

[https://www.cnblogs.com/hf8051/p/4530906.html](https://www.cnblogs.com/hf8051/p/4530906.html)

[https://www.ibm.com/docs/en/aix/7.2?topic=r-route-command](https://www.ibm.com/docs/en/aix/7.2?topic=r-route-command)

[https://elearning.wsldp.com/pcmagazine/add-permanent-routes-centos-7/](https://elearning.wsldp.com/pcmagazine/add-permanent-routes-centos-7/)

[https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/networking_guide/sec-configuring_static_routes_using_nmcli](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/networking_guide/sec-configuring_static_routes_using_nmcli)

[https://unix.stackexchange.com/questions/501260/where-does-network-manager-store-settings](https://unix.stackexchange.com/questions/501260/where-does-network-manager-store-settings)

[https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/networking_guide/sec-configuring_static_routes_in_ifcfg_files](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/networking_guide/sec-configuring_static_routes_in_ifcfg_files)
