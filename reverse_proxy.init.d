
#!/sbin/openrc-run

name="reverse_proxy"
description="Proxy Reverso Docker Compose Service"

command="/usr/bin/docker-compose"
command_args="-f /docker/reverse_proxy/docker-compose.yml up -d"
pidfile="/run/${RC_SVCNAME}.pid"

start() {
    ebegin "Starting ${name}"
    /usr/bin/docker-compose -f /docker/reverse_proxy/docker-compose.yml up -d
    eend $?
}

stop() {
    ebegin "Stopping ${name}"
    /usr/bin/docker-compose -f /docker/reverse_proxy/docker-compose.yml down
    eend $?
}
