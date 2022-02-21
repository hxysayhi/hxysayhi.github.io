---
layout: post
title:  "如何在nginx创建临时重定向和永久重定向"
description: "关于临时重定向、永久重定向，以及如何在nginx中进行相关配置"
date:   2022-02-03 23:38:50 +0800
categories: Technology learn
permalink: /posts/36358949/
tags: [IT, note, nginx]
---

### 重定向的概念

http重定向是将一个域名或者地址重新指向另一个域名或地址的方式。重定向的方式有多种，每一种对客户端而言都有些不同之处。其中两种最常见的重定向方式是临时重定向和永久重定向。

临时重定向的返回码是 302。 临时重定向是用于一个url暂时需要通过一个临时站点进行服务的场景。当你的网站需要进行临时维护时，你可能就会希望在你进行维护期间，将访问重定向到另一个临时页码，在页面中提供临时服务或者通知用户网站正在进行维护，很快会恢复服务。

永久重定向的返回码是 301。这个返回码希望告诉浏览器，应该放弃访问当前的url，并不再尝试访问当前URL。这种方式适用于当你的站点进行了永久性的迁移的情况，比如进行了域名更换等。

你可以通过在nginx的配置中向server 配置块中添加如下内容来创建一个临时重定向：

```
rewrite^/oldlocation$http://www.newdomain.com/newlocation redirect;

```

类似地，可以添加如下内容来创建一个永久重定向：

```
rewrite^/oldlocation$http://www.newdomain.com/newlocation permanent;

```

就下来将会对nginx 中每种类型的重定向进行更加深入的解释，以及给出一些特别案例的用法。(待更新。。。。。)


---

ref： [How To Create Temporary and Permanent Redirects with Nginx](https://www.digitalocean.com/community/tutorials/how-to-create-temporary-and-permanent-redirects-with-nginx)

