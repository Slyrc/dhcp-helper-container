FROM alpine:latest as builder

USER root

RUN apk add --no-cache build-base linux-headers git && \
    cd /root && git clone https://github.com/Slyrc/dhcp-helper && \
    cd ./dhcp-helper/src && make 

FROM scratch

COPY --from=builder /root/dhcp-helper/src/dhcp-helper /dhcp-helper

EXPOSE 67/udp

ENTRYPOINT ["/dhcp-helper"]
