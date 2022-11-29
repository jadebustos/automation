##
## Initial ostree install
##

# set locale defaults for the Install
lang es_ES.UTF-8
keyboard es
timezone UTC

# initialize any invalid partition tables and destroy all of their contents
zerombr

# erase all disk partitions and create a default label
clearpart --all --initlabel

# automatically create xfs partitions with no LVM and no /home partition
autopart --type=plain --fstype=xfs --nohome

# installation will run in text mode
text

# activate network devices and configure with static ip
network --bootproto=static --ip=192.168.122.124 --netmask=255.255.255.0 --gateway=192.168.122.1 --nameserver=192.168.122.1 --hostname=rhel.example.com --noipv6

# Kickstart requires that we create default user 'core' with sudo
# privileges using password 'edge'
user --name=core --groups=wheel --password=edge --homedir=/var/home/core

# set up the OSTree-based install with disabled GPG key verification, the base
# URL to pull the installation content, 'rhel' as the management root in the
# repo, and 'rhel/8/x86_64/edge' as the branch for the installation
ostreesetup --nogpg --url=http://192.168.122.1/ostree-rhel8/repo/ --osname=rhel --remote=edge --ref=rhel/8/x86_64/edge

# reboot after installation is successfully completed
reboot --eject

%post

%end

%post

%end

%post

##
## Create a scale from zero systemd service for a container web
## server using socket activation
##

# create systemd user directories for rootless services, timers,
# and sockets
mkdir -p /var/home/core/.config/systemd/user/default.target.wants
mkdir -p /var/home/core/.config/systemd/user/sockets.target.wants
mkdir -p /var/home/core/.config/systemd/user/timers.target.wants
mkdir -p /var/home/core/.config/systemd/user/multi-user.target.wants

# define listener for socket activation
cat << EOF > /var/home/core/.config/systemd/user/container-httpd-proxy.socket
[Socket]
ListenStream=192.168.122.124:8080
FreeBind=true

[Install]
WantedBy=sockets.target
EOF

# define proxy service that launches web container and forwards
# requests to it
cat << EOF > /var/home/core/.config/systemd/user/container-httpd-proxy.service 
[Unit]
Requires=container-httpd.service
After=container-httpd.service
Requires=container-httpd-proxy.socket
After=container-httpd-proxy.socket

[Service]
ExecStart=/usr/lib/systemd/systemd-socket-proxyd 127.0.0.1:8080
EOF

##
## Create a service to launch the container workload and restart
## it on failure
##

cat > /var/home/core/.config/systemd/user/container-httpd.service <<EOF
# container-httpd.service
# autogenerated by Podman 3.0.2-dev
# Thu May 20 10:16:40 EDT 2021

[Unit]
Description=Podman container-httpd.service
Documentation=man:podman-generate-systemd(1)

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=/bin/rm -f %t/container-httpd.pid %t/container-httpd.ctr-id
ExecStart=/usr/bin/podman run --conmon-pidfile %t/container-httpd.pid --cidfile %t/container-httpd.ctr-id --cgroups=no-conmon --replace -d --label io.containers.autoupdate=image --name httpd -p 127.0.0.1:8080:8081 quay.io/rhte_2019/2048-demoday:latest
ExecStartPost=/bin/sleep 1
ExecStop=/usr/bin/podman stop --ignore --cidfile %t/container-httpd.ctr-id -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/container-httpd.ctr-id
PIDFile=%t/container-httpd.pid
Type=forking
EOF

##
## Create a service and timer to periodically check if the container
## image has been updated and then, if so, refresh the workload
##

# podman auto-update looks up containers with a specified
# "io.containers.autoupdate" label (i.e., the auto-update policy).
#
# If the label is present and set to “image”, Podman reaches out
# to the corresponding registry to check if the image has been updated.
# An image is considered updated if the digest in the local storage
# is different than the one in the remote registry. If an image must
# be updated, Podman pulls it down and restarts the systemd unit
# executing the container.

cat > /var/home/core/.config/systemd/user/podman-auto-update.service <<EOF
[Unit]
Description=Podman auto-update service
Documentation=man:podman-auto-update(1)

[Service]
ExecStart=/usr/bin/podman auto-update

[Install]
WantedBy=multi-user.target default.target
EOF

# This timer ensures podman auto-update is run every minute
cat > /var/home/core/.config/systemd/user/podman-auto-update.timer <<EOF
[Unit]
Description=Podman auto-update timer

[Timer]
# This example runs the podman auto-update daily within a two-hour
# randomized window to reduce system load
#OnCalendar=daily
#Persistent=true
#RandomizedDelaySec=7200

# activate every minute
OnBootSec=30
OnUnitActiveSec=30

[Install]
WantedBy=timers.target
EOF

# pre-pull the container images at startup to avoid delay in http response
cat > /var/home/core/.config/systemd/user/pre-pull-container-image.service <<EOF
[Service]
Type=simple
ExecStart=podman pull quay.io/rhte_2019/2048-demoday:latest
RestartSec=30
Restart=on-failure

