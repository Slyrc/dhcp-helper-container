#!/bin/sh
set -eu

DEV="eth0"
NODE_IP="192.168.178.201"
LAN_BCAST="192.168.178.255"
LAN_CIDR="192.168.178.0/24"

# Our dedicated prefs (high + recognizable)
P10=61010
P11=61011
P12=61012
P20=61020
P21=61021

# 1) Ensure clsact exists (DON'T wipe other qdiscs/filters)
tc qdisc add dev "$DEV" clsact 2>/dev/null || true

# 2) Delete ONLY our rules (by pref + type + protocol)
tc filter del dev "$DEV" ingress protocol ip pref "$P10" flower 2>/dev/null || true
tc filter del dev "$DEV" ingress protocol ip pref "$P11" flower 2>/dev/null || true
tc filter del dev "$DEV" ingress protocol ip pref "$P12" flower 2>/dev/null || true

tc filter del dev "$DEV" egress  protocol ip pref "$P20" flower 2>/dev/null || true
tc filter del dev "$DEV" egress  protocol ip pref "$P21" flower 2>/dev/null || true

# 3) Ingress: Client -> dhcp-helper
# DHCPv4 Client: UDP src 68 -> dst 67
# Rewrite ONLY dport: 67 -> 1067
# We also match dst_ip patterns to limit scope.

# a) Limited broadcast
tc filter add dev "$DEV" ingress protocol ip pref "$P10" flower \
  ip_proto udp src_port 68 dst_port 67 dst_ip 255.255.255.255 \
  action pedit munge ip dport set 1067 pipe \
  action csum ip and udp

# b) Directed broadcast (/24 bcast)
tc filter add dev "$DEV" ingress protocol ip pref "$P11" flower \
  ip_proto udp src_port 68 dst_port 67 dst_ip "$LAN_BCAST" \
  action pedit munge ip dport set 1067 pipe \
  action csum ip and udp

# c) Unicast renewals to node IP (some clients do this)
tc filter add dev "$DEV" ingress protocol ip pref "$P12" flower \
  ip_proto udp src_port 68 dst_port 67 dst_ip "$NODE_IP" \
  action pedit munge ip dport set 1067 pipe \
  action csum ip and udp

# 4) Egress: dhcp-helper -> Client
# dhcp-helper (altports): UDP src 1067 -> dst 1068
# Rewrite back to real DHCP ports: 67/68
# Add src_ip=$NODE_IP to ensure we only rewrite packets
# originating from this node.

# a) Broadcast replies
tc filter add dev "$DEV" egress protocol ip pref "$P20" flower \
  ip_proto udp src_ip "$NODE_IP" src_port 1067 dst_port 1068 dst_ip 255.255.255.255 \
  action pedit munge ip sport set 67 munge ip dport set 68 pipe \
  action csum ip and udp

# b) Unicast replies into LAN
tc filter add dev "$DEV" egress protocol ip pref "$P21" flower \
  ip_proto udp src_ip "$NODE_IP" src_port 1067 dst_port 1068 dst_ip "$LAN_CIDR" \
  action pedit munge ip sport set 67 munge ip dport set 68 pipe \
  action csum ip and udp


# Quick output of our counters
echo "=== TC ingress (counters) ==="
tc -s filter show dev "$DEV" ingress || true
echo
echo "=== TC egress (counters) ==="
tc -s filter show dev "$DEV" egress || true
