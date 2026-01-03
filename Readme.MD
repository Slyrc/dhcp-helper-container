# DHCP-HELPER - "From scratch container"

Original software created by: https://thekelleys.org.uk/dhcp-helper/
Simon Kelley  <simon@thekelleys.org.uk>

This version contains slight improvments for using it with a DHCP server in Kubernetes e.g.: Pihole.

**Disclaimer: Please be careful! I am not responsible if you crash/damage your system using any of the commands/tools provided in this repo!**

## Goal: 

Create a small minimall container which only holds static dhcp-helper bin.
Get a container size which is smaller than 0.1mb.

Optional - make it run as non root.

We use musl to build a static bin. Afterwards dhcp_helper is only 130K!!
This static bin can now be used for our "from scratch" container.

```
Successfully pulled image "ghcr.io/slyrc/dhcp-helper:latest" in 356ms (356ms including waiting). Image size: 54970 bytes.
```

The end result is only: **54970 bytes!**

If you use the container linked to this repo, be aware that it is only arm64! If you need a different arch clone the repo and build it yourself.

## Important

You can not use the 

```
-u <user> flag
```

unless you add the user and group to the image as well. Currently only "nobody" is in the image. Check the Dockerfile.

## Example usage (In K8s/K3s) with root

The most common use case would be to run this container in your K8s/K3s cluster. It will then take your DHCP requests and forwards them into the cluster to the DHCP server.
This example requires that you run the container as root. The dhcp-helper will drop its privileges and go to user nobody.
This is the easiest example and basically directly usable out of the box.

We also have the option to run this as non root. **BUT** this requires more config and at least some basic knowledge about DHCP.
Check next section for non root option.

```
  #
  # DHCP relay -> forward dhcp request to pihole dhcp
  #
  apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: dhcp-relay
      namespace: pihole
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: dhcp-relay
      template:
        metadata:
          labels:
            app: dhcp-relay
          annotations:
            restart-trigger: "{{ now | quote }}"
        spec:
          # Needed because we need to listen to Broadcast which is not possible with kubernetes CNI
          hostNetwork: true
          # Needs to be always on that node as pi is responding with static ip of that node for the DHCP server
          nodeSelector:
            kubernetes.io/hostname: cube01
          dnsPolicy: ClusterFirstWithHostNet
          containers:
            - name: dhcp-relay
              image: ghcr.io/slyrc/dhcp-helper:latest
              imagePullPolicy: Always
              # Wait 65s to be sure old dhcp-relay is gone and pihole is ready
              args:
                - "-w"
                - "65"
                - "-n"
                - "-i"
                - "eth0"
                - "-s"
                - "pihole-dhcp.pihole.svc.cluster.local"
              securityContext:
                runAsUser: 0
                runAsGroup: 0
                allowPrivilegeEscalation: false
                capabilities:
                  drop: ["ALL"]
                  add:
                    - NET_BIND_SERVICE
                    - NET_ADMIN
                    - SETPCAP
                    - SETUID
                    - SETGID
              resources:
                limits:
                  cpu: 100m
                  memory: 100Mi
                requests:
                  cpu: 10m
                  memory: 50Mi
```

---

# Example usage (In K8s/K3s) with non root

Running dhcp-helper as non root is possible in certian configurations. Please note that I have not fully tested this over a long period of time.
Also I would not recommend using this out in the wild for production. May be fine at your HomeLab.

**NOTE I went deep into the rabbit hole** - This may not be for everyone.

We start by altering the actual deployment of the dhcp-helper to something like this:

```
  apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: dhcp-relay
      namespace: pihole
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: dhcp-relay
      template:
        metadata:
          labels:
            app: dhcp-relay
          annotations:
            restart-trigger: "{{ now | quote }}"
        spec:
          # Needed because we need to listen to Broadcast which is not possible with kubernetes CNI
          hostNetwork: true
          # Needs to be always on that node as pi is responding with static ip of that node for the DHCP server
          nodeSelector:
            kubernetes.io/hostname: cube01
          dnsPolicy: ClusterFirstWithHostNet
          containers:
            - name: dhcp-relay
              image: ghcr.io/slyrc/dhcp-helper:latest
              imagePullPolicy: Always
              # Wait 65s to be sure old dhcp-relay is gone and pihole is ready
              args:
                - "-w"
                - "65"
                - "-d"
                - "-p"
                - "-n"
                - "-i"
                - "eth0"
                - "-s"
                - "pihole-dhcp.pihole.svc.cluster.local"
              securityContext:
                runAsUser: 65534
                runAsGroup: 65534
                allowPrivilegeEscalation: false
                capabilities:
                  drop: ["ALL"]
              resources:
                limits:
                  cpu: 100m
                  memory: 100Mi
                requests:
                  cpu: 10m
                  memory: 50Mi
```

