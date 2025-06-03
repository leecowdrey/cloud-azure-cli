#!/bin/bash
[[ $(id -u) -ne 0 ]] && exit 1
USERNAME="${1:-vendor}"
NLG="${2:-en_GB}"
NTZ="${3:-Europe/London}"
SSHP=${4:-22}
AZ_AKS_REQUIRED_VERSION="1.24.6"
CEPH_HELM_VERSION="v3.10.0"

export DEBIAN_FRONTEND=noninteractive
export LANG=${NLG}
mkdir -m 700 -p /home/${USERNAME}/.ssh
cat <<EOF1 > /home/${USERNAME}/.ssh/config
Host *
	VerifyHostKeyDNS no
EOF1
apt-get -y update ; apt-get -y dist-upgrade ; apt-get -y autoremove ; apt-get -y autoclean
sed -i -e "s/# ${NLG}.*/${NLG} UTF-8/" /etc/locale.gen && dpkg-reconfigure -f noninteractive locales && update-locale LANG=${NLG}
timedatectl set-timezone ${NTZ}
apt-get install -y apt-transport-https apt-transport-https ca-certificates curl unzip sshpass notary yamllint python3 python3-pip ansible notary sed pwgen dnsutils sudo

echo -e "${USERNAME,,}\tALL=(ALL:ALL) NOPASSWD:ALL" /etc/sudoers.d/${USERNAME,,}
chmod 440 /etc/sudoers.d/${USERNAME,,}

curl -sL https://aka.ms/InstallAzureCLIDeb | bash
az aks install-cli --client-version "${AZ_AKS_REQUIRED_VERSION}"
curl -sLO https://get.helm.sh/helm-${CEPH_HELM_VERSION}-linux-amd64.tar.gz && tar -zxvf helm-${CEPH_HELM_VERSION}-linux-amd64.tar.gz && mv -f linux-amd64/helm /usr/local/bin/helm
rm -f helm-${CEPH_HELM_VERSION}-linux-amd64.tar.gz &> /dev/null
rm -R -f linux-amd64 &> /dev/null
chmod 755 /usr/local/bin/helm

curl -sLO https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && \
mv -f yq_linux_amd64 /usr/local/bin/yq
chmod 755 /usr/local/bin/yq

# Fix additional custom IP route for destination spoke site as cant set via cloudinit
# from bastion, polt (user:root,password:root) can be verified via: ssh -p 10830 root@172.16.49.12 -s netconf
#
cat <<EOF2 > /etc/systemd/system/route.service
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
ExecStart=/usr/bin/ip route add 172.16.49.0/24 via 172.16.50.9 dev eth0

[Install]
WantedBy=multi-user.target
EOF2
systemctl daemon-reload && \
systemctl enable route.service && \
systemctl start route.service && \
systemctl status route.service

# Docker
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
chmod a+r /etc/apt/keyrings/docker.gpg
apt-get -y update
apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# OS user group updates
usermod -aG docker ${USERNAME}

# az cli
curl -sL https://aka.ms/InstallAzureCLIDeb | bash
az aks install-cli --client-version "${AZ_AKS_REQUIRED_VERSION}"

# user environment prep
mkdir -p /home/${USERNAME}/.local /home/${USERNAME}/.local/bin /home/${USERNAME}/.local/lib
chown -${USERNAME}:${USERNAME} /home/${USERNAME}/.local /home/${USERNAME}/.local/bin /home/${USERNAME}/.local/lib

# update user path
#echo "[[ -d ~/.local.bin ]] && export PATH=~/.local/bin:\$PATH" >> /home/${USERNAME}/.bashrc

# anisble for Azure
su ${USERNAME} -c "python3 -m pip install --upgrade pip"
su ${USERNAME} -c "python3 -m pip install --user ansible"
su ${USERNAME} -c "python3 -m pip install netaddr packaging pathlib"
su ${USERNAME} -c "ansible-galaxy collection install community.crypto"
su ${USERNAME} -c "ansible-galaxy collection install azure.azcollection"
su ${USERNAME} -c "pip3 install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements-azure.txt"

#
exit
