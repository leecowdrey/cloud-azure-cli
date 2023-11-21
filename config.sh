# change these
CUSTOMER="telco"
PRODUCT="dm"
PRODUCT_VERSION="2.0.0"
PRODUCT_VERSION="${PRODUCT_VERSION//./}"
SPRINT="2208"
IMAGE_PREFIX="xxxx/"
#TAG="2.0.0-2208.rb1"
TAG="2.0.3-2211.rb23"
PRODUCT_COMPONENTS=("alarm-endpoint" \
                    "configurator" \
                    "domain-controller" \
                    "druid-config" \
                    "envoy-northbound" \
                    "flink" \
                    "grafana-config" \
                    "grpc" \
                    "kafka-consumer" \
                    "kibana-config" \
                    "licensing" \
                    "monitor" \
                    "restconf-collector" \
                    "rmdm" \
                    "scheduler" \
                    "sdn-app" \
                    "snmp-collector" \
                    "snmpget" \
                    "snmp-trap-converter" \
                    "ssd" \
                    "ssh" \
                    "swagger" \
                    "syslogng" \
                    "tcs" \
                    "telegraf-snmp" \
                    "templates" \
                    "toolbox" \
                    "ui" \
                    "vflow" \
                    "web-server" \
                    "worker")
RELEASE_ARCHIVE="platform-${TAG}.tgz"
AZ_LANG="en_GB"
AZ_REGION="uksouth"
AZ_TIMEZONE="Europe/London"
#
# BASH Array, add as subshell tasks or "fqdn" or "ip-address"
# 194.60.90.4 CommScope Belfast Lab outbound IP
PERMITTED_WAN_IP=( $(dig +short ichibox.drayddns.com) "194.60.90.4" )


# included for platform script compatibility
USING_COLOURS=false
IS_TERMINAL=false


# Azure service principal for automated login - do not change
# one-off creation using az ad sp create-for-rbac --name XXXX_Deploy --role Contributor --scopes /subscriptions/602074cb-7faa-4f50-b6db-8c25b18adadd
#
AZ_SP_APPID="accd6085-7120-49bc-8085-d43a8df4300f" # dummy
AZ_SP_PASSWORD="eff408f6-6afb-405d-8fb0-1a35dc323fe9" # dummy
AZ_SP_TENANT="ee263cd9-c9db-466e-8c56-fde1797691be" # dummy
AZ_SP_DISPLAYNAME="XXXX_Deploy"
#az login --service-principal -u "7cd6414f-307d-4211-a743-ae8aa8d45e8a" -p "r~t8Q~KVeMOAmNPbunmbz95TacKJxAeUC1ZuHcYD" --tenant "31472f81-8fe4-49ec-8bc3-fa1c295640d7"

# do not change these
VENDOR="COMM"
CONFIGFILE="$(dirname "$0")/../configs/platform-config.yaml"

# Azure/Customer Site Networking
#
#                                                                              +----------+
#                                                                              + INTERNET |
#                                                                              |          |
#                                                                              +-----+----+
#                                                                                    |
# +==================================================================================|=======================================+
# │ VNET: COMMON_ADDRESS_PREFIX                    +-----------+                     |         +-----------+                 │
# │                                                | Azure     |                     +---------+ NFS       |                 │
# │                                                | Container |                     |         | STORE     |                 │
# │                                                + Registry  |                     |         +-----------+                 │
# │                                                +-----+-----+                     |                                       │
# │                                                      |                           |                                       │
# │ +----------------------------------------------------+--------+   +-----+   +----+----+    +--------+   +-----+ +------+ │
# │ | K8S CLUSTER                                                 |   | HUB +---+ BASTION |    | COMMON |   + PNF + + VNF  + │
# │ | +---------------------------+ +---------------------------+ +---+ SUB |   +---------+    | SUBNET |   +--+--+ +--+---+ │
# │ | | K8S_CLUSTER_SUBNET_PREFIX +-+ K8S_SERVICE_SUBNET_PREFIX | |   | NET |                  |  aka   |      |       |     │
# │ | +---------------------------+ +---------------------------+ |   | PRE |   +---------+    | (FAKE) |   +--+----------+  │
# │ | K8S_DNS_SERVICE_IP              NODE(s)                     |   | FIX +---+ VPN:HUB +----|INTERNET+---+  VPN:SPOKE  |  │
# │ +-------------------------------------------------------------+   +-----+   +---------+    +--------+   +-------------+  │
# │                                                                                                                          │
# +==========================================================================================================================+
#

