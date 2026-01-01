FROM alpine:latest AS builder

USER root

RUN apk add --no-cache build-base linux-headers git && \
    cd /root && git clone https://github.com/Slyrc/dhcp-helper && \
    cd ./dhcp-helper/src && make && \
    echo "nobody:x:65534:65534:nobody:/:/sbin/nologin" > passwd && \
    echo "nobody:x:65534:" > group

FROM scratch

COPY --from=builder \
  /root/dhcp-helper/src/dhcp-helper /dhcp-helper \
  /root/dhcp-helper/src/passwd /etc/passwd \
  /root/dhcp-helper/src/ /etc/group

EXPOSE 67/udp

ENTRYPOINT ["/dhcp-helper"]
