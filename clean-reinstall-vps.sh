#!/bin/bash
set -euo pipefail

cd /root/viper-script-main
chmod +x installer.sh ErwanScript/ErwanTCP.sh

mkdir -p /run/sshd /etc/systemd/system/ssh.service.d
ssh-keygen -A >/dev/null 2>&1 || true
cat > /etc/systemd/system/ssh.service.d/override.conf <<'EOF'
[Service]
ExecStartPre=
ExecStart=
ExecReload=
ExecStartPre=/usr/sbin/sshd -t -f /etc/ssh/sshd_config
ExecStart=/usr/sbin/sshd -D -f /etc/ssh/sshd_config
ExecReload=/usr/sbin/sshd -t -f /etc/ssh/sshd_config
ExecReload=/bin/kill -HUP $MAINPID
EOF
systemctl daemon-reload
/usr/sbin/sshd -t -f /etc/ssh/sshd_config
systemctl restart ssh

for service in \
    ErwanDNSTT ErwanDNS ErwanWS ErwanTCP ErwanTLS xray stunnel4 udp udp2 \
    openvpn-server@tcp openvpn-server@udp badvpn-udpgw ddos \
    erwan-dns-forwarding erwanssh; do
    systemctl disable --now "$service" >/dev/null 2>&1 || true
done

rm -rf \
    /etc/ErwanScript \
    /etc/ErwanSSH \
    /etc/xray \
    /etc/udp \
    /etc/openvpn/server \
    /etc/openvpn/configs \
    /etc/openvpn/certificates \
    /var/www/html/openvpn

rm -f \
    /usr/bin/menu \
    /usr/bin/extenduser \
    /usr/bin/checkuser \
    /usr/bin/activelogins \
    /usr/bin/xray-menu \
    /lib/systemd/system/ErwanDNS.service \
    /lib/systemd/system/ErwanDNSTT.service \
    /lib/systemd/system/ErwanWS.service \
    /lib/systemd/system/ErwanTCP.service \
    /lib/systemd/system/ErwanTLS.service \
    /lib/systemd/system/badvpn-udpgw.service \
    /etc/systemd/system/xray.service \
    /etc/systemd/system/udp.service \
    /etc/systemd/system/udp2.service \
    /etc/systemd/system/ddos.service \
    /etc/systemd/system/erwan-dns-forwarding.service \
    /etc/systemd/system/erwanssh.service \
    /etc/systemd/system/stunnel4.service \
    /etc/systemd/system/erwan-openvpn-nat.service \
    /etc/cron.d/account-expiry \
    /etc/cron.d/xray-limit \
    /etc/cron.d/useradd-limit \
    /etc/cron.d/udp-limit \
    /etc/cron.d/erwan-restart \
    /etc/stunnel/stunnel.conf \
    /etc/stunnel/stunnel.crt \
    /etc/stunnel/stunnel.key \
    /etc/profile.d/erwan.sh

rm -f /etc/nginx/conf.d/*.conf
systemctl daemon-reload

echo "CLEAN_DONE"
REBOOT_AFTER_INSTALL=0 BUILD_ERWANSSH_RUNTIME=auto bash installer.sh
