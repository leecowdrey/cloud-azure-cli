#!/bin/bash

### change these
CUSTOMER="telco" # use abbrevation, initials or something short
PRODUCT_VERSION="2.0"
AZ_SUBSCRIPTION="XXXX" # change to match Azure provisioned account
AZ_SCOPE="https://management.core.windows.net//.default"
AZ_REGION="uksouth"
AZ_LANG="en_GB"
AZ_TIMEZONE="Europe/London"
AZ_ZONES="1 2 3"
CUSTOMER_BACKUP_VPN_HOST="81.159.245.92"


SKIP_CEPH=0

### do not change anything below
RETVAL=0
trap clean SIGINT
NOLOGOUT=1
AZ_CONNECTED=1
ACCEPT_SIGINT=1
WAIT_SLEEP_SECONDS=15

### shell hacks for WSL, Debian/Ubuntu etc.
[[ $(grep -i Microsoft /proc/version &> /dev/null) -eq 0 ]] && DO_SUDO="sudo" || DO_SUDO=""

### Domain Manager aks resource prefix
PRODUCT="dm"
PRODUCT_VERSION="${PRODUCT_VERSION//./}"

### customer translations
CUSTOMER_BACKUP_VPN_IP=""
CUSTOMER_BACKUP_VPN_PING_OK=1
CUSTOMER_BACKUP_VPN_IPV4=1
CUSTOMER_BACKUP_VPN_IPV6=1

### azure container service (aks/k8s)
AZ_AKS_REQUIRED_VERSION="1.24.3"
AZ_AKS_LATEST_VERSION=""
AZ_AKS_DEFAULT_VERSION=""
AZ_AKS_CLUSTER="${PRODUCT,,}${PRODUCT_VERSION}clstr"
AZ_AKS_CLUSTER="${AZ_AKS_CLUSTER// /}"
AZ_AKS_CLUSTER_NODES=2 # System Node pool
AZ_AKS_CSI_PLUGINS="/etc/kubernetes/volumeplugins"
AZ_PUBLIC_IP_SKU="Standard"

AZ_AKS_NODE_OS_DISK_SIZE=128
AZ_AKS_DISK_TYPE="Linux"
AZ_AKS_DISK_SKU="Standard_LRS"
AZ_AKS_NODE_OS_SKU="Ubuntu"
AZ_AKS_NODE_DISK_TYPE="Managed"
AZ_AKS_NODE_TYPE="Standard_D16_v4" # 16vCPU, 64GiB RAM,cache 200Gb, max disks 32, max nics 8 (8000 bw)

AZ_AKS_DM_POOL_NODES=3 # User node pool
AZ_AKS_DM_POOL="${PRODUCT,,}${PRODUCT_VERSION}work"
AZ_AKS_DM_POOL="${AZ_AKS_DM_POOL// /}"
AZ_AKS_DM_SC_RWO_CLASS="csdm-rwo"
AZ_AKS_DM_SC_RWO_K8S_TYPE="filesystem"
AZ_AKS_DM_SC_RWO_AZ_TYPE="azurefile-csi"
AZ_AKS_DM_SC_RWO_SIZE=200 # Gib
AZ_AKS_DM_SC_RWX_CLASS="csdm-rwx"
AZ_AKS_DM_SC_RWX_K8S_TYPE="filesystem"
AZ_AKS_DM_SC_RWX_AZ_TYPE="azurefile-csi"
AZ_AKS_DM_SC_RWO_SIZE=200 # Gib


AZ_AKS_NODE_LB_SKU="standard"
AZ_AKS_NETWORK_PLUGIN="azure"
AZ_AKS_PRIVATE_DNS_ZONE="system"
AZ_AKS_ACR_SKU="Basic"

AZ_RG="${PRODUCT,,}${PRODUCT_VERSION}rg"
AZ_RG="${AZ_RG// /}"
AZ_AKS_CEPH_POOL_NODES=3 # User node pool
AZ_AKS_CEPH_POOL="${PRODUCT,,}${PRODUCT_VERSION}ceph"
AZ_AKS_CEPH_POOL="${AZ_AKS_CEPH_POOL// /}"
#AZ_AKS_ACR="${PRODUCT,,}${PRODUCT)VERSION}acr"


### rook ceph
CEPH_DASHBOARD_ENABLED="true" # true or false
CEPH_DASHBOARD_INTERNAL_PORT=8443
CEPH_DASHBOARD_EXTERNAL_PORT=8443
CEPH_DASHBOARD_OPEN="false"
CEPH_DASHBOARD_OPEN_PID=0
CEPH_DASHBOARD_USERNAME="admin"
CEPH_DASHBOARD_PASSWORD=""
CEPH_DASHBOARD_OPEN_LOG="/tmp/rook-ceph-dashboard.log"
CEPH_OSD_DISK_SIZE=200 # per OSD in GiB
CEPH_CHART_VERSION="v1.9.8"
CEPH_CLUSTER_YAML="rook-ceph-cluster.yaml"
CEPH_OPERATOR_YAML="rook-ceph-operator.yaml"
CEPH_TOOLBOX_YAML="rook-ceph-toolbox-job.yaml"
CEPH_HELM_VERSION="v3.10.0"

### azure networking
AZ_BACKUP_VPN_SKU="VpnGw2AZ" # max 30 S2S/VNet-to-VNet tunnels, max 128 P2S SSTP connections, max 128 P2S IKEv2/OpenVPN connections, 1.25Gbps agg throughput,BGP supported, zone redudant

### aks networking
AZ_VNET_NAME="${PRODUCT,,}${PRODUCT_VERSION}vnet"
AZ_ADDRESS_PREFIX="10.0.0.0/20" # 10.0.0.1 - 10.0.15.254
AZ_AKS_VNET_NAME="${PRODUCT,,}${PRODUCT_VERSION}k8sVnet"
AZ_AKS_SUBNET_NAME="${PRODUCT,,}${PRODUCT_VERSION}k8sSubnet"
AZ_AKS_SUBNET_PREFIX="10.8.0.0/22"
AZ_AKS_ADDRESS_PREFIX="10.8.0.0/22" # 10.8.0.1 - 10.8.3.254

SERVICE_VNET_NAME="${PRODUCT,,}${PRODUCT_VERSION}serviceVnet"
SERVICE_SUBNET_NAME="${PRODUCT,,}${PRODUCT_VERSION}serviceSubnet"
SERVICE_SUBNET_PREFIX="10.1.0.0/22"
SERVICE_ADDRESS_PREFIX="10.1.0.0/22" # 10.1.0.1 - 10.1.7.254
DNS_SERVICE_IP="10.1.0.10"

DOCKER_BRIDGE_VNET_NAME="${PRODUCT,,}${PRODUCT_VERSION}DockerBridgeVnet"
DOCKER_BRIDGE_SUBNET_NAME="${PRODUCT,,}${PRODUCT_VERSION}DockerBridgeSubnet"
DOCKER_BRIDGE_SUBNET_PREFIX="172.17.0.0/16"
DOCKER_BRIDGE_ADDRESS_PREFIX="172.17.0.0/16"

