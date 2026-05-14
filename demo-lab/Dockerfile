FROM debian:12-slim

RUN apt-get update && apt-get install -y \
    openssh-server sudo procps iproute2 net-tools rsync tar gzip passwd cron \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash demo \
    && echo "demo ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/demo \
    && chmod 440 /etc/sudoers.d/demo

RUN mkdir -p /var/run/sshd /home/demo/.ssh \
    && chmod 700 /home/demo/.ssh \
    && chown -R demo:demo /home/demo/.ssh

COPY ssh/sysremote_demo.pub /home/demo/.ssh/authorized_keys

RUN chown demo:demo /home/demo/.ssh/authorized_keys \
    && chmod 600 /home/demo/.ssh/authorized_keys \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

CMD ["/usr/sbin/sshd", "-D"]
