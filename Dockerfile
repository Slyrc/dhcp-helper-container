FROM alpine:latest AS builder

USER root

RUN apk add --no-cache build-base linux-headers git && \
    REPO_URL="https://github.com/Slyrc/dhcp-helper-container.git" && \
    git clone "$REPO_URL" /root/dhcp && \
    tag="$(git -C /root/dhcp describe --tags --abbrev=0 --match 'v[0-9]*' HEAD)" && \
    git -C /root/dhcp checkout "$tag" && make -C /root/dhcp/src && \
    echo "nobody:x:65534:65534:nobody:/:/sbin/nologin" > /root/passwd && \
    echo "nobody:x:65534:" > /root/group

FROM scratch

COPY --from=builder /root/dhcp/src/dhcp-helper /dhcp-helper
COPY --from=builder /root/passwd /etc/passwd
COPY --from=builder /root/group  /etc/group

EXPOSE 67/udp

ENTRYPOINT ["/dhcp-helper"]
