#!/bin/bash
source config.sh
source common.sh
alert "networks"
 
step1() {
  doing "- ${FUNCNAME[0]} Networks/Subnets"
  local RETVAL=0
  [[ -z $(az group list --query "[?contains(name,'${AZ_RG}')].name" -o tsv) ]] && az group create --name "${AZ_RG}" --location "${AZ_REGION}" --output none --only-show-errors
  az network vnet create --resource-group "${AZ_RG}" \
   --name "${COMMON_VNET}" \
   --address-prefix "${COMMON_ADDRESS_PREFIX}" \
   --location "${AZ_REGION}" \
   --output none \
   --only-show-errors && \
  COMMON_SUBNET_ID=$(az network vnet subnet create --resource-group "${AZ_RG}" \
    --name "${COMMON_SUBNET}" \
    --vnet-name "${COMMON_VNET}" \
    --address-prefixes "${COMMON_SUBNET_ADDRESS_PREFIX}" \
    --query "id" --output tsv --only-show-errors) && \
  SPOKE_SUBNET_ID=$(az network vnet subnet create --resource-group "${AZ_RG}" \
    --name "${SPOKE_SUBNET_NAME}" \
    --vnet-name "${COMMON_VNET}" \
    --address-prefixes "${SPOKE_SUBNET_PREFIX}" \
    --query "id" --output tsv --only-show-errors) && \
  HUB_SUBNET_ID=$(az network vnet subnet create --resource-group "${AZ_RG}" \
    --name "${HUB_SUBNET_NAME}" \
    --vnet-name "${COMMON_VNET}" \
    --address-prefixes "${HUB_SUBNET_PREFIX}" \
    --query "id" --output tsv --only-show-errors) && \
  K8S_CLUSTER_SUBNET_ID=$(az network vnet subnet create \
    --resource-group "${AZ_RG}" \
    --name "${K8S_CLUSTER_SUBNET_NAME}" \
    --vnet-name "${COMMON_VNET}" \
    --address-prefixes "${K8S_CLUSTER_SUBNET_PREFIX}" \
    --query "id" --output tsv --only-show-errors)
#  K8S_SERVICE_SUBNET_ID=$(az network vnet subnet create \
#    --resource-group "${AZ_RG}" \
#    --name "${K8S_SERVICE_SUBNET_NAME}" \
#    --vnet-name "${COMMON_VNET}" \
#    --address-prefixes "${K8S_SERVICE_SUBNET_PREFIX}" \
#    --query "id" --output tsv --only-show-errors)
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step2() {
  doing "- ${FUNCNAME[0]} Network Security Groups"
  local RETVAL=0
  COMMON_NSG_ID=$(az network nsg create --resource-group "${AZ_RG}" \
   --name "${COMMON_NSG_NAME}" \
   --location "${AZ_REGION}" \
   --query "NewNSG.id" --output tsv --only-show-errors) && \
  K8S_NSG_ID=$(az network nsg create --resource-group "${AZ_RG}" \
    --name "${K8S_NSG_NAME}" \
   --location "${AZ_REGION}" \
   --tags "${PRODUCT,,}${PRODUCT_VERSION,,}" \
   --query "NewNSG.id" --output tsv --only-show-errors) && \
  HUB_NSG_ID=$(az network nsg create --resource-group "${AZ_RG}" \
    --name "${HUB_NSG_NAME}" \
   --location "${AZ_REGION}" \
   --tags "${PRODUCT,,}${PRODUCT_VERSION,,}" \
   --query "NewNSG.id" --output tsv --only-show-errors) && \
  SPOKE_NSD_ID=$(az network nsg create --resource-group "${AZ_RG}" \
   --name "${SPOKE_NSG_NAME}" \
   --location "${AZ_REGION}" \
   --query "NewNSG.id" --output tsv --only-show-errors) && \
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step3() {
  doing "- ${FUNCNAME[0]} Network Interfaces"
  local RETVAL=0
  az network nic create --resource-group "${AZ_RG}" \
    --name "${BASTION_NIC_ETH0}" \
    --subnet "${BASTION_SUBNET_NAME}" \
    --location "${AZ_REGION}" \
    --vnet-name "${COMMON_VNET}" \
    --network-security-group "${BASTION_NSG_NAME}" \
    --private-ip-address-version "${IP_VERSION}" \
    --ip-forwarding true \
    --output none \
    --only-show-errors && \
  az network nic create --resource-group "${AZ_RG}" \
    --name "${SPOKE_NIC_ETH0}" \
    --subnet "${COMMON_SUBNET}" \
    --location "${AZ_REGION}" \
    --vnet-name "${COMMON_VNET}" \
    --network-security-group "${COMMON_NSG_NAME}" \
    --private-ip-address-version "${IP_VERSION}" \
    --ip-forwarding true \
    --output none \
    --only-show-errors && \
  az network nic create --resource-group "${AZ_RG}" \
    --name "${SPOKE_NIC_ETH1}" \
    --subnet "${SPOKE_SUBNET_NAME}" \
    --location "${AZ_REGION}" \
    --vnet-name "${COMMON_VNET}" \
    --network-security-group "${SPOKE_NSG_NAME}" \
    --private-ip-address-version "${IP_VERSION}" \
    --ip-forwarding true \
    --output none \
    --only-show-errors && \
  az network nic create --resource-group "${AZ_RG}" \
    --name "${HUB_NIC_ETH0}" \
    --subnet "${COMMON_SUBNET}" \
    --location "${AZ_REGION}" \
    --vnet-name "${COMMON_VNET}" \
    --network-security-group "${COMMON_NSG_NAME}" \
    --private-ip-address-version "${IP_VERSION}" \
    --ip-forwarding true \
    --output none \
    --only-show-errors && \
  az network nic create --resource-group "${AZ_RG}" \
    --name "${HUB_NIC_ETH1}" \
    --subnet "${K8S_CLUSTER_SUBNET_NAME}" \
    --location "${AZ_REGION}" \
    --vnet-name "${COMMON_VNET}" \
    --network-security-group "${COMMON_NSG_NAME}" \
    --private-ip-address-version "${IP_VERSION}" \
    --ip-forwarding true \
    --output none \
    --only-show-errors && \
  az network nic create --resource-group "${AZ_RG}" \
    --name "${HUB_NIC_ETH2}" \
    --subnet "${HUB_SUBNET_NAME}" \
    --location "${AZ_REGION}" \
    --vnet-name "${COMMON_VNET}" \
    --network-security-group "${HUB_NSG_NAME}" \
    --private-ip-address-version "${IP_VERSION}" \
    --ip-forwarding true \
    --output none \
    --only-show-errors && \
  az network nic create --resource-group "${AZ_RG}" \
    --name "${RMD_NIC_ETH0}" \
    --subnet "${SPOKE_SUBNET_NAME}" \
    --location "${AZ_REGION}" \
    --vnet-name "${COMMON_VNET}" \
    --network-security-group "${SPOKE_NSG_NAME}" \
    --private-ip-address-version "${IP_VERSION}" \
    --ip-forwarding true \
    --output none \
    --only-show-errors && \
  az network nic create --resource-group "${AZ_RG}" \
    --name "${POLT_NIC_ETH0}" \
    --subnet "${SPOKE_SUBNET_NAME}" \
    --location "${AZ_REGION}" \
    --vnet-name "${COMMON_VNET}" \
    --network-security-group "${SPOKE_NSG_NAME}" \
    --private-ip-address-version "${IP_VERSION}" \
    --ip-forwarding true \
    --output none \
    --only-show-errors && \
  az network nic create --resource-group "${AZ_RG}" \
    --name "${XXXX_NIC_ETH0}" \
    --subnet "${K8S_CLUSTER_SUBNET_NAME}" \
    --location "${AZ_REGION}" \
    --vnet-name "${COMMON_VNET}" \
    --network-security-group "${XXXX_NSG_NAME}" \
    --private-ip-address-version "${IP_VERSION}" \
    --ip-forwarding true \
    --output none \
    --only-show-errors && \
  az network nic create --resource-group "${AZ_RG}" \
    --name "${XXXX_NIC_ETH1}" \
    --subnet "${HUB_SUBNET_NAME}" \
    --location "${AZ_REGION}" \
    --vnet-name "${COMMON_VNET}" \
    --network-security-group "${HUB_NSG_NAME}" \
    --private-ip-address-version "${IP_VERSION}" \
    --ip-forwarding true \
    --output none \
    --only-show-errors
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step4() {
  doing "- ${FUNCNAME[0]} IP Addressing/Network Assignment"
  local RETVAL=0
  local BASTION_DNS_PREFIX=""
  local XXXX_DNS_PREFIX=""
  generate_dns_prefix BASTION_DNS_PREFIX 16
  az network public-ip create \
   --name "${BASTION_VM_NAME}" \
   --resource-group "${AZ_RG}" \
   --location "${AZ_REGION}" \
   --sku "${IP_SKU}" \
   --version "${IP_VERSION}" \
   --dns-name "${BASTION_DNS_PREFIX}" \
   --output none \
   --only-show-errors && \
  generate_dns_prefix XXXX_DNS_PREFIX 16
  az network public-ip create \
   --name "${XXXX_VM_NAME}" \
   --resource-group "${AZ_RG}" \
   --location "${AZ_REGION}" \
   --sku "${IP_SKU}" \
   --version "${IP_VERSION}" \
   --dns-name "${XXXX_DNS_PREFIX}" \
   --output none \
   --only-show-errors && \
  az network nic ip-config update \
   --name ipconfig1 \
   --resource-group "${AZ_RG}" \
   --nic-name "${BASTION_NIC_ETH0}" \
   --public-ip-address "${BASTION_VM_NAME}" \
   --private-ip-address "${BASTION_NIC_ETH0_PRIVATE_IP}" \
   --output none \
   --only-show-errors && \
  az network nic ip-config update \
   --name ipconfig1 \
   --resource-group "${AZ_RG}" \
   --nic-name "${SPOKE_NIC_ETH0}" \
   --private-ip-address "${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --output none \
   --only-show-errors && \
  az network nic ip-config update \
   --name ipconfig1 \
   --resource-group "${AZ_RG}" \
   --nic-name "${SPOKE_NIC_ETH1}" \
   --private-ip-address "${SPOKE_NIC_ETH1_PRIVATE_IP}" \
   --output none \
   --only-show-errors && \
  az network nic ip-config update \
   --name ipconfig1 \
   --resource-group "${AZ_RG}" \
   --nic-name "${HUB_NIC_ETH0}" \
   --private-ip-address "${HUB_NIC_ETH0_PRIVATE_IP}" \
   --output none \
   --only-show-errors && \
  az network nic ip-config update \
   --name ipconfig1 \
   --resource-group "${AZ_RG}" \
   --nic-name "${HUB_NIC_ETH1}" \
   --private-ip-address "${HUB_NIC_ETH1_PRIVATE_IP}" \
   --output none \
   --only-show-errors && \
  az network nic ip-config update \
   --name ipconfig1 \
   --resource-group "${AZ_RG}" \
   --nic-name "${HUB_NIC_ETH2}" \
   --private-ip-address "${HUB_NIC_ETH2_PRIVATE_IP}" \
   --output none \
   --only-show-errors && \
  az network nic ip-config update \
   --name ipconfig1 \
   --resource-group "${AZ_RG}" \
   --nic-name "${RMD_NIC_ETH0}" \
   --private-ip-address "${RMD_NIC_ETH0_PRIVATE_IP}" \
   --output none \
   --only-show-errors && \
  az network nic ip-config update \
   --name ipconfig1 \
   --resource-group "${AZ_RG}" \
   --nic-name "${POLT_NIC_ETH0}" \
   --private-ip-address "${POLT_NIC_ETH0_PRIVATE_IP}" \
   --output none \
   --only-show-errors && \
  az network nic ip-config update \
   --name ipconfig1 \
   --resource-group "${AZ_RG}" \
   --nic-name "${XXXX_NIC_ETH0}" \
   --public-ip-address "${XXXX_VM_NAME}" \
   --private-ip-address "${XXXX_NIC_ETH0_PRIVATE_IP}" \
   --output none \
   --only-show-errors && \
  az network nic ip-config update \
   --name ipconfig1 \
   --resource-group "${AZ_RG}" \
   --nic-name "${XXXX_NIC_ETH1}" \
   --private-ip-address "${XXXX_NIC_ETH1_PRIVATE_IP}" \
   --output none \
   --only-show-errors
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step5() {
  doing "- ${FUNCNAME[0]} Network Security Groups Rules"
  local RETVAL=0
  local PRIORITY=0
  # internal subnet to same subnet
  get_next_nsg_priority "${HUB_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${HUB_NSG_NAME}" \
   --name "intra-${HUB_SUBNET_NAME}" \
   --priority ${PRIORITY} \
   --direction "Inbound" \
   --source-address-prefixes "${HUB_SUBNET_PREFIX}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${HUB_SUBNET_PREFIX}" \
   --destination-port-ranges '*' \
   --protocol '*' \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  get_next_nsg_priority "${SPOKE_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${SPOKE_NSG_NAME}" \
   --name "intra-${SPOKE_SUBNET_NAME}" \
   --priority ${PRIORITY} \
   --direction "Inbound" \
   --source-address-prefixes "${SPOKE_SUBNET_PREFIX}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${SPOKE_SUBNET_PREFIX}" \
   --destination-port-ranges '*' \
   --protocol '*' \
   --output none \
   --access "Allow" \
   --only-show-errors && \
   
  # hub/spoke to k8s cluster subnet
  get_next_nsg_priority "${K8S_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${K8S_NSG_NAME}" \
   --name "${HUB_SUBNET_NAME}-${K8S_CLUSTER_SUBNET_NAME}" \
   --priority ${PRIORITY} \
   --direction "Inbound" \
   --source-address-prefixes "${HUB_SUBNET_PREFIX}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${K8S_CLUSTER_SUBNET_PREFIX}" \
   --destination-port-ranges '*' \
   --protocol '*' \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  get_next_nsg_priority "${K8S_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${K8S_NSG_NAME}" \
   --name "${SPOKE_SUBNET_NAME}-${K8S_CLUSTER_SUBNET_NAME}" \
   --priority ${PRIORITY} \
   --direction "Inbound" \
   --source-address-prefixes "${SPOKE_SUBNET_PREFIX}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${K8S_CLUSTER_SUBNET_PREFIX}" \
   --destination-port-ranges '*' \
   --protocol '*' \
   --access "Allow" \
   --output none \
   --only-show-errors && \

  # k8s cluster subnet to hub/spoke
  get_next_nsg_priority "${K8S_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${HUB_NSG_NAME}" \
   --name "${K8S_CLUSTER_SUBNET_NAME}-${HUB_SUBNET_NAME}" \
   --priority ${PRIORITY} \
   --direction "Inbound" \
   --source-address-prefixes "${K8S_CLUSTER_SUBNET_PREFIX}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${HUB_SUBNET_PREFIX}" \
   --destination-port-ranges '*' \
   --protocol '*' \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  get_next_nsg_priority "${K8S_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${SPOKE_NSG_NAME}" \
   --name "${K8S_CLUSTER_SUBNET_NAME}-${SPOKE_SUBNET_NAME}" \
   --priority ${PRIORITY} \
   --direction "Inbound" \
   --source-address-prefixes "${K8S_CLUSTER_SUBNET_PREFIX}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${SPOKE_SUBNET_PREFIX}" \
   --destination-port-ranges '*' \
   --protocol '*' \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  get_next_nsg_priority "${K8S_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${K8S_NSG_NAME}" \
   --name "Ssh-${XXXX_VM_NAME}-${XXXX_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${XXXX_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges ${SSH_PORT} \
   --protocol "Tcp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \
   
  # SSH real Internet to Bastion
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
  
  get_next_nsg_priority "${HUB_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${HUB_NSG_NAME}" \
   --name "Ssh-${BASTION_VM_NAME}-${BASTION_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${BASTION_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges ${SSH_PORT} \
   --protocol "Tcp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \
   
  # SSH across common subnet   
  get_next_nsg_priority "${COMMON_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${COMMON_NSG_NAME}" \
   --name "Ssh-${SPOKE_NIC_ETH0_PRIVATE_IP}-${HUB_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes "${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${HUB_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges ${SSH_PORT} \
   --protocol "Tcp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  get_next_nsg_priority "${COMMON_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${COMMON_NSG_NAME}" \
   --name "Ssh-${HUB_NIC_ETH0_PRIVATE_IP}-${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes "${HUB_NIC_ETH0_PRIVATE_IP}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges ${SSH_PORT} \
   --protocol "Tcp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \
   
  # Ping across common subnet
  get_next_nsg_priority "${COMMON_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${COMMON_NSG_NAME}" \
   --name "IcmpPing-${SPOKE_NIC_ETH0_PRIVATE_IP}-${HUB_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes "${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${HUB_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges ${SSH_PORT} \
   --protocol "Icmp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  get_next_nsg_priority "${COMMON_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${COMMON_NSG_NAME}" \
   --name "IcmpPing-${HUB_NIC_ETH0_PRIVATE_IP}-${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes "${HUB_NIC_ETH0_PRIVATE_IP}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges ${SSH_PORT} \
   --protocol "Icmp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \

  # DHCP Client for CloudInit is backup in case CloudInit fails (apparently)
  
  # DHCP Client for Hub CloudInit
  get_next_nsg_priority "${COMMON_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${COMMON_NSG_NAME}" \
   --name "DhcpClient-${HUB_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${HUB_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges "67-68" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  get_next_nsg_priority "${K8S_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${K8S_NSG_NAME}" \
   --name "DhcpClient-${HUB_NIC_ETH1_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${HUB_NIC_ETH1_PRIVATE_IP}" \
   --destination-port-ranges "67-68" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  get_next_nsg_priority "${K8S_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${K8S_NSG_NAME}" \
   --name "DhcpClient-${XXXX_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${XXXX_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges "67-68" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  get_next_nsg_priority "${HUB_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${HUB_NSG_NAME}" \
   --name "DhcpClient-${HUB_NIC_ETH2_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${HUB_NIC_ETH2_PRIVATE_IP}" \
   --destination-port-ranges "67-68" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  get_next_nsg_priority "${K8S_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${XXXX_NSG_NAME}" \
   --name "DhcpClient-${XXXX_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${XXXX_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges "67-68" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \

  # DHCP Client for Spoke CloudInit
  get_next_nsg_priority "${COMMON_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${COMMON_NSG_NAME}" \
   --name "DhcpClient-${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges "67-68" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  get_next_nsg_priority "${SPOKE_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${SPOKE_NSG_NAME}" \
   --name "DhcpClient-${SPOKE_NIC_ETH1_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${SPOKE_NIC_ETH1_PRIVATE_IP}" \
   --destination-port-ranges "67-68" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \

  # DHCP Client for Bastion CloudInit
  get_next_nsg_priority "${HUB_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${HUB_NSG_NAME}" \
   --name "DhcpClient-${BASTION_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${BASTION_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges "67-68" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \

  # DHCP Client for RMD CloudInit
  get_next_nsg_priority "${SPOKE_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${SPOKE_NSG_NAME}" \
   --name "DhcpClient-${RMD_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${RMD_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges "67-68" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \

  # DHCP Client for POLT CloudInit
  get_next_nsg_priority "${SPOKE_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${SPOKE_NSG_NAME}" \
   --name "DhcpClient-${POLT_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes '*' \
   --source-port-ranges '*' \
   --destination-address-prefixes "${POLT_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges "67-68" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \

  # IPsec VPN across common subnet Hub/Spoke (initiat bothways)
  get_next_nsg_priority "${COMMON_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${COMMON_NSG_NAME}" \
   --name "HubSpokeIsakmp-${SPOKE_NIC_ETH0_PRIVATE_IP}-${HUB_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes "${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${HUB_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges "500" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  get_next_nsg_priority "${COMMON_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${COMMON_NSG_NAME}" \
   --name "HubSpokeIsakmp-${HUB_NIC_ETH0_PRIVATE_IP}-${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes "${HUB_NIC_ETH0_PRIVATE_IP}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges "500" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  get_next_nsg_priority "${COMMON_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${COMMON_NSG_NAME}" \
   --name "HubSpokeIpsecNatT-${SPOKE_NIC_ETH0_PRIVATE_IP}-${HUB_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes "${HUB_NIC_ETH0_PRIVATE_IP}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges "4500" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  get_next_nsg_priority "${COMMON_NSG_NAME}" PRIORITY && \
  az network nsg rule create --resource-group "${AZ_RG}" \
   --nsg-name "${COMMON_NSG_NAME}" \
   --name "HubSpokeIpsecNatT-${HUB_NIC_ETH0_PRIVATE_IP}-${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --direction "Inbound" \
   --priority ${PRIORITY} \
   --source-address-prefixes "${SPOKE_NIC_ETH0_PRIVATE_IP}" \
   --source-port-ranges '*' \
   --destination-address-prefixes "${HUB_NIC_ETH0_PRIVATE_IP}" \
   --destination-port-ranges "4500" \
   --protocol "Udp" \
   --access "Allow" \
   --output none \
   --only-show-errors && \
  # HTTPS real Internet to CSDM VM
  for ((I = 0; I < ${#PERMITTED_WAN_IP[@]}; ++I)); do
	  get_next_nsg_priority "${XXXX_NSG_NAME}" PRIORITY && \
	  az network nsg rule create --resource-group "${AZ_RG}" \
	   --nsg-name "${XXXX_NSG_NAME}" \
	   --name "Public-Https-${XXXX_VM_NAME}-${PERMITTED_WAN_IP[$I]}-${XXXX_NIC_ETH0_PRIVATE_IP}" \
	   --direction "Inbound" \
	   --priority ${PRIORITY} \
	   --source-address-prefixes "${PERMITTED_WAN_IP[$I]}" \
	   --source-port-ranges '*' \
	   --destination-address-prefixes "${XXXX_NIC_ETH0_PRIVATE_IP}" \
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

step6() {
  doing "- ${FUNCNAME[0]} Private DNS & A/PTR Records"
  local RETVAL=0
  local PTR_IP=""
  az network private-dns zone create --resource-group "${AZ_RG}" \
    --name "${PRIVATE_DNS_ZONE_NAME,,}" \
	--output none \
	--only-show-errors && \
  az network private-dns link vnet create --resource-group "${AZ_RG}" \
    --name "${PRIVATE_DNS_LINK_NAME}" \
	--zone-name "${PRIVATE_DNS_ZONE_NAME,,}" \
	--virtual-network "${COMMON_VNET}" \
	--registration-enabled false \
	--output none \
	--only-show-errors && \
  dns_a_to_ptr "${RMD_NIC_ETH0_PRIVATE_IP}" PTR_IP
  az network private-dns record-set a add-record \
    --resource-group "${AZ_RG}" \
    --zone-name "${PRIVATE_DNS_ZONE_NAME,,}" \
	--record-set-name "${RMD_VM_NAME,,}" \
	--ipv4-address "${RMD_NIC_ETH0_PRIVATE_IP}" \
	--output none \
	--only-show-errors && \
  az network private-dns record-set ptr add-record \
    --resource-group "${AZ_RG}" \
	--ptrdname "${PRIVATE_DNS_ZONE_NAME,,}" \
	--record-set-name "${PTR_IP}.in-addr.arpa" \
    --zone-name "${PRIVATE_DNS_ZONE_NAME,,}" \
	--output none \
	--only-show-errors && \
  dns_a_to_ptr "${POLT_NIC_ETH0_PRIVATE_IP}" PTR_IP
  az network private-dns record-set a add-record \
    --resource-group "${AZ_RG}" \
    --zone-name "${PRIVATE_DNS_ZONE_NAME,,}" \
	--record-set-name "${POLT_VM_NAME,,}" \
	--ipv4-address "${POLT_NIC_ETH0_PRIVATE_IP}" \
	--output none \
	--only-show-errors && \
  az network private-dns record-set ptr add-record \
    --resource-group "${AZ_RG}" \
	--ptrdname "${PRIVATE_DNS_ZONE_NAME,,}" \
	--record-set-name "${PTR_IP}" \
    --zone-name "${PRIVATE_DNS_ZONE_NAME,,}" \
	--output none \
	--only-show-errors
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step7() {
  doing "- ${FUNCNAME[0]} Host Based Encryption"
  local RETVAL=0
  local AZ_FEATURE_HOST_BASED_ENCRYPTION_STATUS=""

  AZ_FEATURE_HOST_BASED_ENCRYPTION_STATUS=$(az feature list -o tsv --query "[?contains(name, 'Microsoft.Compute/EncryptionAtHost')].{State:properties.state}" --only-show-errors)
  if [ "${AZ_FEATURE_HOST_BASED_ENCRYPTION_STATUS,,}" != "registered" ] ; then
    az feature register --name EncryptionAtHost --namespace Microsoft.Compute --output none --only-show-errors
    RETVAL=$?
    if [ ${RETVAL} -eq 0 ] ; then
      doing "- waiting for Host-based encryption to enable"
      until [[ $(az feature list -o tsv --query "[?contains(name, 'Microsoft.Compute/EncryptionAtHost')].{State:properties.state}" --only-show-errors) == "Registered" ]] ; do
      sleep ${WAIT_SLEEP_SECONDS}
      done
    fi
  fi
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
step7
RETVAL=$?
[[ ${RETVAL} -eq 0 ]] && success "- completed" || error "- fail"
[[ ! ${NOLOGOUT} -eq 0 ]] && logout_az
clean_tmp_files
exit ${RETVAL}
