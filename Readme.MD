# DHCP-HELPER - "From scratch container"

## Goal: 

Get a small minimall container which only holds static dhcp-helper bin.
In the end the container is less then 0.1mb.

We use musl to build a static bin. Afterwards dhcp_helper is only 129.4K!!

This static bin can now be used for our "from scratch" container.

```
Successfully pulled image "ghcr.io/slyrc/dhcp-helper:latest" in 646ms (646ms including waiting). Image size: 54588 bytes.
```

The end result: **54588 bytes!**

If you use the container linked to this repo be aware that it is only arm64! If you need a different arch clone the repo and build it yourself.

## Important

You can not use the 

```
-u <user> flag
```

unless you add the user and group to the image as well. Currently only "nobody" is in the image. Check the Dockerfile.

## Example usage (In K8s)

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