### ssh bastion
BASTION_VNET_NAME="${PRODUCT,,}${PRODUCT_VERSION}bastionVnet"
BASTION_SUBNET_NAME="${PRODUCT,,}${PRODUCT_VERSION}bastionSubnet"
BASTION_SUBNET_PREFIX="10.0.0.0/24"
BASTION_ADDRESS_PREFIX="10.0.0.0/24" # 10.0.0.1 - 10.0.0.254
BASTION_PUBLIC_IP=""
BASTION_PRIVATE_IP=""
BASTION_SSH_PORT=22
BASTION_MOSH_PORT="60000-60010"
BASTION_OS_SKU="11-backports-gen2" # Debian 11 Bullseye generation-2
BASTION_OS_URN=""
BASTION_OS_PUBLISHER="Debian"
BASTION_OS_OFFER="debian-11"
BASTION_OS_AUTO_UPDATE="true"
#BASTION_NODE_TYPE="Standard_D2s_v3" # 2vCPU, 8GiB RAM, cache 4Gb, host based encryption supported
#BASTION_NODE_TYPE="Standard_B1s" # 2vCPU, 4GiB RAM, cache 16Gb, host based encryption support
BASTION_NODE_TYPE="Standard_B1s" # bustable (130% CPU for 30 minutes with earned credits) 1vCPU, 1GiB RAM, cache 4Gb, host based encryption support
BASTION_AD_EXTENSION_NAME="AADLoginForLinux"
BASTION_AD_EXTENSION_PUBLISHER="Microsoft.Azure.ActiveDirectory.LinuxSSHMicrosoft.Azure.ActiveDirectory.LinuxSSH"
BASTION_AD_EXTENSION_VERSION=""
BASTION_OS_USERNAME="labuser"
BASTION_OS_PASSWORD="${CUSTOMER,,}@password"
BASTION_NAME="${CUSTOMER,,}${PRODUCT,,}${PRODUCT_VERSION}b"
BASTION_EAH_ENABLE="true" # encryption at host
BASTION_FQDN=""
BASTION_TMP=$(mktemp -q -p /tmp)
BASTION_SSH_KEY_PRIVATE="~/.ssh/id_rsa"
BASTION_SSH_KEY_PUBLIC=$(mktemp -q -p /tmp)
BASTION_SSH_KEY_PUBLIC_VALUE="ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAIEA/fjkk7h5nKfIuztGardI7pIpylXyEdZ+AJK0gI4MmgCxMk+Ob4/8rUs2/ymBklNmFnXZYLHZLcjB2YsXuphJ30W6o569EPVrubXi8lePeiVszZsmW4pWqrzjhErmzZOuoXrOrE/jO4Fgr68aS8Xv8CbhpvvH25LEwKByGG9etLU= lee@cowdrey.co.uk"
[[ ! -f "${BASTION_SSH_KEY_PUBLIC}" ]] && echo "${BASTION_SSH_KEY_PUBLIC_VALUE}" > "${BASTION_SSH_KEY_PUBLIC}"


### helpers
help() {
  echo "usage: ${0##*/} [ [--nologout] [--sigint] [--help] [stepX] [stepX] ]"
  echo "        clean   - remove all AKS creations"
  echo "        step1   - resource group"
  echo "        step2   - container registry"
  echo "        step3   - networks, public/private IP addresses"
  echo "        step4   - bastion vm"
  echo "        step5   - bastion networks/ACLs"
  echo "        step6   - aks cluster setup"
  echo "        step7   - aks get credentials "
  echo "        step8   - ceph nodepool"
  echo "        step9   - ceph"
  echo "        step10  - ceph"
  echo "        step11  - ceph"
  echo "        step12  - ceph"
  echo "        step13  - ceph"
  echo "        step14  - ceph dashboard"
  echo "        step15  - ceph toolbox"
  echo "        step16  - ceph"
  echo "        step17  - ceph"
  echo "        step18  - ceph"
  echo "        step19  - ceph"
  echo "        step20  - dm nodepool"
  echo "or, "
  echo "usage: ${0##*/} "
  exit 0
}

clean_aks_rg() {
  local RETVAL=0
  local RESOURCES=$(az resource list --resource-group "${AZ_RG}" --query "[].name" --output tsv|wc -l)
  [[ ${RESOURCES} -gt 0 ]] && az group delete --name "${AZ_RG}" --yes ; RETVAL=$?
  return ${RETVAL}
}

clean_tmp_files() {
  local RETVAL=0
  [[ -f "${BASTION_SSH_KEY_PUBLIC}" ]] && rm -f "${BASTION_SSH_KEY_PUBLIC}" &> /dev/null
  [[ -f "${BASTION_TMP}" ]] && rm -f "${BASTION_TMP}" &> /dev/null
  [[ -f "${CEPH_CLUSTER_YAML}" ]] && rm -f "${CEPH_CLUSTER_YAML}" &> /dev/null
  [[ -f "${CEPH_OPERATOR_YAML}" ]] && rm -f "${CEPH_OPERATOR_YAML}" &> /dev/null
  [[ -f "${CEPH_TOOLBOX_YAML}" ]] && rm -f "${CEPH_TOOLBOX_YAML}" &> /dev/null
  [[ -f "${CEPH_DASHBOARD_OPEN_LOG}" ]] && rm -f "${CEPH_DASHBOARD_OPEN_LOG}" &> /dev/null
  return ${RETVAL}
}

clean() {
  local RETVAL=0
  trap '' SIGINT
  clean_aks_rg && \
  clean_tmp_files
  RETVAL=$?
  trap - INT
  return ${RETVAL}
}

install_az_aks_cli() {
  local RETVAL=0
  sudo az aks install-cli --client-version "${AZ_AKS_REQUIRED_VERSION}" &> /dev/null
  RETVAL=$?
  return ${RETVAL}
}

upgrade_az_aks_cli() {
  local RETVAL=0
  local AZ_AKS_WANTED_VERSION=""
  AZ_AKS_WANTED_VERSION=$(kubectl version --client --output=yaml|grep "gitVersion"|awk -F ":" '{gsub(/ /,"");gsub(/v/,"");print $2}')
  if [[ "${AZ_AKS_REQUIRED_VERSION,,}" == "${AZ_AKS_WANTED_VERSION,,}" ]] ; then
    RETVAL=0
  else
    echo "Azure AKS ${AZ_REGION} current AKS version: ${AZ_AKS_WANTED_VERSION}"
    echo "Azure AKS ${AZ_REGION} required AKS version: ${AZ_AKS_REQUIRED_VERSION}"
    sudo az aks install-cli --client-version "${AZ_AKS_REQUIRED_VERSION}" &> /dev/null && \
    az upgrade --all --yes --output none &> /dev/null
    RETVAL=$?
  fi
  return ${RETVAL}
}

install_helm() {
  local RETVAL=0
  if [ -n "${1}" ] ; then
    if [ "${1,,}" == "--force" ] ; then
      [[ -f /usr/local/bin/helm ]] && sudo rm -f /usr/local/bin/helm &> /dev/null
    fi
  fi
  [[ -f helm-${CEPH_HELM_VERSION}-linux-amd64.tar.gz ]] && rm -f helm-${CEPH_HELM_VERSION}-linux-amd64.tar.gz &> /dev/null
  curl -sLO https://get.helm.sh/helm-${CEPH_HELM_VERSION}-linux-amd64.tar.gz && \
  tar -zxvf helm-${CEPH_HELM_VERSION}-linux-amd64.tar.gz && \
  sudo mv -f linux-amd64/helm /usr/local/bin/helm
  RETVAL=$?
  return ${RETVAL}
}

