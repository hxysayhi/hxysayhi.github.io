#!/usr/bin/env bash

title=`echo $@ | sed 's/[ ][ ]*/-/g'`
post_date=`date  +"%Y-%m-%d %T"`
post_name="`date "+%Y-%m-%d"`-${title}.markdown"
random_addr=`openssl rand -hex 8 | md5 | cut -c1-8`

cat > ../_posts/${post_name} << EOF
---
layout: post
title:  "${title}"
date:   ${post_date} +0800
categories: jekyll update
permalink: /posts/${random_addr}/
---

EOF

