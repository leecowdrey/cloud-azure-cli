#!/bin/bash
source config.sh
source common.sh
alert "Azure Container Registry (ACR)"

function nfs_remote_cli() {
   [[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
   ssh -A \
	 -o "StrictHostKeyChecking=no" \
	 -i ${SSH_KEY_PRIVATE} \
	 -p ${SSH_PORT} \
	 ${NFS_OS_USERNAME}@${NFS_NIC_ETH0_PUBLIC_IP} ${2} \
	 "${1}" # &> /dev/null
  return $?
}

function push_to_nfs() {
   [[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  scp -A -o "StrictHostKeyChecking=no" \
      -i ${SSH_KEY_PRIVATE} \
      -P ${SSH_PORT} \
      ${1} \
	  ${NFS_PON_USERNAME}@${NFS_NIC_ETH0_PRIVATE_IP}:${2} # &> /dev/null
  return $?
}

step1() {
  doing "- ${FUNCNAME[0]} creating container registry ACR ${AZ_ACR_NAME} in region ${AZ_REGION}"
  local RETVAL=0
  local AVAILABLE_NAME=""
  AVAILABLE_NAME=$(az acr check-name --name "${AZ_ACR_NAME}" --query "nameAvailable" --output tsv --only-show-errors)
  if [ "${AVAILABLE_NAME,,}" == "true" ] ; then
   az acr create --resource-group "${AZ_RG}" \
    --name "${AZ_ACR_NAME}" \
    --sku "${AZ_ACR_SKU}" \
    --location "${AZ_REGION}" \
    --admin-enabled true \
    --output none \
    --only-show-errors && \
   AZ_ACR_USERNAME=$(az acr credential show --resource-group "${AZ_RG}" --name "${AZ_ACR_NAME}" --query "username" --output tsv --only-show-errors)
   AZ_ACR_PASSWORD=$(az acr credential show --resource-group "${AZ_RG}" --name "${AZ_ACR_NAME}" --query "passwords[0].value" --output tsv --only-show-errors)
   RETVAL=$?
   [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]} created " || error "- fail ${FUNCNAME[0]}"
  fi
  return ${RETVAL}
}

step2() {
  doing "- ${FUNCNAME[0]} Determine WAN IP address (NFS NSG update)"
  local RETVAL=0
  local PRIORITY=0
  AZ_ACR_LOGIN_IP=$(getent ahostsv4 ${AZ_ACR_LOGIN_URL}|head -1|awk '{print $1}')
  RETVAL=$?
  if [ $? -eq 0 ] ; then
      get_next_nsg_priority "${NFS_NSG_NAME}" PRIORITY "${NFS_AZ_RG}"
	  az network nsg rule create --resource-group "${NFS_AZ_RG}" \
	   --nsg-name "${NFS_NSG_NAME}" \
	   --name "Ssh-${AZ_ACR_NAME}-${AZ_ACR_LOGIN_IP}-${NFS_NIC_ETH0_PRIVATE_IP}" \
	   --direction "Inbound" \
	   --priority ${PRIORITY} \
	   --source-address-prefixes "${AZ_ACR_LOGIN_IP}" \
	   --source-port-ranges '*' \
	   --destination-address-prefixes "${NFS_NIC_ETH0_PRIVATE_IP}" \
	   --destination-port-ranges "443" \
	   --protocol "Tcp" \
	   --access "Allow" \
	   --output none \
	   --only-show-errors && \
      get_next_nsg_priority "${NFS_NSG_NAME}" PRIORITY "${NFS_AZ_RG}"
	  az network nsg rule create --resource-group "${NFS_AZ_RG}" \
	   --nsg-name "${NFS_NSG_NAME}" \
	   --name "Acr-${AZ_ACR_NAME}-${AZ_ACR_LOGIN_IP}-${NFS_NIC_ETH0_PRIVATE_IP}" \
	   --direction "Inbound" \
	   --priority ${PRIORITY} \
	   --source-address-prefixes "${AZ_ACR_LOGIN_IP}" \
	   --source-port-ranges '*' \
	   --destination-address-prefixes "${NFS_NIC_ETH0_PRIVATE_IP}" \
	   --destination-port-ranges '*'} \
	   --protocol "Tcp" \
	   --access "Allow" \
	   --output none \
	   --only-show-errors
	  RETVAL=$?
  fi
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step3() {
  doing "- ${FUNCNAME[0]} login to ACR ${AZ_ACR_NAME}"
  local RETVAL=0
  [[ ${AZ_CONNECTED} -ne 0 ]] && az login --scope "${AZ_SCOPE}"
  [[ -z "${AZ_ACR_USERNAME}" ]] && AZ_ACR_USERNAME=$(az acr credential show --resource-group "${AZ_RG}" --name "${AZ_ACR_NAME}" --query "username" --output tsv --only-show-errors)
  [[ -z "${AZ_ACR_PASSWORD}" ]] && AZ_ACR_PASSWORD=$(az acr credential show --resource-group "${AZ_RG}" --name "${AZ_ACR_NAME}" --query "passwords[0].value" --output tsv --only-show-errors)
  nfs_remote_cli "az login --use-device-code"
  nfs_remote_cli "az acr login  --name "${AZ_ACR_NAME}" --username "${AZ_ACR_USERNAME}" --password "${AZ_ACR_PASSWORD}" --output none --only-show-errors"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step4() {
  doing "- ${FUNCNAME[0]} Tagging Docker CSDM images ${IMAGE_PREFIX,,}*:${TAG}"
  local RETVAL=0
  function tag() {
    doing "- tagging ${IMAGE_PREFIX,,}${1}:${2}"
    nfs_remote_cli "docker tag ${IMAGE_PREFIX,,}${1}:${2} ${AZ_ACR_LOGIN_URL,,}/csdm/${1}:${2} &> /dev/null"
	return $?
  }
  tag "combined" "${TAG}" && \
  tag "flink_init" "${TAG}" && \
  tag "combined" "${TAG}" && \
  tag "flink_init" "${TAG}" && \
  tag "keycloaktheme" "${TAG}" && \
  tag "kibana-config" "${TAG}" && \
  tag "licensing" "${TAG}" && \
  tag "restconfcollector" "${TAG}" && \
  tag "sdn-app" "${TAG}" && \
  tag "snmpcollector" "${TAG}" && \
  tag "swagger" "${TAG}" && \
  tag "tcs" "${TAG}" && \
  tag "telegraf" "${TAG}" && \
  tag "telegraf_init" "${TAG}" && \
  tag "toolbox" "${TAG}" && \
  tag "ui" "${TAG}" && \
  tag "vflow" "${TAG}"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step5() {
  doing "- ${FUNCNAME[0]} pushing local Docker images ${IMAGE_PREFIX,,}*:${TAG} to ACR ${AZ_ACR_NAME}${AZ_ACR_DOMAIN_NAME,,}"
  local RETVAL=0
  function push() {
    doing "- pushing ${IMAGE_PREFIX,,}${1}:${2}"
    nfs_remote_cli "docker push --quiet ${AZ_ACR_LOGIN_URL,,}/${IMAGE_PREFIX,,}${1}:${2} &> /dev/null"
	return $?
  }
  push "combined" "${TAG}" && \
  push "flink_init" "${TAG}" &&\
  push "combined" "${TAG}" && \
  push "flink_init" "${TAG}" && \
  push "keycloaktheme" "${TAG}" && \
  push "kibana-config" "${TAG}" && \
  push "licensing" "${TAG}" && \
  push "restconfcollector" "${TAG}" && \
  push "sdn-app" "${TAG}" && \
  push "snmpcollector" "${TAG}" && \
  push "swagger" "${TAG}" && \
  push "tcs" "${TAG}" && \
  push "telegraf" "${TAG}" && \
  push "telegraf_init" "${TAG}" && \
  push "toolbox" "${TAG}" && \
  push "ui" "${TAG}" && \
  push "vflow" "${TAG}"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step6() {
  doing "- ${FUNCNAME[0]} untagging local Docker images ${IMAGE_PREFIX,,}*:${TAG}"
  local RETVAL=0
  function untag() {
    doing "- untagging ${IMAGE_PREFIX,,}${1}:${2}"
    nfs_remote_cli "docker rmi --force ${AZ_ACR_LOGIN_URL,,}/${IMAGE_PREFIX,,}${1}:${2} &> /dev/null"
	return $?
  }
  untag "combined" "${TAG}" && \
  untag "flink_init" "${TAG}" &&\
  untag "combined" "${TAG}" && \
  untag "flink_init" "${TAG}" && \
  untag "keycloaktheme" "${TAG}" && \
  untag "kibana-config" "${TAG}" && \
  untag "licensing" "${TAG}" && \
  untag "restconfcollector" "${TAG}" && \
  untag "sdn-app" "${TAG}" && \
  untag "snmpcollector" "${TAG}" && \
  untag "swagger" "${TAG}" && \
  untag "tcs" "${TAG}" && \
  untag "telegraf" "${TAG}" && \
  untag "telegraf_init" "${TAG}" && \
  untag "toolbox" "${TAG}" && \
  untag "ui" "${TAG}" && \
  untag "vflow" "${TAG}"
  RETVAL=$?
  nfs_remote_cli "docker rmi mcr.microsoft.com/mcr/hello-world &> /dev/null"
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step7() {
  doing "- ${FUNCNAME[0]} checking ACR health ${AZ_ACR_NAME}"
  local RETVAL=0
  nfs_remote_cli "az acr check-health --name "${AZ_ACR_NAME}" --yes --ignore-errors --output none --only-show-errors"
  RETVAL=$?
  nfs_remote_cli "docker rmi mcr.microsoft.com/mcr/hello-world &> /dev/null"
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

abort() {
  doing "- aborting/rolling back changes to Docker"
  step5 && \
  nfs_remote_cli "docker rmi mcr.microsoft.com/mcr/hello-world &> /dev/null"
  [[ ! ${NOLOGOUT} -eq 0 ]] && logout_az
  clean_tmp_files
  trap - SIGINT
  error "- aborted"
  exit 2
}
### main entry
login_az && \
step1 && \
trap abort SIGINT && \
step3 && \
step4 && \
step5 && \
step6 && \
trap - SIGINT && \
step7
RETVAL=$?
[[ ${RETVAL} -eq 0 ]] && success "- completed" || error " - fail "
[[ ! ${NOLOGOUT} -eq 0 ]] && logout_az
clean_tmp_files
exit ${RETVAL}
