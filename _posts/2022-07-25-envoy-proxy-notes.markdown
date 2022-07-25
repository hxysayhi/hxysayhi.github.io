---
layout: post
title:  "envoy proxy调研笔记"
description: "envoy proxy 相关调研内容。"
date:   2022-07-25 20:27:32 +0800
categories: Technology notes
permalink: /posts//pic/4a1349e1/
preview: "内容摘要: 我们主要想了解 envoy 如何提供 L4/L7的代理服务，envoy具体提供哪些功能，我们如何利用这些功能实现我们的业务场景。在envoy如何提供代理能力方面，主要有两点：1. envoy 如何从控制面获取配置； 2. envoy 如何根据配置信息进行路由。在如何利用envoy提供的功能实现我们的业务场景方面，主要是 如何将 k8s集群中的相关资源对象的描述信息，转换为envoy 的配置。"
tags: [IT, k8s, ingress, envoy, proxy]
---

# 内容提要

我们主要想了解 envoy 如何提供 L4/L7的代理服务，envoy具体提供哪些功能，我们如何利用这些功能实现我们的业务场景。在envoy如何提供代理能力方面，主要有两点：1. envoy 如何从控制面获取配置； 2. envoy 如何根据配置信息进行路由。在如何利用envoy提供的功能实现我们的业务场景方面，主要是 如何将 k8s集群中的相关资源对象的描述信息，转换为envoy 的配置。

本文我们将围绕以上两个方面，进行介绍，主要有以下相关内容：

