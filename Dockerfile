FROM ubuntu

WORKDIR /usr/src/app

# If needed, you can set your proxy in ENV lines, or use proxy as build parameters:
# docker build --build-arg http_proxy=http://yourproxy:8080 --build-arg https_proxy=http://yourproxy:8080 -t local/k8s-network-test-daemonset:0.1 .
#ENV http_proxy=http://yourproxy:8080
#ENV https_proxy=http://yourproxy:8080

# setting for apt-get install
ENV DEBIAN_FRONTEND=noninteractive

# Install some network tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends apt-utils&& \
    apt-get install -y --no-install-recommends python curl jq net-tools iputils-ping time cron dnsutils && \
    rm -rf /var/lib/apt/lists/*

ENV http_proxy=
ENV https_proxy=

COPY *.sh ./
RUN chmod 755 *.sh 

EXPOSE 8123:8123

ADD crontab /etc/crontab
RUN chmod 0644 /etc/crontab

CMD [ "/usr/src/app/entrypoint.sh" ]