#  azure_vnet_cidr: 172.16.0.0/12
#  common_subnet_cidr: 172.16.48.0/24
#  hub_subnet_cidr: 172.16.50.0/24
#  k8s_cluster_cidr: 172.16.0.0/20
##k8s_network_cidr: 172.16.32.0/20 
#  spoke_subnet_cidr: 172.16.49.0/24
##docker_bridge_ip: 172.17.0.1/16 
#  common_gateway_ip: 172.16.48.1
#  hub_subnet_gateway_ip: 172.16.48.1
#  spoke_subnet_gateway_ip:  172.16.49.1
#  k8s_nbi_lb_ip: 172.16.0.11
#  bastion_nic_eth0_private_ip: 172.16.50.8
#  hub_nic_eth0_private_ip: 172.16.48.9
#  hub_nic_eth1_private_ip: 172.16.50.9
#  hub_nic_eth2_private_ip: 172.16.0.9
##k8s_dns_service_ip: 10.0.0.16
#  spoke_nic_eth0_private_ip: 172.16.48.10
#  spoke_nic_eth1_private_ip: 172.16.49.10
#  k8s_nsd_id:
#  k8s_nsg_name: k8snsg
#  k8s_cluster_subnet_id:
#  k8s_cluster_subnet_name: clustersubnet
#  k8s_service_subnet_id:
#  k8s_service_subnet_name: podsubnet

NFS_ADDRESS_PREFIX="192.168.192.0/24"
NFS_SUBNET_ADDRESS_PREFIX="192.168.192.0/24"
NFS_NIC_ETH0_PUBLIC_IP=""
NFS_NIC_ETH0_FQDN=""
NFS_NIC_ETH0_PRIVATE_IP="192.168.192.168"
#
COMMON_ADDRESS_PREFIX="172.16.0.0/12"
COMMON_SUBNET_ADDRESS_PREFIX="172.16.48.0/24"
BASTION_NIC_ETH0_GATEWAY_IP="172.16.50.1"
BASTION_NIC_ETH0_PRIVATE_IP="172.16.50.8"
BASTION_SUBNET_PREFIX="172.16.50.8"
HUB_NIC_ETH0_GATEWAY_IP="172.16.48.1"
HUB_NIC_ETH0_PRIVATE_IP="172.16.48.9"
HUB_NIC_ETH1_PRIVATE_IP="172.16.0.9"
HUB_NIC_ETH2_PRIVATE_IP="172.16.50.9"
HUB_SUBNET_PREFIX="172.16.50.0/24"
K8S_CLUSTER_SUBNET_PREFIX="172.16.0.0/20"
K8S_CLUSTER_DNS_IP1="172.16.0.2" # reserved by Azure
K8S_CLUSTER_DNS_IP2="172.16.0.3" # reserved by Azure
K8S_CLUSTER_GATEWAY_IP="172.16.0.1" # reserved by Azure
SPOKE_NIC_ETH0_GATEWAY_IP="172.16.48.1"
SPOKE_NIC_ETH0_PRIVATE_IP="172.16.48.10"
SPOKE_NIC_ETH1_GATEWAY_IP="172.16.49.1"
SPOKE_NIC_ETH1_PRIVATE_IP="172.16.49.10"
SPOKE_SUBNET_PREFIX="172.16.49.0/24"
RMD_NIC_ETH0_GATEWAY_IP="172.16.49.1"
RMD_NIC_ETH0_PRIVATE_IP="172.16.49.11"
POLT_NIC_ETH0_GATEWAY_IP="172.16.49.1"
POLT_NIC_ETH0_PRIVATE_IP="172.16.49.12"
K8S_NBI_LB_PRIVATE_IP="172.16.0.10"
K8S_SBI_LB_PRIVATE_IP="172.16.0.11"
K8S_REGISTRY_IP=""
K8S_REGISTRY_PORT="32000"
K8S_REGISTRY_SIZE="30Gi"

XXXX_NIC_ETH0_GATEWAY_IP="172.16.0.1"
XXXX_NIC_ETH0_PRIVATE_IP="172.16.0.7"
XXXX_NIC_ETH1_PRIVATE_IP="172.16.50.7"
XXXX_SUBNET_PREFIX="172.16.0.0/20"

