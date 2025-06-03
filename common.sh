if [ -t 1 ] ; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    LTGREEN='\033[01;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    LTBLUE='\033[1;34m'
    GRAY='\033[1;30m'
    LTGRAY='\033[0;37m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
    COLS=$(tput cols)
    USING_COLOURS=true
    IS_TERMINAL=true
else
    RED=""
    GREEN=""
    LTGREEN=""
    YELLOW=""
    BLUE=""
    LTBLUE=""
    GRAY=""
    LTGRAY=""
    CYAN=""
    NC=""
    COLS=80
    USING_COLOURS=false
    IS_TERMINAL=false
fi
if [[ -v $COLUMNS ]] ; then
    COLUMNS="$COLS"
fi
COLOURS_SET="1"

### shell hacks for WSL, Debian/Ubuntu etc.
[[ $(grep -i Microsoft /proc/version &> /dev/null) -eq 0 ]] && DO_SUDO="sudo" || DO_SUDO=""

# show message with timestamp
function msg_show()
{
(set +x
    local symbol="$1"
    local col="$2"
    local msg="$3"
    local nl=0
    local t; local tlen; local msglen; local spaces
    if [[ -z "$symbol" ]] ; then
        symbol="  "
    fi
    t=$(date +'%H:%M:%S')
    tlen="${#t}"
    msglen="${#msg}"

    ((len=COLS - tlen - 3))
    ((msglen=msglen + 4))
    # if not using terminal or msg length exceeds our threshold we show timestamp on new line
    if [[ -z "$GRAY" || ${msglen} -gt $len ]] ; then
        nl=1
    fi
    echo -e "${symbol}  ${col}${msg}${NC}"
    if [[ $nl -eq 0 ]] ; then
        echo -en "\033[1A\033[${len}C" # eg go up one line and move right $len spaces
    else
        spaces=$(printf "%*s" $len "")
        echo -n "$spaces"
    fi
    echo -e "${GRAY}[$t]${NC}"
)
}

# Show error message and possible workaround message but not exit
function error()
{
(
set +x
    local err="$1"
    local workaround="$2"
    msg_show "❌" "${RED}" "${err}!"
    if [ -n "$workaround" ] ; then
        echo -e "🔎  ${LTGREEN}${workaround}${NC}"
    fi
)
    #exit 255
}

# Show warning message and possible workaround message
function warning()
{
(
set +x
    local msg="$1"
    local workaround="$2"
	local DEBUGGING=1
	[[ $- == *e* ]] && (DEBUGGING=0 ; set +x)
    msg_show "🔥" "${YELLOW}" "${msg}"
    if [ -n "$workaround" ] ; then
        echo -e "🔎  ${LTGREEN}${workaround}${NC}"
    fi
)
}

# Proceed to do something
function doing()
{
(
set +x
    local msg="$1"
	local DEBUGGING=1
	[[ $- == *e* ]] && (DEBUGGING=0 ; set +x)
    msg_show "▶️ " "${GREEN}" "$msg"
)
}

# Proceed to do something a tad drastic
function alert()
{
(
set +x
    local msg="$1"
    local workaround="$2"
	local DEBUGGING=1
	[[ $- == *e* ]] && (DEBUGGING=0 ; set +x)
    msg_show "✋" "${YELLOW}" "$msg"
    if [ -n "$workaround" ] ; then
        echo -e "🔎  ${LTGREEN}${workaround}${NC}"
    fi
)
}

# Successfully completed a task or script
function info()
{
(
set +x
	[[ $- == *e* ]] && (DEBUGGING=0 ; set +x)
    local msg="$1"
    msg_show "ℹ" "${LTGRAY}" "$msg"
)
}

# Successfully completed a task or script
function success()
{
(
set +x
    local msg="$1"
    msg_show "✅" "${GREEN}" "$msg"
)
}

# sleep given # of seconds with some progress graph shown
function xsleep()
{
(
set +x
    local ts="${1:-$WAIT_SLEEP_SECONDS}"

    local eta ; local etam; local etah; local etas; local etai; local etax
    local ts ; local st; local cts ; local el
    ((etah=ts / (60*60), etam=ts / 60, etas=ts % 60))
    etai=$(printf "%d:%02d:%02d" $etah $etam $etas)
    if [ ! -t 1 ] ; then
        echo -en "⏲   Waiting for ${CYAN}$etai${NC}..."
        sleep $ts
        #echo "Done"
        return
    fi
    eta=$ts
    echo -en "\033[?25l" # hide cursor
    for ((st=0; st<=ts; st++)) ; do
        echo -ne "\r⏲   Waiting ${GRAY}|${GREEN}"
        cts=$(echo "print(int((60.0/$ts)*$st))" | python3)
        for ((el=0; el<60; el++)) ; do
            if [[ $cts -eq $el ]] ; then
                echo -ne "${GRAY}"
            fi
            echo -ne "━"
        done
        ((etah=eta / (60*60), etam=eta / 60, etas=eta % 60))
        etax=$(printf "%d:%02d:%02d" $etah $etam $etas)
        echo -ne "${GRAY}| ${WHITE}eta ${CYAN}$etax${NC}     \r"
        sleep 1
        ((eta=eta - 1))
    done
    echo -e "\033[0K\033[?25h" # clear to EOL, show cursor
    echo -e "⏲   Waited for ${CYAN}$etai${NC}"
)
}

function help() {
  echo "usage: ${0##*/} [ [--nologout] [--sigint] [--help] [clean] [stepX] ]"
  echo "or, "
  echo "usage: ${0##*/} "
  exit 0
}

function lookup_platform_config()
{
  declare -n RET="${1}"
  RET=$(yq -e ".${1}" < "${CONFIGFILE}" 2>/dev/null)
  RETVAL=$?
  if [ ${RETVAL} -ne 0 ] ; then
    RET=""
  fi
  return ${RETVAL}
}

function lookup_platform_config()
{
  declare -n RET="${1}"
  local SECRETNAME="${2}"
  local NAMESPACE="${3}"
  local JSONFILTER="${4}"
  local GOTEMPLATE="${5}"
  local DECODE="${6:-true}"
  local KCTL=""
  
  KCTL="kubectl get secret"
  [[ -n "${NAMESPACE}" ]] && KCTL+=" -n ${NAMESPACE}"
  KCTL+=" {}.${SECRETNAME}"
  [[ -n "${JSONFILTER}" ]] && KCTL+=" -o=jsonpath={${JSONFILTER}}"
  [[ -n "${GOTEMPLATE}" ]] && KCTL+=" -o go-template={${GOTEMPLATE}}"
  [[ "${DECODE,,}" == "true" ]] && KCTL+="|base64 --decode"
  RET=$($KCTL})
  RETVAL=$?
  return ${RETVAL}
}
	
