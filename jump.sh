#!/bin/bash
source config.sh
source common.sh

  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  #[[ -z "${NFS_NIC_ETH0_FQDN}" ]] && NFS_NIC_ETH0_FQDN=$(az vm show --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --show-details --query "fqdns" -o tsv --only-show-errors)
  [[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  echo "ssh -A -o \"StrictHostKeyChecking=no\" -o \"ServerAliveInterval=60\" -i ${SSH_KEY_PRIVATE} -p ${SSH_PORT} -J ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${SSH_PORT},${VPN_OS_USERNAME}@${HUB_NIC_ETH0_PRIVATE_IP}:${SSH_PORT} -L 8443:${CSDM_NIC_ETH0_PRIVATE_IP}:443 ${CSDM_OS_USERNAME}@${CSDM_NIC_ETH1_PRIVATE_IP}"
  echo "https://127.0.0.1:8443/"