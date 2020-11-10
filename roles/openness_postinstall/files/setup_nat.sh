#!/bin/bash -e

for nodeinfo in $(vcactl config-show | awk '/host-ip:/{hi=$2}/host-mask:/{hm=$2;print ip","hi"/"hm}$1=="ip:"{ip=$2}'); do
    # Setup network
    nodenet=$(echo $nodeinfo | cut -f2 -d,)
    nodeint=$(sudo ip -4 address show | awk -v net=$nodenet '/^[0-9]+:/{name=$2}/inet /&&$2==net{print name}' | cut -f1 -d:)
    iptables -t nat -A POSTROUTING -s $nodenet -d 0/0 -j MASQUERADE
    iptables -I FORWARD -j ACCEPT -i $nodeint
    iptables -I FORWARD -j ACCEPT -o $nodeint

done