function login_az() {
  local RETVAL=0
  local AZ_STATE=""
  check_env && \
  if [ ! -f ~/.azure.${AZ_SUBSCRIPTION} ] ; then
    command -v az &> /dev/null || install_az
    az login --scope "${AZ_SCOPE}" #&& \#
	#az login --service-principal -u "${AZ_SP_APPID}" -p "${AZ_SP_PASSWORD}" --tenant "${AZ_SP_TENANT}" && \
    touch ~/.azure.${AZ_SUBSCRIPTION}
    RETVAL=$?
    if [ ${RETVAL} -eq 0 ] ; then
      az config set extension.use_dynamic_install=yes_without_prompt --output none --only-show-errors && \
      az account set -s "${AZ_SUBSCRIPTION}" --output none --only-show-errors && \
      check_roles && \
      check_env_cloud && \
      az account subscription list --query "[?displayName=='${AZ_SUBSCRIPTION}'].id" --output tsv --only-show-errors|cut -d"/" -f3 > ~/.azure.${AZ_SUBSCRIPTION}
      RETVAL=$?
    else
      error "- Login to Azure failed, try manually using: az login --scope \"${AZ_SCOPE}\" --use-device-code"
      exit 1
    fi
  fi
  AZ_SUBSCRIPTION_ID=$(cat ~/.azure.${AZ_SUBSCRIPTION}) && \
  [[ $(az group list --query "[?location=='${AZ_REGION}'&&name=='${AZ_RG}'].name" --output tsv --only-show-errors|wc -l) -eq 0 ]] && \
    ( AZ_RG_ID=$(az group create --name "${AZ_RG}" --location "${AZ_REGION}" --query id --output tsv --only-show-errors); RETVAL=$? )
  [[ -z "${AZ_RG_ID}" ]] && ( AZ_RG_ID=$(az group show --name "${AZ_RG}" --query "id" --output tsv --only-show-errors) ; RETVAL=$? )
  RETVAL=$?
  return ${RETVAL}
}

