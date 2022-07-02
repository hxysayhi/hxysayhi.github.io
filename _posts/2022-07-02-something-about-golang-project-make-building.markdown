---
layout: post
title:  "使用make进行golang编译中的小问题及解决方案"
description: "关于golang使用make 编译时候遇到的几个小问题"
date:   2022-07-02 03:29:38 +0800
categories: Technology notes
permalink: /posts/61a056t8/
tags: [IT, golang, make]
preview: "内容摘要: 关于golang使用make 编译时候遇到的几个小问题：编译时提示遇到时钟偏差、编译时报错no required module provides package main.go"
---

1. 报错信息：Clock skew detected. Your build may be incomplete.

```bash
make: Warning: Clock skew detected. Your build may be incomplete.
```

表示检测到了时钟偏差，通常发生在将代码从开发主机拷贝到编译主机进行编译，而两个设备系统之间的时间上存在差距。

解决方案：

```bash
find ./ -type f | xargs touch
```

将所有文件进行一次touch，刷新时间为本地时间，然后进行编译

2. 报错信息：
 
```
no required module provides package main.go; to add it:
    
              go get main.go
              
```

解决方案

修改 makefile中 build 的命令行：
    
由
```bash
    go build -o bin/manager main.go
```
    
改为：


```bash
    go build -o bin/manager ${MODULE}/path/to/the/dir/of/main.go
```

${MODULE} 为当前项目module值，可在 go.mod中获取，即开头的 module值
    
/path/to/the/dir/of/main.go 为main.go所在目录在本项目中的相对路径