upgrade_helm() {
  local RETVAL=0
  local HELM_WANTED_VERSION=""
  HELM_WANTED_VERSION=$(helm version --short|awk '{gsub(/ /,"");gsub(/+.*/,"");print $1}')
   if [[ "${CEPH_HELM_VERSION,,}" == "${HELM_WANTED_VERSION,,}" ]] ; then
    RETVAL=0
  else
    echo "Azure AKS ${AZ_REGION} current HELM version: ${CEPH_HELM_VERSION}"
    echo "Azure AKS ${AZ_REGION} required HELM version: ${HELM_WANTED_VERSION}"
    install_helm --force
    RETVAL=$?
  fi
  return ${RETVAL}
}

check_env() {
  local RETVAL=0
  command -v az aks &> /dev/null || install_az_aks_cli && upgrade_az_aks_cli
  command -v helm &> /dev/null || install_helm && upgrade_helm
  RETVAL=$?
  return ${RETVAL}
}

check_roles() {
  local RETVAL=0
  local ROLES=""
  local AAEKCUR=1
  local AAKA=1
  local AAKCA=1
  local AKSCAR=1
  local AKSCUR=1
  local AKSCR=1
  local AKSRA=1
  local AKSRCA=1
  local BR=1
  local CNC=1
  local KCAAO=1
  local NC=1
  local O=1
  local R=1
  local SR=1
  local VNC=1
  ROLES=$(az role assignment list --query "[].roleDefinitionName" -o tsv|sort -u)
  while IFS= read -r ROLE ; do
    case ${ROLE} in
      "Azure Arc Enabled Kubernetes Cluster User Role") AAEKCUR=0 ;;
      "Azure Arc Kubernetes Admin") AAKA=0 ;;
      "Azure Arc Kubernetes Cluster Admin") AAKCA=0 ;;
      "Azure Kubernetes Service Cluster Admin Role") AKSCAR=0 ;;
      "Azure Kubernetes Service Cluster User Role") AKSCUR=0 ;;
      "Azure Kubernetes Service Contributor Role") AKSCR=0 ;;
      "Azure Kubernetes Service RBAC Admin") AKSRA=0 ;;
      "Azure Kubernetes Service RBAC Cluster Admin") AKSRCA=0 ;;
      "Billing Reader") BR=0 ;;
      "Classic Network Contributor") CNC=0 ;;
      "Contributor") C=0 ;;
      "Kubernetes Cluster - Azure Arc Onboarding") KCAAO=0 ;;
      "Network Contributor") NC=0 ;;
      "Owner") O=0 ;;
      "Reader") R=0 ;;
      "Security Reader") SR=0 ;;
      "Virtual Machine Contributor") VNC=0 ;;
      *) ;;
    esac
  done <<< ${ROLES}
  if [[ ${AAEKCUR} -eq 0 && ${AAKA} -eq 0 && ${AAKCA} -eq 0 && ${AKSCAR} -eq 0 && ${AKSCUR} -eq 0 && ${AKSCR} -eq 0 && ${AKSRA} -eq 0 && ${AKSRCA} -eq 0 && ${BR} -eq 0 && ${C} -eq 0 && ${CNC} -eq 0 && ${KCAAO} -eq 0 && ${NC} -eq 0 && ${O} -eq 0 && ${R} -eq 0 && ${SR} -eq 0 && ${VNC} -eq 0 ]] ; then
    echo "all required roles assigned"
    RETVAL=0
  else
    RETVAL=2
    [[ ${AAEKCUR} -ne 0 ]] && echo "role missing: Azure Arc Enabled Kubernetes Cluster User Role"
    [[ ${AAKA} -ne 0 ]] && echo "role missing: Azure Arc Kubernetes Admin"
    [[ ${AAKCA} -ne 0 ]] && echo "role missing: Azure Arc Kubernetes Cluster Admin"
    [[ ${AKSCAR} -ne 0 ]] && echo "role missing: Azure Kubernetes Service Cluster Admin Role"
    [[ ${AKSCUR} -ne 0 ]] && echo "role missing: Azure Kubernetes Service Cluster User Role"
    [[ ${AKSCR} -ne 0 ]] && echo "role missing: Azure Kubernetes Service RBAC Admin"
    [[ ${AKSRA} -ne 0 ]] && echo "role missing: Azure Kubernetes Service RBAC Cluster Admin"
    [[ ${AKSRCA} -ne 0 ]] && echo "role missing: Azure Kubernetes Service Contributor Role"
    [[ ${BR} -ne 0 ]] && echo "role missing: Billing Reader"
    [[ ${CNC} -ne 0 ]] && echo "role missing: Classic Network Contributor"
    [[ ${KCAAO} -ne 0 ]] && echo "role missing: Kubernetes Cluster - Azure Arc Onboarding"
    [[ ${NC} -ne 0 ]] && echo "role missing: Network Contributor"
    [[ ${O} -ne 0 ]] && echo "role missing: Owner"
    [[ ${R} -ne 0 ]] && echo "role missing: Reader"
    [[ ${SR} -ne 0 ]] && echo "role missing: Security Reader"
    [[ ${VNC} -ne 0 ]] && echo "role missing: virtual Machine Contributor"
  fi
  return ${RETVAL}
}

dummy() {
  return 0
}

run_vm_cmd() {
  local RETVAL=0
  local VM_RG="${1}"
  local VM_NAME="${2}"
  local VM_CMD="${3}"
  az vm run-command invoke -g "${VM_RG}" -n "${VM_NAME}" --command-id RunShellScript --scripts "${VM_CMD}"
  RETVAL=$?
  return ${RETVAL}
}

wait_pods() {
  local RETVAL=0
  local STATUS=""
  local MESSAGE=""
  local NAMESPACE="${1}"
  local POD_LABEL="${2}"
  #az aks wait --resource-group dm20rg --name cephcluster
  STATUS=$(kubectl --namespace "${NAMESPACE}" get "${POD_LABEL}" -o 'jsonpath={.items[*].status.phase}')
  RETVAL=$?
  while [[ "${STATUS,,}" != "ready" || ${RETVAL} -ne 0 ]]; do
   MESSAGE=$(kubectl --namespace "${NAMESPACE}" get "${POD_LABEL}" -o 'jsonpath={.items[*].status.message}')
   echo "waiting: ${NAMESPACE}:${POD_LABEL}:${STATUS} ${MESSAGE}"
   sleep ${WAIT_SLEEP_SECONDS}
   STATUS=$(kubectl --namespace "${NAMESPACE}" get "${POD_LABEL}" -o 'jsonpath={.items[*].status.phase}')
   RETVAL=$?
  done
  echo "complete: ${NAMESPACE}:${POD_LABEL}:${STATUS} ${MESSAGE}"
  RETVAL=0
  return ${RETVAL}
}

list_pods() {
  local RETVAL=0
  local NAMESPACE="${1}"
  local POD_LABEL="${2}"
  kubectl --namespace "${NAMESPACE}" get pods ${POD_LABEL}
  RETVAL=$?
  return ${RETVAL}
}