function logout_az() {
  local RETVAL=0
  if [ -f ~/.azure.${AZ_SUBSCRIPTION} ] ; then
    az logout --output none --only-show-errors
    RETVAL=$?
    rm -f ~/.azure.${AZ_SUBSCRIPTION} &> /dev/null
  fi
  return ${RETVAL}
}

function clean_tmp_files() {
  local RETVAL=0
  rm -f /tmp/azure.???????? &> /dev/null
  return ${RETVAL}
}

function clean_az() {
  local RETVAL=0
  VPN_OS_URN=$(az vm image list --location "${AZ_REGION}" --offer "${VPN_OS_OFFER}" --publisher "${VPN_OS_PUBLISHER}" --sku "${VPN_OS_SKU}" --all --query '[-1].urn' --output tsv --only-show-errors) && \
  az vm image terms cancel --urn "${VPN_OS_URN}" --output none --only-show-errors
  [[ -n $(az group list --query "[?location=='${AZ_REGION}' && name=='${AZ_RG}'].name" --output tsv --only-show-errors) ]] && \
    (az group delete --name "${AZ_RG}" --yes --output none --only-show-errors; RETVAL=$?)
  # takes extremely long time, so skip for now
  #[[ $(az feature list -o tsv --query "[?contains(name, 'Microsoft.Compute/EncryptionAtHost')].{State:properties.state}" --only-show-errors) == "Registered" ]] && \
  #  ( az feature unregister --name EncryptionAtHost --namespace Microsoft.Compute --only-show-errors ; RETVAL=$? )
  return ${RETVAL}
}

function clean() {
  local RETVAL=0
  trap '' SIGINT
  clean_az
  clean_tmp_files
  RETVAL=$?
  trap - INT
  return ${RETVAL}
}

install_notary() {
  local RETVAL=0
  sudo apt -y install notary &> /dev/null
  RETVAL=$?
  return ${RETVAL}
}

function install_az() {
  local RETVAL=0
  [[ ! $(apt-cache policy|grep -i packages.microsoft.com/repos/azure-cli &> /dev/null) ]] && (curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash ; RETVAL=$?)
  return ${RETVAL}
}

function install_az_aks_cli() {
  local RETVAL=0
  [[ $(az aks list --output none --only-show-errors &> /dev/null) ]] && REVTAL=$? || ( sudo az aks install-cli --client-version "${AZ_AKS_REQUIRED_VERSION}" &> /dev/null ; RETVAL=$? )
  return ${RETVAL}
}

function upgrade_az_aks_cli() {
  local RETVAL=0
  local AZ_AKS_CURRENT_VERSION=""
  AZ_AKS_CURRENT_VERSION=$(kubectl version --client --output=yaml|grep "gitVersion"|awk -F ":" '{print $2}')
  AZ_AKS_CURRENT_VERSION="${AZ_AKS_CURRENT_VERSION// /}"
  AZ_AKS_CURRENT_VERSION="${AZ_AKS_CURRENT_VERSION//v/}"
  if [[ "${AZ_AKS_REQUIRED_VERSION,,}" == "${AZ_AKS_CURRENT_VERSION,,}" ]] ; then
    RETVAL=0
  else
    doing "Azure AKS ${AZ_REGION} current AKS version: ${AZ_AKS_CURRENT_VERSION}"
    doing "Azure AKS ${AZ_REGION} required AKS version: ${AZ_AKS_REQUIRED_VERSION}"
    sudo az aks install-cli --client-version "${AZ_AKS_REQUIRED_VERSION}" &> /dev/null && \
    az upgrade --all --yes --output none --only-show-errors &> /dev/null
    RETVAL=$?
  fi
  return ${RETVAL}
}