When checking now the securityContext of the container you see that we run as user "nobody" and drop all capabilities. This brings us into a very special situation:

We are now not allowed to bind on ports which are marked as "privileged". You can check on your system what port range is marked as privileged.

```shell
sysctl net.ipv4.ip_unprivileged_port_start
```

As for now (03.01.2026) Kubernetes still can not handle ambient CAPS. Because of that we need to work arround this and explore different solutions.
- https://github.com/kubernetes/kubernetes/issues/56374

It will probably return `net.ipv4.ip_unprivileged_port_start = 1024` - This means that we are not allowed to use ports > 1024.
Taking now DHCP we know it runs on 67/UDP, which is a privileged port. We have now several options:

1. Set `net.ipv4.ip_unprivileged_port_start = 0` allowing non root users to bin on all ports, setting `allowPrivilegeEscalation: true` and `CAP_NET_ADMIN`

2. Use `allowPrivilegeEscalation: true` and add `CAP_NET_BIND_SERVICE` as well as `CAP_NET_ADMIN`

3. Keep `allowPrivilegeEscalation: false` and drop all capabilities - **BUT** change dhcp-helper to use alternate ports. (1067 and 1068) - As well as some custom DHCP server settings to avoid using `CAP_NET_ADMIN`

(Note - Option 1 and 2 could also be used with special DHCP server config to avoid using `CAP_NET_ADMIN`)
We will focus here on version 3. - Please note that the Deployment here is using version 3.

Chaning the ports for DHCP helper to 1067 and 1068 introduces a problem, as DHCP uses port 67/68.
We can work arround that by using `tc` - `Linux Traffic Control`.

## DHCP via dhcp-helper (hostNetwork) + tc port remap (67/68 ↔ 1067/1068)
(With Pi-hole/dnsmasq DHCP also running on alternate ports 1067/1068)!!!

This setup solves the classic problem:
- DHCPv4 relies on broadcasts and privileged UDP ports 67/68.
- In Kubernetes/CNI environments, DHCP broadcast + privileged ports can be awkward/unreliable.
- We run dhcp-helper as a Pod with hostNetwork: true, using alternate ports 1067/1068.
- We run Pi-hole/dnsmasq DHCP in the cluster also on alternate ports 1067/1068.
  - Pi-hole/dnsmasq also needs the config: dhcp-broadcast!! -> https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html
    This is they key to run the pod with - "drop all capabilities" as we skip ARP insert for normal unkown clients
    and always use broadcast --- check here: https://github.com/Slyrc/dhcp-helper-container/blob/0112f001b3f98e5c1e7d4c633efc3ae7bb9d13aa/src/dhcp-helper.c#L591
- On the node, we use tc to rewrite LAN-facing DHCP ports:
  - Ingress (LAN → node): dst_port 67 → 1067
  - Egress  (node → LAN): src_port 1067 → 67 and dst_port 1068 → 68

Key idea:
The LAN always speaks “real DHCP” (67/68).
Inside the node/pods/cluster we speak “alt DHCP” (1067/1068).
tc is the translator at the LAN edge.

---

## Ports / terminology

Standard DHCPv4 (LAN side)
- Client → Server: UDP 68 → 67
- Server → Client: UDP 67 → 68

Alternate ports (internal: dhcp-helper and dnsmasq)
- Client → Helper (after ingress rewrite): UDP 68 → 1067  (only dport changes)
- Helper → Client (before egress rewrite): UDP 1067 → 1068
- Pi-hole/dnsmasq DHCP server listens on: UDP 1067 (server) / uses 1068 (client)

Host interface
- e.g. eth0

---

## What the node tc script does (exactly)

### Ingress rules (LAN → dhcp-helper)
Match only DHCP client requests:
- ip_proto udp
- src_port 68
- dst_port 67
- dst_ip is one of:
  - 255.255.255.255 (limited broadcast)
  - <LAN_BCAST>     (directed broadcast, e.g. 192.168.178.255)
  - <NODE_IP>       (some clients renew via unicast to the server/relay IP)

Action:
- rewrite dst_port 67 → 1067
- fix checksums (csum)

Result:
- dhcp-helper receives DHCP requests on UDP 1067.