[Install]
WantedBy=multi-user.target default.target
EOF

# enable socket listener
ln -s /var/home/core/.config/systemd/user/container-httpd-proxy.socket /var/home/core/.config/systemd/user/sockets.target.wants/container-httpd-proxy.socket

# enable timer
ln -s /var/home/core/.config/systemd/user/podman-auto-update.timer /var/home/core/.config/systemd/user/timers.target.wants/podman-auto-update.timer

# enable pre-pull container image
ln -s /var/home/core/.config/systemd/user/pre-pull-container-image.service /var/home/core/.config/systemd/user/default.target.wants/pre-pull-container-image.service
ln -s /var/home/core/.config/systemd/user/pre-pull-container-image.service /var/home/core/.config/systemd/user/multi-user.target.wants/pre-pull-container-image.service

# fix ownership of user local files and SELinux contexts
chown -R core: /var/home/core
restorecon -vFr /var/home/core

# enable linger so user services run whether user logged in or not
cat << EOF > /etc/systemd/system/enable-linger.service
[Service]
Type=oneshot
ExecStart=loginctl enable-linger core

[Install]
WantedBy=multi-user.target default.target
EOF

/usr/bin/systemctl enable enable-linger.service

# enable 8080 port through the firewall to expose the application
/usr/bin/cat << EOF > /etc/systemd/system/expose-application.service
[Unit]
Wants=firewalld.service
After=firewalld.service

[Service]
Type=oneshot
ExecStart=firewall-cmd --permanent --add-port=8080/tcp 
ExecStartPost=firewall-cmd --reload

[Install]
WantedBy=multi-user.target default.target
EOF

/usr/bin/systemctl enable expose-application.service

# sudo configuration for core user
/usr/bin/cat << EOF > /etc/sudoers.d/core
core    ALL=(ALL) NOPASSWD: ALL
EOF

/usr/bin/chmod 0644 /etc/sudoers.d/core
/usr/bin/chown root. /etc/sudoers.d/core
/usr/bin/chcon -t etc_t /etc/sudoers.d/core

# public key configuration for core user
/usr/bin/mkdir -p /var/home/core/.ssh
/usr/bin/chmod 0700 /var/home/core/.ssh

/usr/bin/cat << EOF > /var/home/core/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCvPl4Aof9kRJPDgSKphNV4WAX7kNMcBVwsevuqCJphqmoLHS2onMiZRgcYJV6neKcFzB+kTOKhVzorC8uWNO5K+bTCeF0XkPeDrpCckatYVMtApWhvuqBTwER5x4i2mXAoEfJKNmgZkK3a6/bFdup9nXFi183ZAxaJJPXtkXZRA4dYiRDxKcWdcndDKGM+mFZD6R9en7Up38a4SZsYxCA/MX123ozYurLPniKXL2D4p+pioriCGVLX5BpiCiMrglaHX1XzBUmbHePWDxUoCzKCiD2LVDWZKK3McAXzzOOwMJeTq6GI0wA4FQlpAg9W+aCsCWyiySumS/PFTUGXwbnWI44YJN+H0ywlUWIeP5IsDMGqiYBcXPjdg96tYIY8ueEUbIRf13FLJQlsxCLBNiWwSB08JwJwAD06N3fiWAkJ/weQsNEQeLU7RSJxX0YlmZDr4r+MTnS02A2CcDaA0CfB4M93kJYQX8bk8S+dav7bis8CMsQ7Z+zGXvwrmPOtYRGTKqRPRvgJRj9xVuwuPZvuBkNj7zTLqQCdedC4u5xyc1byl1xcGDSs6Ef//KB4/AJfAf295N6/wYJzd7DZB8AdHuQiLEgAnUgDB8aSrHVjGlzzHZmpZdapVYSOPNBEqxR5ejF1ZQqDpCDV+bSanflUMpR2XIDiv0ayY7LTly9+Xw== jadebustos@euler.jadbp.lab
EOF

/usr/bin/chmod 0644 /var/home/core/.ssh/authorized_keys
/usr/bin/chcon -Rt ssh_home_t /var/home/core/.ssh
/usr/bin/chown -R core. /var/home/core/.ssh
%end

%post

/usr/bin/systemctl enable cockpit.socket
%end

%post

##
## Create a greenboot script to determine if an upgrade should
## succeed or rollback. At startup, the script writes the ostree commit
## hash to the files orig.txt, if it doesn't already exist, and
## current.txt, whether it exists or not. The two files are then
## compared. If those files are different, the upgrade fails after
## three attempts and the ostree image is rolled back. A upgrade can
## be allowed to succeed by deleting the orig.txt file prior to the
## upgrade attempt.
##

mkdir -p /etc/greenboot/check/required.d
cat > /etc/greenboot/check/required.d/01_check_upgrade.sh <<EOF
#!/bin/bash

rpm -qa | bind-utils grep  > /dev/null 2>&1
rc=$?

if [ $rc -eq 0 ]
then
  exit 0  
fi

exit 1
EOF

chmod +x /etc/greenboot/check/required.d/01_check_upgrade.sh
%end