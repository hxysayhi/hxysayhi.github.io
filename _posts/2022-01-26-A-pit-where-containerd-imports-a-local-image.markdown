---
layout: post
title:  "containerd导入本地镜像的一个小坑"
date:   2022-01-26 23:31:24 +0800
categories: jekyll update
permalink: /posts/0e8b92e6/
tags: [writing, note, container]
---

containerd 命令行工具为 ctr

本地镜像导入命令：

```bash
ctr image import <path/to/image/file>
```


注意：当tar包没有tag信息时，导入之后，无报错，errno 为0，但是 通过 `ctr images ls` 查看却没有相关的镜像。这种情况，需要添加 `--digests=true`  来导入：

```bash
ctr image import --digests=true <path/to/images/file>
```
