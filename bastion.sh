#!/bin/bash
source config.sh
source common.sh
alert "bastion"

function bastion_remote_cli() {
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
   ssh -A \
	 -o "StrictHostKeyChecking=no" \
	 -i ${SSH_KEY_PRIVATE} \
	 -p ${SSH_PORT} \
	 ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP} ${2} \
	 "${1}" &> /dev/null
  return $?
}

function push_to_bastion() {
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  scp -A -o "StrictHostKeyChecking=no" \
      -o "ServerAliveInterval=60" \
      -i ${SSH_KEY_PRIVATE} \
      -P ${SSH_PORT} ${3} \
      ${1} \
	  ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${2} &> /dev/null
  return $?
}

step1() {
  doing "- ${FUNCNAME[0]}"
  local RETVAL=0
  local VPN_1=""
  local EXISTS_ID=""
  BASTION_OS_URN=$(az vm image list --location "${AZ_REGION}" --offer "${BASTION_OS_OFFER}" --publisher "${BASTION_OS_PUBLISHER}" --sku "${BASTION_OS_SKU}" --all --query '[-1].urn' --output tsv --only-show-errors)
  EXISTS_ID=$(az vm show --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "id" --output tsv --only-show-errors 2>/dev/null)
  [[ -n "${EXISTS_ID}" ]] && az vm delete --ids "${EXISTS_ID}" --yes --force-deletion yes --output none --only-show-errors
  az vm create --resource-group "${AZ_RG}" \
   --name "${BASTION_VM_NAME}" \
   --location "${AZ_REGION}" \
   --admin-password "${BASTION_OS_PASSWORD}" \
   --admin-username "${BASTION_OS_USERNAME}" \
   --ssh-key-values "${SSH_KEY_PUBLIC_VALUE}" \
   --image "${BASTION_OS_URN}" \
   --encryption-at-host "${BASTION_EAH_ENABLE,,}" \
   --enable-auto-update "${BASTION_OS_AUTO_UPDATE,,}" \
   --size "${BASTION_NODE_TYPE}" \
   --nics ${BASTION_NIC_ETH0} \
   --output none \
   --only-show-errors
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step2() {
  doing "- ${FUNCNAME[0]} Updating SSH Host Keys"
  local RETVAL=0
  wait_for_private_ip "${BASTION_VM_NAME}" "${BASTION_NIC_ETH0}" "${BASTION_NIC_ETH0_PRIVATE_IP}" "${AZ_RG}" && \
  if [ -f ~/.ssh/known_hosts ] ; then
   ssh-keygen -f ~/.ssh/known_hosts -R ${BASTION_NIC_ETH0_PRIVATE_IP} 2> /dev/null
  fi
  update_vm_sshd_config "${AZ_RG}" "${BASTION_VM_NAME}" "${BASTION_OS_USERNAME}" "${SSH_PORT}"
  RETVAL=$?
  if [ ${RETVAL} -eq 0 ] ; then
    [[ -z "${BASTION_NIC_ETH0_FQDN}" ]] && BASTION_NIC_ETH0_FQDN=$(az vm show --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --show-details --query "fqdns" -o tsv --only-show-errors)
    [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
   success "- ${FUNCNAME[0]}"
   info "Bastion fqdn:${BASTION_NIC_ETH0_FQDN},hostname:${BASTION_VM_NAME},private-ip:${BASTION_NIC_ETH0_PRIVATE_IP},public-ip:${BASTION_NIC_ETH0_PUBLIC_IP},username:${BASTION_OS_USERNAME},password:${BASTION_OS_PASSWORD}"
   info "ssh -A -p ${SSH_PORT} -A ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_FQDN}"
   info "ssh -A -p ${SSH_PORT} -A ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}"
   ssh-keygen -f ~/.ssh/known_hosts -R ${BASTION_NIC_ETH0_PUBLIC_IP} 2> /dev/null
   ssh-keyscan -p ${SSH_PORT} -t rsa -H ${BASTION_NIC_ETH0_PUBLIC_IP} >> ~/.ssh/known_hosts
  fi
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step3() {
  doing "- ${FUNCNAME[0]} Host Prepare"
  local RETVAL=0
  if [ -f "${BASTION_OS_PREPARE}" ] ; then
   push_to_bastion "${BASTION_OS_PREPARE}" "/tmp/" && \
   bastion_remote_cli "chmod 744 /tmp/${BASTION_OS_PREPARE} ; sudo /tmp/${BASTION_OS_PREPARE} \"${BASTION_OS_USERNAME}\" \"${AZ_LANG}\" \"${AZ_TIMEZONE}\" \"${SSH_PORT}\" &> ~/prepare.log 2>&1"
   RETVAL=$?
  else
   RETVAL=1
  fi
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step4() {
  doing "- ${FUNCNAME[0]} NFS Network Security Groups Rules addition for Bastion"
  local RETVAL=0
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  az network nsg rule create --resource-group "${NFS_AZ_RG}" \
   --nsg-name "${NFS_NSG_NAME}" \
   --name "Ssh-${NFS_VM_NAME}-${BASTION_NIC_ETH0_PUBLIC_IP}-${NFS_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority 202 \
   --source-address-prefixes "${BASTION_NIC_ETH0_PUBLIC_IP}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${NFS_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges ${SSH_PORT} \
   --protocol "Tcp" \
   --access "Allow" \
   --output none \
   --only-show-errors
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

### main entry
login_az && \
step1 && \
step2 && \
step3 && \
step4 
RETVAL=$?
[[ ${RETVAL} -eq 0 ]] && success "- completed" || error "- fail"
[[ ! ${NOLOGOUT} -eq 0 ]] && logout_az
clean_tmp_files
exit ${RETVAL}
