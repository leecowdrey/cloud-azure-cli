#!/bin/bash
source config.sh
source common.sh
alert "NFS"

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
      -P ${SSH_PORT} ${3} \
      ${1} \
	  ${NFS_OS_USERNAME}@${NFS_NIC_ETH0_PUBLIC_IP}:${2} # &> /dev/null
  return $?
}

step1() {
  local RETVAL=0
  local EXISTS_ID=""
  local PRIORITY=0
  
  [[ -z $(az group list --query "[?contains(name,'${NFS_AZ_RG}')].name" -o tsv) ]] && az group create --name "${NFS_AZ_RG}" --location "${AZ_REGION}" --output none --only-show-errors

  az network vnet create --resource-group "${NFS_AZ_RG}" \
   --name "${NFS_VNET}" \
   --address-prefix "${NFS_ADDRESS_PREFIX}" \
   --location "${AZ_REGION}" \
   --output none \
   --only-show-errors && \

  NFS_SUBNET_ID=$(az network vnet subnet create --resource-group "${NFS_AZ_RG}" \
    --name "${NFS_SUBNET_NAME}" \
    --vnet-name "${NFS_VNET}" \
    --address-prefixes "${NFS_SUBNET_ADDRESS_PREFIX}" \
    --query "id" --output tsv --only-show-errors) && \
  NFS_NSG_ID=$(az network nsg create --resource-group "${NFS_AZ_RG}" \
    --name "${NFS_NSG_NAME}" \
   --location "${AZ_REGION}" \
   --query "NewNSG.id" --output tsv --only-show-errors) && \

  az network nic create --resource-group "${NFS_AZ_RG}" \
    --name "${NFS_NIC_ETH0}" \
    --subnet "${NFS_SUBNET_NAME}" \
    --location "${AZ_REGION}" \
    --vnet-name "${NFS_VNET}" \
    --network-security-group "${NFS_NSG_NAME}" \
    --private-ip-address-version "${IP_VERSION}" \
    --ip-forwarding true \
    --output none \
    --only-show-errors && \

  generate_dns_prefix NFS_DNS_PREFIX 16
  az network public-ip create \
   --name "${NFS_VM_NAME}" \
   --resource-group "${NFS_AZ_RG}" \
   --location "${AZ_REGION}" \
   --sku "${IP_SKU}" \
   --version "${IP_VERSION}" \
   --dns-name "${NFS_DNS_PREFIX}" \
   --output none \
   --only-show-errors && \
  az network nic ip-config update \
   --name ipconfig1 \
   --resource-group "${NFS_AZ_RG}" \
   --nic-name "${NFS_NIC_ETH0}" \
   --public-ip-address "${NFS_VM_NAME}" \
   --private-ip-address "${NFS_NIC_ETH0_PRIVATE_IP}" \
   --output none \
   --only-show-errors && \

  for ((I = 0; I < ${#PERMITTED_WAN_IP[@]}; ++I)); do
	  get_next_nsg_priority "${NFS_NSG_NAME}" PRIORITY "${NFS_AZ_RG}"
	  az network nsg rule create --resource-group "${NFS_AZ_RG}" \
	   --nsg-name "${NFS_NSG_NAME}" \
	   --name "Public-Ssh-${NFS_VM_NAME}-${PERMITTED_WAN_IP[$I]}-${NFS_NIC_ETH0_PRIVATE_IP}" \
	   --direction "Inbound" \
	   --priority ${PRIORITY} \
	   --source-address-prefixes "${PERMITTED_WAN_IP[$I]}" \
	   --source-port-ranges '*' \
	   --destination-address-prefixes "${NFS_NIC_ETH0_PRIVATE_IP}" \
	   --destination-port-ranges ${SSH_PORT} \
	   --protocol "Tcp" \
	   --access "Allow" \
	   --output none \
	   --only-show-errors
  done

  get_next_nsg_priority "${NFS_NSG_NAME}" PRIORITY "${NFS_AZ_RG}"
  az network nsg rule create --resource-group "${NFS_AZ_RG}" \
   --nsg-name "${NFS_NSG_NAME}" \
   --name "DhcpClient-${NFS_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${NFS_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges "67-68" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \

  NFS_OS_URN=$(az vm image list --location "${AZ_REGION}" --offer "${NFS_OS_OFFER}" --publisher "${NFS_OS_PUBLISHER}" --sku "${NFS_OS_SKU}" --all --query '[-1].urn' --output tsv --only-show-errors)
  EXISTS_ID=$(az vm show --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "id" --output tsv --only-show-errors 2>/dev/null)
  [[ -n "${EXISTS_ID}" ]] && az vm delete --ids "${EXISTS_ID}" --yes --force-deletion yes --output none --only-show-errors
  az vm create --resource-group "${NFS_AZ_RG}" \
   --name "${NFS_VM_NAME}" \
   --location "${AZ_REGION}" \
   --admin-password "${NFS_OS_PASSWORD}" \
   --admin-username "${NFS_OS_USERNAME}" \
   --ssh-key-values "${SSH_KEY_PUBLIC_VALUE}" \
   --image "${NFS_OS_URN}" \
   --encryption-at-host "${NFS_EAH_ENABLE,,}" \
   --enable-auto-update "${NFS_EAH_ENABLE,,}" \
   --size "${NFS_NODE_TYPE}" \
   --nics ${NFS_NIC_ETH0} \
   --output none \
   --only-show-errors
  # update_vm_sudoers "${NFS_AZ_RG}" "${NFS_VM_NAME} "${NFS_OS_USERNAME}"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step2() {
  doing "- ${FUNCNAME[0]} Updating SSH Host Keys"
  local RETVAL=0
  wait_for_private_ip "${NFS_VM_NAME}" "${NFS_NIC_ETH0}" "${NFS_NIC_ETH0_PRIVATE_IP}" "${NFS_AZ_RG}" && \
  if [ -f ~/.ssh/known_hosts ] ; then
   ssh-keygen -f ~/.ssh/known_hosts -R ${NFS_NIC_ETH0_PRIVATE_IP} 2> /dev/null
  fi
  update_vm_sshd_config "${NFS_AZ_RG}" "${NFS_VM_NAME}" "${NFS_OS_USERNAME}" "${SSH_PORT}"
  RETVAL=$?
  if [ ${RETVAL} -eq 0 ] ; then
    [[ -z "${NFS_NIC_ETH0_FQDN}" ]] && NFS_NIC_ETH0_FQDN=$(az vm show --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --show-details --query "fqdns" -o tsv --only-show-errors)
    [[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
   success "- ${FUNCNAME[0]}"
   info "NFS fqdn:${NFS_NIC_ETH0_FQDN},hostname:${NFS_VM_NAME},private-ip:${NFS_NIC_ETH0_PRIVATE_IP},public-ip:${NFS_NIC_ETH0_PUBLIC_IP},username:${NFS_OS_USERNAME},password:${NFS_OS_PASSWORD}"
   info "ssh -A -p ${SSH_PORT} -A ${NFS_OS_USERNAME}@${NFS_NIC_ETH0_FQDN}"
   info "ssh -A -p ${SSH_PORT} -A ${NFS_OS_USERNAME}@${NFS_NIC_ETH0_PUBLIC_IP}"
   ssh-keygen -f ~/.ssh/known_hosts -R ${NFS_NIC_ETH0_PUBLIC_IP} 2> /dev/null
   ssh-keyscan -p ${SSH_PORT} -t rsa -H ${NFS_NIC_ETH0_PUBLIC_IP} >> ~/.ssh/known_hosts
  fi
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step3() {
  doing "- ${FUNCNAME[0]} Host Prepare"
  local RETVAL=0
  if [ -f "nfs/${NFS_OS_PREPARE}" ] ; then
   push_to_nfs "nfs/${NFS_OS_PREPARE}" "/tmp/" && \
   nfs_remote_cli "chmod 744 /tmp/${POLT_SIM_PREPARE} ; sudo /tmp/${NFS_OS_PREPARE} \"${NFS_OS_USERNAME}\" \"${AZ_LANG}\" \"${AZ_TIMEZONE}\" \"${SSH_PORT}\" &> ~/prepare.log 2>&1"
   RETVAL=$?
  else
   RETVAL=1
  fi
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step4() {
  doing "- ${FUNCNAME[0]} Transfer"
  local RETVAL=0
  push_to_nfs "nfs/csdm/csdm-${TAG}.tar.gz" "~/csdm/"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step5() {
  doing "- ${FUNCNAME[0]} Docker repo load"
  local RETVAL=0
  nfs_remote_cli "docker load --input csdm/csdm-combined-${TAG}.tar.gz" && \
  nfs_remote_cli "docker load --input csdm/csdm-flink_init-${TAG}.tar.gz" && \
  nfs_remote_cli "docker load --input csdm/csdm-keycloaktheme-${TAG}.tar.gz" && \
  nfs_remote_cli "docker load --input csdm/csdm-kibana-config-${TAG}.tar.gz" && \
  nfs_remote_cli "docker load --input csdm/csdm-licensing-${TAG}.tar.gz" && \
  nfs_remote_cli "docker load --input csdm/csdm-restconfcollector-${TAG}.tar.gz" && \
  nfs_remote_cli "docker load --input csdm/csdm-sdn-app-${TAG}.tar.gz" && \
  nfs_remote_cli "docker load --input csdm/csdm-snmpcollector-${TAG}.tar.gz" && \
  nfs_remote_cli "docker load --input csdm/csdm-swagger-${TAG}.tar.gz" && \
  nfs_remote_cli "docker load --input csdm/csdm-tcs-${TAG}.tar.gz" && \
  nfs_remote_cli "docker load --input csdm/csdm-telegraf-${TAG}.tar.gz" && \
  nfs_remote_cli "docker load --input csdm/csdm-telegraf_init-${TAG}.tar.gz" && \
  nfs_remote_cli "docker load --input csdm/csdm-toolbox-${TAG}.tar.gz" && \
  nfs_remote_cli "docker load --input csdm/csdm-ui-${TAG}.tar.gz" && \
  nfs_remote_cli "docker load --input csdm/csdm-vflow-${TAG}.tar.gz" && \
  nfs_remote_cli "rm -f csdm/csdm-*-${TAG}.tar.gz &> /dev/null"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step6() {
  local RETVAL=0
  doing "- ${FUNCNAME[0]} Backup SSH Key Generation/Transfer"
   [[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  if [ ! -f "${NFS_BACKUP_KEY}" ] ; then
    ssh-keygen -b ${NFS_BACKUP_KEY_BITS} -t ${NFS_BACKUP_KEY_TYPE} -f ${NFS_BACKUP_KEY} -q -N "" &> /dev/null
	[[ -f "${NFS_BACKUP_KEY}" ]] && chmod 400 ${NFS_BACKUP_KEY} &> /dev/null
	[[ -f "${NFS_BACKUP_KEY}.pub" ]] && chmod 444 ${NFS_BACKUP_KEY}.pub &> /dev/null
  fi
  ssh \
	 -o "StrictHostKeyChecking=no" \
	 -o "IdentitiesOnly=yes" \
	 -i ${NFS_BACKUP_KEY} \
	 -p ${SSH_PORT} \
	 ${NFS_OS_USERNAME}@${NFS_NIC_ETH0_PUBLIC_IP} "exit" &> /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    ssh-copy-id \
	   -o "StrictHostKeyChecking=no" \
  	   -i ${NFS_BACKUP_KEY} \
	   -p ${SSH_PORT} \
	   ${NFS_OS_USERNAME}@${NFS_NIC_ETH0_PUBLIC_IP} &> /dev/null 2>&1
    RETVAL=$?
  else
    RETVAL=0
  fi
  local SSH_KEY_FULL_PATH=$(realpath $NFS_BACKUP_KEY)
  info "NFS Backup Key:"
  info "- Public Key:  ${SSH_KEY_FULL_PATH}.pub"
  info "- Private Key: ${SSH_KEY_FULL_PATH}"
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

### main entry
login_az && \
step1 && \
step2 && \
step3 && \
step4 && \
step5 && \
step6
RETVAL=$?
[[ ${RETVAL} -eq 0 ]] && success "- completed" || error "- fail"
[[ ! ${NOLOGOUT} -eq 0 ]] && logout_az
clean_tmp_files
exit ${RETVAL}

