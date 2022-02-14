---
layout: post
title:  "jekyll静态blog部署 checklist"
date:   2022-01-23 12:33:55 +0800
categories: jekyll update
permalink: /posts/824d93f1/
tags: [writing, note, jekyll]
---
1. 安装jekyll

    1.1 安装ruby

    为了避免版本冲突问题，使用rbenv进行安装（以ubuntu为例，参考[https://gorails.com/setup/ubuntu/18.04](https://gorails.com/setup/ubuntu/18.04)）

    - 安装rbenv

      ```shell
      cd
      git clone https://github.com/rbenv/rbenv.git ~/.rbenv
      echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
      echo 'eval "$(rbenv init -)"' >> ~/.bashrc
      exec $SHELL

      git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
      echo 'export PATH="$HOME/.rbenv/plugins/ruby-build/bin:$PATH"' >> ~/.bashrc
      exec $SHELL
      ```

    - 安装ruby

      ```shell
      rbenv install 3.0.3
      rbenv global 3.0.3
      ```
      检查安装是否符合预期

      ```
      ruby -v
      ```

    - 安装 Bundler

      ```shell
      gem install bundler
      ```

    1.2 安装jekyll

      ```shell
      gem install jekyll bundler
      ```


2. 创建blog project

    方案一： 安装好ruby后，安装jekyll，并创建blog project：

    ```bash
    gem install bundler jekyll

    jekyll new myblog
    ```

    方案二：直接选择自己喜欢的主题，从github将项目克隆到本地




1. vps上部署git仓库，配置hook实现自动部署blog能力(参考[https://jekyllrb.com/docs/deployment/automated/](https://jekyllrb.com/docs/deployment/automated/))


    3.1 创建git用户，并配置权限

    - 创建 `/var/www/myblog` 目录，将用户属组配置为git用户


    3.2 创建git仓库

    以git用户登录vps

    ```bash
    cd
    mkdir myrepo.git
    cd myrepo.git
    git --bare init
    ```

    在 `myrepo.git` 中创建 `hooks/post-receive` 文件，内容如下：

    ```bash
    # Install Ruby Gems to ~/gems
    export PATH="$HOME/.rbenv/bin:$PATH"
    eval "$(rbenv init -)"
    export PATH="$HOME/.rbenv/plugins/ruby-build/bin:$PATH"
    export GEM_HOME=$HOME/gems
    export PATH=$GEM_HOME/bin:$PATH

    TMP_GIT_CLONE=$HOME/tmp/jekyll-blog
    GEMFILE=$TMP_GIT_CLONE/Gemfile
    PUBLIC_WWW=/var/www/myblog

    git clone $GIT_DIR $TMP_GIT_CLONE
    BUNDLE_GEMFILE=$GEMFILE bundle install
    BUNDLE_GEMFILE=$GEMFILE bundle exec jekyll build -s $TMP_GIT_CLONE -d $PUBLIC_WWW
    rm -Rf $TMP_GIT_CLONE
    exit 
    ```


    3.3 本地blog project绑定vps git 仓库

    ```bash
    cd myblog
    git init
    git remote add deploy git@remote-address:/path/to/myrepo.git
    git push --set-upstream deploy master
    ```

    后续push时将会触发vps git hook进行自动部署



2. vps上部署nginx
   
    4.1 部署nginx

    4.2 根据前面步骤中 `PUBLIC_WWW` 的值，配置nginx 

    4.3 安装域名证书（可通过certbot完成）