list_ready_nodes() {
  local RETVAL=0
  local NAMESPACE="${1}"
  local JSONPATH='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}' && \
  kubectl --namespace "${NAMESPACE}" get nodes -o jsonpath="${JSONPATH}" | grep "Ready=True"
  RETVAL=$?
  return ${RETVAL}
  #kubectl get pod -o=custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName --all-namespaces
}

list_services() {
  local RETVAL=0
  local NAMESPACE="${1}"
  local POD_LABEL="${2}"
  kubectl --namespace "${NAMESPACE}" get services
  RETVAL=$?
  return ${RETVAL}
}

list_pv() {
  local RETVAL=0
  local NAMESPACE="${1}"
  local POD_LABEL="${2}"
  kubectl --namespace "${NAMESPACE}" get pv
  RETVAL=$?
  return ${RETVAL}
}

list_password() {
  local RETVAL=0
  local NAMESPACE="${1}"
  local SECRET="${2}"
  kubectl --namespace "${NAMESPACE}" get secret ${SECRET} -o go-template='{{range $k,$v := .data}}{{"### "}}{{$k}}{{"\n"}}{{$v|base64decode}}{{"\n\n"}}{{end}}'
  RETVAL=$?
  return ${RETVAL}
}


login_az() {
  local RETVAL=0
  local AZ_STATE=""
  if [ ${AZ_CONNECTED} -ne 0 ] ; then
    AZ_STATE=$(az account show --query "state" -o tsv)
    RETVAL=$?
    if [[ "${AZ_STATE,,}" != "enabled" || ${RETVAL} -ne 0 ]] ; then
      az login --scope "${AZ_SCOPE}"
      RETVAL=$?
      [[ ${RETVAL} -ne 0 ]] && exit ${RETVAL}
    else
      AZ_CONNECTED=0
    fi
    
    AZ_SUBSCRIPTION=$(az account list --query "[].name" -o tsv)
    az account set -s "${AZ_SUBSCRIPTION}"
    RETVAL=$?
  fi
  return ${RETVAL}
}

logout_az() {
  local RETVAL=0
  local AZ_CONNECTED=1
  if [ ${AZ_CONNECTED} -eq 0 ] ; then
    AZ_CONNECTED=$(az account show | jq -r ."state")
    if [ "${AZ_CONNECTED,,}" == "enabled" ] ; then
      az logout
      RETVAL=$?
    fi
  fi
  return ${RETVAL}
}

### install/configuration steps

step1() {
  local RETVAL=0
  az group create --name "${AZ_RG}" --location "${AZ_REGION}"
  RETVAL=$?
  return ${RETVAL}
}

step2() {
  local RETVAL=0
  #az acr create --resource-group "${AZ_RG}" --name "${AZ_AKS_ACR}" --sku "${AZ_AKS_ACR_SKU}"
  #RETVAL=$?
  return ${RETVAL}
}

step3() {
  local RETVAL=0
  az network vnet create \
   --resource-group "${AZ_RG}" \
   --name "${AZ_VNET_NAME}" \
   --address-prefix "${AZ_ADDRESS_PREFIX}" \
   --location "${AZ_REGION}" && \
  az network vnet subnet create \
    --resource-group "${AZ_RG}" \
    --vnet-name "${AZ_VNET_NAME}" \
    --name "${AZ_VNET_NAME}" \
    --address-prefixes "${AZ_ADDRESS_PREFIX}" && \
  az network vnet create \
   --resource-group "${AZ_RG}" \
   --name "${BASTION_VNET_NAME}" \
   --address-prefix "${BASTION_ADDRESS_PREFIX}" \
   --subnet-name "${BASTION_SUBNET_NAME}" \
   --subnet-prefix "${BASTION_SUBNET_PREFIX}" \
   --location "${AZ_REGION}" && \
  az network vnet create \
   --resource-group "${AZ_RG}" \
   --name "${SERVICE_VNET_NAME}" \
   --address-prefix "${SERVICE_ADDRESS_PREFIX}" \
   --subnet-name "${SERVICE_SUBNET_NAME}" \
   --subnet-prefix "${SERVICE_SUBNET_PREFIX}" \
   --location "${AZ_REGION}" && \
  az network vnet create \
   --resource-group "${AZ_RG}" \
   --name "${AZ_AKS_VNET_NAME}" \
   --address-prefix "${AZ_AKS_ADDRESS_PREFIX}" \
   --subnet-name "${AZ_AKS_SUBNET_NAME}" \
   --subnet-prefix "${AZ_AKS_SUBNET_PREFIX}" \
   --location "${AZ_REGION}"  && \
  az network vnet create \
   --resource-group "${AZ_RG}" \
   --name "${DOCKER_BRIDGE_VNET_NAME}" \
   --address-prefix "${DOCKER_BRIDGE_ADDRESS_PREFIX}" \
   --subnet-name "${DOCKER_BRIDGE_SUBNET_NAME}" \
   --subnet-prefix "${DOCKER_BRIDGE_SUBNET_PREFIX}" \
   --location "${AZ_REGION}"
  RETVAL=$?
  return ${RETVAL}
}

