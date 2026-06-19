# **docker-phantun**

这是一个一键运行 Phantun 的 Docker 镜像：  
对于会用 Docker 的人来说，它能减少运行 Phantun 需要的手动操作，大幅降低脑细胞死亡数量。

## ---

**场景演示：转发 Sing-box 的 HY2 协议**

下面以一个转发 Sing-box 发布的 HY2 协议的场景为例，演示此镜像的用法。  
**网络拓扑：**  
家庭PC \<=\> 家里运行Docker版Phantun客户端的x86虚拟机 \<====互联网====\> VPS上Docker中的Phantun服务端 \<=\> VPS上的Sing-box HY2协议端口  
**端口规划：**

* **VPS 上的 Sing-box 发布的 HY2 协议 UDP 端口号**：10000  
* **VPS 上的 Phantun 服务端监听的 TCP 端口号**：20000  
* **家里虚拟机 Phantun 客户端监听的 UDP 端口号**：10000

## ---

**一、基础准备**

家里虚拟机和 VPS 上**都要开启**内核 IPv4 转发：  
```
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```
*注：VPS 端的防火墙需开启 TCP 20000 端口的入站放行。*

## ---

**二、VPS 上的服务端部署**

### **1\. 安装 Docker-CE**

`curl -fsSL https://get.docker.com -o get-docker.sh`  
`sudo bash get-docker.sh`

### **2\. 部署 Phantun 服务端**

创建 Phantun 服务端的 Docker Compose 配置文件 docker-compose.yml，内容如下：  
```
services:
  phantun-server:
    image: metrak/phantun:latest
    container_name: phantun-server
    network_mode: "host"
    cap_add: [NET_ADMIN]
    devices: [/dev/net/tun]
    environment:
      - NIC=ens18        # 用 ip add 或 ifconfig 查一下网卡的真实名称
      - TCP_PORT=20000   # Phantun 监听的公网伪装 TCP 端口
    command: ["server", "--local", "20000", "--remote", "127.0.0.1:10000"]
    restart: unless-stopped
```
保存退出后，启动容器：  
`docker compose up -d`

## ---

**三、家里虚拟机部署客户端**

### **1\. 安装 Docker-CE**

国内网络安装方法参见清华大学镜像源的相关说明：[Docker-CE 软件源帮助](https://mirrors.tuna.tsinghua.edu.cn/help/docker-ce/)。  
*注：若连不上 Docker Hub，可使用代理或在 Docker 服务的配置文件 /etc/systemd/system/multi-user.target.wants/docker.service 中配置代理解决。*

### **2\. 部署 Phantun 客户端**

创建 Phantun 客户端的 Docker Compose 配置文件 docker-compose.yml，内容如下：  
```
services:
  phantun-client:
    image: metrak/phantun:latest
    container_name: phantun-client
    network_mode: "host"
    cap_add: [NET_ADMIN]
    devices: [/dev/net/tun]
    environment:
      - NIC=ens18        # 用 ip add 或 ifconfig 查一下网卡的真实名称
      - TCP_PORT=20000
    command: ["client", "--local", "0.0.0.0:10000", "--remote", "你的VPS公网IP:20000"]
    restart: unless-stopped
```
保存退出后，启动容器：  
`docker compose up -d`

## ---

**四、家庭 PC 测试**

在家庭 PC 的客户端软件（如 v2rayN 等）中，将原本直接连 VPS 上 HY2 的配置文件，**目标 IP 地址改为家里虚拟机的内网 IP，端口号不变**。  
最后进行测试，查看连通效果。
