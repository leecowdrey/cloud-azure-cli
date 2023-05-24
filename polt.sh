#!/bin/bash
source config.sh
source common.sh
alert "POLT"

function polt_drag_from_nfs() {
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  [[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  ssh -A -o "StrictHostKeyChecking=no" \
      -p ${SSH_PORT} \
      -J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${SPOKE_NIC_ETH0_PRIVATE_IP}:${SSH_PORT} \
      ${POLT_OS_USERNAME}@${POLT_NIC_ETH0_PRIVATE_IP} \
      "scp -o \"StrictHostKeyChecking=no\" -P ${SSH_PORT} ${NFS_OS_USERNAME}@${NFS_NIC_ETH0_PUBLIC_IP}:${1} ${2}" # &> /dev/null
  return $?
}

function polt_remote_cli() {
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  [[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  ssh -A \
	-o "StrictHostKeyChecking=no" \
    -o "ServerAliveInterval=60" \
	-i ${SSH_KEY_PRIVATE} \
	-p ${SSH_PORT} \
	-J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${SPOKE_NIC_ETH0_PRIVATE_IP}:${SSH_PORT} \
	${POLT_OS_USERNAME}@${POLT_NIC_ETH0_PRIVATE_IP} ${2} \
	"${1}" # &> /dev/null
  return $?
}

function push_to_polt() {
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  scp -A \
	-o "StrictHostKeyChecking=no" \
	-i ${SSH_KEY_PRIVATE} \
	-P ${SSH_PORT} \
	-J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${SPOKE_NIC_ETH0_PRIVATE_IP}:${SSH_PORT} ${3} \
	${1} \
	${POLT_OS_USERNAME}@${POLT_NIC_ETH0_PRIVATE_IP}:${2} #&> /dev/null
  return $?
}

step1() {
  doing "- ${FUNCNAME[0]}"
  local RETVAL=0
  local EXISTS_ID=""
  local DISK_ID=""
  local DISK_EXISTS_ID=""
  local CLOUD_INIT=$(mktemp -q -p /tmp azure.XXXXXXXX)
  POLT_OS_URN=$(az vm image list --location "${AZ_REGION}" --offer "${POLT_OS_OFFER}" --publisher "${POLT_OS_PUBLISHER}" --sku "${POLT_OS_SKU}" --all --query '[-1].urn' --output tsv --only-show-errors)
  EXISTS_ID=$(az vm show --resource-group "${AZ_RG}" --name "${POLT_VM_NAME}" --query "id" --output tsv --only-show-errors 2>/dev/null)
  [[ -n "${EXISTS_ID}" ]] && az vm delete --ids "${EXISTS_ID}" --yes --force-deletion yes --output none --only-show-errors
  DISK_EXISTS_ID=$(az disk show --resource-group "${AZ_RG}" --name "${POLT_DATA_DISK_NAME}" --query "id" --output tsv --only-show-errors 2>/dev/null)
  [[ -n "${DISK_EXISTS_ID}" ]] && az disk delete --ids "${DISK_EXISTS_ID}" --yes --output none --only-show-errors
  cat <<EOF1 > ${CLOUD_INIT}
#cloud-config
fqdn: ${POLT_VM_NAME,,}.${PRIVATE_DNS_ZONE_NAME,,}
EOF1
  az vm create --resource-group "${AZ_RG}" \
   --name "${POLT_VM_NAME}" \
   --location "${AZ_REGION}" \
   --admin-password "${POLT_OS_PASSWORD}" \
   --admin-username "${POLT_OS_USERNAME}" \
   --ssh-key-values "${SSH_KEY_PUBLIC_VALUE}" \
   --image "${POLT_OS_URN}" \
   --encryption-at-host "${POLT_EAH_ENABLE,,}" \
   --enable-auto-update "${POLT_OS_AUTO_UPDATE,,}" \
   --custom-data "${CLOUD_INIT}" \
   --size "${POLT_NODE_TYPE}" \
   --nics ${POLT_NIC_ETH0} \
   --output none \
   --only-show-errors && \
   DISK_ID=$(az vm disk attach --resource-group "${AZ_RG}" \
     --vm-name "${POLT_VM_NAME}" \
	 --name "${POLT_DATA_DISK_NAME}" \
	 --new \
	 --size-gb "${POLT_DATA_DISK_SIZE}" \
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
  wait_for_private_ip "${POLT_VM_NAME}" "${POLT_NIC_ETH0}" "${POLT_NIC_ETH0_PRIVATE_IP}" && \
  if [ -f ~/.ssh/known_hosts ] ; then
   ssh-keygen -f ~/.ssh/known_hosts -R ${POLT_NIC_ETH0_PRIVATE_IP} 2> /dev/null
  fi
  update_vm_sshd_config "${AZ_RG}" "${POLT_VM_NAME}" "${POLT_OS_USERNAME}" "${SSH_PORT}"
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  ssh -A -o "StrictHostKeyChecking=no" -i ${SSH_KEY_PRIVATE} -p ${SSH_PORT} -J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP},${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP} ${VPN_OS_USERNAME}@${SPOKE_NIC_ETH0_PRIVATE_IP} "ssh-keygen -f ~/.ssh/known_hosts -R ${POLT_NIC_ETH0_PRIVATE_IP} 2> /dev/null ; ssh-keyscan -p ${SSH_PORT} -t rsa -H ${POLT_NIC_ETH0_PRIVATE_IP} >> ~/.ssh/known_hosts"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step3() {
  doing "- ${FUNCNAME[0]} Host Prepare"
  local RETVAL=0
  push_to_polt "${POLT_SIM_PREPARE}" "/tmp" && \
  polt_remote_cli "chmod 744 /tmp/${POLT_SIM_PREPARE} ; sudo /tmp/${POLT_SIM_PREPARE} \"${POLT_OS_USERNAME}\" \"${AZ_LANG}\" \"${AZ_TIMEZONE}\" \"${SSH_PORT}\" \"${POLT_VM_NAME,,}.${PRIVATE_DNS_ZONE_NAME,,}\" &> ~/prepare.log 2>&1"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step4() {
  doing "- ${FUNCNAME[0]} Determine WAN IP address (NFS NSG update)"
  local RETVAL=0
  local WAN_IP=""
  local PRIORITY=0
  WAN_IP=$(polt_remote_cli "dig +short myip.opendns.com @resolver1.opendns.com") 
  RETVAL=$?
  if [ $? -eq 0 ] ; then
      get_next_nsg_priority "${NFS_NSG_NAME}" PRIORITY "${NFS_AZ_RG}"
	  az network nsg rule create --resource-group "${NFS_AZ_RG}" \
	   --nsg-name "${NFS_NSG_NAME}" \
	   --name "Ssh-${POLT_VM_NAME}-${WAN_IP}-${NFS_NIC_ETH0_PRIVATE_IP}" \
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
  doing "- ${FUNCNAME[0]} pon-dockerrep image load"
  local RETVAL=0
  polt_remote_cli "mkdir -p ~/docker"
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/docker/${POLT_DOCKER_ARANGODB}" "~/docker/" && \
  polt_remote_cli "docker load --input ~/docker/${POLT_DOCKER_ARANGODB}" && \
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/docker/${POLT_DOCKER_AUTOCONF}" "~/docker/" && \
  polt_remote_cli "docker load --input ~/docker/${POLT_DOCKER_AUTOCONF}" && \
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/docker/${POLT_DOCKER_BAA}" "~/docker/" && \
  polt_remote_cli "docker load --input ~/docker/${POLT_DOCKER_BAA}" && \
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/docker/${POLT_DOCKER_BBF_OBBAA}" "~/docker/" && \
  polt_remote_cli "docker load --input ~/docker/${POLT_DOCKER_BBF_OBBAA}" && \
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/docker/${POLT_DOCKER_HTTPD}" "~/docker/" && \
  polt_remote_cli "docker load --input ~/docker/${POLT_DOCKER_HTTPD}" && \
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/docker/${POLT_DOCKER_KAFKA}" "~/docker/" && \
  polt_remote_cli "docker load --input ~/docker/${POLT_DOCKER_KAFKA}" && \
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/docker/${POLT_DOCKER_POLT}" "~/docker/" && \
  polt_remote_cli "docker load --input ~/docker/${POLT_DOCKER_POLT}" && \
  polt_remote_cli "docker tag pon-dockerrepo.broadbus.com:5000/polt:${POLT_DOCKER_POLT_VERSION} pon-dockerrepo.broadbus.com:5000/polt:latest" && \
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/docker/${POLT_DOCKER_VOMCI}" "~/docker/" && \
  polt_remote_cli "docker load --input ~/docker/${POLT_DOCKER_VOMCI}" && \
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/docker/${POLT_DOCKER_ZOOKEEPER}" "~/docker/" && \
  polt_remote_cli "docker load --input ~/docker/${POLT_DOCKER_ZOOKEEPER}" && \
  polt_remote_cli "rm -R -f ~/docker &> /dev/null"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step6() {
  doing "- ${FUNCNAME[0]} Simulator Upload"
  local RETVAL=0
  local PTDIR="export ORCAHOST=https://${POLT_NIC_ETH0_PRIVATE_IP}:5000 ; export PONTOOLS_DIR=/home/ponuser/pon-tools ; export PATH=\$PATH:\${PONTOOLS_DIR}"

  #info "io-orchestrate/orca venv"
  #polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/${POLT_IO_ORCHESTRATE}" "/persist/staging/"
  #polt_remote_cli "sudo dpkg -i /persist/staging/${POLT_IO_ORCHESTRATE}"
  #polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/${POLT_ORCA_VENV}" "/persist/staging/"
  #polt_remote_cli "sudo dpkg -i /persist/staging/${POLT_ORCA_VENV}"

  info "polt_drag_from_nfs: ${POLT_BULK_RELEASE}"
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/${POLT_BULK_RELEASE}" "/persist/staging/"

  info "polt_drag_from_nfs: ${POLT_PON_BULK_RELEASE}"
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/${POLT_PON_BULK_RELEASE}" "/persist/staging/"

  info "polt_drag_from_nfs: ${POLT_OLT_BULK_RELEASE}"
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/${POLT_OLT_BULK_RELEASE}" "/persist/staging/"

  info "step01/version"
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/step01.sh" "/persist/staging/"
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/version" "/persist/staging/" 
  polt_remote_cli "cd /persist/staging/ ; chmod 744 step01.sh ; ./step01.sh"

  info "polt_drag_from_nfs: various scripts"
  polt_drag_from_nfs "polt/deploy/*.sh" "/persist/staging/"
  polt_remote_cli "cd /persist/staging/ ; chmod 744 *.sh"

  info "olt-platform_install_br"
  polt_remote_cli "cd /persist/staging/ ; printf \"exit\n\" | bash -s ./olt-platform_install_br.sh"

  info "pontools"
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/${POLT_PON_TOOLS}" "/persist/staging/"
  polt_remote_cli "mkdir -p /persist/pon-tools/1.0.0.sprint${POLT_SIM_VERSION} ; tar zxf /persist/staging/${POLT_PON_TOOLS} -C /persist/pon-tools/1.0.0.sprint${POLT_SIM_VERSION}/"
  polt_remote_cli "echo \"orcahost=https://${POLT_NIC_ETH0_PRIVATE_IP}:5000\" > /persist/pon-tools/1.0.0.sprint${POLT_SIM_VERSION}/.poncfg "
  polt_remote_cli "echo \"{ \"orcahost\": \"https://${POLT_NIC_ETH0_PRIVATE_IP}:5000\" }\" > /persist/pon-tools/1.0.0.sprint${POLT_SIM_VERSION}/.poncfg.json"

  info "pon-venv"
  polt_drag_from_nfs "polt/sim_sprint${POLT_SIM_VERSION}/${POLT_PON_VENV}" "/persist/staging/"
  polt_remote_cli "sudo dpkg -i /persist/staging/${POLT_PON_VENV}"

  info "pontools-envupdate"
  polt_remote_cli "cd /persist/pon-tools/1.0.0.sprint${POLT_SIM_VERSION}/ ; ./pontools-envupdate.sh --pontools /persist/pon-tools/1.0.0.sprint${POLT_SIM_VERSION} --orcahost https://${POLT_NIC_ETH0_PRIVATE_IP}:5000"

  info "setupOlt" && \
  polt_remote_cli "cd /persist/staging/ ; ${PTDIR} ; ./setupOlt.sh " # -p preset polt";vomciConnMethod="grpc

  info "setupOnu"
  polt_remote_cli "cd /persist/staging/ ; ${PTDIR} ; ./setupOnu.sh" # -n ${POLT_ONUS} preset to 2

  info "startSim"
  polt_remote_cli "cd /persist/staging/ ; ${PTDIR} ; ./startSim.sh" "-t"
  #
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
step6 
RETVAL=$?
[[ ${RETVAL} -eq 0 ]] && success "- completed" || error "- fail"
[[ ! ${NOLOGOUT} -eq 0 ]] && logout_az
clean_tmp_files
exit ${RETVAL}

