FROM alpine:3.20
RUN apk add --no-cache tinyproxy
COPY tinyproxy.conf.tmpl /etc/tinyproxy/tinyproxy.conf.tmpl
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
USER nobody
ENTRYPOINT ["/entrypoint.sh"]