#
PRIVATE_DNS_SUFFIX="vendor.local"
PRIVATE_DNS_ZONE_NAME="${CUSTOMER,,}.${PRIVATE_DNS_SUFFIX}"
PRIVATE_DNS_LINK_NAME="${CUSTOMER,,}dnslnk"
#
ACCEPT_SIGINT=1
AZ_ACR_DOMAIN_NAME=".azurecr.io"
AZ_ACR_ID=""
AZ_ACR_NAME="${CUSTOMER,,}reg${AZ_REGION}"
AZ_ACR_LOGIN_URL="${AZ_ACR_NAME}${AZ_ACR_DOMAIN_NAME,,}"
AZ_ACR_LOGIN_IP=""
AZ_ACR_PASSWORD=""
AZ_ACR_PULL_ROLE="AcrPull"
AZ_ACR_SKU="Standard"
AZ_ACR_TOKEN=""
AZ_ACR_USERNAME=""
AZ_AKS_CLUSTER_ID=""
AZ_AKS_CLUSTER="k8s"
AZ_AKS_CLUSTER="${AZ_AKS_CLUSTER// /}"
AZ_AKS_CLUSTER_ADMIN_USERNAME="${CUSTOMER,,}"
AZ_AKS_CLUSTER_IP=""
AZ_AKS_CLUSTER_NODES=2 # System Node pool, 2 for singlenode, 4+ for multinode (these are masters)
AZ_AKS_CLUSTER_POOL="inf"
AZ_AKS_CSI_PLUGINS="/etc/kubernetes/volumeplugins"
AZ_AKS_DEFAULT_VERSION=""
AZ_AKS_DISK_SKU="Standard_LRS"
AZ_AKS_DISK_TYPE="Linux"
AZ_AKS_DM_POOL="xxxx"
AZ_AKS_DM_POOL="${AZ_AKS_DM_POOL// /}"
AZ_AKS_DM_POOL_NODES=1 # User (xxxx) node pool, 1 for singlenode, 3 for multinode (these are workers)
AZ_AKS_DM_SC_LOCAL_AUTO_EXPAND="true"
AZ_AKS_DM_SC_LOCAL_AZ_TYPE="azurefile-csi"
AZ_AKS_DM_SC_LOCAL_CLASS="xxxx-local"
AZ_AKS_DM_SC_LOCAL_RECLAIM="Retain" # Retain or Delete
AZ_AKS_DM_SC_LOCAL_SKU="Premium_LRS"
AZ_AKS_DM_SC_RWO_AUTO_EXPAND="true"
AZ_AKS_DM_SC_RWO_AZ_TYPE="azurefile-csi"
AZ_AKS_DM_SC_RWO_CLASS="xxxx-rwo"
AZ_AKS_DM_SC_RWO_RECLAIM="Retain" # Retain or Delete
AZ_AKS_DM_SC_RWO_SKU="Premium_LRS"
AZ_AKS_DM_SC_RWX_AUTO_EXPAND="true"
AZ_AKS_DM_SC_RWX_AZ_TYPE="azurefile-csi"
AZ_AKS_DM_SC_RWX_CLASS="xxxx-rwx"
AZ_AKS_DM_SC_RWX_RECLAIM="Retain" # Retain or Delete
AZ_AKS_DM_SC_RWX_SKU="Premium_LRS"
AZ_AKS_DNS_PREFIX="${CUSTOMER,,}"
AZ_AKS_LATEST_VERSION=""
AZ_AKS_NETWORK_PLUGIN="kubenet" # azure or kubenet
AZ_AKS_NETWORK_POLICY="none" # calico or azure  or none
AZ_AKS_NODE_DISK_TYPE="Managed"
AZ_AKS_NODE_LB_SKU="standard" # basic or standard
AZ_AKS_NODE_OS_DISK_SIZE=128
AZ_AKS_NODE_OS_SKU="Ubuntu"
AZ_AKS_INF_NODE_TYPE="Standard_D16as_v4" # 16vCPU, 64GiB RAM,cache 200Gb, max disks 32, max nics 8 (8000 bw)
AZ_AKS_DM_NODE_TYPE="Standard_D32d_v4" # 32vCPU, 128GiB RAM,cache 1.200Gb, max disks 32, max nics 8 (8000 bw)
AZ_AKS_PRIVATE_DNS_ZONE="system"
AZ_AKS_PRIVATE_DNS_ZONE="system"
AZ_AKS_REQUIRED_VERSION="1.24.6"
AZ_CONNECTED=1
AZ_HELM_VERSION="v3.10.0"
AZ_HELM_WAIT_TIMEOUT="20m0s"
AZ_RG="${CUSTOMER,,}"
AZ_RG_ID=""
AZ_SCOPE="https://management.core.windows.net//.default"
AZ_SUBSCRIPTION="xxxx" # change to match Azure provisioned account
AZ_SUBSCRIPTION_ID=""
AZ_ZONES="1"
BASTION_NIC_ETH0="bastioneth0"
BASTION_NIC_ETH0_FQDN=""
BASTION_NIC_ETH0_PUBLIC_IP=""
BASTION_NODE_TYPE="Standard_F2s_v2"
BASTION_NSD_ID=""
BASTION_NSG_NAME="hubnsg"
BASTION_SUBNET_NAME="hubsubnet"
BASTION_EAH_ENABLE="true" # encryption at host
BASTION_VM_NAME="bastion"
BASTION_OS_AUTO_UPDATE="false"
BASTION_OS_OFFER="debian-11"
BASTION_OS_USERNAME="${CUSTOMER,,}"
BASTION_OS_PASSWORD="${CUSTOMER,,}@s3cr3t00" # The password length must be between 12 and 72. Password must have the 3 of the following: 1 lower case character, 1 upper case character, 1 number and 1 special character.RMD_OS_USERNAME="${CUSTOMER,,}"
BASTION_OS_PUBLISHER="Debian" 
BASTION_OS_SKU="11-backports-gen2" 
BASTION_OS_URN=""
BASTION_OS_PREPARE="bastion_prepare.sh"
COMMON_NSG_ID=""
COMMON_NSG_NAME="commonnsg"
COMMON_SUBNET="commonsubnet"
COMMON_VNET="${CUSTOMER,,}vnet"

