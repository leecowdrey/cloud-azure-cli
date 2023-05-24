#!/bin/bash
source config.sh
source common.sh
alert "nsg-dip"

step1() {
  doing "- ${FUNCNAME[0]} Removing Public SSH IP Addresses (NFS)"
  local RETVAL=0
  local PRIORITY=0
  local NFS_IDS=""
  NFS_IDS=$(az network nsg rule list --resource-group "${NFS_AZ_RG}" \
    --nsg-name "${NFS_NSG_NAME}" \
	--query "[?contains(name,'Public-Ssh-')].id" \
	--output tsv \
	--only-show-errors)
  RETVAL=$?  
  [[ -n "${NFS_IDS}" ]] && (az network nsg rule delete --resource-group "${NFS_AZ_RG}" --nsg-name "${NFS_NSG_NAME}" --ids "${NFS_IDS}" --output none --only-show-errors ; RETVAL=$?)
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step2() {
  doing "- ${FUNCNAME[0]} Removing Public SSH IP Addresses (${BASTION_VM_NAME})"
  local RETVAL=0
  local PRIORITY=0
  local BASTION_IDS=""
  BASTION_IDS=$(az network nsg rule list --resource-group "${AZ_RG}" \
    --nsg-name "${HUB_NSG_NAME}" \
	--query "[?contains(name,'Public-Ssh-')].id" \
	--output tsv \
	--only-show-errors)
  RETVAL=$?  
  [[ -n "${BASTION_IDS}" ]] && (az network nsg rule delete --resource-group "${AZ_RG}" --nsg-name "${HUB_NSG_NAME}" --ids "${BASTION_IDS}" --output none --only-show-errors ; RETVAL=$?)
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step3() {
  doing "- ${FUNCNAME[0]} Adding Public SSH IP Addresses (NFS})"
  local RETVAL=0
  local PRIORITY=0
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
  RETVAL=$?  
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step4() {
  doing "- ${FUNCNAME[0]} Adding Public SSH IP Addresses (${BASTION_VM_NAME})"
  local RETVAL=0
  local PRIORITY=0
  for ((I = 0; I < ${#PERMITTED_WAN_IP[@]}; ++I)); do
	  get_next_nsg_priority "${HUB_NSG_NAME}" PRIORITY && \
	  az network nsg rule create --resource-group "${AZ_RG}" \
	   --nsg-name "${HUB_NSG_NAME}" \
	   --name "Public-Ssh-${BASTION_VM_NAME}-${PERMITTED_WAN_IP[$I]}-${BASTION_NIC_ETH0_PRIVATE_IP}" \
	   --direction "Inbound" \
	   --priority ${PRIORITY} \
	   --source-address-prefixes "${PERMITTED_WAN_IP[$I]}" \
	   --source-port-ranges '*' \
	   --destination-address-prefixes "${BASTION_NIC_ETH0_PRIVATE_IP}" \
	   --destination-port-ranges ${SSH_PORT} \
	   --protocol "Tcp" \
	   --access "Allow" \
	   --output none \
	   --only-show-errors 
  done  
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step5() {
  doing "- ${FUNCNAME[0]} Removing Public HTTPS (${CSDM_VM_NAME})"
  local RETVAL=0
  local PRIORITY=0
  local CSDM_IDS=""
  CSDM_IDS=$(az network nsg rule list --resource-group "${AZ_RG}" \
    --nsg-name "${CSDM_NSG_NAME}" \
	--query "[?contains(name,'Public-Https-')].id" \
	--output tsv \
	--only-show-errors)
  RETVAL=$?  
  [[ -n "${CSDM_IDS}" ]] && (az network nsg rule delete --resource-group "${AZ_RG}" --nsg-name "${CSDM_NSG_NAME}" --ids "${CSDM_IDS}" --output none --only-show-errors ; RETVAL=$?)
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step6() {
  doing "- ${FUNCNAME[0]} Adding Public HTTPS IP Addresses (${CSDM_VM_NAME})"
  local RETVAL=0
  local PRIORITY=0
  for ((I = 0; I < ${#PERMITTED_WAN_IP[@]}; ++I)); do
	  get_next_nsg_priority "${CSDM_NSG_NAME}" PRIORITY && \
	  az network nsg rule create --resource-group "${AZ_RG}" \
	   --nsg-name "${CSDM_NSG_NAME}" \
	   --name "Public-Https-${CSDM_VM_NAME}-${PERMITTED_WAN_IP[$I]}-${CSDM_NIC_ETH0_PRIVATE_IP}" \
	   --direction "Inbound" \
	   --priority ${PRIORITY} \
	   --source-address-prefixes "${PERMITTED_WAN_IP[$I]}" \
	   --source-port-ranges '*' \
	   --destination-address-prefixes "${CSDM_NIC_ETH0_PRIVATE_IP}" \
	   --destination-port-ranges 443 \
	   --protocol "Tcp" \
	   --access "Allow" \
	   --output none \
	   --only-show-errors 
  done  
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