1. [envoy是什么？](#t1)为了解决什么问题，具有什么特点，能力边界在哪里。
2. envoy的基本概念与框架。
   
    明确envoy中的基本术语，以及envoy的基本工作框架，处理流程。
    
3. envoy的动态配置能力。控制面如何将k8s集群中的route资源描述信息动态实时地传达到envoy？
4. envoy如何进行路由？
   
    有了路由配置信息后，envoy如何对请求进行路由。这部分内容主要聚焦在路由能力，这个能力主要是由http route filter提供。这部分涉及到一些代码实现层面的处理以及相关数据结构。
    
5. envoy的主要组件与模型：线程模型、常见组件、过滤器等。
6. 控制面组件实践。
   
    对几个控制面组件的简单对比。
    
7. envoy支持特性概览
   
    为了便于评估envoy能够对哪些业务需求提供支持，简单罗列了envoy提供的功能特性。
    

---

# <span id="t1">Envoy 是什么</span>

根据[envoy官网](https://www.envoyproxy.io/)的定义，envoy是一个开源的为云原生应用而设计的边缘和服务代理（edge and service proxy）。使用c++ 编写，设计定位是用于大规模微服务服务网格架构的通用数据平面。为的是解决以下在大规模微服务场景中存在的挑战：1. 复杂异构系统中的网络维护；2. 流量监控中的困难；3.  扩缩容。

通常来说有两种部署方式，一种是作为sidecar 和微服务应用部署在一起，将网络相关的逻辑从微服务中抽离出来，提供服务网格的数据面能。

![Untitled](/pic/4a1349e1/p0.png)

另一种部署方式是作为一个代理网关部署，作为微服务集群的流量入口。

![Untitled](/pic/4a1349e1/p1.png)

envoy可以提供的能力有：负载均衡、可用性增强能力（如超时、熔断、重试等）、可观测性、指标监控等。

envoy的一大特点是可以通过xDS实现实时的动态配置更新。在k8s容器集群中，部署的应用会不停地新增、减少、漂移，路由配置会不停地发生变化，xDS 这一特性能很好地在这种频繁发生路由配置变化的场景下高效运作。不仅仅是路由相关的配置可以热加载生效，envoy 可以通过xds进行除本身二进制文件之外的几乎所有变更，也就是除非需要更新envoy本身，否则任何变更都无需将envoy停止运行，这为我们的运维变更带来了极大的便利性。

除了支持xds进行动态配置，envoy也支持进行静态配置，但是通常来说，由于其配置具有很高的灵活度，也导致了配置具有较高的复杂性，难以人工维护，通常来说都是由代码生成。

envoy只扮演数据平面的角色，不扮演控制平面的角色。尽管envoy适用于k8s集群云原生场景，但是并不会对k8s集群的路由相关资源进行监控，并转换为相关的路由配置。因此我们需要有控制面程序来完成对k8s集群中路由相关资源进行监控，来完成路由配置的生成，并通过xds将配置同步到envoy中。

当前常见的控制面实现有：istio、contour、emissary-ingress（ambassador）、gloo等。以conotur为例，常见的部署形态如下所示：

![Untitled](/pic/4a1349e1/p2.png)

参考链接：

1. [https://www.tetrate.io/blog/get-started-with-envoy-in-5-minutes/](https://www.tetrate.io/blog/get-started-with-envoy-in-5-minutes/)
2. [https://www.tetrate.io/what-is-envoy-proxy/#:~:text=Introducing Envoy Proxy,data plane for service mesh](https://www.tetrate.io/what-is-envoy-proxy/#:~:text=Introducing%20Envoy%20Proxy,data%20plane%20for%20service%20mesh).

---

# envoy的基本概念和框架

## 基本概念：

[https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/arch_overview/intro/terminology](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/arch_overview/intro/terminology)：

**Host**：一个逻辑的网络应用。一个物理设备上可以共存多个hosts，只要他们能够独立寻址。

**Downstream**：downstream host与envoy建立连接，向envoy发送请求，从envoy获得response。

**Upstream**：upstream host接收来自envoy的连接，接受请求，并返回response。

**Listener**：一个 listener 是一个命名的网络位置，downstream hosts可以与这个网络位置建立连接。envoy会暴露一个或多个listener供downstream hosts连接。

**Cluster**：一个 cluster是一组逻辑上相近的upstream hosts，envoy会与之建立连接。envoy 可以通过service discovery 发现cluster 的hosts 成员。一个请求到来，确定会被路由到一个cluster 时，会通过指定的负载均衡策略确定将请求发送到这个cluster 中的哪个host。

**Mesh** ： ****envoy mesh是一组envoy proxies组成的，为许多不同的service 和 应用平台提供 消息传输的底层设施。

**Runtime configuration：** 带外实时配置系统与特使一起部署。可以更改配置设置，从而影响操作，而无需重新启动Envoy或更改主要配置。

## 基本术语：

[https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/life_of_a_request](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/life_of_a_request)：

- *Cluster*: a logical service with a set of endpoints that Envoy forwards requests to. *一个由一组endpoints组成的逻辑的service，envoy将请求发往cluster。*
- *Downstream*: an entity connecting to Envoy. This may be a local application (in a sidecar model) or a network node. In non-sidecar models, this is a remote client.
- *Endpoints*: network nodes that implement a logical service. They are grouped into clusters. Endpoints in a cluster are *upstream* of an Envoy proxy.  *对应于pod节点、或者一个host节点*
- *Filter*: a module in the connection or request processing pipeline providing some aspect of request handling. An analogy from Unix is the composition of small utilities (filters) with Unix pipes (filter chains).
- *Filter chain*: a series of filters.  *listener 后面可以绑定 filter chain，发送到listener上的请求进来之后，就会经过这个filter chain上的filter 的处理。*
- *Listeners*: Envoy module responsible for binding to an IP/port, accepting new TCP connections (or UDP datagrams) and orchestrating the downstream facing aspects of request processing. 可以理解为定义的暴露给下游连接的socket server
- *Upstream*: an endpoint (network node) that Envoy connects to when forwarding requests for a service. This may be a local application (in a sidecar model) or a network node. In non-sidecar models, this corresponds with a remote backend.

提问：

1. filter chain 上在 filter 间传递处理的是什么？

## 基本框架：

### 关键子系统

envoy的核心能力是处理流量，当一个请求到来时，主要经历envoy 中两个主要子系统的处理（[ref](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/life_of_a_request#high-level-architecture)）：

![lor-architecture.svg](/pic/4a1349e1/lor-architecture.svg)

- Listener subsystem：处理来自downstream的请求，同时负责管理downstream的请求的生命周期，并负责传输response。downstream的http/2编解码器就属于这个组件。
- Cluster subsystem：负责选择和管理到upstream endpoint的连接。这个组件管理 上游 cluster 和 endpoint的健康新情况，进行负载均衡，管理连接池。upstream的 http/2 编解码器属于这个组件。

我们使用上面的Listener subsystem和Cluster subsystem来指代由顶级 ListenerManager 和 ClusterManager 类创建的模块组和实例类。

这两个子系统由 http router filter连接起来，http route filter通常来说是 listener 上的filter chain 的最后一个filter。http router filter 的作用是确定将来自downstream 的request 发送到哪个 upstream。也就是负责十分关键的路由环节，其过程将在后面章节进行描述。

### 线程模型

`Envoy`使用单进程多线程架构，有一个基于事件的线程模型。其中一个扮演主线程的控制各种协调任务，而一些工作线程负责监听、过滤和转发。一旦某个链接被监听器 `Listener`接受，那么这个链接将会剩余的生命周期绑定在这个 `Woker` 线程。这种架构会使得大部分工作工作在单线程的情况下，只有少量的工作会涉及到线程间通信，这使得`Envoy`代码是非阻塞的。（[参考](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/arch_overview/intro/threading_model)）

### 流量生命周期

1. Listener TCP accept[¶](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/life_of_a_request#listener-tcp-accept)

worker thread 持有自己的一个Listener 实例，当新的tcp连接到来时，内核决定由哪个worker thread接受请求进行处理。

2. Listener filter chains and network filter chain matching[¶](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/life_of_a_request#listener-filter-chains-and-network-filter-chain-matching)

![Untitled](/pic/4a1349e1/p3.png)

Listener接受请求后，依次调用 Listener filter chain 和 network filter chain对请求进行处理。

Envoy 会在network filters之前处理listener fileters。我们可以在listener fileters中操作连接元数据，通常是为了影响后来的filters或集群如何处理连接。

listener filters 对新接受的socket进行操作，并可以停止或随后继续执行进一步的filter。listener filter的顺序很重要，因为 Envoy 在listener接受socket后，在创建连接前，会按顺序处理这些filter。

我们可以使用listener filters的结果来进行filter匹配，并选择一个合适的network filter chain。例如，我们可以使用 HTTP 检查器监听器过滤器来确定 HTTP 协议（HTTP/1.1 或 HTTP/2）。基于这个结果，我们就可以选择并运行不同的network filter chain。

3. **TLS transport socket decryption[¶](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/life_of_a_request#tls-transport-socket-decryption)**

卸载TLS

4. **Network filter chain processing[¶](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/life_of_a_request#network-filter-chain-processing)**

接下来就进入 network filter chain的处理阶段，处理http 的listener的 network filter chain 的最后一个filter是 http connection manager（HCM）。HCM 负责创建 http/2 编解码器 以及管理 http filter chain。

结合前面的处理流程，一个请求进来之后的处理流程如下图所示：

![lor-network-filters.svg](/pic/4a1349e1/lor-network-filters.svg)

5. **HTTP/2 codec decoding[¶](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/life_of_a_request#http-2-codec-decoding)**

进行解码，使后续处理协议无关

6. **HTTP filter chain processing[¶](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/life_of_a_request#http-filter-chain-processing)**

HCM 中 filter chain 处理流程大致如下图：

![lor-http-filters.svg](/pic/4a1349e1/lor-http-filters.svg)

HCM 的filter chain中最后一个filter 为 route filter ，负责选定route configuration， 确定upstream cluster。当route filter被调用，路由选择过程就完成了。所选路由的配置将指向上游集群名称。然后，路由器过滤器向 ClusterManager 请求集群的 HTTP 连接池。

7. **Load balancing[¶](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/life_of_a_request#load-balancing)**

每个cluster都有一个负载均衡器，它在新请求到达时选择一个endpoint。

一旦选择了一个endpoint，这个endpoint的连接池就被用来寻找一个连接来转发请求。

![lor-lb.svg](/pic/4a1349e1/lor-lb.svg)

8. **HTTP/2 codec encoding[¶](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/life_of_a_request#http-2-codec-encoding)**

进行 http/2 编码

9. **TLS transport socket encryption[¶](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/life_of_a_request#tls-transport-socket-encryption)**

进行 tls 传输加密

![lor-client.svg](/pic/4a1349e1/lor-client.svg)

10. **Response path and HTTP lifecycle[¶](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/life_of_a_request#response-path-and-http-lifecycle)**

response 以与request 相反的顺序经历 http filters 和 network filters。在request 处理时调用的是filter 的decoder，对response进行处理时调用的是filter 的encoder，关于这个的详细信息，在后面对filter 进行介绍时会进行更加清楚的描述。

11. **Post-request processing[¶](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/life_of_a_request#post-request-processing)**

请求完成后，流会被销毁，同时还会进行一些后置处理：

- 统计信息更新（例如timing, active requests, upgrades, health checks）
- access log 记录
- trace span 完成。trace span 描述请求的持续时间和详细信息。

# envoy动态配置 （xDS）

## 概念介绍

当使用动态配置时，我们不需要重新启动 Envoy 进程就可以生效。相反，Envoy 通过从磁盘或网络上的文件读取配置，动态地重新加载配置。动态配置使用所谓的**发现服务 API**，指向配置的特定部分。这些 API 也被统称为 **xDS**。当使用 xDS 时，Envoy 调用外部基于 gRPC/REST 的配置provider，这些provider实现了发现服务 API 来检索配置。

外部基于 gRPC/REST 的配置提供者也被称为**控制平面**。当使用磁盘上的文件时，我们不需要控制平面。Envoy 提供了控制平面的 Golang 实现，但是 Java 和其他控制平面的实现也可以使用。

### xDS发现服务

Envoy 内部有多个发现服务 API，分别对应一个[资源类型](https://www.envoyproxy.io/docs/envoy/v1.21.4/api-docs/xds_protocol#resource-types)。所有这些在下表中都有描述。

[Untitled](https://www.notion.so/89ae5db7011541daa65942c1bc3f411f)

### **聚合发现服务（ADS）**

表中的发现服务是独立的，有不同的 gRPC/REST 服务名称。使用聚合发现服务（ADS），我们可以使用一个单一的 gRPC 服务，在一个 gRPC 流中支持所有的资源类型（监听器、路由、集群…）。ADS 还能确保不同资源的更新顺序正确。请注意，ADS 只支持 gRPC。如果没有 ADS，我们就需要协调其他 gRPC 流来实现正确的更新顺序。

In general, to avoid traffic drop, sequencing of updates should follow a make before break model, wherein:

- CDS updates (if any) must always be pushed first.
- EDS updates (if any) must arrive after CDS updates for the respective clusters.
- LDS updates must arrive after corresponding CDS/EDS updates.
- RDS updates related to the newly added listeners must arrive after CDS/EDS/LDS updates.
- VHDS updates (if any) related to the newly added RouteConfigurations must arrive after RDS updates.
- Stale CDS clusters and related EDS endpoints (ones no longer being referenced) can then be removed.

### **增量 gRPC xDS**

全量模式下，每次我们订阅或每次我们发送资源更新时，我们必须包括所有的资源。例如，每次 RDS 更新必须包含每条路由。如果我们不包括一个路由，Envoy 会认为该路由已被删除。这样做更新会导致很高的带宽和计算成本，特别是当有大量的资源在网络上被发送时。Envoy 支持 xDS 的 delta 变体，我们可以只包括我们想添加 / 删除 / 更新的资源，以改善这种情况。

关于envoy xDS 动态配置接口的更多信息见[链接](https://www.envoyproxy.io/docs/envoy/v1.21.4/api-docs/xds_protocol#xds-rest-and-grpc-protocol)。

## 总结

关于xDS小结如下：

### 数据来源

三种xds配置数据来源：文件系统、rest接口、grpc stream

1. 文件系统：envoy 监控指定的文件，当文件内容发生变化时，加载生效。
2. rest接口：控制平面 xDS server 提供的是rest 接口供 envoy 调用获取配置信息，这种模式下，需要envoy 主动进行polling，需要考虑polling周期和性能消耗。
3. grpc stream：控制平面 xDS server 提供 grpc stream服务，envoy 与server建立连接，订阅资源，控制面通过流实时将配置同步到envoy。

### 四种变体

两个纬度：

- State of the World (SotW) vs. incremental.
  
    全量更新 vs 增量更新
    
- xDS vs ADS
  
    每个资源类型一个gRPC 流 vs 集成所有资源类型在一个gRPC 流
    

两个纬度的不同变体组合出四种变体：

1. State of the World (Basic xDS): SotW, separate gRPC stream for each resource type
2. Incremental xDS: incremental, separate gRPC stream for each resource type
3. Aggregated Discovery Service (ADS): SotW, aggregate stream for all resource types
4. Incremental ADS: incremental, aggregate stream for all resource types

contour只提供了 SotW的stream模式，这意味着cluster 和 Listener 这两个资源的订阅和更新需要是全量的。而其他资源可以依托于其他关联资源，以一定的粒度进行全量更新。（The SotW approach was the original mechanism used by xDS, in which the client must specify all resource names it is interested in with each request, and for LDS and CDS resources, the server must return all resources that the client has subscribed to in each request.）[摘自此处](https://www.envoyproxy.io/docs/envoy/v1.21.4/api-docs/xds_protocol#four-variants)。

以订阅流程为例：

`DiscoveryRequest` 中的 `resource_names` 信息作为资源订阅标识出现。 `Cluster` 和 `Listener` 将使用一个空的 `resource_names`，因为 Envoy 需要获取管理服务器对应于节点标识的所有 `Cluster`（CDS）和 `Listener`（LDS）。对于其他资源类型，如 `RouteConfigurations`（RDS）和 `ClusterLoadAssignments`（EDS），则遵循此前的 CDS/LDS 更新，Envoy 能够明确地枚举这些资源。

---

# envoy如何进行路由

envoy.filters.http.router的主要工作是查看路由表，并对请求进行相应的路由，包括转发和重定向。

http filter 使用传入的请求信息，根据虚拟主机信息和路由规则将请求与上游集群相匹配，匹配的上游集群可能有多个，这时会从上游集群中选择出一个，然后在该集群内根据配置的负载均衡策略选择个上游endpoint进行请求转发。

## 主要流程

当一个 HTTP 请求进来时，虚拟主机、域名和路由匹配依次发生。

1. `host`或`authority`头被匹配到每个虚拟主机的`domains`字段中指定的值。例如，如果主机头被设置为 `foo.io`，则虚拟主机 `foo_vhost` 匹配。
2. 接下来会检查匹配的虚拟主机内`routs`下的条目。如果发现匹配，就不做进一步检查，而是选择一个集群。例如，如果我们匹配了 `foo.io` 虚拟主机，并且请求前缀是 `/api`，那么集群 `foo_io_api` 就被选中。
3. 如果提供，虚拟主机中的每个虚拟集群（`virtual_clusters`）都会被检查是否匹配。如果有匹配的，就使用一个虚拟集群，而不再进行进一步的虚拟集群检查。

因此，虚拟主机的顺序以及每个主机内的路由都很重要。

## 数据结构

从代码实现层面来看，匹配流程及使用到的数据结构大致如下：

一个请求过来之后，会通过 请求中的host信息去找到对应的 virtual_host 的配置信息，然后在从 virtual_host 的配置信息中选取出 匹配 的 route 项，route项里面明确了要发送的 cluster ， 也就是我们集群里面的应用service

主要就是：

1. 从config中findVirtualHost
2. 从VirtualHost中getRouteFromEntries

config中结构大致如下：
主要有三个map： virtual_hosts_、wildcard_virtual_host_suffixes_、wildcard_virtual_host_prefixes_

{
virtual_hosts_                     VirtualHosts
wildcard_virtual_host_suffixes_    WildcardVirtualHosts
wildcard_virtual_host_prefixes_    WildcardVirtualHosts
}

VirtualHosts 是一个map， 结构为：map<host, VirtualHost>
WildcardVirtualHosts 是一个嵌套map， 结构为： map<length_of_host，map<host, VirtualHost>>

VirtualHost 中存有 routeEntry， 存在 vector中，routeEntry 有 各种 匹配规则

结合上面所述的存储结构，路由匹配的过程执行的步骤大致如下：

1. 从config中findVirtualHost
    依次从 virtual_hosts_、wildcard_virtual_host_suffixes_、wildcard_virtual_host_prefixes_ 查找 VirtualHost
    virtual_hosts_ 中是直接 通过key查找；
    wildcard_virtual_host_suffixes_、wildcard_virtual_host_prefixes_ 是 根据最长匹配的优先原则，按 length_of_host 由大到小，在map<host, VirtualHost> 中 通过 key 查找。

  如果所有map中都没有匹配的对象，则返回default_virtual_host.

2. 从VirtualHost中getRouteFromEntries
   这个步骤是遍历 vector 进行匹配，发现匹配的 routeEntry就返回，不再管后面有没有匹配的routeEntry
   
    ![lor-route-config.svg](/pic/4a1349e1/lor-route-config.svg)
   

完整域名匹配的情况容易理解，以下补充说明在前缀匹配和后缀匹配情形下的匹配流程，wildcard_virtual_host_suffixes_ 的结构大致如下：

```
{
    6: {
        ".a.com": VirtualHost,
        ".b.com": VirtualHost
        },
    5: {
        ".a.cn": VirtualHost,
        ".c.cn": VirtualHost
       }
}
```

匹配的时候会根据长度遍历一级map，对二级map根据域名的子字符串hash查找符合的virtual host。这种方式可以较好地降低匹配的成本。前缀匹配的逻辑与之大致相同。

## 请求匹配条件

根据前面的内容，对根据域名选取出对应的virtual host 的过程已经比较明确，接下来对如何从virtual host中匹配出符合条件的routeEntry 进行介绍。从virtual host 中匹配出符合条件的routeEntry 并没有什么特别的处理手法，就是进行顺序匹配，值得注意的是，一旦有符合匹配条件的routeEntry出现，就不会再继续进行匹配，因此在配置路由规则时，顺序是十分重要的。

那么routeEntry中可以配置些什么匹配条件呢？

- 路径匹配
    - prefix：前缀匹配
    - path：全路径匹配
    - safe_rege：根据正则表达式匹配
    - connect_matcher: 只匹配connect请求（alpha）

- header匹配

可指定一组 Header，根据路由配置中所有指定的 Header 检查请求 Header。如果所有指定的头信息都存在于请求中，并且设置了相同的值，则进行匹配。

多个匹配规则可以应用于Header：

- range_match：范围匹配，检查请求header 中的值是否在指定的十进制整数范围内。支持负数。
- present_match:  存在匹配，key是否存在
- string_match: 字符串匹配
    - regex_match
    - exact_match
    - prefix_match
    - suffix_match
    - contains_match

示例：

```bash
- match:
    prefix: "/"
    headers:
    # 头部`regex_match`匹配所提供的正则表达式
    - name: regex_match
      string_match:
        safe_regex_match:
          google_re2: {}
          regex: "^v\\d+$"
    # Header `exact_match`包含值`hello`。
    - name: exact_match
      string_match:
        exact:"hello"
    # 头部`prefix_match`以`api`开头。
    - name: prefix_match
      string_match:
        prefix:"api"
    # 头部`后缀_match`以`_1`结束
    - name: suffix_match
      string_match:
        suffix: "_1"
    # 头部`contains_match`包含值 "debug"
    - name: contains_match
      string_match:
        contains: "debug"
```

- invert_match

  反转匹配，`invert_match` 可以被其他匹配器使用。例如：

```bash
- match:
    prefix: "/"
    headers:
    - name: env
      contains_match: "test"
      invert_match: true
```

上面的片段将检查 `env` 头的值是否包含字符串`test`。如果我们设置了 `env` 头，并且它不包括字符串`test`，那么整个匹配的评估结果为真。

需要注意的是，invert_match 不是直接对匹配结果取反，以上面的例子为例，invert_match 为false时，匹配条件表示 env 存在，且值包含 test；invert_match 为true的时候，不是前面条件的取反，也就是不是 “env 不存在 或 env 存在且值不包含test” ，而是仅仅表示 “env 存在，且其值不包含test”。

- query_parameters 查询参数匹配
  
    使用 `query_parameters`字段，我们可以指定路由应该匹配的 URL 查询的参数。过滤器将检查来自`path`头的查询字符串，并将其与所提供的参数进行比较。
    

​    query_parameters匹配规则:

| 规则名称   | 描述                                   |
| :--------- | -------------------------------------- |
| exact      | 必须与查询参数的精确值相匹配           |
| prefix     | 前缀必须符合查询参数值的开头           |
| suffix     | 后缀必须符合查询参数值的结尾           |
| safe_regex | 查询参数值必须符合指定的正则表达式     |
| contains   | 检查查询参数值是否包含一个特定的字符串 |

除了上述规则外，我们还可以使用 `ignore_case`字段来指示精确、前缀或后缀匹配是否应该区分大小写。如果设置为 “true”，匹配就不区分大小写。

例子1:

```bash
- match:
    prefix: "/"
    query_parameters:
    - name: env
      present_match: true
```

如果有一个名为 `env` 的查询参数被设置，上面的片段将评估为真。它没有说任何关于该值的事情。它只是检查它是否存在。例如，使用上述匹配器，下面的请求将被评估为真。

`GET /hello?env=test`

例子2:   使用前缀规则进行不区分大小写的查询参数匹配

```bash
- match:
    prefix: "/"
    query_parameters:
    - name: env
      string_match:
        prefix: "env_"
        ignore_case: true
```

如果有一个名为 `env`的查询参数，其值以 `env_`开头，则上述内容将评估为真。例如`env_staging`和 `ENV_prod`评估为真。

- **[gRPC 和 TLS 匹配器](https://lib.jimmysong.io/envoy-handbook/hcm/request-matching/#grpc-%E5%92%8C-tls-%E5%8C%B9%E9%85%8D%E5%99%A8)**
    - gRPC 匹配器将只在 gRPC 请求上匹配。
    - TLS 匹配器，它将根据提供的选项来匹配 TLS 上下文。
    

利用envoy提供的以上请求匹配能力，我们可以灵活组合出符合业务场景的匹配条件，使得不同的请求可以按照我们的意图发送到不同的upstream clusters。

## upstream cluster 与 endpoint选择

当一个请求过来，经过前面的域名以及其他条件的匹配后，会选择出一个routeEntry，接下来将会从routeEntry中选择出一个upstream cluster 进行请求转发。

一个routeEntry可以关联一个或多个upstream cluster，当关联一个cluster时，则使用该cluster。当routeEntry中关联多个upstream cluster，通常是关联多个weight cluster 的场景，此时会根据权重随机选择一个cluster。

随机选择cluster 的流程是 根据请求，产生一个数，将该数按总权重取模，并根据取模后的值所在的区间确定选择哪个cluster。

![Untitled](/pic/4a1349e1/p4.png)

在1.21.x 版本的envoy上，在weight cluster 中有 header name 属性，通过指定这个值，可以由用户通过指定的header 传入“随机值”，如果用户指定来该属性值，且在请求中携带了合法有效的数值，则将使用该值，否则生成一个随机值。

mark todo：由于在验证流量分割比例的时候，发现存在比例偏离较大的情况，对这个随机值的生成方式存在一些疑惑点，待查明。

在确定upstream cluster后，会根据指定的负载均衡策略从cluster 的 endpoint中选择一个endpoint进行流量转发。

envoy支持的负载均衡策略有（[ref](https://www.envoyproxy.io/docs/envoy/v1.21.4/intro/arch_overview/upstream/load_balancing/load_balancers#arch-overview-load-balancing-types)）：

- **Weighted round robin**
- **Weighted least request**
- **Ring hash**
- **Maglev**
- **Random**

一旦选择了一个endpoint，这个endpoint的连接池就被用来寻找一个连接来转发请求。如果不存在与主机的连接，或者所有连接都处于最大并发流限制，则会建立一个新连接并将其放置在连接池中，除非集群的最大连接断路器已经触发熔断。如果配置了并达到了连接的最大生命周期流限制，则会在池中分配一个新连接，并丢弃受影响的 HTTP/2 连接。

![lor-lb.svg](/pic/4a1349e1/lor-lb%201.svg)

---

# envoy的重要组件与模型

## envoy线程模型

Envoy 有一个基于事件的线程模型。一个主线程负责服务器生命周期、配置处理、统计等以及一些工作线程处理请求。所有线程都围绕一个事件循环 (libevent) 运行，并且任何给定的下游 TCP 连接（包括其上的所有多路复用流）将在其生命周期内仅由一个工作线程处理。每个工作线程都维护自己的与上游端点的 TCP 连接池。 UDP 处理利用 SO_REUSEPORT 让内核始终将源/目标 IP:port 元组散列到同一个工作线程。 UDP 过滤器状态为给定的工作线程共享，过滤器负责根据需要提供会话语义。这与我们在下面讨论的面向连接的 TCP 过滤器形成对比，其中过滤器状态存在于每个连接上，并且在 HTTP 过滤器的情况下，是基于每个请求的。

工作线程很少共享状态并以微不足道的并行方式运行。这种线程模型可以扩展到非常高核心数的 CPU。线程间极少需要共享数据，使得线程的运行可以避免阻塞。

## Listener和worker thread

![lor-listeners.svg](/pic/4a1349e1/lor-listeners.svg)

ListenerManager 负责获取表示Listener的配置并实例化绑定到各自 IP/端口的多个Listener实例。Listener可能处于以下三种状态之一：

- Warming：Listener正在等待配置依赖（例如路由配置、动态秘密）。Listener尚未准备好接受 TCP 连接。
- Active：Listener绑定到其 IP/端口并接受 TCP 连接。
- Draining：Listener不再接受新的 TCP 连接，而其现有的 TCP 连接被允许继续运行一段时间。

每个worker thread为每个配置的Listener维护自己的Listener实例。每个Listener可以通过 SO_REUSEPORT 绑定到同一个端口，或者共享一个绑定到这个端口的socket。当一个新的 TCP 连接到达时，内核决定哪个worker thread将接受该连接，并且该worker thread的Listener将调用其 Server::ConnectionHandlerImpl::ActiveTcpListener::onAccept() 回调。

## 连接池

集群中的每个端点将有一个或多个连接池。例如，根据所支持的上游协议，每个协议可能有一个连接池分配。Envoy 中的每个工作线程也为每个集群维护其连接池。例如，如果 Envoy 有两个线程和一个同时支持 HTTP/1 和 HTTP/2 的集群，将至少有四个连接池。连接池的方式是基于底层线程协议的。对于 HTTP/1.1，连接池根据需要获取端点的连接（最多到断路限制）。当请求变得可用时，它们就被绑定到连接上。 当使用 HTTP/2 时，连接池在**一个连接**上复用多个请求，最多到  `max_concurrent_streams` 和 `max_requests_per_connections` 指定的限制。HTTP/2 连接池建立尽可能多的连接，以满足请求。

## envoy过滤器

1. http过滤器

envoy支持一系列的http filter，这些filter对http级别的消息进行处理，不知道底层协议或复用。有三种类型的http过滤器：

- decoder： 在请求路径上调用
- encoder：在响应路径上调用
- decoder/encoder： 在请求和响应路径上都会被调用

假设有如下filter chain：

![Untitled](/pic/4a1349e1/p5.png)

     在请求路径上的调用情况如下：

![Untitled](/pic/4a1349e1/p6.png)

      在响应路径上的调用情况如下：

![Untitled](/pic/4a1349e1/p7.png)

单个http filter可以停止或继续执行后续的filter，并在单个请求流的范围内相互分享状态。

通常来说，filter chain上的最后一个filter 是 route filter 。

**内置http filter：**

CORS、CORS、健康检查、JWT认证等

**http filter列表：**

[https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/http_filters#config-http-filters](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/http_filters#config-http-filters)

---


# 控制面选型

当前基于 envoy 提供的控制面主要有 istio、emissary-ingress（ambassador）、contour、gloo等，其中istio主要是实现 service mesh，我们想要envoy 作为 api gateway 存在，主要考察 emissary-ingress（ambassador）、contour、gloo。由于都是基于envoy 的控制面，所以他们能够提供的特性，取决于envoy本身的特性，在基本能力的支持上没有大的差异。

**项目github相关指标**

| project | watch | fork | star | issue(open/closed) | bug issue |
| --- | --- | --- | --- | --- | --- |
| gloo | 108 | 348 | 3.4k | 945/1991 | 310/670 |
| contour | 80 | 561 | 3.1k | 390/1317 | 50/253 |
| emissary-ingress | 87 | 612 | 3.8k | 315/1123 | 12/62 |

可见gloo的bug issue 数量较大。

**gateway api支持情况**

- emissary
  
    now supports a limited subset of the new `v1alpha1`[Gateway API](https://gateway-api.sigs.k8s.io/)
    
- contour
    - now exclusively supports Gateway API v1alpha2, the latest available version.

**支持envoy版本情况：**

调研时发现，emissary-ingress使用的envoy版本为 1.17.4，但envoy在调研时已经迭代到1.22.x 的发布版本。

| emissary ingress | envoy |
| --- | --- |
| 2.1.0 | 7a33e53fd3d3c4befa53030797f344fcacaa61f4/1.17.4-dev/Modified/RELEASE/BoringSSL |
| 2.2.0 | 049f125c1c9a6cd7e49bd4a660cdeccd9f6ec383/1.17.4/Modified/RELEASE/BoringSSL |

contour在调研时支持的是1.21.x版本。

envoy每个版本会增加一些新的功能，可能会带来api 的变化，导致版本之间可能是不兼容的。比如contour 1.20.1 支持envoy 1.21.x ，无法和envoy 1.22.x 有效对接。

考虑到bug issue 和 版本支持的情况，目前选择了contour 进行开发适配。


---

# envoy支持特性概览

- 自动健康探测
- 被动健康探测
- 自动重试
- 熔断
- 局部速率限制
- 全局速率限制（需使用外部速率限制服务）
- 影子请求（流量镜像）
- 异常点检测（被动健康探测）
- 请求对冲
- tls卸载
- http/1.1
- http/2
- http/3 （alpha）
- websockets
- L3/L4 路由
- L7 路由
- 一流的观察性：日志、指标、tracing(请求id生成和追踪)
- 流量分割
- 操作header信息（包括request的header以及 response的header）
- timeout配置

---

相关内容：

1. [envoy 动态路由配置信息查看](https://hxysayhi.com/blog/posts/61a05b5d/)