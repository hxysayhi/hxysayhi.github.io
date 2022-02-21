---
layout: post
title:  "jekyll post page 生成脚本"
description: "一个简单的脚本，用于创建新的post page，主要用于创建markdown文件、生成头部内容，生成随机短地址作为固定链接"
date:   2022-01-26 23:34:48 +0800
categories: Technology writing
permalink: /posts/65e8b919/
tags: [IT, jekyll, tool]
---

脚本功能：
1. md 文件创建
2. md 头内容生成
3. 生成随机短地址作为permalink，以便为每个page实现固定地址


脚本内容：

```bash
#!/usr/bin/env bash

DIR="${0%/*}"

title=`echo $@ | sed 's/[ ][ ]*/-/g'`
post_date=`date  +"%Y-%m-%d %T"`
post_name="`date "+%Y-%m-%d"`-${title}.markdown"
random_addr=`openssl rand -hex 8 | md5 | cut -c1-8`

cat > ${DIR}/../_posts/${post_name} << EOF
---
layout: post
title:  "${title}"
date:   ${post_date} +0800
categories: default
permalink: /posts/${random_addr}/
tags: [writing]
---

EOF


```

使用方法：

```bash
./new_post.sh <the new page name>
```
