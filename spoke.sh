#!/bin/bash
source config.sh
source common.sh
alert "spoke"

step1() {
  doing "- ${FUNCNAME[0]} Spoke VM"
  local RETVAL=0
  local VPN_1=""
  local EXISTS_ID=""
  local SPOKE_CFG_VYOS=$(mktemp -q -p /tmp azure.XXXXXXXX)
  wait_for_private_ip "${SPOKE_VM_NAME}" "${SPOKE_NIC_ETH0}" "${SPOKE_NIC_ETH0_PRIVATE_IP}"
  wait_for_private_ip "${SPOKE_VM_NAME}" "${SPOKE_NIC_ETH1}" "${SPOKE_NIC_ETH1_PRIVATE_IP}"
  cat <<EOF1 > "${SPOKE_CFG_VYOS}"
source /opt/vyatta/etc/functions/script-template
configure
set interfaces ethernet eth0 description '${COMMON_SUBNET}'
set interfaces ethernet eth1 description '${SPOKE_SUBNET_NAME}'
set system login user ${VPN_OS_USERNAME} authentication plaintext-password '${VPN_OS_PASSWORD}'
set system login user ${VPN_OS_USERNAME} authentication public-keys ${SSH_KEY_PUBLIC_EMAIL} key '${SSH_KEY_PUBLIC_KEY}'
set system login user ${VPN_OS_USERNAME} authentication public-keys ${SSH_KEY_PUBLIC_EMAIL} type '${SSH_KEY_PUBLIC_TYPE}'
set system login user ${VPN_OS_USERNAME} full-name '${CUSTOMER^^}'
set service ssh client-keepalive-interval '60'
set service ssh disable-host-validation
set service ssh disable-password-authentication
#set service ssh access-control allow user ${VPN_OS_USERNAME}
set service ssh port ${SSH_PORT}
set system time-zone '${AZ_TIMEZONE}'
set system ipv6 disable
delete system login user vyos
set system login banner post-login 'Unauthorized access is prohibited - parts Copyright © 2022 CommScope, Inc.'
commit
save
exit
EOF1
  VPN_OS_URN=$(az vm image list --location "${AZ_REGION}" --offer "${VPN_OS_OFFER}" --publisher "${VPN_OS_PUBLISHER}" --sku "${VPN_OS_SKU}" --all --query '[-1].urn' --output tsv --only-show-errors)
  EXISTS_ID=$(az vm show --resource-group "${AZ_RG}" --name "${SPOKE_VM_NAME}" --query "id" --output tsv --only-show-errors 2>/dev/null)
  [[ -n "${EXISTS_ID}" ]] && az vm delete --ids "${EXISTS_ID}" --yes --force-deletion yes --output none --only-show-errors || az vm image terms accept --urn "${VPN_OS_URN}" --output  none --only-show-errors
  az vm create --resource-group "${AZ_RG}" \
   --name "${SPOKE_VM_NAME}" \
   --location "${AZ_REGION}" \
   --admin-password "${VPN_OS_PASSWORD}" \
   --admin-username "${VPN_OS_USERNAME}" \
   --ssh-key-values "${SSH_KEY_PUBLIC_VALUE}" \
   --image "${VPN_OS_URN}" \
   --encryption-at-host "${VPN_EAH_ENABLE,,}" \
   --size "${SPOKE_NODE_TYPE}" \
   --nics ${SPOKE_NIC_ETH0} ${SPOKE_NIC_ETH1} \
   --output none \
   --only-show-errors && \
  VPN_RUN_SCRIPT=$(cat ${SPOKE_CFG_VYOS} | base64 -w 0 ; rm -f ${SPOKE_CFG_VYOS} &> /dev/null)
  VPN_1="echo \"${VPN_RUN_SCRIPT}\"|base64 -d|/bin/vbash"
  az vm run-command invoke -g "${AZ_RG}" -n "${SPOKE_VM_NAME}" --command-id RunShellScript --scripts "${VPN_1}" --output none --only-show-errors && \
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}"
  [[ ${RETVAL} -eq 0 ]] && info "Spoke hostname:${SPOKE_VM_NAME},private-ip:${SPOKE_NIC_ETH0_PRIVATE_IP},username:${VPN_OS_USERNAME},password:${VPN_OS_PASSWORD}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step2() {
  doing "- ${FUNCNAME[0]} Hub/Spoke IPsec VPN - Spoke End"
  local RETVAL=0
  local VPN_1=""
  local SPOKE_CFG_VYOS=$(mktemp -q -p /tmp azure.XXXXXXXX)
  #wait_for_hub_spoke_vms && \
  cat <<EOF5 > "${SPOKE_CFG_VYOS}"
