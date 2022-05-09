---
layout: post
title:  "envoy 动态路由配置信息查看"
description: "在contour +  envoy 的部署使用模式下,查看 contour发往envoy的配置，以及 envoy 接受的配置"
date:   2022-05-09 22:13:26 +0800
categories: Technology notes
permalink: /posts/61a05b5d/
tags: [IT, envoy, contour, ingress, k8s]
preview: "内容摘要: envoy 通过静态配置和动态配置接口共同决定 路由配置信息。本文介绍在contour +  envoy 的部署使用模式下，在contour +  envoy 的部署使用模式下,如何查看 contour发往envoy的配置，以及 envoy 接受的配置"
---

envoy 通过静态配置和动态配置接口共同决定 路由配置信息。在contour +  envoy 的部署使用模式下，envoy 的静态配置中主要定义了如何从contour 获取动态配置信息，而contour 作为 envoy 的控制面 xds server运行，将从k8s 集群 的ingress 资源描述中获取到的路由信息通过xds发送给 envoy。

因此，我们可以通过两种方式来获取 envoy路由配置的相关信息：

1. 一种是通过contour 暴露的接口，去看 contour 给 envoy 发送的内容
2. 一种是通过 envoy 暴露的接口去看envoy接收生效的内容

### 查看 contour发送的内容

contour 提供了命令行交互能力，可以执行命令 `contour cli eds` 等命令去获取endpoint等配置的信息。

相关命令：

获取 contour pod信息：

```bash
CONTOUR_POD=$(kubectl -n projectcontour get pod -l app=contour -o jsonpath='{.items[0].metadata.name}')

```

进入该pod执行查看命令：

```bash
kubectl -n projectcontour exec ${CONTOUR_POD} -c contour -- contour cli eds --cafile=/certs/ca.crt --cert-file=/certs/tls.crt --key-file=/certs/tls.key

```

其中eds 表示查看 endpoint 相关配置

支持以下基本信息查看：

- eds： endpoint 信息
- cds： cluster信息
- rds： route信息
- lds： listener 信息

注意这个是一个持续监听的接口，执行后不会退出，当k8s集群ingress相关资源对象发生变化时，又或获取最新配置内容。

### 查看envoy收到生效的配置内容

contour 提供 shutdown-manager 的 envoy pod中，会通过 9001 端口暴露一个进行了过滤的管理接口，提供了以下一些路由相关配置的获取接口：

- /clusters
- /listeners
- /config_dump (全量配置)

因为pod上没有做9001端口的暴露，我们通过`kubectl port-forward` 去作转发：

```bash
kubectl -n projectcontour port-forward --address 0.0.0.0 ${pod-name} ${local-port}:9001

```

例如：

在ip为xx.xx.xx.xx的节点上对 pod/envoy-xxxxx 进行端口转发，指定本地转发端口为9901：

```bash
kubectl -n projectcontour port-forward --address 0.0.0.0 pod/envoy-xxxxx 9901:9001
```

访问以下地址可获取配置信息：

```bash
http://xx.xx.xx.xx:9901/config_dump
```

如果想将配置信息dump到文件，可将返回内容重定向到文件

```bash
curl http://xx.xx.xx.xx:9901/config_dump > ./envoy_config.dump

```