step4() {
  local RETVAL=0
  local BASTION_RUN_SCRIPT=""
  local BASTION_1=""
  local BASTION_2=""
  local BASTION_3=""
  local BASTION_4=""
  local BASTION_5=""
  local BASTION_6=""
  local BASTION_7=""
  local BASTION_8=""
  local BASTION_9=""
  local BASTION_10=""
  local BASTION_11=""
  local BASTION_12=""
  local BASTION_13=""
  local BASTION_14=""
  local BASTION_15=""

  # custom-data
  cat <<EOF4 > "${BASTION_TMP}"
Port ${BASTION_SSH_PORT}
#AddressFamily any
#ListenAddress 0.0.0.0
#ListenAddress ::
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
# Ciphers and keying
#RekeyLimit default none
#SyslogFacility AUTH
#LogLevel INFO
StrictModes yes
PermitRootLogin no
LoginGraceTime 1m
AllowUsers ${BASTION_OS_USERNAME,,}
MaxAuthTries 3
PubkeyAuthentication yes
AuthorizedKeysFile     .ssh/authorized_keys .ssh/authorized_keys2
HostbasedAuthentication no
IgnoreUserKnownHosts no
IgnoreRhosts yes
PasswordAuthentication no
PermitEmptyPasswords no
UsePAM no
AllowAgentForwarding yes
AllowTcpForwarding yes
X11Forwarding yes
#X11DisplayOffset 10
X11UseLocalhost yes
PermitTTY yes
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
#PermitUserEnvironment no
#Compression delayed
ClientAliveInterval 0
ClientAliveCountMax 3
UseDNS no
#PidFile /var/run/sshd.pid
#MaxStartups 10:30:100
Banner none
AcceptEnv LANG LC_*
Subsystem sftp  /usr/lib/openssh/sftp-server
EOF4

  BASTION_RUN_SCRIPT=$(cat ${BASTION_TMP} | base64 -w 0 ; rm -f ${BASTION_TMP} &> /dev/null)
  BASTION_1="apt-get -y update && apt-get -y dist-upgrade && apt-get -y autoremove && apt-get -y autoclean"
  BASTION_2="export LANG=\"${AZ_LANG}\" ; sed -i -e \"s/# ${AZ_LANG}.*/${AZ_LANG} UTF-8/\" /etc/locale.gen && dpkg-reconfigure -f noninteractive locales && update-locale LANG=${AZ_LANG}"
  BASTION_3="timedatectl set-timezone ${AZ_TIMEZONE}"
  BASTION_4="echo \"${BASTION_RUN_SCRIPT}\"|base64 -d > /etc/ssh/sshd_config && sshd -t && systemctl restart ssh"
  BASTION_5="apt-get install -y apt-transport-https ca-certificates curl unzip mosh"
  BASTION_6="curl -sL https://aka.ms/InstallAzureCLIDeb | bash"
  BASTION_7="az aks install-cli --client-version \"${AZ_AKS_REQUIRED_VERSION}\" &> /dev/null"
  BASTION_8="cd /tmp ; curl -sLO https://get.helm.sh/helm-${CEPH_HELM_VERSION}-linux-amd64.tar.gz && tar -zxvf helm-${CEPH_HELM_VERSION}-linux-amd64.tar.gz && mv -f linux-amd64/helm /usr/local/bin/helm ; rm -f helm-${CEPH_HELM_VERSION}-linux-amd64.tar.gz"

  BASTION_AD_EXTENSION_VERSION=$(az vm extension image list --location "${AZ_REGION}" --publisher "${BASTION_AD_EXTENSION_PUBLISHER}" --name "${BASTION_AD_EXTENSION_NAME}" --latest --query "[-1].version" --output tsv) && \
  BASTION_OS_URN=$(az vm image list --location "${AZ_REGION}" --offer "${BASTION_OS_OFFER}" --publisher "${BASTION_OS_PUBLISHER}" --sku "${BASTION_OS_SKU}" --all --query '[-1].urn' --output tsv) && \
  az vm create --resource-group "${AZ_RG}" \
   --name "${BASTION_NAME}" \
   --location "${AZ_REGION}" \
   --admin-password "${BASTION_OS_PASSWORD}" \
   --admin-username "${BASTION_OS_USERNAME}" \
   --public-ip-sku "${AZ_PUBLIC_IP_SKU}" \
   --public-ip-address-allocation "Static" \
   --public-ip-address-dns-name "${BASTION_NAME}" \
   --ssh-key-values @"${BASTION_SSH_KEY_PUBLIC}" \
   --image "${BASTION_OS_URN}" \
   --vnet-name "${BASTION_VNET_NAME}" \
   --subnet "${BASTION_SUBNET_NAME}" \
   --encryption-at-host "${BASTION_EAH_ENABLE,,}" \
   --public-ip-address-dns-name "${BASTION_NAME}" \
   --enable-auto-update "${BASTION_EAH_ENABLE,,}" \
   --size "${BASTION_NODE_TYPE}" && \
  BASTION_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv) && \
  BASTION_PRIVATE_IP=$(az vm show --resource-group "${AZ_RG}" --name "${BASTION_NAME}" --show-details --query "privateIps" -o tsv) && \
  run_vm_cmd "${AZ_RG}" "${BASTION_NAME}" "${BASTION_1}" && \
  run_vm_cmd "${AZ_RG}" "${BASTION_NAME}" "${BASTION_2}" && \
  run_vm_cmd "${AZ_RG}" "${BASTION_NAME}" "${BASTION_3}" && \
  run_vm_cmd "${AZ_RG}" "${BASTION_NAME}" "${BASTION_4}" && \
  run_vm_cmd "${AZ_RG}" "${BASTION_NAME}" "${BASTION_5}" && \
  run_vm_cmd "${AZ_RG}" "${BASTION_NAME}" "${BASTION_6}" && \
  run_vm_cmd "${AZ_RG}" "${BASTION_NAME}" "${BASTION_7}" && \
  run_vm_cmd "${AZ_RG}" "${BASTION_NAME}" "${BASTION_8}"
  #
  # not working yet
  # 'Install handler failed for the extension. More information on troubleshooting is available at https://aka.ms/vmextensionlinuxtroubleshoot'
  # Code: VMExtensionHandlerNonTransientError
  # Message: The handler for VM extension type 'Microsoft.Azure.ActiveDirectory.LinuxSSH.AADLoginForLinux' has reported terminal failure for VM extension 'AADLoginForLinux' with error message: '[ExtensionOperationError] Non-zero exit code: 51, /var/lib/waagent/Microsoft.Azure.ActiveDirectory.LinuxSSH.AADLoginForLinux-1.0.1588.3/./installer.sh install
  #
  # finally add ActiveDirectory plugin for Linux SSH authentication
  #az vm extension set --resource-group "${AZ_RG}" \
  # --name "${BASTION_AD_EXTENSION_NAME}" \
  # --publisher "${BASTION_AD_EXTENSION_PUBLISHER}" \
  # --version "${BASTION_AD_EXTENSION_VERSION}" \
  # --vm-name "${BASTION_NAME}" && \
  RETVAL=$?
  return ${RETVAL}
}

step5() {
  local RETVAL=0
  [[ -z "${BASTION_PUBLIC_IP}" ]] && BASTION_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv)
  [[ -z "${BASTION_PRIVATE_IP}" ]] && BASTION_PRIVATE_IP=$(az vm show --resource-group "${AZ_RG}" --name "${BASTION_NAME}" --show-details --query "privateIps" -o tsv)
  [[ -z "${BASTION_FQDN}" ]] && BASTION_FQDN=$(az vm show --resource-group "${AZ_RG}" --name "${BASTION_NAME}" --show-details --query "fqdns" -o tsv)
  az network nsg create --resource-group "${AZ_RG}" \
   --name "${BASTION_NAME}nsg" \
   --location "${AZ_REGION}" \
   --tags "${PRODUCT,,}${PRODUCT_VERSION,,}" &&
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${BASTION_NAME}nsg" \
   --name "ssh" \
   --priority 100 \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${BASTION_PRIVATE_IP}/32" \
   --destination-port-ranges ${BASTION_SSH_PORT} \
   --protocol "Tcp" \
   --access "Allow" \
   --description "SSH access to Bastion" &&
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${BASTION_NAME}nsg" \
   --name "mosh" \
   --priority 110 \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${BASTION_PRIVATE_IP}/32" \
   --destination-port-ranges ${BASTION_MOSH_PORT} \
   --protocol "Udp" \
   --access "Allow" \
   --description "MOSH access to Bastion" && \
  az network nic update \
    --resource-group "${AZ_RG}" \
    --name "${BASTION_NAME}VMNic" \
    --network-security-group "${BASTION_NAME}nsg" && \
  az network vnet subnet update \
    --resource-group "${AZ_RG}" \
    --vnet-name "${BASTION_VNET_NAME}" \
    --name "${BASTION_SUBNET_NAME}" \
    --network-security-group "${BASTION_NAME}nsg"
  RETVAL=$?
  echo "bastion fqdn:       ${BASTION_FQDN}"
  echo "bastion hostname:   ${BASTION_NAME}"
  echo "bastion public ip:  ${BASTION_PUBLIC_IP}"
  echo "bastion private ip: ${BASTION_PRIVATE_IP}"
  echo "bastion username:   ${BASTION_OS_USERNAME}"
  echo "bastion password:   ${BASTION_OS_PASSWORD}"
  echo "bastion ssh:        \$ ssh -i ${BASTION_SSH_KEY_PRIVATE} -p ${BASTION_SSH_PORT} ${BASTION_OS_USERNAME}@${BASTION_FQDN}"
  echo "bastion mosh:       \$ mosh ${BASTION_OS_USERNAME}@${BASTION_FQDN} --ssh=\"ssh -p ${BASTION_SSH_PORT} -i ${BASTION_SSH_KEY_PRIVATE}\""
  return ${RETVAL}
}


