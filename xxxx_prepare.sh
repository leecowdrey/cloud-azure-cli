#!/bin/bash
[[ $(id -u) -ne 0 ]] && exit 1
USERNAME="${1:-telco}"
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
apt-get install -y locales-all apt-transport-https apt-transport-https ca-certificates curl unzip sshpass gnupg lsb-release software-properties-common bridge-utils dnsutils snapd jq yamllint net-tools sudo python3-pip

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

# Fix FQDN (Ubuntu cloud-init on 18.04 broken)
hostnamectl set-hostname ${FQDN}
hostnamectl status
hostname ${FQDN}

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
	echo -e "UUID=${DISKUUID}\t/backing_store\text4\tdefaults,nofail\t1\t2" | tee -a /etc/fstab
	systemctl daemon-reload
	mkdir -p /backing_store
	chmod 755 /backing_store
	chown ${USERNAME}:${USERNAME} /backing_store && \
	mount -t ext4 /dev/sdc1 /backing_store
fi

# Fix additional custom IP route for destination spoke site as cant set via cloudinit
# from xxxx, polt (user:root,password:root) can be verified via: ssh -p 10830 root@172.16.49.12 -s netconf
#
cat <<EOF6 > /etc/systemd/system/route.service
[Unit]
Description=IP Route Updater
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
Group=root
StandardOutput=append:/var/log/route.log
StandardError=append:/var/log/route.log
ExecStart=/sbin/ip route add 172.16.49.0/24 via 172.16.50.9 dev eth1

[Install]
WantedBy=multi-user.target
EOF6
systemctl daemon-reload && \
systemctl enable route.service && \
systemctl start route.service && \
systemctl status route.service

# Add user to sudo list
echo -e "${USERNAME,,}\tALL=(ALL:ALL) NOPASSWD:ALL" /etc/sudoers.d/${USERNAME,,}
chmod 440 /etc/sudoers.d/${USERNAME,,}

# XXXX prereq
groupadd -f microk8s
usermod -a -G microk8s ${USERNAME}

#
exit
