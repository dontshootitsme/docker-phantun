# **docker-phantun**

这是一个一键运行 Phantun 的 Docker 镜像：  
对于会用 Docker 的人来说，它能减少运行 Phantun 需要的手动操作，大幅降低脑细胞死亡数量。

## ---

**环境变量说明（Server / Client 均适用）**

| 变量 | 默认值 | 说明 |
| ---- | ------ | ---- |
| `NIC` | `eth0` | 本机网卡真实名称（用 `ip addr` 查看），iptables 规则会挂在这个网卡上 |
| `TCP_PORT` | `20000` | Phantun 伪装的公网 TCP 端口号，需与 `command` 中的 `--local`（服务端）/ 对端端口（客户端）一致 |
| `TUN_NAME` | `ptun<TCP_PORT><4位指纹>` | Phantun 使用的 TUN 接口名。**不要使用 `tun0`/`tun1` 这类名字**，它们会被内核自动分配给其他 TUN 设备（如 easytier），一旦冲突，镜像内的 iptables 转发规则就会指向不存在的接口，隧道彻底失效。默认名由端口号 + 命令行参数 md5 前 4 位构成（如 `ptun20000a1b2`）：同主机上不同端口、不同配置的实例都不会重名，且同一实例重启后名字不变，旧规则可被自动清理 |

> 历史版本曾将 TUN 接口名写死为 `tun0`，如果主机上已有其他 `tun0` 设备，Phantun 会自动改用 `tun1`，而 iptables 规则仍指向 `tun0`，导致所有流量被丢弃。如果你正遇到"客户端 TCP 能握手但数据不通/直接超时"的问题，请升级镜像并检查 `ip link` 中 Phantun 实际使用的接口名与 `iptables -S FORWARD` 中的规则是否一致。

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