function install_helm() {
  local RETVAL=0
  if [ -n "${1}" ] ; then
    if [ "${1,,}" == "--force" ] ; then
      [[ -f /usr/local/bin/helm ]] && sudo rm -f /usr/local/bin/helm &> /dev/null
    fi
  fi
  [[ -f helm-${AZ_HELM_VERSION}-linux-amd64.tar.gz ]] && rm -f helm-${AZ_HELM_VERSION}-linux-amd64.tar.gz &> /dev/null
  curl -sLO https://get.helm.sh/helm-${AZ_HELM_VERSION}-linux-amd64.tar.gz && \
  tar -zxvf helm-${AZ_HELM_VERSION}-linux-amd64.tar.gz && \
  sudo mv -f linux-amd64/helm /usr/local/bin/helm
  sudo chmod 755 /usr/local/bin/helm
  RETVAL=$?
  return ${RETVAL}
}

function upgrade_helm() {
  local RETVAL=0
  #local HELM_WANTED_VERSION=""
  #HELM_WANTED_VERSION=$(helm version --short|awk '{gsub(/ /,");gsub(/+.*/,");print $1}')
  # if [[ "${AZ_HELM_VERSION,,}" == "${HELM_WANTED_VERSION,,}" ]] ; then
  #  RETVAL=0
  #else
  #  echo "Azure AKS ${AZ_REGION} current HELM version: ${AZ_HELM_VERSION}"
  #  echo "Azure AKS ${AZ_REGION} required HELM version: ${HELM_WANTED_VERSION}"
  #  install_helm --force
  #  RETVAL=$?
  #fi
  return ${RETVAL}
}

function install_yq() {
  local RETVAL=0
  if [ -n "${1}" ] ; then
    if [ "${1,,}" == "--force" ] ; then
      [[ -f /usr/local/bin/yq ]] && sudo rm -f /usr/local/bin/yq &> /dev/null
    fi
  fi
  curl -sLO https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && \
  sudo mv -f yq_linux_amd64 /usr/local/bin/yq
  sudo chmod 755 /usr/local/bin/yq
  RETVAL=$?
  return ${RETVAL}
}

#function install_docker() {
#  local RETVAL=0
#  sudo apt install --no-install-recommends apt-transport-https ca-certificates curl gnupg2
#  curl -L https://raw.githubusercontent.com/docker/compose-cli/main/scripts/install/install_linux.sh | sh
#  RETVAL=$?
#  return ${RETVAL}
#}

#function upgrade_docker() {
#  local RETVAL=0
#  return ${RETVAL}
#}

function check_env() {
  local RETVAL=0
  local MISSING=""
  qp() {
    dpkg -s ${1} &> /dev/null
    [[ $? -ne 0 ]] && (MISSING+=" ${1}" ; warning "missing ${1}")
  }
  # check for installed shell commands
  qp apt-transport-https
  qp ca-certificates
  qp curl
  qp unzip
  qp sshpass
#  qp yamllint
#  qp python3-pip
#  qp ansible
  qp notary
  qp sed
  qp pwgen
  qp dnsutils
  [[ -n "${MISSING}" ]] && (sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ${MISSING} ; RETVAL=$?)
  [[ ${RETVAL} -ne 0 ]] && error "failed to install environment dependencies"
  return ${RETVAL}
}

function check_env_python() {
  local RETVAL=0
  pip3 install --upgrade pip --quiet
  [[ $(python3 -m pip list|grep ansible &>/dev/null 2>&1) -ne 0 ]] && python3 -m pip install --user ansible
  [[ $(ansible-galaxy collection list|grep azure.azcollection &>/dev/null 2>&1) -ne 0 ]] && ansible-galaxy collection install azure.azcollection
  [[ $(python3 -m pip list|grep azure- &>/dev/null 2>&1) -ne 0 ]] && pip3 install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements-azure.txt
  [[ ${RETVAL} -ne 0 ]] && error "failed to install environment dependencies"
  return ${RETVAL}
}

function check_env_cloud() {
  local RETVAL=0
  # check for azure and k8s components
  [[ $(az aks get-versions --location "${AZ_REGION}" --query "id" --output tsv) ]] || install_az_aks_cli && upgrade_az_aks_cli
  #command -v helm &> /dev/null || install_helm && upgrade_helm
  command -v yq &> /dev/null || install_yq
  RETVAL=$?
  return ${RETVAL}
}

