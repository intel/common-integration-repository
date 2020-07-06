```text
SPDX-License-Identifier: Apache-2.0       
Copyright (c) 2019 Intel Corporation
```


# Introduction
The aim of this document is to familiarize the user with the Common platform Integration use cases on-boarding process. This guide will provide instructions on how to configure and deploy typical use cases on Bare Metal Intel architecture platforms with Ansible.

# Use cases Applications
It is the responsibility of Related component team (current Visual cloud team mainly) to provide the application to be deployed on platform. The application must be provided in a format of Docker image available either from an external Docker repository (ie. Docker Hub) or a locally build/imported Docker image, which will be deployed with Kubernetes later.

You can refer to the [BKM](https://wiki.ith.intel.com/pages/viewpage.action?spaceKey=SDND&title=BMRA+Container+Deployment) for more tips which are kept updated.

Typical [visual cloud usage](https://github.com/OpenVisualCloud) repository provides images for the supported applications in this document. You can find more introduction in the OVC repo while this document will focus on the recipe and deployment of the use cases.

This document will explain the deployments of following use cases: 
1. Flannel: Non use cases here, only implement flannel network CNI based on BMRA. This can be the basic environment for later use cases.
2. SRIOV: Non use cases here, only implement SRIOV network CNI based on BMRA. This can be the basic environment for later use cases.
3. CDN: Content Delivery transcode Network deployment, focus on media transcode including live streaming and VOD service.
4. Smart City: SMTC implements aspects of smart city sensing, analytics and management feature.
5. ADI:AD insertion system, which features on-demand video transcoding and streaming, and AD insertion based on video content analysis.

# Cloud deployment with Flannel network
The deployment implements Flannel as network CNI based on BMRA. Following changes and steps are need:

1. Copy "inventory.ini" "group_vars" "hosts_vars" under example folder to your deployment home folder:
   ```
   cp common_platform/
   cp examples/inventory.ini ./
   cp -r examples/group_vars/ examples/host_vars/ ./
   ```

2. edit the inventorys according to your real needs:
   ```
   vi inventory.ini (add ips)
   ```

3. edit the config yaml for group_vars for "flannel" as following (compared with orignial file):
   ```
   sriov_net_dp_enabled: false
   cmk_shared_num_cores: 16
   cmk_exclusive_num_cores: 16
   qat_dp_enabled: false
   gpu_dp_enabled: false
   userspace_ovs_dpdk: false
   http_proxy: "http://proxy-chain.intel.com:912"
   https_proxy: "http://proxy-chain.intel.com:912"
   additional_no_proxy: "127.0.0.1,10.166.31.228,10.166.31.38,10.166.31.51,10.166.31.244,10.166.30.157"
   ```
 4. edit the config yaml for host_vars for all nodes(nodeX.yml):
    ```
    sriov_cni_enabled: false
    userspace_cni_enabled: false
    vpp_enabled: false
    ovs_dpdk_enabled: false
    isolcpus: "4-11"
    ```  
 5. Follow the normal steps of BMRA to continue the deployments:
    ```
    git submodule update --init
    ansible-playbook -i inventory.ini playbooks/cluster.yml 
    ``` 


# Cloud deployment with SRIOV network
The deployment implements Flannel as network CNI based on BMRA. Following changes and steps are need:

1. Copy "inventory.ini" "group_vars" "hosts_vars" under example folder to your deployment home folder:
   ```
   cp common_platform/
   cp examples/inventory.ini ./
   cp -r examples/group_vars/ examples/host_vars/ ./
   ```

2. edit the inventorys according to your real needs:
   ```
   vi inventory.ini (add ips)
   ```

3. edit the config yaml for group_vars for "SRIOV" as following (compared with orignial file):
   ```
   cmk_shared_num_cores: 8
   cmk_exclusive_num_cores: 8
   qat_dp_enabled: false
   gpu_dp_enabled: false
   sriov_net_dp: true
   http_proxy: "http://proxy-chain.intel.com:912"
   https_proxy: "http://proxy-chain.intel.com:912"
   additional_no_proxy: "127.0.0.1,10.166.31.228,10.166.31.38,10.166.31.51,10.166.31.244,10.166.30.157"
   kube_pods_subnet: 10.246.0.0/16
   ```
 4. edit the config yaml for host_vars for all nodes(nodeX.yml):
    ```
    sriov_enabled: true
    sriov_nics: [enp24s0f0,enp24s0f1]
    sriov_numvfs: 8
    sriov_cni_enabled: true
    sriov_net_dp_config:
    - pfnames: ["enp24s0f0"] # PF interface names - their VFs will be attached to specific driver
    driver: "i40evf" # available options: "i40evf", "vfio-pci", "igb_uio"
    - pfnames: ["enp24s0f1"] # PF interface names - their VFs will be attached to specific driver
    driver: "i40evf" # available options: "i40evf", "vfio-pci", "igb_uio"
    userspace_cni_enabled: false
    vpp_enabled: false
    ovs_dpdk_enabled: false
    force_nic_drivers_update: true
    isolcpus: "4-11"
    ```  

 5. Follow the normal steps of BMRA to continue the deployments:
    ```
    git submodule update --init
    ansible-playbook -i inventory.ini playbooks/cluster.yml 
    ``` 

# CDN Use case Deployment
The purpose of this section is to guide the user on the complete process of onboarding Sample Application, testing the deployment on platform.

Following steps are need:
1. Make sure Flannel deployment run successfully.
2. copy cdn_inventory.ini to your working folder and edit it with correct ips(k8s ips are same as previous Flannel deployment):
    ```
    cp examples/cdn_inventory.ini ./
    vi cdn_inventory.ini 
    ``` 
3. Update group_vars/usercase.yml:
    ```
    cdn_transcode_enabled: true 
    ```

4. Setup CDN based on flannel environment:
    ```
    ansible-playbook -i cdn_inventory.ini playbooks/usecase/usecases.yml 
    ```

5. Once the deployment is working successfully, you can check them with cmd on master "kubectl get pods" and get following pods running:
    ```
    cdn-service-8d5cc5997-wn4rm
    kafka-service-847c468f69-w8xzb
    live0-service-b5dd6ff4f-hhdqp
    redis-service-6d5d6987cc-ztfjl
    vod0-service-6b5558475b-mh642
    zookeeper-service-59dd57f8bf-pv9c2
    ```
6. Open the URL https://master_ip in Chrome, click the playlist, video can be played well.

# Smart City Use case deployment
The purpose of this section is to guide the user on the complete process of onboarding Sample Application, testing the deployment on platform.
SMTC has 2 kinds of deployment:
* SMTC Based on BMRA.
* SMTC plus Openness, which extend SMTC application to network edge.

## SMTC BMRA deployment
This deployment only implements network cloud deployment, Following steps are need:
1. Make sure Flannel deployment run successfully.
2. copy smtc_inventory.ini to your working folder and edit it with correct ips(k8s ips are same as previous Flannel deployment):
    ```
    cp examples/smtc_inventory.ini ./
    vi smtc_inventory.ini 
    ``` 
3. Update group_vars/usercase.yml:
    ```
    smtc_enabled: true
    openness_enabled: false
    ```

4. Setup SMTC based on flannel environment:
    ```
    ansible-playbook -i smtc_inventory.ini playbooks/usecase/usecases.yml 
    ```

5. Open the URL https://master_ip in Chrome, we can see all sensors and all analytics are available in the web.

## SMTC Openness deployment
This use case need implement network cloud and edge both. Following steps are need:
1. Make sure Flannel deployment run successfully.
2. copy smtc_inventory.ini to your working folder and edit it with correct ips(k8s ips are same as previous Flannel deployment):
    ```
    cp examples/smtc_inventory.ini ./
    vi smtc_inventory.ini 
    ``` 
3. Update group_vars/usercase.yml:
    ```
    smtc_enabled: true
    openness_enabled: true
    ```

4. Setup SMTC based on flannel environment:
    ```
    ansible-playbook -i smtc_inventory.ini playbooks/usecase/usecases.yml 
    ```

5. Open the URL https://bmra_master_ip in Chrome, we can see all sensors and all analytics are available in the web.

# ADI Use case deployment

This use case will guide user on how deploy for AD insertion use cases and following steps are need:
1. Make sure Flannel deployment run successfully.
2. copy adi_inventory.ini to your working folder and edit it with correct ips(k8s ips are same as previous Flannel deployment):
    ```
    cp examples/adi_inventory.ini ./
    vi adi_inventory.ini 
    ``` 
3. Update group_vars/usercase.yml:
    ```
    ad_insertion_enabled: true
    ```

4. Setup ADI based on flannel environment:
    ```
    ansible-playbook -i adi_inventory.ini playbooks/usecase/usecases.yml 
    ```

5. Open the URL https://master_ip in Chrome, click the playlist.