step6() {
  local RETVAL=0
  local AZ_SUBNET_ID=""
  local AZ_FEATURE_HOST_BASED_ENCRYPTION_STATUS=""
  
  AZ_FEATURE_HOST_BASED_ENCRYPTION_STATUS=$(az feature list -o tsv --query "[?contains(name, 'Microsoft.Compute/EncryptionAtHost')].{State:properties.state}")
  if [ "${AZ_FEATURE_HOST_BASED_ENCRYPTION_STATUS,,}" != "registered" ] ; then
    az feature register --name EncryptionAtHost --namespace Microsoft.Compute
    RETVAL=$?
    while [[ "${AZ_FEATURE_HOST_BASED_ENCRYPTION_STATUS,,}" != "registered" && ${RETVAL} -eq 0 ]] ; do
     echo "waiting: Host-based encryption to enable"
     sleep ${WAIT_SLEEP_SECONDS}
     AZ_FEATURE_HOST_BASED_ENCRYPTION_STATUS=$(az feature list -o tsv --query "[?contains(name, 'Microsoft.Compute/EncryptionAtHost')].{State:properties.state}")
    done
  fi
  [[ ${RETVAL} -eq 0 ]] && AZ_SUBNET_ID=$(az network vnet subnet show --resource-group "${AZ_RG}" --vnet-name "${AZ_VNET_NAME}" --name "${AZ_VNET_NAME}" --query "id" -o tsv) && \
  az aks create \
    --resource-group "${AZ_RG}" \
    --name "${AZ_AKS_CLUSTER}" \
    --kubernetes-version "${AZ_AKS_REQUIRED_VERSION}" \
    -s ${AZ_AKS_NODE_TYPE} \
    --node-osdisk-type ${AZ_AKS_NODE_DISK_TYPE} \
    --node-osdisk-size ${AZ_AKS_NODE_OS_DISK_SIZE} \
    --node-count ${AZ_AKS_CLUSTER_NODES} \
    --load-balancer-sku "${AZ_AKS_NODE_LB_SKU}" \
    --network-plugin "${AZ_AKS_NETWORK_PLUGIN}" \
    --service-cidr "${SERVICE_ADDRESS_PREFIX}" \
    --dns-service-ip "${DNS_SERVICE_IP}" \
    --docker-bridge-address "${DOCKER_BRIDGE_ADDRESS_PREFIX}" \
    --zones ${AZ_ZONES} \
    --enable-encryption-at-host \
    --vnet-subnet-id "${AZ_SUBNET_ID}"

# need to use express route or vpn to access if enable-private-cluster included
#   --enable-private-cluster \
#   --disable-public-fqdn \
#   --private-dns-zone "${AZ_AKS_PRIVATE_DNS_ZONE}" \
#  --attach-acr "${AZ_AKS_ACR}"
#  --enable-managed-identity --enable-addons monitoring --enable-msi-auth-for-monitoring \
  RETVAL=$?
  return ${RETVAL}
}

step7() {
  local RETVAL=0
  az aks get-credentials --name "${AZ_AKS_CLUSTER}" \
    --overwrite-existing \
    --resource-group "${AZ_RG}"
  RETVAL=$?
  #kubectl get nodes
  return ${RETVAL}
}

step8() {
  local RETVAL=0
  [[ ${SKIP_CEPH} -eq 0 ]] && return ${RETVAL}
  az aks nodepool add --cluster-name "${AZ_AKS_CLUSTER}" \
    --name "${AZ_AKS_CEPH_POOL}" \
    --kubernetes-version "${AZ_AKS_REQUIRED_VERSION}" \
    --node-count "${AZ_AKS_CEPH_POOL_NODES}" \
    --node-vm-size "${AZ_AKS_NODE_TYPE}" \
    --node-osdisk-size "${AZ_AKS_NODE_OS_DISK_SIZE}" \
    --resource-group "${AZ_RG}" \
    --zones ${AZ_ZONES} \
    --enable-encryption-at-host \
    --node-taints storage-node=true:NoSchedule
  RETVAL=$?
  return ${RETVAL}
}
    
step9() {
  local RETVAL=0
  [[ ${SKIP_CEPH} -eq 0 ]] && return ${RETVAL}
  cat <<EOF9 > "${CEPH_OPERATOR_YAML}"
# https://github.com/rook/rook/blob/master/Documentation/Helm-Charts/operator-chart.md
crds:
  enabled: true
csi:
  provisionerTolerations:
    - effect: NoSchedule
      key: storage-node
      operator: Exists
  pluginTolerations:
    - effect: NoSchedule
      key: storage-node
      operator: Exists
agent:
  # AKS: https://rook.github.io/docs/rook/v1.7/flexvolume.html#azure-aks
  flexVolumeDirPath: "${AZ_AKS_CSI_PLUGINS}"
EOF9
  RETVAL=$?
  return ${RETVAL}
}

step10() {
  local RETVAL=0
  [[ ${SKIP_CEPH} -eq 0 ]] && return ${RETVAL}
  helm install rook-ceph-operator rook-ceph \
  --namespace rook-ceph \
  --create-namespace \
  --version "${CEPH_CHART_VERSION}" \
  --repo https://charts.rook.io/release/ \
  --values "${CEPH_OPERATOR_YAML}" && \
  wait_pods "rook-ceph" "rook-ceph-operator"
  RETVAL=$?
  return ${RETVAL}
}