function check_roles() {
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
  local SC=1
  ROLES=$(az role assignment list --query "[].roleDefinitionName" -o tsv --only-show-errors|sort -u)
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
    RETVAL=0
  else
    RETVAL=2
    [[ ${AAEKCUR} -ne 0 ]] && error "Azure role missing: Arc Enabled Kubernetes Cluster User Role"
    [[ ${AAKA} -ne 0 ]] && error "Azure role missing: Arc Kubernetes Admin"
    [[ ${AAKCA} -ne 0 ]] && error "Azure role missing: Arc Kubernetes Cluster Admin"
    [[ ${AKSCAR} -ne 0 ]] && error "Azure role missing: Kubernetes Service Cluster Admin Role"
    [[ ${AKSCUR} -ne 0 ]] && error "Azure role missing: Kubernetes Service Cluster User Role"
    [[ ${AKSCR} -ne 0 ]] && error "Azure role missing: Kubernetes Service RBAC Admin"
    [[ ${AKSRA} -ne 0 ]] && error "Azure role missing: Kubernetes Service RBAC Cluster Admin"
    [[ ${AKSRCA} -ne 0 ]] && error "Azure role missing: Kubernetes Service Contributor Role"
    [[ ${BR} -ne 0 ]] && error "Azure role missing: Billing Reader"
    [[ ${CNC} -ne 0 ]] && error "Azure role missing: Classic Network Contributor"
    [[ ${KCAAO} -ne 0 ]] && error "Azure role missing: Kubernetes Cluster - Arc Onboarding"
    [[ ${NC} -ne 0 ]] && error "Azure role missing: Network Contributor"
    [[ ${O} -ne 0 ]] && error "Azure role missing: Owner"
    [[ ${R} -ne 0 ]] && error "Azure role missing: Reader"
    [[ ${SR} -ne 0 ]] && error "Azure role missing: Security Reader"
    [[ ${VNC} -ne 0 ]] && error "Azure role missing: Virtual Machine Contributor"
  fi
  return ${RETVAL}
}

