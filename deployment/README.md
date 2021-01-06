```text
SPDX-License-Identifier: Apache-2.0
Copyright (c) 2020 Intel Corporation
```
- [Introduction](#introduction)
- [Hardware Platform](#hardware-platform)
- [Kubernetes Cluster Setup with CIR](#kubernetes-cluster-setup-with-cir)
- [Ad-insertion Use Case Setup with CIR](#ad-insertion-use-case-setup-with-cir)
- [Troubleshooting during ADI Deployment](#troubleshooting-during-adi-deployment)

# Introduction
This guide will introduce some BKMs to deploy Ad-insertion on VCAC-A with CIR in PRC environment. Replacements of some unreachable and low-speed access docker/binaries repositories are included in this guide due to the PRC network policy. If you have some better mirrored repositories, please replace them accordingly.

# Hardware Platform
CIR ADI deployment was tested on Cascade Lake SP platforms.<br>

  | Host | Type | CPU | Memory | OS | VCAC SW version |
  |---|---|---|---|---|:---:|
  | Ansible Host | NUC | Intel Core i7-4790 3.60GHz - 4 cores | 8G DDR3 | CentOS 7.6.1810| \ |
  | Kubernetes Controller | Server | Intel Xeon Gold 6252N 2.30GHz - 24 cores | 192G DDR4 | CentOS 7.6.1810| \ |
  | Kubernetes Worker | Server | Intel Xeon Gold 6252N 2.30GHz x2 - 48 cores | 192G DDR4 | CentOS 7.6.1810| R4 |

# Kubernetes Cluster Setup with CIR

## CIR preparation
   Following guide on GitHub to get CIR source and submodule initial completed after your ansible host is ready with dependencies installed.<br>
   Then configure CIR correctly:
   ```
   git clone https://github.com/intel/common-integration-repository.git
   cd common-integration-repository/ && git submodule update --init --recursive

   # Edit the hostname and IP address and comment "ansible_python_interpreter" in openness_adi_inventory.ini
   cp examples/openness/openness_adi_inventory.ini ./ 
   cp -r examples/openness/basic/* ./
   
   # Enable passwordless login between all nodes in the cluster
   ssh-keygen -t rsa   # If not exists
   ssh-copy-id $k8s_cluster_master1_ip
   ssh-copy-id $k8s_cluster_node1_ip
   ...
   ```

## Kubernetes Cluster preparation
   Bellows are some pre-configurations on all Kubernetes cluster nodes.
1. Synchronize the time of all Kubernetes cluster nodes, if there are different.
   ```
   # Change time zone
   ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

   # Check their time zone and the time.
   date -R

   # If there’re different, adjust them manually or synchronize from NTP server.
   date -s "2020-11-1 00:00:00"  # manually
   yum install -y ntpdate && ntpdate ntp1.aliyun.com  # Or your location NTP server.

   # If use ntpdate command, it is better to add it in "crontab" to update regularly.
   */5 * * * * ntpdate ntp1.aliyun.com
   ```
2. Synchronize the ssh-key from Kubernetes master to all Kubernetes workers
   ```
   ssh-keygen -t rsa   # If not exists
   ssh-copy-id $k8s_cluster_node1_ip
   ssh-copy-id $k8s_cluster_node2_ip
   ...
   ```
3. Configure Yum and EPEL Mirror Repository on CentOS<br>
   The network connection to default yum and epel repository is bad in PRC environment, we can replace them to local one like from Tencent on all Kubernetes nodes.
   ```
   mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak
   wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.cloud.tencent.com/repo/centos7_base.repo

   yum install epel-release -y
   mv /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo.backup
   wget -O /etc/yum.repos.d/epel.repo http://mirrors.cloud.tencent.com/repo/epel-7.repo
   ```
4. GitHub Host Mapping and Switch Golang Proxy<br>
   Sometimes accessing github.com will timeout, we can set below options on all Kubernetes nodes. Please note this workaround can’t solve low speed issue.
   ```
   echo "151.101.228.133 raw.githubusercontent.com
   192.30.255.112 github.com " >> /etc/hosts
   echo "export GO111MODULE=on
   export GOPROXY=https://goproxy.cn" >> /etc/profile && source /etc/profile
   ```
   You can get IP like "151.101.228.133" from https://www.ipaddress.com/ "IP address lookup" function, just type the domain name you are going to access. 

5. Configure Pypi Repository<br>
   Replace default pypi repo https://pypi.org/simple on all Kubernetes nodes can speed up the pip package installation.
   ```
   # Please pay attention to indentation, vim ~/.pip/pip.conf to check.
   if [ ! -f ~/.pip/pip.conf ]; then
       yum install python-pip -y && mkdir ~/.pip
       echo "[global]
   index-url = https://mirrors.cloud.tencent.com/pypi/simple
   [install]
   trusted-host=mirrors.cloud.tencent.com" >> ~/.pip/pip.conf
   fi
   ```
6. Deploy Docker Image Cache Service (**`Highly Recommended`**)<br>
   Before CIR and AD-Insertion deployment, it’s recommended to setup docker register to cache docker images like "elasticsearch-oss" which is very low to be downloaded. Please make sure the server that deploying the docker cache service is not any node of the Kubernetes cluster.<br>
   **If you don’t want to deploy this service, please don’t apply `common_integration_repository/deployment/patch/AD-Insertion.patch` in next step.**
   ```
   # CentOS7
   wget -O /etc/yum.repos.d/docker-ce.repo https://download.docker.com/linux/centos/docker-ce.repo
   sed -i 's+download.docker.com+mirrors.cloud.tencent.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo

   yum install docker-ce -y

   #/home/docker is the image cache path on the host
   docker run -d -p 5000:5000 --restart always \
              --name registry \
              -e REGISTRY_PROXY_REMOTEURL=https://docker.elastic.co \
              -v /home/docker:/var/lib/registry \
              registry:2 

   # Use a docker client host to test, create or edit /etc/docker/daemon.json
   cat /etc/docker/daemon.json
   
   {
     "registry-mirrors": [
     "http://$your_docker_registry_server_ip:5000/"
     ]
   }

   # Prepare in advance
   docker pull elasticsearch/elasticsearch-oss:6.8.1

   ```

7. Update CIR Playbook with Patches<br>
   This section will change yum, Docker, Kubernetes mirror repository, Helm stable chart, AD-Insertion Dockerfile and VCAC node related CIR playbook, you can get the patches from common_integration_repository/deployment/patch folder. **And you can only apply `AD_Insertion.patch` or `ADI_without_docke_cache.patch` according to your docker cache service setup status.** 
   ```
   cd common_integration_repository/

   # Apply patches.
   patch -Np0 < deployment/patch/Openness.patch

   patch -Np0 < deployment/patch/AD-Insertion.patch  # You have deployed docker cache service.
   # choose either AD_Insertion.patch or ADI_without_docke_cache.patch, not both
   patch -Np0 < deployment/patch/ADI_without_docker_cache.patch # Not deployed docker cache service.

   # If you want to recover them.
   patch -REp0 < deployment/patch/Openness.patch
   
   patch -REp0 < deployment/patch/AD-Insertion.patch
   patch -REp0 < deployment/patch/ADI_without_docker_cache.patch
   ```
8. Configure CIR Variables<br>
   Follow up the CIR guide to configure all variables. To fix those unreachable and low speed access repositories issue, you can use your favorite source websit to replace with the following options in `group_vars/all/all.yml`
   ```
   ---
   # Kubernetes version
   kubernetes: true
   kube_version: v1.18.8
   #kube_version: v1.17.11
   #kube_version: v1.16.14

   #Add for deploy on PRC#
   _kubernetes_repository_url: "https://mirrors.tuna.tsinghua.edu.cn/kubernetes/yum/repos/kubernetes-el7-x86_64/"
   _docker_repository_url: "https://mirrors.cloud.tencent.com/docker-ce/linux/centos/7/$basearch/stable"
   _docker_repository_key: "https://mirrors.cloud.tencent.com/docker-ce/linux/centos/gpg"
   _vca_node_docker_packages_url:
     - "https://mirrors.cloud.tencent.com/docker-ce/linux/ubuntu/dists/xenial/pool/stable/amd64/containerd.io_1.2.13-2_amd64.deb"
     - "https://mirrors.cloud.tencent.com/docker-ce/linux/ubuntu/dists/xenial/pool/stable/amd64/docker-ce-cli_19.03.12~3-0~ubuntu-xenial_amd64.deb"
     - https://mirrors.cloud.tencent.com/docker-ce/linux/ubuntu/dists/xenial/pool/stable/amd64/docker-ce_19.03.12~3-0~ubuntu-xenial_amd64.deb
   _docker_registry_mirrors:
     - https://mirror.ccs.tencentyun.com
     - http://hub-mirror.c.163.com
     # If you have deployed local docker cache service
     - http://$your_local_docker_register_IP
   ######################
   ```
9. Kubernetes Cluster Deployment<br>
   ```
   # The following docker image will be used during deployment and can be cached first, after k8s-master and k8s-node has installed Docker, then use command "docker load -i $IMAGE_NAME:TAG" to import and use command "docker save $IMAGE_NAME:TAG -o /FILE/TO/PATH " to export docker images.
   docker pull ubuntu:16.04
   docker pull centos:centos7.4.1708
   docker pull weaveworks/weave-npc:2.7.0
   docker pull weaveworks/weave-kube:2.7.0

   # Run following command on you Ansible host:
   ansible-playbook -i openness_adi_inventory.ini playbooks/orchestration/orchestration.yml -e "profile=basic"
   ```

# Ad-insertion Use Case Setup with CIR
## Ad-insertion Deployment
   After the Kubernetes deployment completed, run following command to install Ad-insertion:
   ```
   # First, you need to verify that the cluster is running well, be ensure to check your kubernetes nodes and pods is running.
   kubectl get pod -A
   kubectl get node 

   # Before install, it is recommended that you prepare the following docker images on the Kubernetes workers first, to avoid unexpected failure during deployment.

   docker pull centos:7.6.1810
   docker pull ubuntu:18.04
   docker pull wurstmeister/kafka:2.12-2.4.0
   
   # If you don’t have local docker cache services setup
   docker pull docker.elastic.co/elasticsearch/elasticsearch-oss:6.8.1 

   # If you have local docker cache services setup
   docker pull elasticsearch/elasticsearch-oss:6.8.1

   docker pull wurstmeister/kafka:2.12-2.4.0
   docker pull zookeeper:3.5.6
   ansible-playbook -i openness_adi_inventory.ini playbooks/usecase/usecases.yml
   ```

# Troubleshooting during ADI Deployment

1. Pexpect Install Error<br>
   Run following command on all Kubernetes nodes:
   ```
   # The pexpect version is defined in usecase.yml
   /usr/bin/pip2 install -i https://pypi.tuna.tsinghua.edu.cn/simple pexpect==3.3
   ```
2. FFMPEG Command Failed due to error in mp4 file downloading<br>
   Firstly, we need to make sure the container can access GitHub to download something successfully, then if error happens, we can manually delete /usr/src/ad-insertion/volume incorrect file according to error information and run again.
 
   Here is the default volume folder tree:
   ```
   volume/
   ├── ad
   │   └── archive
   │       ├── car6.mp4
   │       ├── catfood.mp4
   │       └── travel6.mp4
   ├── .gitignore
   └── video
       └── archive
       └── .gitignor
   ```
3. Ad-Insertion Kafka or Analytics PODs are not running<br>
   Firstly look your Ansible execution results, if have some problems of check pods status and there not have K8s-master subsequent steps, then:
   ```
   # Prepare the following docker images.

   # If you don’t have local docker cache services setup
   docker pull docker.elastic.co/elasticsearch/elasticsearch-oss:6.8.1 

   # If you have local docker cache services setup
   docker pull elasticsearch/elasticsearch-oss:6.8.1

   docker pull wurstmeister/kafka:2.12-2.4.0
   docker pull zookeeper:3.5.6

   # Run below command on Kubernetes master
   # Check your K8s cluster coredns pods status.
   kubectl get pod -A |grep coredns 

   # If they are not running, please delete them and new pods will be generated again.
   kubectl delete pod -n kube-system $COREDNS1_NAME $COREDNS2_NAME

   # Delete Ad-Insertion K8s resources on K8s master host.
   cd /usr/src/ad-insertion/build && make stop_kubernetes

   # Check the "kubectl" binary file that whether it exists on your kubernets node(s), if not exist, you can copy it from kubernetes master.
   whereis kubectl
   scp /PATH/OF/kubectl $node_ip:/PATH

   # If your kubernetes node(s) firewalld is stopping, we also need to stop firewalld on kubernetes master.
   systemctl stop firewalld

   # Wait all pods completed correctly, then re-deploy the Ad-Insertion.
   ansible-playbook -i openness_adi_inventory.ini playbooks/usecase/usecases.yml
   ```

4. The task "build Host Kernel and VCA Driver" error when build VCAC related of something.
   ```
   # Remove the kubernetes node(s) (VCAC Host) VCAC-Host-build-folder.
   rm -rf /home/vca/VCAC-A/Intel_Media_Analytics_Host/build/

   # Then run again.
   ansible-playbook -i openness_adi_inventory.ini playbooks/orchestration/orchestration.yml -e "profile=basic"
   ``` 

5. The task "kubernetes/common : install packages" error when yum install kubernetes components.
   ```
   yum install -y kubelet-1.18.4 kubeadm-1.18.4 kubectl-1.18.4 # The corresponding version can be in the error or all.yml
   
   # If tips "Package does not match intended download" , you can directly install the package with the prompt, like this:
   "https://mirrors.tuna.tsinghua.edu.cn/kubernetes/yum/repos/kubernetes-el7-x86_64/Packages/cc3c8a1a046fc5cb1a690dd0673e631804194395d68de71c145c247bda0c79ab-kubeadm-1.18.4-1.x86_64.rpm: [Errno -1] Package does not match intended download. Suggestion: run yum --enablerepo=kubernetes clean metadata"

   yum install https://mirrors.tuna.tsinghua.edu.cn/kubernetes/yum/repos/kubernetes-el7-x86_64/Packages/cc3c8a1a046fc5cb1a690dd0673e631804194395d68de71c145c247bda0c79ab-kubeadm-1.18.4-1.x86_64.rpm
   
   ```

6. When build ad_insertion images occurred following error:
   ```
   [mov,mp4,m4a,3gp,3g2,mj2 @ 0x55d82dd16080] Format mov,mp4,m4a,3gp,3g2,mj2 detected only with low score of 1, misdetection possible!
   [mov,mp4,m4a,3gp,3g2,mj2 @ 0x55d82dd16080] moov atom not found
   archive/bottle-detection.mp4: Invalid data found when processing input
   make[2]: *** [content-provider/archive/CMakeFiles/build_ssai_content_provider_archive] Error 1
   make[1]: *** [content-provider/archive/CMakeFiles/build_ssai_content_provider_archive.dir/all] Error 2
   
   # This may cause some video files not to be downloaded completely
   cd /usr/src/ad-insertion/volume/video/archive

   # Check the file size.
   ls -l # Maybe there is some file size is 0, delete it.

   ```

7. The task "initilaze cluster" occured error when re-run ansible playbook.
   The reason for this error is that the kubernetes cluster is exist, but it's not ready in current.
   ```
   # Get kubernetes cluster status on k8s master
   kubectl cluster-info
   
   # If your kubernetes cluster is not ready, that may have the following reasons:
   
   # 1. The pod of kubernetes cluster component or related of kubernetes services is not running.
   kubectl get pod -A
   systemctl status kubelet
   systemctl status docker

   # 2. The service port is not open in firewalld.
   firewall-cmd --list-all # Check ports: 6443/tcp 2379-2380/tcp 10250-10252/tcp
   firewall-cmd --zone=public --add-port=6443/tcp --permanent # Premit the port 6443 through
   ```
