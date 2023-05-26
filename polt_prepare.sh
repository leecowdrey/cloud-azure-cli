#!/bin/bash
[[ $(id -u) -ne 0 ]] && exit 1
USERNAME="${1:-vendor}"
NLG="${2:-en_GB}"
NTZ="${3:-Europe/London}"
SSHP=${4:-22}
HELM_VERSION="v3.10.0"
FQDN="${5:-polt}"
export DEBIAN_FRONTEND=noninteractive
export LANG="${NLG}.UTF-8"
export LANGUAGE="${NLG}.UTF-8"
export LC_ALL="${NLG}.UTF-8"

# user SSH adjustments
mkdir -m 700 -p /home/${USERNAME}/.ssh
cat <<EOF1 > /home/${USERNAME}/.ssh/config
Host *
    VerifyHostKeyDNS no
EOF1
chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.ssh/config && chmod 600 /home/${USERNAME}/.ssh/config

# Core OS Packages
apt-get -y update ; apt-get -y dist-upgrade ; apt-get -y autoremove ; apt-get -y autoclean
apt-get install -y locales-all apt-transport-https apt-transport-https ca-certificates curl unzip sshpass gnupg lsb-release software-properties-common jq i2c-tools dnsutils

# Locale and Time zone
timedatectl set-timezone ${NTZ}
echo "LANG=${NLG}.UTF-8" > /etc/default/locale
sed -i -e "s/# ${NLG}.*/${NLG} UTF-8/" /etc/locale.gen
dpkg-reconfigure -f noninteractive locales
update-locale LANG=${NLG}.UTF-8
cat <<EOF2 > /etc/profile.d/00-locale.sh
#!/bin/bash
export LANG="${NLG}.UTF-8"
export LANGUAGE="${NLG}.UTF-8"
export LC_ALL="${NLG}.UTF-8"
EOF2
chmod 644 /etc/profile.d/00-locale.sh

# Fix hosts file
sed -i -e "s/127.0.0.1.*/127.0.0.1 localhost pon-dockerrepo.broadbus.com pon-dockerrepo/" /etc/hosts

# Fix FQDN (Ubuntu cloud-init on 18.04 broken)
hostnamectl set-hostname ${FQDN}
hostnamectl status
hostname ${FQDN}

# Fix network - libivrt/KVM Bridge setup (post cloud-init hack)
ETH0_ETHER=$(ifconfig eth0|grep ether|grep -o -E ..:..:..:..:..:..)
cat <<EOF3 > /etc/network/interfaces
auto eth0
allow-hotplug eth0
iface eth0 inet manual
#iface eth0 inet dhcp
#iface eth0 inet6 manual
#  try_dhcp 1
auto br0
iface br0 inet dhcp
  bridge_ports eth0
  bridge_hw ${ETH0_ETHER}
  bridge_stp off
  bridge_waitport 0
  bridge_fd 0
EOF3

# shared memory fstab
# tmpfs /dev/shm tmpfs defaults,nodev,nosuid,noexec 0 0

# kernel sysctl
cat <<EOF4 >> /etc/sysctl.conf
net.bridge.bridge-nf-call-ip6tables=0
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-arptables=0
kernel.randomize_va_space=2
fs.suid_dumpable=0
EOF4

#
dmesg|grep sdc|head -1 &> /dev/null
if [ $? -eq 0 ] ; then
	fdisk /dev/sdc <<EOF5
g
n
1


w
EOF5
	mkfs.ext4 -F /dev/sdc1
	partprobe /dev/sdc1
	DISKUUID=$(blkid -o value -s UUID /dev/sdc1)
	echo -e "UUID=${DISKUUID}\t/datadisk\text4\tdefaults,nofail\t1\t2" | tee -a /etc/fstab
	systemctl daemon-reload
	mkdir -p /datadisk
	chmod 755 /datadisk
	mount -t ext4 /dev/sdc1 /datadisk && \
	mv -f /srv /datadisk/ && \
	ln -s /datadisk/srv /srv && \
	mkdir -p /datadisk/persist && \
	chown ${USERNAME}:${USERNAME} /datadisk/persist && \
	ln -s /datadisk/persist /persist && \
	mv -f /opt /datadisk/ && \
	ln -s /datadisk/opt /opt && \
	mv -f /home /datadisk/ && \
	ln -s /datadisk/home /home
fi


# POLT dependencies
useradd --home-dir /home/labuser --groups ${USERNAME} --create-home --shell /sbin/nologin labuser
echo "labuser:Broadbus1"|chpasswd
usermod -L labuser

# Python 3.8 is required and not the default in UbuntuServer 18.04
if [[ $(lsb_release --release --short) =~ .*18\.04.* ]] ; then
  add-apt-repository -y ppa:deadsnakes/ppa
  apt-get -y update
  apt-get install -y python3.8
  update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 1
  update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8 2
  rm -f /usr/bin/python3 &> /dev/null
  ln -s /usr/bin/python3.6 /usr/bin/python3
fi
apt-get install -y python3-apparmor python3-apport python3-apt python3-aptdaemon python3-asn1crypto python3-blinker python3-certifi python3-cffi-backend python3-chardet python3-click python3-colorama python3-commandnotfound python3-crypto python3-cryptography python3-cups python3-cupshelpers python3-dbus python3-debianbts python3-defer python3-distupgrade python3-flask python3-gdbm python3-httplib2 python3-idna python3-jinja2 python3-minimal python3-pip python3-problem-report python3-psutil python3-pycurl python3-reportlab-accel python3-software-properties python3-update-manager python3-venv python3-xdg python3-virtualenv

# Install helm
[[ -f helm-v3.10.0-linux-amd64.tar.gz ]] && rm -f helm-v3.10.0-linux-amd64.tar.gz &> /dev/null
curl -sLO https://get.helm.sh/helm-v3.10.0-linux-amd64.tar.gz && \
tar -zxvf helm-v3.10.0-linux-amd64.tar.gz && \
mv -f linux-amd64/helm /usr/local/bin/helm && \
rm -R -f linux-amd64 &> /dev/null

# libvirt/KVM
if [[ $(egrep -c '(vmx|svm)' /proc/cpuinfo) -gt 0 ]] ; then
  apt-get install -y --no-install-recommends qemu-system libvirt-clients libvirt-daemon-system bridge-utils virtinst qemu-utils
  modprobe vhost_net
  virsh net-destroy default
  virsh net-undefine default
  GROUPS_ADD="libvirt,libvirt-qemu,docker"
else
  GROUPS_ADD="docker"
fi

# Docker
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
chmod a+r /etc/apt/keyrings/docker.gpg
apt-get -y update
apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# OS user group updates
usermod -aG ${GROUPS_ADD} ${USERNAME}
usermod -aG ${USERNAME},${GROUPS_ADD} labuser

# POLT environment prep
mkdir -p /home/${USERNAME}/deploy
chown ${USERNAME}:${USERNAME} /home/${USERNAME}/deploy
mkdir -p /home/labuser
chown labuser:${USERNAME} /home/labuser
chmod 775 /home/labuser
[[ -d /persist ]] && ( mkdir -p /persist/staging && chown ${USERNAME}:${USERNAME} /persist/staging)

#
exit