function list_aks_nodes() {
  local RETVAL=0
  declare -a NODENAMES
  read -a NODENAMES <<< $(kubectl get nodes -o "jsonpath={.items[*].status.addresses[?(@.type=='Hostname')].address}")
  RETVAL=$?
  if [ ${#NODENAMES[@]} -gt 0 ] ; then
    for ((I = 0; I < ${#NODENAMES[@]}; ++I)); do
      success "- found cluster node ${NODENAMES[$I]}"
    done
  fi
  unset NODENAMES
  return ${RETVAL}
}

function wait_for_hub_spoke_vms() {
  local RETVAL=0
  doing "- waiting for private IP(s) for VM ${HUB_VM_NAME}"
  until [ -n "$(az vm show --resource-group "${AZ_RG}" --name "${HUB_VM_NAME}" --show-details --query "privateIps" -o tsv --only-show-errors 2> /dev/null)" ] ; do
    xsleep ${WAIT_SLEEP_SECONDS}
  done
  success "- got private IP(s) on VM ${HUB_VM_NAME}"
  doing "- waiting for private IP(s) for VM ${SPOKE_VM_NAME}"
  until [ -n "$(az vm show --resource-group "${AZ_RG}" --name "${SPOKE_VM_NAME}" --show-details --query "privateIps" -o tsv --only-show-errors 2> /dev/null)" ] ; do
    xsleep ${WAIT_SLEEP_SECONDS}
  done
  success "- got private IP(s) on VM ${SPOKE_VM_NAME}"
  return ${RETVAL}
}

function wait_for_private_ip() {
  # 1 VM name
  # 2 NIC name
  # 3 IP
  # 4 RG
  local RETVAL=0
  doing "- waiting for private IP ${2}:${3} for VM ${1}"
  until [[ $(az network nic ip-config list --resource-group "${4:-$AZ_RG}" --nic-name "${2}" --query "[].privateIpAddress" -o tsv --only-show-errors 2> /dev/null) =~ .*${3}.* ]] ; do
    xsleep ${WAIT_SLEEP_SECONDS}
  done
  success "- got private IP ${2}:${3} on VM ${1}"
  return ${RETVAL}
}

function wait_for_loadbalancer_external_ip() {
  # 1 lb service name
  local RETVAL=0
  doing "- waiting for LoadBalancer ${1} external IP allocation/acceptance"
  until [[ -n "$(kubectl get service ${1} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')" ]] ; do
    xsleep ${WAIT_SLEEP_SECONDS}
  done
  success "- got LoadBalancer ${1} external IP allocation/acceptance"
  return ${RETVAL}
}

function wait_for_private_link_service() {
  # 1 resource group
  # 2 aks cluster name
  # 3 aks service name i.e. /nbi-load-balancer
  local RETVAL=0
  doing "- waiting for private link service ${3} on ${2} in rg ${1}"
  until [[ $(az network private-link-service list -g MC_telco_k8s_uksouth --query '[].tags."k8s-azure-owner-service"' -o tsv --only-show-errors 2> /dev/null) =~ .*${3}.* ]] ; do
    xsleep ${WAIT_SLEEP_SECONDS}
  done
  success "- got private link service ${3} on ${2} in rg ${1}"
  return ${RETVAL}
}

function generate_dns_prefix() {
  # 1 variable to assign result to
  # 2 length
  local RETVAL=0
  declare -n RET="${1}"
  local LENGTH="${2:-8}"
  # azure mandated regex ^[a-z][a-z0-9-]{1,61}[a-z0-9]$
  RET="z$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c $(( ${LENGTH} - 1)) )"
  RETVAL=$?
  return ${RETVAL}
}

function passwd_generator() {
  # 1 variable to assign result to
  # 2 length
  local RETVAL=0
  declare -n RET="${1}"
  local LENGTH="${2:-16}"
  RET=$(pwgen -B -c -s -y -r @\$\<\>\"\'\& ${LENGTH} 1)
  RETVAL=$?
  return ${RETVAL}
}

function create_password() {
  local RETVAL=0
  local SECRET="${1}"
  local KEY="${2}"
  local NEW_PASSWORD="${3}"
  kubectl create secret -n csdm generic ${SECRET} --from-literal=${KEY}=${NEW_PASSWORD} &> /dev/null
  RETVAL=$?
  return ${RETVAL}
}

function get_next_nsg_priority() {
  # 1 nsg name
  # 2 variable to assign toA
  # 3 resource group override
  declare -n PRIORITY_NEXT="${2}"
  local RETVAL=$?
  local RG="${3:-$AZ_RG}"
  local PRIORITY_CURRENT=0
  PRIORITY_CURRENT=$(( $(az network nsg rule list --resource-group "${RG}" --nsg-name "${1}" --query "[-1].priority" -o tsv --only-show-errors 2> /dev/null) ))
  [[ -z ${PRIORITY_CURRENT} || ${PRIORITY_CURRENT} -eq 0 ]] && PRIORITY_NEXT=100 || PRIORITY_NEXT=$(( $PRIORITY_CURRENT + 10 ))
  RETVAL=$?
  return ${RETVAL}
}

function run_vm_cmd() {
  local RETVAL=0
  local VM_RG="${1}"
  local VM_NAME="${2}"
  local VM_CMD="${3}"
  az vm run-command invoke -g "${VM_RG}" -n "${VM_NAME}" --command-id RunShellScript --scripts "${VM_CMD}" --output none --only-show-errors
  RETVAL=$?
  return ${RETVAL}
}

function dns_a_to_ptr() {
  # 1 IPv4 Address
  # 2 variable to assign value to
  local RETVAL=0
  declare -a IPA
  declare -n PTR="${2}"
  IFS="."; read -ra IPA <<< "${1}"
  PTR="${IPA[3]}.${IPA[2]}.${IPA[1]}.${IPA[0]}.in-addr.arpa"
  RETVAL=$?
  IFS=""
  unset IPA
  return ${RETVAL}
}

function update_vm_sshd_config() {
  local RETVAL=0
  local VM_RG="${1}"
  local VM_NAME="${2}"
  local VM_SSH_USER="${3}"
  local VM_SSH_PORT="${4:-$SSH_PORT}"
  local SSHD_TMP=$(mktemp -q -p /tmp azure.XXXXXXXX)
  local SSHD_RUN=""
  local CMD_1=""
  cat <<EOF > "${SSHD_TMP}"
Port ${VM_SSH_PORT}
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
AllowUsers ${VM_SSH_USER,,}
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
EOF
  SSHD_RUN=$(cat ${SSHD_TMP} | base64 -w 0 ; rm -f ${SSHD_TMP} &> /dev/null)
  CMD_1="echo \"${SSHD_RUN}\"|base64 -d > /etc/ssh/sshd_config && sshd -t && systemctl restart ssh"
  run_vm_cmd "${VM_RG}" "${VM_NAME}" "${CMD_1}"
  RETVAL=$?
  return ${RETVAL}
}

function update_vm_sudoers() {
  # this is not needed on Azure, as undertaken by Cloud-init
  local RETVAL=0
  local VM_RG="${1}"
  local VM_NAME="${2}"
  local VM_USER="${3}"
  az vm run-command invoke -g "${VM_RG}" -n "${VM_NAME}" --command-id RunShellScript --scripts "echo -e \"${3}\tALL=(ALL:ALL) NOPASSWD:ALL\"|(EDITOR='tee -a' visudo -f /etc/sudoers.d/${3}" --output none --only-show-errors
  RETVAL=$?
  return ${RETVAL}
}

function clean_local_ssh_host_keys() {
  local RETVAL=0
  ssh-keygen -f ~/.ssh/known_hosts -R ${HUB_NIC_ETH0_PRIVATE_IP} 2> /dev/null
  ssh-keygen -f ~/.ssh/known_hosts -R ${HUB_NIC_ETH1_PRIVATE_IP} 2> /dev/null
  ssh-keygen -f ~/.ssh/known_hosts -R ${HUB_NIC_ETH2_PRIVATE_IP} 2> /dev/null
  ssh-keygen -f ~/.ssh/known_hosts -R ${SPOKE_NIC_ETH0_PRIVATE_IP} 2> /dev/null
  ssh-keygen -f ~/.ssh/known_hosts -R ${SPOKE_NIC_ETH1_PRIVATE_IP} 2> /dev/null
  ssh-keygen -f ~/.ssh/known_hosts -R ${RMD_NIC_ETH0_PRIVATE_IP} 2> /dev/null
  ssh-keygen -f ~/.ssh/known_hosts -R ${POLT_NIC_ETH0_PRIVATE_IP} 2> /dev/null
  ssh-keygen -f ~/.ssh/known_hosts -R ${BASTION_NIC_ETH0_PRIVATE_IP} 2> /dev/null
  ssh-keygen -f ~/.ssh/known_hosts -R ${CSDM_NIC_ETH0_PRIVATE_IP} 2> /dev/null
  ssh-keygen -f ~/.ssh/known_hosts -R ${CSDM_NIC_ETH1_PRIVATE_IP} 2> /dev/null
  ssh-keygen -f ~/.ssh/known_hosts -R ${NFS_NIC_ETH0_PRIVATE_IP} 2> /dev/null
  [[ -z "${BASTION_NIC_ETH0_FQDN}" ]] && BASTION_NIC_ETH0_FQDN=$(az vm show --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --show-details --query "fqdns" -o tsv --only-show-errors)
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  ssh-keygen -f ~/.ssh/known_hosts -R ${BASTION_NIC_ETH0_PUBLIC_IP} 2> /dev/null
  ssh-keygen -f ~/.ssh/known_hosts -R ${BASTION_NIC_ETH0_FQDN} 2> /dev/null
  #[[ -z "${NFS_NIC_ETH0_FQDN}" ]] && NFS_NIC_ETH0_FQDN=$(az vm show --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --show-details --query #"fqdns" -o tsv --only-show-errors)
  #[[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  #ssh-keygen -f ~/.ssh/known_hosts -R ${NFS_NIC_ETH0_FQDN} 2> /dev/null
  #ssh-keygen -f ~/.ssh/known_hosts -R ${NFS_NIC_ETH0_PUBLIC_IP} 2> /dev/null
  #RETVAL=$?
  return ${RETVAL}
}

function update_ssh_host() {
  local RETVAL=0
  # 1 vm
  # 2 username
  # 3 ip
  # 4 ssh port
  run_vm_cmd "${AZ_RG}" "${1}" "su - ${2} -c \"[[ ! -d ~/.ssh ]] && mkdir -m 700 -p ~/.ssh\""
  run_vm_cmd "${AZ_RG}" "${1}" "su - ${2} -c \"[[ -f ~/.ssh/known_hosts ]] && ssh-keygen -f ~/.ssh/known_hosts -R ${3}\""
  run_vm_cmd "${AZ_RG}" "${1}" "su - ${2} -c \"ssh-keyscan -p ${SSH_PORT} -t rsa -H ${3} >> ~/.ssh/known_hosts\""
  RETVAL=$?  
}

function update_ssh_host_keys() {
  local RETVAL=0
  wait_for_private_ip "${BASTION_VM_NAME}" "${BASTION_NIC_ETH0}" "${BASTION_NIC_ETH0_PRIVATE_IP}" && \
  wait_for_private_ip "${HUB_VM_NAME}" "${HUB_NIC_ETH0}" "${HUB_NIC_ETH0_PRIVATE_IP}" && \
  wait_for_private_ip "${SPOKE_VM_NAME}" "${SPOKE_NIC_ETH0}" "${SPOKE_NIC_ETH0_PRIVATE_IP}" && \
  [[ -z "${BASTION_NIC_ETH0_FQDN}" ]] && BASTION_NIC_ETH0_FQDN=$(az vm show --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --show-details --query "fqdns" -o tsv --only-show-errors)
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  #update_ssh_host "${BASTION_VM_NAME}" "${VPN_OS_USERNAME}" "${HUB_NIC_ETH0_PRIVATE_IP}" "${SSH_PORT}" && \
  #update_ssh_host "${HUB_VM_NAME}" "${VPN_OS_USERNAME}" "${SPOKE_NIC_ETH0_PRIVATE_IP}" "${SSH_PORT}"
  if [ -d ~/.ssh ] ; then
    if [ -f ~/.ssh/known_hosts ] ; then
      ssh-keygen -f ~/.ssh/known_hosts -R ${HUB_NIC_ETH0_PRIVATE_IP} 2> /dev/null
      ssh-keygen -f ~/.ssh/known_hosts -R ${HUB_NIC_ETH1_PRIVATE_IP} 2> /dev/null
      ssh-keygen -f ~/.ssh/known_hosts -R ${HUB_NIC_ETH2_PRIVATE_IP} 2> /dev/null
      ssh-keygen -f ~/.ssh/known_hosts -R ${SPOKE_NIC_ETH0_PRIVATE_IP} 2> /dev/null
      ssh-keygen -f ~/.ssh/known_hosts -R ${SPOKE_NIC_ETH1_PRIVATE_IP} 2> /dev/null
      ssh-keygen -f ~/.ssh/known_hosts -R ${RMD_NIC_ETH0_PRIVATE_IP} 2> /dev/null
      ssh-keygen -f ~/.ssh/known_hosts -R ${POLT_NIC_ETH0_PRIVATE_IP} 2> /dev/null
      ssh-keygen -f ~/.ssh/known_hosts -R ${BASTION_NIC_ETH0_PRIVATE_IP} 2> /dev/null
      ssh-keygen -f ~/.ssh/known_hosts -R ${BASTION_NIC_ETH0_PUBLIC_IP} 2> /dev/null
      ssh-keygen -f ~/.ssh/known_hosts -R ${BASTION_NIC_ETH0_FQDN} 2> /dev/null
	fi
  else
    mkdir -m 700 -p ~/.ssh
  fi
  ssh-keyscan -p ${SSH_PORT} -t rsa -H ${BASTION_NIC_ETH0_PUBLIC_IP} >> ~/.ssh/known_hosts && \
  ssh -A -o "StrictHostKeyChecking=no" -i ${SSH_KEY_PRIVATE} -p ${SSH_PORT} ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP} "ssh-keyscan -p ${SSH_PORT} -t rsa -H ${HUB_NIC_ETH0_PRIVATE_IP} >> ~/.ssh/known_hosts" && \
  ssh -A -o "StrictHostKeyChecking=no" -i ${SSH_KEY_PRIVATE} -p ${SSH_PORT} -J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT} ${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP} "ssh-keyscan -p ${SSH_PORT} -t rsa -H ${SPOKE_NIC_ETH0_PRIVATE_IP} >> ~/.ssh/known_hosts"
  RETVAL=$?
  return ${RETVAL}
}
