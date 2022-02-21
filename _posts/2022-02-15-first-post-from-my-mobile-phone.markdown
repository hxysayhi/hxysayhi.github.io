---
layout: post
title:  "在手机上创建、编辑并推送的第一条内容"
description: "这是在手机上创建、编辑，并完成推送的第一条内容。简单记录了一下解决方案"
date:   2022-02-15 08:51:34 +0800
categories: default
permalink: /posts/2898f5e0/
tags: [writing, tool]
---

这是在手机上创建、编辑，并完成推送的第一条内容。 

这既是一个纪念，也是一个测试！ 

在创建时，由于手机环境下，没有提前配置好随机字符串生成命令，导致固定链接生成失败，看来创建脚本可能还需要优化一下。


ios端git 环境是 通过安装 ish shell，在虚拟Linux环境中安装git实现的。

文档编辑是配合其他本地编辑工具完成。

---

update：

为了便于进行markdown文档编辑和预览，以及git commit的管理，使用 working copy进行管理和编辑。但是working copy的push功能需要付费，因此将working copy下管理的仓库挂载到ish中，利用ish中的git进行push。