source /opt/vyatta/etc/functions/script-template
configure
run generate vpn rsa-key bits 2048
set vpn ipsec logging log-level '1'
set vpn ipsec logging log-modes 'any'
set vpn ipsec logging log-modes 'ike'
set vpn ipsec logging log-modes 'esp'
set vpn ipsec logging log-modes 'net'
set vpn ipsec esp-group ESP_${AZ_SUBSCRIPTION^^}_01 compression 'disable'
set vpn ipsec esp-group ESP_${AZ_SUBSCRIPTION^^}_01 lifetime '3600'
set vpn ipsec esp-group ESP_${AZ_SUBSCRIPTION^^}_01 mode 'tunnel'
set vpn ipsec esp-group ESP_${AZ_SUBSCRIPTION^^}_01 pfs 'dh-group19'
set vpn ipsec esp-group ESP_${AZ_SUBSCRIPTION^^}_01 proposal 10 encryption 'aes256gcm128'
set vpn ipsec esp-group ESP_${AZ_SUBSCRIPTION^^}_01 proposal 10 hash 'sha512'
set vpn ipsec ike-group IKE_${AZ_SUBSCRIPTION^^}_01 key-exchange 'ikev2'
set vpn ipsec ike-group IKE_${AZ_SUBSCRIPTION^^}_01 lifetime '28800'
set vpn ipsec ike-group IKE_${AZ_SUBSCRIPTION^^}_01 proposal 10 dh-group '19'
set vpn ipsec ike-group IKE_${AZ_SUBSCRIPTION^^}_01 proposal 10 encryption 'aes256gcm128'
set vpn ipsec ike-group IKE_${AZ_SUBSCRIPTION^^}_01 proposal 10 hash 'sha512'
set vpn ipsec ike-group IKE_${AZ_SUBSCRIPTION^^}_01 dead-peer-detection action 'restart'
set vpn ipsec ike-group IKE_${AZ_SUBSCRIPTION^^}_01 dead-peer-detection interval '30'
set vpn ipsec ike-group IKE_${AZ_SUBSCRIPTION^^}_01 dead-peer-detection timeout '120'
set vpn ipsec ipsec-interfaces interface 'eth0'
set vpn ipsec site-to-site peer ${HUB_NIC_ETH0_PRIVATE_IP} connection-type 'initiate'
set vpn ipsec site-to-site peer ${HUB_NIC_ETH0_PRIVATE_IP} authentication id '${SPOKE_NIC_ETH0_PRIVATE_IP}'
set vpn ipsec site-to-site peer ${HUB_NIC_ETH0_PRIVATE_IP} authentication mode 'pre-shared-secret'
set vpn ipsec site-to-site peer ${HUB_NIC_ETH0_PRIVATE_IP} authentication pre-shared-secret '${VPN_SECRET}'
set vpn ipsec site-to-site peer ${HUB_NIC_ETH0_PRIVATE_IP} default-esp-group 'ESP_${AZ_SUBSCRIPTION^^}_01'
set vpn ipsec site-to-site peer ${HUB_NIC_ETH0_PRIVATE_IP} ike-group 'IKE_${AZ_SUBSCRIPTION^^}_01'
set vpn ipsec site-to-site peer ${HUB_NIC_ETH0_PRIVATE_IP} local-address '${SPOKE_NIC_ETH0_PRIVATE_IP}'
set vpn ipsec site-to-site peer ${HUB_NIC_ETH0_PRIVATE_IP} tunnel 1 local prefix '${SPOKE_SUBNET_PREFIX}'
set vpn ipsec site-to-site peer ${HUB_NIC_ETH0_PRIVATE_IP} tunnel 1 remote prefix '${HUB_SUBNET_PREFIX}'
commit
save
run restart vpn
exit
EOF5
  VPN_RUN_SCRIPT=$(cat ${SPOKE_CFG_VYOS} | base64 -w 0 ; rm -f ${SPOKE_CFG_VYOS} &> /dev/null)
  VPN_1="echo \"${VPN_RUN_SCRIPT}\"|base64 -d|/bin/vbash"
  az vm run-command invoke -g "${AZ_RG}" -n "${SPOKE_VM_NAME}" --command-id RunShellScript --scripts "${VPN_1}" --output none --only-show-errors
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step3() {
  doing "- ${FUNCNAME[0]} Updating SSH Host Keys"
  local RETVAL=0
  [[ -z "${BASTION_NIC_ETH0_FQDN}" ]] && BASTION_NIC_ETH0_FQDN=$(az vm show --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --show-details --query "fqdns" -o tsv --only-show-errors)
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  ssh -A -o "StrictHostKeyChecking=no" -i ${SSH_KEY_PRIVATE} -p ${SSH_PORT} -J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT} ${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP} "ssh-keygen -f ~/.ssh/known_hosts -R ${SPOKE_NIC_ETH0_PRIVATE_IP} 2> /dev/null ; ssh-keyscan -p ${SSH_PORT} -t rsa -H ${SPOKE_NIC_ETH0_PRIVATE_IP} >> ~/.ssh/known_hosts"  
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step4() {
  doing "- ${FUNCNAME[0]} Determine WAN IP address (NFS NSG update)"
  local RETVAL=0
  local WAN_IP=""
  local PRIORITY=0
  [[ -z "${BASTION_NIC_ETH0_FQDN}" ]] && BASTION_NIC_ETH0_FQDN=$(az vm show --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --show-details --query "fqdns" -o tsv --only-show-errors)
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  WAN_IP=$(ssh -A -o "StrictHostKeyChecking=no" -i ${SSH_KEY_PRIVATE} -p ${SSH_PORT} -J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP}:${SSH_PORT} ${VPN_OS_USERNAME}@${SPOKE_NIC_ETH0_PRIVATE_IP} "dig +short myip.opendns.com @resolver1.opendns.com") 
  RETVAL=$?
  if [ $? -eq 0 ] ; then
      get_next_nsg_priority "${NFS_NSG_NAME}" PRIORITY "${NFS_AZ_RG}"
	  az network nsg rule create --resource-group "${NFS_AZ_RG}" \
	   --nsg-name "${NFS_NSG_NAME}" \
	   --name "Ssh-${SPOKE_VM_NAME}-${WAN_IP}-${NFS_NIC_ETH0_PRIVATE_IP}" \
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
