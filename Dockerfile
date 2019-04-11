FROM alpine

RUN apk --no-cache --no-progress upgrade && \
    apk --no-cache --no-progress add iptables bash ca-certificates curl && \
    mkdir -p /sample_config

COPY init.sh update.sh /
COPY cg.conf config.yml /sample_config/

RUN chmod +x /init.sh /update.sh && /update.sh

CMD ["/init.sh","daemon"]