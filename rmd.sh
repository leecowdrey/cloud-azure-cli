#!/bin/bash
source config.sh
source common.sh
alert "RMD"

function rmd_drag_from_nfs() {
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  [[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  ssh -A -o "StrictHostKeyChecking=no" \
      -p ${SSH_PORT} \
      -J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${SPOKE_NIC_ETH0_PRIVATE_IP}:${SSH_PORT} \
      ${RMD_OS_USERNAME}@${RMD_NIC_ETH0_PRIVATE_IP} \
      "scp -o \"StrictHostKeyChecking=no\" -P ${SSH_PORT} ${NFS_OS_USERNAME}@${NFS_NIC_ETH0_PUBLIC_IP}:${1} ${2}" # &> /dev/null
  return $?
}

function rmd_remote_cli() {
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  [[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  ssh -A \
	-o "StrictHostKeyChecking=no" \
    -o "ServerAliveInterval=60" \
	-i ${SSH_KEY_PRIVATE} \
	-p ${SSH_PORT} \
	-J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${SPOKE_NIC_ETH0_PRIVATE_IP}:${SSH_PORT} \
	${RMD_OS_USERNAME}@${RMD_NIC_ETH0_PRIVATE_IP} \
	"${1}" # &> /dev/null
  return $?
}

function push_to_rmd() {
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  scp -A \
	-o "StrictHostKeyChecking=no" \
	-i ${SSH_KEY_PRIVATE} \
	-P ${SSH_PORT} \
	-J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${SPOKE_NIC_ETH0_PRIVATE_IP}:${SSH_PORT} ${3} \
	${1} \
	${RMD_OS_USERNAME}@${RMD_NIC_ETH0_PRIVATE_IP}:${2} #&> /dev/null
  return $?
}

step1() {
  doing "- ${FUNCNAME[0]}"
  local RETVAL=0
  local EXISTS_ID=""
  local CLOUD_INIT=$(mktemp -q -p /tmp azure.XXXXXXXX)
  wait_for_private_ip "${RMD_VM_NAME}" "${RMD_NIC_ETH0}" "${RMD_NIC_ETH0_PRIVATE_IP}"
  RMD_OS_URN=$(az vm image list --location "${AZ_REGION}" --offer "${RMD_OS_OFFER}" --publisher "${RMD_OS_PUBLISHER}" --sku "${RMD_OS_SKU}" --all --query '[-1].urn' --output tsv --only-show-errors)
  EXISTS_ID=$(az vm show --resource-group "${AZ_RG}" --name "${RMD_VM_NAME}" --query "id" --output tsv --only-show-errors 2>/dev/null)
  [[ -n "${EXISTS_ID}" ]] && az vm delete --ids "${EXISTS_ID}" --yes --force-deletion yes --output none --only-show-errors
  cat <<EOF1 > ${CLOUD_INIT}
#cloud-config
fqdn: ${RMD_VM_NAME,,}.${PRIVATE_DNS_ZONE_NAME,,}
EOF1
  az vm create --resource-group "${AZ_RG}" \
   --name "${RMD_VM_NAME}" \
   --location "${AZ_REGION}" \
   --admin-password "${RMD_OS_PASSWORD}" \
   --admin-username "${RMD_OS_USERNAME}" \
   --ssh-key-values "${SSH_KEY_PUBLIC_VALUE}" \
   --image "${RMD_OS_URN}" \
   --encryption-at-host "${RMD_EAH_ENABLE,,}" \
   --enable-auto-update "${RMD_OS_AUTO_UPDATE,,}" \
   --custom-data "${CLOUD_INIT}" \
   --size "${RMD_NODE_TYPE}" \
   --nics ${RMD_NIC_ETH0} \
   --output none \
   --only-show-errors && \
  [[ -f "${CLOUD_INIT}" ]] && rm -f ${CLOUD_INIT} &> /dev/null
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step2() {
  doing "- ${FUNCNAME[0]} Updating SSH Host Keys"
  local RETVAL=0
  wait_for_private_ip "${RMD_VM_NAME}" "${RMD_NIC_ETH0}" "${RMD_NIC_ETH0_PRIVATE_IP}" && \
  if [ -f ~/.ssh/known_hosts ] ; then
   ssh-keygen -f ~/.ssh/known_hosts -R ${RMD_NIC_ETH0_PRIVATE_IP} 2> /dev/null
  fi
  update_vm_sshd_config "${AZ_RG}" "${RMD_VM_NAME}" "${RMD_OS_USERNAME}" "${SSH_PORT}"
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  ssh -A -o "StrictHostKeyChecking=no" -i ${SSH_KEY_PRIVATE} -p ${SSH_PORT} -J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP}:${SSH_PORT} ${VPN_OS_USERNAME}@${SPOKE_NIC_ETH0_PRIVATE_IP} "ssh-keygen -f ~/.ssh/known_hosts -R ${RMD_NIC_ETH0_PRIVATE_IP} 2> /dev/null ; ssh-keyscan -p ${SSH_PORT} -t rsa -H ${RMD_NIC_ETH0_PRIVATE_IP} >> ~/.ssh/known_hosts"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step3() {
  doing "- ${FUNCNAME[0]} Host Prepare"
  local RETVAL=0
  push_to_rmd "${RMD_SIM_PREPARE}" "/tmp" && \
  rmd_remote_cli "chmod 744 /tmp/${RMD_SIM_PREPARE} ; sudo /tmp/${RMD_SIM_PREPARE} \"${RMD_OS_USERNAME}\" \"${AZ_LANG}\" \"${AZ_TIMEZONE}\" \"${SSH_PORT}\" \"${RMD_VM_NAME,,}.${PRIVATE_DNS_ZONE_NAME,,}\" &> ~/prepare.log 2>&1"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step4() {
  doing "- ${FUNCNAME[0]} Determine WAN IP address (NFS NSG update)"
  local RETVAL=0
  local WAN_IP=""
  local PRIORITY=0
  WAN_IP=$(rmd_remote_cli "dig +short myip.opendns.com @resolver1.opendns.com") 
  RETVAL=$?
  if [ $? -eq 0 ] ; then
      get_next_nsg_priority "${NFS_NSG_NAME}" PRIORITY "${NFS_AZ_RG}"
	  az network nsg rule create --resource-group "${NFS_AZ_RG}" \
	   --nsg-name "${NFS_NSG_NAME}" \
	   --name "Ssh-${RMD_VM_NAME}-${WAN_IP}-${NFS_NIC_ETH0_PRIVATE_IP}" \
	   --direction "Inbound" \
	   --priority ${PRIORITY} \
	   --source-address-prefixes "${WAN_IP}" \
	   --source-port-ranges '*' \
	   --destination-address-prefixes "${NFS_NIC_ETH0_PRIVATE_IP}" \
	   --destination-port-ranges ${SSH_PORT} \
	   --protocol "Tcp" \
	   --access "Allow" \
	   --output none \
	   --only-show-errors
	  RETVAL=$?
  fi
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step5() {
  doing "- ${FUNCNAME[0]} Simulator Upload"
  local RETVAL=0
  rmd_drag_from_nfs "rmd/${RMD_SIM_ARCHIVE}" "~/" && \
  rmd_remote_cli "mkdir -p /tmp/sim ; tar -zxf /home/${RMD_OS_USERNAME}/${RMD_SIM_ARCHIVE} -C /tmp/sim ; chmod 744 /tmp/sim/build/install.sh ; sudo /tmp/sim/build/install.sh \"${RMD_OS_USERNAME}\" &> /home/${RMD_OS_USERNAME}/install.log 2>&1"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

### main entry
login_az && \
step1 && \
step2 && \
step3 && \
step4 && \
step5
RETVAL=$?
[[ ${RETVAL} -eq 0 ]] && success "- completed" || error "- fail"
[[ ! ${NOLOGOUT} -eq 0 ]] && logout_az
clean_tmp_files
exit ${RETVAL}