XXXX_DATA_DISK_NAME="XXXX_DataDisk_1"
XXXX_DATA_DISK_SIZE="256"
XXXX_EAH_ENABLE="true" # encryption at host
XXXX_NBI_IP1="172.16.0.7"
XXXX_NBI_IP2=""
XXXX_NBI_IP3=""
XXXX_NBI_PORT="8080"
XXXX_NBI_VIP=""
XXXX_NIC_ETH0="xxxxeth0"
XXXX_NIC_ETH0_FQDN=""
XXXX_NIC_ETH0_PUBLIC_IP=""
XXXX_NIC_ETH1="xxxxeth1"
XXXX_NODE_TYPE="Standard_D16as_v4" # 16vCPU, 64GiB RAM,cache 200Gb, max disks 32, max nics 8 (8000 bw)
XXXX_NSD_ID=""
XXXX_NSG_NAME="k8snsg"
XXXX_OS_AUTO_UPDATE="false"
XXXX_OS_OFFER="0001-com-ubuntu-server-focal"
XXXX_OS_PASSWORD="${CUSTOMER,,}@s3cr3t00" # The password length must be between 12 and 72. Password must have the 3 of the following: 1 lower case character, 1 upper case character, 1 number and 1 special character.RMD_OS_USERNAME="${CUSTOMER,,}"
XXXX_OS_PREPARE="XXXX_prepare.sh"
XXXX_OS_PUBLISHER="Canonical"
XXXX_OS_SKU="20_04-lts-gen2"
XXXX_OS_URN=""
XXXX_OS_URN=""
XXXX_OS_USERNAME="${CUSTOMER,,}"
XXXX_SBI_IP1="172.16.50.7"
XXXX_SBI_IP2=""
XXXX_SBI_IP3=""
XXXX_SBI_KAFKA_SECURE_PORT="9093"
XXXX_SBI_KAFKA_UNSECURE_PORT="9092"
XXXX_SBI_NETCONF_CALLHOME_SSH_PORT="4334"
XXXX_SBI_NETCONF_CALLHOME_TLS_PORT="4335"
XXXX_SBI_SYSLOG_PORT="514"
XXXX_SBI_VIP=""
XXXX_VM_NAME="xxxx"

