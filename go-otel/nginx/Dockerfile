FROM ccr.ccs.tencentyun.com/library/centos:latest

RUN rm -rf /etc/yum.repos.d/*

COPY repo/* /etc/yum.repos.d/

RUN yum install -y nginx && yum install -y nginx-module-otel


EXPOSE 80

STOPSIGNAL SIGQUIT

CMD ["/usr/sbin/nginx", "-g", "daemon off;"]