step11() {
  local RETVAL=0
  [[ ${SKIP_CEPH} -eq 0 ]] && return ${RETVAL}
  cat <<EOF11 > "${CEPH_CLUSTER_YAML}"
#
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph # namespace:cluster
spec:
  dataDirHostPath: /var/lib/rook
  mon:
    count: ${AZ_AKS_CLUSTER_NODES}
    allowMultiplePerNode: false
    volumeClaimTemplate:
      spec:
        storageClassName: managed-premium
        resources:
          requests:
            storage: ${CEPH_OSD_DISK_SIZE}Gi
  cephVersion:
    image: quay.io/ceph/ceph:v17.2.3
    allowUnsupported: false
  skipUpgradeChecks: false
  continueUpgradeAfterChecksEvenIfNotHealthy: false
  mgr:
    count: 2
    modules:
      - name: pg_autoscaler
        enabled: true
  dashboard:
    enabled: ${CEPH_DASHBOARD_ENABLED,,}
    ssl: true
  crashCollector:
    disable: false
  storage:
    storageClassDeviceSets:
      - name: set1
        # The number of OSDs to create from this device set
        count: ${AZ_AKS_CLUSTER_NODES}
        # IMPORTANT: If volumes specified by the storageClassName are not portable across nodes
        # this needs to be set to false. For example, if using the local storage provisioner
        # this should be false.
        portable: true
        # Certain storage class in the Cloud are slow
        # Rook can configure the OSD running on PVC to accommodate that by tuning some of the Ceph internal
        # Currently, "gp2" has been identified as such
        tuneDeviceClass: true
        # Certain storage class in the Cloud are fast
        # Rook can configure the OSD running on PVC to accommodate that by tuning some of the Ceph internal
        # Currently, "managed-premium" has been identified as such
        tuneFastDeviceClass: false
        # whether to encrypt the deviceSet or not
        encrypted: false
        # Since the OSDs could end up on any node, an effort needs to be made to spread the OSDs
        # across nodes as much as possible. Unfortunately the pod anti-affinity breaks down
        # as soon as you have more than one OSD per node. The topology spread constraints will
        # give us an even spread on K8s 1.18 or newer.
        placement:
          topologySpreadConstraints:
            - maxSkew: 1
              topologyKey: kubernetes.io/hostname
              whenUnsatisfiable: ScheduleAnyway
              labelSelector:
                matchExpressions:
                  - key: app
                    operator: In
                    values:
                      - rook-ceph-osd
          tolerations:
            - key: storage-node
              operator: Exists
        preparePlacement:
          podAntiAffinity:
            preferredDuringSchedulingIgnoredDuringExecution:
              - weight: 100
                podAffinityTerm:
                  labelSelector:
                    matchExpressions:
                      - key: app
                        operator: In
                        values:
                          - rook-ceph-osd
                      - key: app
                        operator: In
                        values:
                          - rook-ceph-osd-prepare
                  topologyKey: kubernetes.io/hostname
          topologySpreadConstraints:
            - maxSkew: 1
              # IMPORTANT: If you don't have zone labels, change this to another key such as kubernetes.io/hostname
              topologyKey: topology.kubernetes.io/zone
              whenUnsatisfiable: DoNotSchedule
              labelSelector:
                matchExpressions:
                  - key: app
                    operator: In
                    values:
                      - rook-ceph-osd-prepare
        resources:
        # These are the OSD daemon limits. For OSD prepare limits, see the separate section below for "prepareosd" resources
        #   limits:
        #     cpu: "500m"
        #     memory: "4Gi"
        #   requests:
        #     cpu: "500m"
        #     memory: "4Gi"
        volumeClaimTemplates:
          - metadata:
              name: data
              # if you are looking at giving your OSD a different CRUSH device class than the one detected by Ceph
              # annotations:
              #   crushDeviceClass: hybrid
            spec:
              resources:
                requests:
                  storage:  ${CEPH_OSD_DISK_SIZE}Gi
              # IMPORTANT: Change the storage class depending on your environment
              storageClassName: managed-premium
              volumeMode: Block
              accessModes:
                - ReadWriteOnce
        # dedicated block device to store bluestore database (block.db)
        # - metadata:
        #     name: metadata
        #   spec:
        #     resources:
        #       requests:
        #         # Find the right size https://docs.ceph.com/docs/master/rados/configuration/bluestore-config-ref/#sizing
        #         storage: 5Gi
        #     # IMPORTANT: Change the storage class depending on your environment
        #     storageClassName: io1
        #     volumeMode: Block
        #     accessModes:
        #       - ReadWriteOnce
        # dedicated block device to store bluestore wal (block.wal)
        # - metadata:
        #     name: wal
        #   spec:
        #     resources:
        #       requests:
        #         # Find the right size https://docs.ceph.com/docs/master/rados/configuration/bluestore-config-ref/#sizing
        #         storage: 5Gi
        #     # IMPORTANT: Change the storage class depending on your environment
        #     storageClassName: io1
        #     volumeMode: Block
        #     accessModes:
        #       - ReadWriteOnce
        # Scheduler name for OSD pod placement
        # schedulerName: osd-scheduler
    # when onlyApplyOSDPlacement is false, will merge both placement.All() and storageClassDeviceSets.Placement.
    onlyApplyOSDPlacement: false
  resources:
  #  prepareosd:
  #    limits:
  #      cpu: "200m"
  #      memory: "200Mi"
  #   requests:
  #      cpu: "200m"
  #      memory: "200Mi"
  priorityClassNames:
    # If there are multiple nodes available in a failure domain (e.g. zones), the
    # mons and osds can be portable and set the system-cluster-critical priority class.
    mon: system-node-critical
    osd: system-node-critical
    mgr: system-cluster-critical
  disruptionManagement:
    managePodBudgets: true
    osdMaintenanceTimeout: 30
    pgHealthCheckTimeout: 0
    manageMachineDisruptionBudgets: false
    machineDisruptionBudgetNamespace: openshift-machine-api
  # security oriented settings
  # security:
  # To enable the KMS configuration properly don't forget to uncomment the Secret at the end of the file
  #   kms:
  #     # name of the config map containing all the kms connection details
  #     connectionDetails:
  #        KMS_PROVIDER: "vault"
  #        VAULT_ADDR: VAULT_ADDR_CHANGE_ME # e,g: https://vault.my-domain.com:8200
  #        VAULT_BACKEND_PATH: "rook"
  #        VAULT_SECRET_ENGINE: "kv"
  #     # name of the secret containing the kms authentication token
  #     tokenSecretName: rook-vault-token
EOF11
  RETVAL=$?
  return ${RETVAL}
}

step12() {
  local RETVAL=0
  [[ ${SKIP_CEPH} -eq 0 ]] && return ${RETVAL}
  helm install rook-ceph-cluster rook-ceph-cluster \
   --namespace rook-ceph \
   --create-namespace \
   --version "${CEPH_CHART_VERSION}" \
   --repo https://charts.rook.io/release/ \
   --values ${CEPH_CLUSTER_YAML} \
   --wait
  RETVAL=$?
  return ${RETVAL}
}

step13() {
  local RETVAL=0
  [[ ${SKIP_CEPH} -eq 0 ]] && return ${RETVAL}
  wait_pods "rook-ceph" "cephcluster" && \
  wait_pods "rook-ceph" "cephFileSystems"
  RETVAL=$?
  return ${RETVAL}
}

step14() {
  local RETVAL=0
  [[ ${SKIP_CEPH} -eq 0 ]] && return ${RETVAL}
  if [ "${CEPH_DASHBOARD_ENABLED,,}" == "true" ] ; then
    CEPH_DASHBOARD_PASSWORD=$(kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath='{.data.password}' | base64 -d) && \
    [[ "${CEPH_DASHBOARD_OPEN,,}" == "true" ]] && nohup kubectl -n rook-ceph port-forward svc/rook-ceph-mgr-dashboard ${CEPH_DASHBOARD_INTERNAL_PORT}:${CEPH_DASHBOARD_EXTERNAL_PORT} > ${CEPH_DASHBOARD_OPEN_LOG} 2>&1 &
    CEPH_DASHBOARD_OPEN_PID=$!
    RETVAL=$?
    echo "dashboard: username=${CEPH_DASHBOARD_USERNAME}"
    echo "dashboard: password=${CEPH_DASHBOARD_PASSWORD}"
    echo "dashboard: port-forward PID=${CEPH_DASHBOARD_OPEN_PID}"
    echo "dashboard: port-forward log=${CEPH_DASHBOARD_OPEN_LOG}"
    echo "dashboard: to connect use ssh -L 8443:localhost:8443 kubeadmin@{aks-ip}, then https://127.0.0.1:8443"
  else
    echo "dashboard: skipping, not enabled"
    RETVAL=0
  fi
  return ${RETVAL}
}

