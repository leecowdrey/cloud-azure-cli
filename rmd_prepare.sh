#!/bin/bash
[[ $(id -u) -ne 0 ]] && exit 1
USERNAME="${1:-telco}"
NLG="${2:-en_GB}"
NTZ="${3:-Europe/London}"
SSHP=${4:-22}
FQDN="${5:-rmd}"
export DEBIAN_FRONTEND=noninteractive
export LANG="${NLG}.UTF-8"
export LANGUAGE="${NLG}.UTF-8"
export LC_ALL="${NLG}.UTF-8"
mkdir -m 700 -p /home/${USERNAME}/.ssh
cat <<EOF1 > /home/${USERNAME}/.ssh/config
Host *
    VerifyHostKeyDNS no
EOF1
chown ${USERNAME} /home/${USERNAME}/.ssh/config && chmod 600 /home/${USERNAME}/.ssh/config
apt-get -y update ; apt-get -y dist-upgrade ; apt-get -y autoremove ; apt-get -y autoclean
apt-get install -y locales-all apt-transport-https apt-transport-https ca-certificates curl unzip sshpass yamllint python3-pip dnsutils
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

# fix motd
echo "Unauthorized access is prohibited - parts Copyright © 2999 vendor, Inc." > /etc/update-motd.d/00-vendor-banner
chmod 444 /etc/update-motd.d/00-vendor-banner

#
exit