### Egress rules (dhcp-helper → LAN)
Match only dhcp-helper’s alt-port replies:
- ip_proto udp
- src_port 1067
- dst_port 1068
- dst_ip is one of:
  - 255.255.255.255 (broadcast replies)
  - <LAN_CIDR>      (unicast replies into the LAN subnet)
- extra safety check
  - src_ip = <NODE_IP>  (avoid rewriting unrelated traffic)

Action:
- rewrite src_port 1067 → 67
- rewrite dst_port 1068 → 68
- fix checksums (csum)

Result:
- LAN clients see normal DHCP replies on UDP 67 → 68.

---

## Packet flow (ASCII diagram)

Legend:
- --> packet direction
- [tc INGRESS] / [tc EGRESS] show where rewrites happen
- 67→1067 means “port rewritten”
- (host) = Linux node
- (pod)  = Kubernetes Pod (hostNetwork)
- (svc)  = Kubernetes Service / DNS name

### 1) Client gets/renews a lease (DISCOVER/REQUEST)

LAN Client<br />
  |<br />
  | UDP 68 --> 67<br />
  |   dst_ip: 255.255.255.255  (limited broadcast)<br />
  |   OR dst_ip: <LAN_BCAST>   (directed broadcast)<br />
  |   OR dst_ip: <NODE_IP>     (some renewals)<br />
  v<br />
+--------------------------------------------------------------+<br />
| (host) Node / eth0                                           |<br />
|                                                              |<br />
|  [tc INGRESS]                                                |<br />
|   match: udp src_port=68 dst_port=67                         |<br />
|          dst_ip in {255.255.255.255, <LAN_BCAST>, <NODE_IP>} |<br />
|   action: dport 67 --> 1067                                  |<br />
|                                                              |<br />
+--------------------------------------------------------------+<br />
  |<br />
  | UDP 68 --> 1067   (now targets helper’s alt server port)<br />
  v<br />
+--------------------------------------------------------------+<br />
| (pod) dhcp-helper (hostNetwork: true)                        |<br />
|   listens on UDP 1067 (alt server port)                      |<br />
|   relays request (sets giaddr)                               |<br />
|   forwards to DHCP server using alt ports too                |<br />
+--------------------------------------------------------------+<br />
  |<br />
  | UDP 1068 --> 1067   (forward to DHCP server in-cluster)<br />
  v<br />
+--------------------------------------------------------------+<br />
| (svc/pod) Pi-hole / dnsmasq DHCP (ALT PORT MODE)             |<br />
|   listens on UDP 1067                                        |<br />
|   replies from UDP 1067 --> 1068                             |<br />
+--------------------------------------------------------------+<br />

### 2) Server replies (OFFER/ACK) back to the client

Pi-hole / dnsmasq<br />
  |<br />
  | UDP 1067 --> 1068   (alt ports)<br />
  v<br />
+--------------------------------------------------------------+<br />
| (pod) dhcp-helper (hostNetwork)                              |<br />
|   sends towards LAN using alt ports:                         |<br />
|     UDP 1067 --> 1068                                        |<br />
+--------------------------------------------------------------+<br />
  |<br />
  v<br />
+--------------------------------------------------------------+<br />
| (host) Node / eth0                                           |<br />
|                                                              |<br />
|  [tc EGRESS]                                                 |<br />
|   match: udp src_port=1067 dst_port=1068                     |<br />
|          src_ip=<NODE_IP>                                    |<br />
|          dst_ip=255.255.255.255 OR dst_ip in <LAN_CIDR>      |<br />
|   action: sport 1067 --> 67                                  |<br />
|           dport 1068 --> 68                                  |<br />
|                                                              |<br />
+--------------------------------------------------------------+<br />
  |<br />
  | UDP 67 --> 68   (back to real DHCP on the wire)<br />
  v<br />
LAN Client receives OFFER/ACK<br />

---

## Why the egress dst_ip match does NOT break renewals

Renewals are often unicast once a client is configured.
That is why egress rules allow:
- dst_ip in <LAN_CIDR>  (unicast replies still match and get rewritten)

Broadcast replies are covered by:
- dst_ip = 255.255.255.255

So both cases work:
- “client not configured yet” (broadcast)
- “client has an IP and renews” (unicast)

---

## Debug / verification

tc counters (shows whether filters match)
```bash
sudo tc -s filter show dev eth0 ingress
sudo tc -s filter show dev eth0 egress
```

## Use the tc script

If your plan is to use this, find the script attached here in the repo.
You would need to execute the script as root. I would recommend to have this in autostart of your node. E.g.: runit stage 2.

Remember that you need to use alt ports on dhcp-helper and the pihole dhcp!

## End

Changes and any improvments are welcome :)
