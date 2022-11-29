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
network --bootproto=static --ip=192.168.122.124 --netmask=255.255.255.0 --gateway=192.168.122.1 --nameserver=192.168.122.1 --hostname=rhel.melmac.univ --noipv6

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