step15() {
  local RETVAL=0
  [[ ${SKIP_CEPH} -eq 0 ]] && return ${RETVAL}
  cat <<EOF15 > "${CEPH_TOOLBOX_YAML}"
apiVersion: batch/v1
kind: Job
metadata:
  name: rook-ceph-toolbox-job
  namespace: rook-ceph # namespace:cluster
  labels:
    app: ceph-toolbox-job
spec:
  template:
    spec:
      initContainers:
        - name: config-init
          image: rook/ceph:v1.10.1
          command: ["/usr/local/bin/toolbox.sh"]
          args: ["--skip-watch"]
          imagePullPolicy: IfNotPresent
          env:
            - name: ROOK_CEPH_USERNAME
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-mon
                  key: ceph-username
            - name: ROOK_CEPH_SECRET
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-mon
                  key: ceph-secret
          volumeMounts:
            - mountPath: /etc/ceph
              name: ceph-config
            - name: mon-endpoint-volume
              mountPath: /etc/rook
      containers:
        - name: script
          image: rook/ceph:v1.10.1
          volumeMounts:
            - mountPath: /etc/ceph
              name: ceph-config
              readOnly: true
          command:
            - "bash"
            - "-c"
            - |
              # Modify this script to run any ceph, rbd, radosgw-admin, or other commands that could
              # be run in the toolbox pod. The output of the commands can be seen by getting the pod log.
              #
              # example: print the ceph status
              ceph status
      volumes:
        - name: mon-endpoint-volume
          configMap:
            name: rook-ceph-mon-endpoints
            items:
              - key: data
                path: mon-endpoints
        - name: ceph-config
          emptyDir: {}
      restartPolicy: Never
EOF15
  return ${RETVAL}
}

step16() {
  local RETVAL=0
  [[ ${SKIP_CEPH} -eq 0 ]] && return ${RETVAL}
  kubectl create -f ${CEPH_TOOLBOX_YAML}
  RETVAL=$?
  return ${RETVAL}
}

step17() {
  local RETVAL=0
  [[ ${SKIP_CEPH} -eq 0 ]] && return ${RETVAL}
  #echo "toolbox: use \$ kubectl -n rook-ceph exec -it \$(kubectl -n rook-ceph get pod -l \"app=rook-ceph-tools\" -o jsonpath=\'{.items[0].metadata.name}\') bash"
  wait_pods "rook-ceph" "rook-ceph-toolbox-job"
  RETVAL=$?
  return ${RETVAL}
}

step18() {
  local RETVAL=0
  [[ ${SKIP_CEPH} -eq 0 ]] && return ${RETVAL}
  kubectl -n rook-ceph logs -l job-name=rook-ceph-toolbox-job
  RETVAL=$?
  return ${RETVAL}
}

step19() {
  local RETVAL=0
  [[ ${SKIP_CEPH} -eq 0 ]] && return ${RETVAL}
  #ignore if fails
  kubectl -n rook-ceph delete deployment rook-ceph-toolbox-job &> /dev/null
  #RETVAL=$?
  return ${RETVAL}
}


step20() {
  local RETVAL=0
  local NODE_PING=1
  if [[ "${CUSTOMER_BACKUP_VPN_HOST}" =~ ^[0-9] ]] ; then
    CUSTOMER_BACKUP_VPN_IP=$(getent hosts "${CUSTOMER_BACKUP_VPN_HOST}"|head -1|awk '{print $1'})
  else
    CUSTOMER_BACKUP_VPN_IP="${CUSTOMER_BACKUP_VPN_HOST}"
  fi
  if [[ ${CUSTOMER_BACKUP_VPN_IP} =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] ; then
    CUSTOMER_BACKUP_VPN_IPV4=0
    ${DO_SUDO} ping -c 1 -n -q ${CUSTOMER_BACKUP_VPN_IP} &> /dev/null
    RETVAL=$?
  else
    CUSTOMER_BACKUP_VPN_IPV6=0
    ${DO_SUDO} ping6 -c 1 -n -q ${CUSTOMER_BACKUP_VPN_IP} &> /dev/null
    RETVAL=$?
  fi
  [[ ${RETVAL} -eq 0 ]] && CUSTOMER_BACKUP_VPN_PING_OK=0
  RETVAL=$?
  return ${RETVAL}
}


step21() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step22() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step23() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step24() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step25() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step26() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step27() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step28() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step29() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step30() {
  local RETVAL=0
  az aks nodepool add --cluster-name "${AZ_AKS_CLUSTER}" \
    --name "${AZ_AKS_DM_POOL}" \
    --kubernetes-version "${AZ_AKS_REQUIRED_VERSION}" \
    --node-count "${AZ_AKS_DM_POOL_NODES}" \
    --node-vm-size "${AZ_AKS_NODE_TYPE}" \
    --node-osdisk-size "${AZ_AKS_NODE_OS_DISK_SIZE}" \
    --resource-group "${AZ_RG}" \
    --enable-encryption-at-host \
    --zones ${AZ_ZONES}
  RETVAL=$?
  return ${RETVAL}
}

step31() {
  local RETVAL=0
  #Enforce encryption on existing secrets
  kubectl get secrets --all-namespaces -o json | kubectl replace -f -
  RETVAL=$?
  return ${RETVAL}
}

step32() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step33() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step34() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step35() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step36() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step37() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step38() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

step39() {
  local RETVAL=0
  #RETVAL=$?
  return ${RETVAL}
}

### main entry
if [ $# -eq 0 ] ; then
  check_env && \
  login_az && \
  check_roles && \
  step1 && \
  step2 && \
  step3 && \
  step4 && \
  step5 && \
  step6 && \
  step7 && \
  step8 && \
  step9 && \
  step10 && \
  step11 && \
  step12 && \
  step13 && \
  step14 && \
  step15 && \
  step16 && \
  step17 && \
  step18 && \
  step19 && \
  step20 && \
  step21 && \
  step22 && \
  step23 && \
  step24 && \
  step25 && \
  step26 && \
  step27 && \
  step28 && \
  step29 && \
  step30 && \
  step31 && \
  step32 && \
  step33 && \
  step34 && \
  step35 && \
  step36 && \
  step37 && \
  step38 && \
  step39
  RETVAL=$?
  logout_az
  clean_tmp_files
else
  check_env && \
  login_az
  RETVAL=$?
  if [[ ${RETVAL} -eq 0 ]] ; then
    for STEP in "$@" ; do
      case "${STEP,,}" in
        --help)     help
                    exit 0
                    ;;
        --nologout) NOLOGOUT=0
                    ;;
        --sigint)   trap - SIGINT
                    ;;
        *)          ${STEP,,}
                    RETVAL=$?
                    ;;
      esac
      [[ ${RETVAL} -ne 0 ]] && break
    done
    [[ ${NOLOGOUT} -ne 0 ]] && logout_az
  fi
fi

trap - SIGINT

exit ${RETVAL}
