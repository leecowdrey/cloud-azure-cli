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
apt-get install -y apt-transport-https apt-transport-https ca-certificates curl unzip sshpass notary

curl -sL https://aka.ms/InstallAzureCLIDeb | bash
az aks install-cli --client-version "${AZ_AKS_REQUIRED_VERSION}"
curl -sLO https://get.helm.sh/helm-${CEPH_HELM_VERSION}-linux-amd64.tar.gz && tar -zxvf helm-${CEPH_HELM_VERSION}-linux-amd64.tar.gz && mv -f linux-amd64/helm /usr/local/bin/helm
rm -f helm-${CEPH_HELM_VERSION}-linux-amd64.tar.gz &> /dev/null
rm -R -f linux-amd64 &> /dev/null
  
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

# user environment prep
mkdir -p /home/${USERNAME}/xxxx /home/${USERNAME}/vnf /home/${USERNAME}/pnf /home/${USERNAME}/backup
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/xxxx /home/${USERNAME}/vnf /home/${USERNAME}/pnf /home/${USERNAME}/backup

#
exit
