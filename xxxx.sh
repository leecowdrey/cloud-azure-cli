#!/bin/bash
source config.sh
source common.sh
alert "XXXX"

function xxxx_drag_from_nfs() {
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  [[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  ssh -A -o "StrictHostKeyChecking=no" \
      -p ${SSH_PORT} \
      -J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP}:${SSH_PORT} \
      ${XXXX_OS_USERNAME}@${XXXX_NIC_ETH1_PRIVATE_IP} \
      "scp -o \"StrictHostKeyChecking=no\" -P ${SSH_PORT} ${NFS_OS_USERNAME}@${NFS_NIC_ETH0_PUBLIC_IP}:${1} ${2}" # &> /dev/null
  return $?
}

function xxxx_remote_cli() {
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  #[[ -z "${NFS_NIC_ETH0_FQDN}" ]] && NFS_NIC_ETH0_FQDN=$(az vm show --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --show-details --query "fqdns" -o tsv --only-show-errors)
  [[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  ssh -A \
	-o "StrictHostKeyChecking=no" \
    -o "ServerAliveInterval=60" \
	-i ${SSH_KEY_PRIVATE} \
	-p ${SSH_PORT} \
	-J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP}:${SSH_PORT} \
	${XXXX_OS_USERNAME}@${XXXX_NIC_ETH1_PRIVATE_IP} ${2} \
	"${1}" # &> /dev/null
  return $?
}

function push_to_xxxx() {
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  scp -A -o "StrictHostKeyChecking=no" \
      -o "ServerAliveInterval=60" \
      -i ${SSH_KEY_PRIVATE} \
      -J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP}:${SSH_PORT} \
      -P ${SSH_PORT} ${3} \
	  ${1} \
      ${XXXX_OS_USERNAME}@${XXXX_NIC_ETH1_PRIVATE_IP}:${2} #&> /dev/null
  return $?
}

step1() {
  doing "- ${FUNCNAME[0]}"
  local RETVAL=0
  local EXISTS_ID=""
  local DISK_ID=""
  local DISK_EXISTS_ID=""
  local CLOUD_INIT=$(mktemp -q -p /tmp azure.XXXXXXXX)
  XXXX_OS_URN=$(az vm image list --location "${AZ_REGION}" --offer "${XXXX_OS_OFFER}" --publisher "${XXXX_OS_PUBLISHER}" --sku "${XXXX_OS_SKU}" --all --query '[-1].urn' --output tsv --only-show-errors)
  EXISTS_ID=$(az vm show --resource-group "${AZ_RG}" --name "${XXXX_VM_NAME}" --query "id" --output tsv --only-show-errors 2>/dev/null)
  [[ -n "${EXISTS_ID}" ]] && az vm delete --ids "${EXISTS_ID}" --yes --force-deletion yes --output none --only-show-errors
  DISK_EXISTS_ID=$(az disk show --resource-group "${AZ_RG}" --name "${XXXX_DATA_DISK_NAME}" --query "id" --output tsv --only-show-errors 2>/dev/null)
  [[ -n "${DISK_EXISTS_ID}" ]] && az disk delete --ids "${DISK_EXISTS_ID}" --yes --output none --only-show-errors
  cat <<EOF1 > ${CLOUD_INIT}
#cloud-config
fqdn: ${XXXX_VM_NAME,,}.${PRIVATE_DNS_ZONE_NAME,,}
EOF1
  az vm create --resource-group "${AZ_RG}" \
   --name "${XXXX_VM_NAME}" \
   --location "${AZ_REGION}" \
   --admin-password "${XXXX_OS_PASSWORD}" \
   --admin-username "${XXXX_OS_USERNAME}" \
   --ssh-key-values "${SSH_KEY_PUBLIC_VALUE}" \
   --image "${XXXX_OS_URN}" \
   --encryption-at-host "${VPN_EAH_ENABLE,,}" \
   --enable-auto-update "${XXXX_EAH_ENABLE,,}" \
   --custom-data "${CLOUD_INIT}" \
   --size "${XXXX_NODE_TYPE}" \
   --nics ${XXXX_NIC_ETH0} ${XXXX_NIC_ETH1} \
   --output none \
   --only-show-errors && \
   DISK_ID=$(az vm disk attach --resource-group "${AZ_RG}" \
     --vm-name "${XXXX_VM_NAME}" \
	 --name "${XXXX_DATA_DISK_NAME}" \
	 --new \
	 --size-gb "${XXXX_DATA_DISK_SIZE}" \
     --query 'id' -o tsv \
	 --only-show-errors) && \
  [[ -f "${CLOUD_INIT}" ]] && rm -f ${CLOUD_INIT} &> /dev/null
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step2() {
  doing "- ${FUNCNAME[0]} Updating SSH Host Keys"
  local RETVAL=0
  wait_for_private_ip "${XXXX_VM_NAME}" "${XXXX_NIC_ETH1}" "${XXXX_NIC_ETH1_PRIVATE_IP}" && \
  if [ -f ~/.ssh/known_hosts ] ; then
   ssh-keygen -f ~/.ssh/known_hosts -R ${XXXX_NIC_ETH1_PRIVATE_IP} 2> /dev/null
  fi
  update_vm_sshd_config "${AZ_RG}" "${XXXX_VM_NAME}" "${XXXX_OS_USERNAME}" "${SSH_PORT}"
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  ssh -A -o "StrictHostKeyChecking=no" -i ${SSH_KEY_PRIVATE} -p ${SSH_PORT} -J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT} ${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP} "ssh-keygen -f ~/.ssh/known_hosts -R ${XXXX_NIC_ETH0_PRIVATE_IP} 2> /dev/null ; ssh-keyscan -p ${SSH_PORT} -t rsa -H ${XXXX_NIC_ETH0_PRIVATE_IP} >> ~/.ssh/known_hosts"
  ssh -A -o "StrictHostKeyChecking=no" -i ${SSH_KEY_PRIVATE} -p ${SSH_PORT} -J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT} ${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP} "ssh-keygen -f ~/.ssh/known_hosts -R ${XXXX_NIC_ETH1_PRIVATE_IP} 2> /dev/null ; ssh-keyscan -p ${SSH_PORT} -t rsa -H ${XXXX_NIC_ETH1_PRIVATE_IP} >> ~/.ssh/known_hosts"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step3() {
  doing "- ${FUNCNAME[0]} Host Prepare"
  local RETVAL=0
  push_to_xxxx "${XXXX_OS_PREPARE}" "/tmp/" && \
  xxxx_remote_cli "chmod 744 /tmp/${XXXX_OS_PREPARE} ; sudo /tmp/${XXXX_OS_PREPARE} \"${XXXX_OS_USERNAME}\" \"${AZ_LANG}\" \"${AZ_TIMEZONE}\" \"${SSH_PORT}\" \"${XXXX_VM_NAME,,}.${PRIVATE_DNS_ZONE_NAME,,}\" &> ~/prepare.log 2>&1"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step4() {
  doing "- ${FUNCNAME[0]} Determine WAN IP address (NFS NSG update)"
  local RETVAL=0
  local WAN_IP=""
  local PRIORITY=0
  WAN_IP=$(xxxx_remote_cli "dig +short myip.opendns.com @resolver1.opendns.com") 
  RETVAL=$?
  if [ $? -eq 0 ] ; then
      get_next_nsg_priority "${NFS_NSG_NAME}" PRIORITY "${NFS_AZ_RG}"
	  az network nsg rule create --resource-group "${NFS_AZ_RG}" \
	   --nsg-name "${NFS_NSG_NAME}" \
	   --name "Ssh-${XXXX_VM_NAME}-${WAN_IP}-${NFS_NIC_ETH0_PRIVATE_IP}" \
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
  doing "- ${FUNCNAME[0]} Release Upload"
  local RETVAL=0
  xxxx_drag_from_nfs "XXXX/${RELEASE_ARCHIVE}" "~/${RELEASE_ARCHIVE}" && \
  xxxx_remote_cli "tar zxf ~/${RELEASE_ARCHIVE} ; rm -f ~/${RELEASE_ARCHIVE} &> /dev/null" && \
  if [[ -f "${NFS_BACKUP_KEY}" ]] ; then
    xxxx_remote_cli "rm -f ~/.ssh/${NFS_BACKUP_KEY} ~/.ssh/${NFS_BACKUP_KEY}.pub &> /dev/null"
    push_to_xxxx "${NFS_BACKUP_KEY}" "~/.ssh"
    push_to_xxxx "${NFS_BACKUP_KEY}.pub" "~/.ssh"
  fi
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step6() {
  doing "- ${FUNCNAME[0]} - Remote platform_config update"
  local RETVAL=0
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  xxxx_remote_cli "mkdir -p ~/bin ; curl -sLO https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && mv -f yq_linux_amd64 ~/bin/azureyq && chmod 755 ~/bin/azureyq" && \
  xxxx_remote_cli "cp -f ~/platform/ansible/configs/platform-config.yaml.blank_singlehost ~/platform/ansible/configs/platform-config.yaml" && \
  xxxx_remote_cli "~/bin/azureyq -i '.dmhost_user = \"${XXXX_OS_USERNAME,,}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  xxxx_remote_cli "~/bin/azureyq -i '.number_of_hosts = ${AZ_AKS_DM_POOL_NODES}' ~/platform/ansible/configs/platform-config.yaml" && \
  xxxx_remote_cli "~/bin/azureyq -i '.northbound_vip = \"${XXXX_NIC_ETH0_PRIVATE_IP}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  xxxx_remote_cli "~/bin/azureyq -i '.southbound_vip = \"${XXXX_NIC_ETH1_PRIVATE_IP}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  xxxx_remote_cli "~/bin/azureyq -i '.pv_backing_store = \"/backing_store\"' ~/platform/ansible/configs/platform-config.yaml" && \
  xxxx_remote_cli "~/bin/azureyq -i '.rmd_subnets = \"${SPOKE_SUBNET_PREFIX}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  xxxx_remote_cli "~/bin/azureyq -i '.external_pv_rwo = \"${AZ_AKS_DM_SC_RWO_CLASS}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  xxxx_remote_cli "~/bin/azureyq -i '.external_pv_rwx = \"${AZ_AKS_DM_SC_RWX_CLASS}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  xxxx_remote_cli "~/bin/azureyq -i '.k8s_dns_servers = \"8.8.8.8,8.8.4.4\"' ~/platform/ansible/configs/platform-config.yaml" && \
  xxxx_remote_cli "~/bin/azureyq -i '.local_pv = \"${AZ_AKS_DM_SC_LOCAL_CLASS}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  xxxx_remote_cli "~/bin/azureyq -i '.backup_host = \"${BASTION_NIC_ETH0_PUBLIC_IP}\"' ~/platform/ansible/configs/platform-config.yaml "&& \
  xxxx_remote_cli "~/bin/azureyq -i '.backup_user = \"${NFS_OS_USERNAME}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  xxxx_remote_cli "~/bin/azureyq -i '.backup_dir = \"${NFS_BACKUP_PATH}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  xxxx_remote_cli "~/bin/azureyq -i '.backup_key = \"/home/${XXXX_OS_USERNAME}/.ssh/${NFS_BACKUP_KEY}\"' ~/platform/ansible/configs/platform-config.yaml"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}
#  xxxx_remote_cli "sudo snap install yq"


step7() {
  doing "- ${FUNCNAME[0]} Platform Installation"
  local RETVAL=0
  xxxx_remote_cli "export PATH=\$PATH:/snap/bin ; cd ~/platform/ansible/install_scripts ; ./install.sh"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step8() {
  doing "- ${FUNCNAME[0]} Connection Details"
  local RETVAL=0
  [[ -z "${XXXX_NIC_ETH0_FQDN}" ]] && XXXX_NIC_ETH0_FQDN=$(az vm show --resource-group "${NFS_AZ_RG}" --name "${XXXX_VM_NAME}" --show-details --query "fqdns" -o tsv --only-show-errors)
  [[ -z "${XXXX_NIC_ETH0_PUBLIC_IP}" ]] && XXXX_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${XXXX_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  echo "for UI use: https://${XXXX_NIC_ETH0_PUBLIC_IP} or https://${XXXX_NIC_ETH0_FQDN}/"
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  #[[ -z "${NFS_NIC_ETH0_FQDN}" ]] && NFS_NIC_ETH0_FQDN=$(az vm show --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --show-details --query "fqdns" -o tsv --only-show-errors)
  [[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  echo "ssh -A -o \"StrictHostKeyChecking=no\" -o \"ServerAliveInterval=60\" -i ${SSH_KEY_PRIVATE} -p ${SSH_PORT} -J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP}:${SSH_PORT} -L 8443:${XXXX_NIC_ETH0_PRIVATE_IP}:443 ${XXXX_OS_USERNAME}@${XXXX_NIC_ETH1_PRIVATE_IP}"
  echo "followed by https://127.0.0.1:8443/"
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
step5 && \
step6 && \
step7 && \
step8
RETVAL=$?
[[ ${RETVAL} -eq 0 ]] && success "- completed" || error "- fail"
[[ ! ${NOLOGOUT} -eq 0 ]] && logout_az
clean_tmp_files
exit ${RETVAL}