HUB_NIC_ETH0="hubeth0"
HUB_NIC_ETH1="hubeth1"
HUB_NIC_ETH2="hubeth2"
HUB_NODE_TYPE="Standard_F8s_v2"
HUB_NSD_ID=""
HUB_NSG_NAME="hubnsg"
HUB_SUBNET_NAME="hubsubnet"
HUB_VM_NAME="hub"
IP_SKU="Standard"
IP_VERSION="IPv4"
K8S_CLUSTER_SUBNET_ID=""
K8S_CLUSTER_SUBNET_NAME="clustersubnet"   # k8s cluster management is separate from k8s nodes in azure
K8S_CLUSTER_API_FQDN=""
K8S_CLUSTER_API_IP=""
K8S_NSD_ID=""
K8S_NSG_NAME="k8snsg"
K8S_SERVICE_SUBNET_ID=""
K8S_SERVICE_SUBNET_NAME="podsubnet"
K8S_DNS_SERVERS="8.8.8.8,8.8.4.4"
NOLOGOUT=0
#
NFS_NSG_ID=""
NFS_NSG_NAME="nfsnsg"
NFS_VNET="nfsvnet"
NFS_AZ_RG="nfs"
NFS_DNS_PREFIX=""
NFS_EAH_ENABLE="true" # encryption at host
NFS_NIC_ETH0="nfseth0"
NFS_NODE_TYPE="Standard_F2s_v2" 
NFS_NSD_ID=""
NFS_NSG_NAME="nfsnsg"
NFS_OS_AUTO_UPDATE="false"
NFS_OS_OFFER="debian-11" 
NFS_OS_USERNAME="commscope"
NFS_OS_PASSWORD="comm@s3cr3t00" 
NFS_OS_PUBLISHER="Debian" 
NFS_OS_SKU="11-backports-gen2" 
NFS_OS_URN=""
NFS_OS_PREPARE="nfs_prepare.sh"
NFS_SUBNET_NAME="nfssubnet"
NFS_VM_NAME="nfs"
NFS_BACKUP_PATH="/home/${NFS_OS_USERNAME}/backup/"
NFS_BACKUP_KEY="nfs_backup"
NFS_BACKUP_KEY_TYPE="rsa"
NFS_BACKUP_KEY_BITS="4096"
#
POLT_SIM_VERSION="2209.3"
POLT_BULK_RELEASE="polt-platform_blkrls_1.0.0.sprint${POLT_SIM_VERSION}.tar.gz"
POLT_EAH_ENABLE="true" # encryption at host
POLT_PON_TOOLS="pon_tools_1.0.0.sprint${POLT_SIM_VERSION}.tar.gz"
POLT_NIC_ETH0="polteth0"
POLT_NODE_TYPE="Standard_F8s_v2" # Standard_F8s_v2 = 8vCPU 16GB RAM 64GB storage 4vNIC, Standard_F16s_v2 = 16 vCPUs, 32GB RAM, 128GB storage, 4 vNICS, Standard_F32s_v2 = 32vCPUs, 64GB RAM, 256GB storage, 4vNICs
POLT_NSD_ID=""
POLT_NSG_NAME="spokensg"
POLT_DATA_DISK_NAME="polt_DataDisk_1"
POLT_DATA_DISK_SIZE="256"
POLT_OLT_BULK_RELEASE="olt_blkrls_1.0.0.sprint${POLT_SIM_VERSION}.tar.gz"
POLT_ONUS="2"
POLT_OS_AUTO_UPDATE="false"
POLT_OS_OFFER="UbuntuServer" # 0001-com-ubuntu-minimal-focal"
POLT_OS_PASSWORD="${CUSTOMER,,}@s3cr3t00"
POLT_OS_PUBLISHER="Canonical"
POLT_OS_SKU="18_04-daily-lts-gen2"
POLT_OS_URN=""
POLT_OS_USERNAME="ponuser" # mandatory value is ponuser
POLT_PON_BULK_RELEASE="pon_blkrls_1.0.0.sprint${POLT_SIM_VERSION}.tar.gz"
POLT_SIM_PREPARE="polt_prepare.sh"
POLT_SUBNET_NAME="spokesubnet"
POLT_VM_NAME="polt"
POLT_PON_VENV="pon_venv_1.0-4.deb"
POLT_ORCA_VENV="orca_venv_3.0-3.deb"
POLT_IO_ORCHESTRATE="io-orchestrate_3.0.0-56.deb"
POLT_DOCKER_ARANGODB="arangodb-3.3.13.tar.gz"
POLT_DOCKER_AUTOCONF="autoconf-1.0.0.42.tar.gz"
POLT_DOCKER_BAA="baa-1.0.0.35.tar.gz"
POLT_DOCKER_BBF_OBBAA="bbf-obbaa-latest.tar.gz"
POLT_DOCKER_HTTPD="httpd-2.4.tar.gz"
POLT_DOCKER_KAFKA="kafka-2.7.1.tar.gz"
POLT_DOCKER_POLT_VERSION="1.0.0.43"
POLT_DOCKER_POLT="polt-${POLT_DOCKER_POLT_VERSION}.tar.gz"
POLT_DOCKER_VOMCI="vomci-1.0.0.44.tar.gz"
POLT_DOCKER_ZOOKEEPER="zookeeper-3.6.3-2.7.1.tar.gz"
PROMETHEUS_ALERTMGR_EXTERNAL_PORT=9093
PROMETHEUS_ALERTMGR_INTERNAL_PORT=9093
PROMETHEUS_DISABLE_INTERNAL=0
PROMETHEUS_EXTERNAL_PORT=9090
PROMETHEUS_GRAFANA_EXTERNAL_PORT=8080
PROMETHEUS_GRAFANA_INTERNAL_PORT=80
PROMETHEUS_INTERNAL_PORT=9090
PROMETHEUS_NAMESPACE="monitoring"
PROMETHEUS_ENABLE="false"
RETVAL=0
RMD_EAH_ENABLE="true" # encryption at host
RMD_NIC_ETH0="rmdeth0"
RMD_NODE_TYPE="Standard_F2s_v2" # 8GB RAM, 2vCPU
RMD_NSD_ID=""
RMD_NSG_NAME="spokensg"
RMD_OS_AUTO_UPDATE="false"
RMD_OS_OFFER="debian-11" # 0001-com-ubuntu-minimal-focal"
RMD_OS_PASSWORD="${CUSTOMER,,}@s3cr3t00" # The password length must be between 12 and 72. Password must have the 3 of the following: 1 lower case character, 1 upper case character, 1 number and 1 special character.
RMD_OS_PUBLISHER="Debian" # Canonical
RMD_OS_SKU="11-backports-gen2" # minimal-20_04-lts-gen2
RMD_OS_URN=""
RMD_OS_USERNAME="${CUSTOMER,,}"
RMD_SIM_ARCHIVE="rmd_sim.tgz"
RMD_SIM_PREPARE="rmd_prepare.sh"
RMD_SUBNET_NAME="spokesubnet"
RMD_VM_NAME="rmd"
SPOKE_NIC_ETH0="spokeeth0"
SPOKE_NIC_ETH1="spokeeth1"
SPOKE_NODE_TYPE="Standard_D2s_v3" # 4	16	100	8	2/2000
SPOKE_NSD_ID=""
SPOKE_NSG_NAME="spokensg"
SPOKE_SUBNET_NAME="spokesubnet"
SPOKE_VM_NAME="spoke"
SSH_KEY_PRIVATE="~/.ssh/id_rsa"
SSH_KEY_PUBLIC_EMAIL="email@domain.com"
SSH_KEY_PUBLIC_KEY="====="
SSH_KEY_PUBLIC_TYPE="ssh-rsa"
SSH_KEY_PUBLIC_VALUE="${SSH_KEY_PUBLIC_TYPE} ${SSH_KEY_PUBLIC_KEY} ${SSH_KEY_PUBLIC_EMAIL}"
SSH_PORT=22
VPN_EAH_ENABLE="true" # encryption at host
VPN_OS_AUTO_UPDATE="false"
VPN_OS_OFFER="vyos-1-2-lts-on-azure"
VPN_OS_PASSWORD="${CUSTOMER,,}@s3cr3t00" # The password length must be between 12 and 72. Password must have the 3 of the following: 1 lower case character, 1 upper case character, 1 number and 1 special character.
VPN_OS_PUBLISHER="sentriumsl"
VPN_OS_SKU="vyos-1-3" # Debian 11 Bullseye generation-2
VPN_OS_URN=""
VPN_OS_USERNAME="${CUSTOMER,,}"
VPN_PING_OK=1
VPN_SECRET="ssssh!itsS3cr3t"
WAIT_SLEEP_SECONDS=15

### not supported to be used within Azure Cloud Shell
[[ $(grep -i Azure /proc/version &> /dev/null) ]] && exit 2

### shell hacks for WSL, Debian/Ubuntu etc.
[[ $(grep -i Microsoft /proc/version &> /dev/null) ]] && DO_SUDO="sudo" || DO_SUDO=""

### eof
