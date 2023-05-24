#!/bin/bash
source config.sh
source common.sh
alert "Azure Kubernetes Cluster (AKS)"

### Reference https://learn.microsoft.com/en-us/azure/aks/concepts-clusters-workloads

function drag_from_nfs() {
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  [[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  ssh -A \
      -o "StrictHostKeyChecking=no" \
      -i ${SSH_KEY_PRIVATE} \
      -p ${SSH_PORT} ${3} \
      ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP} \
      "scp -o \"StrictHostKeyChecking=no\" -P ${SSH_PORT} ${NFS_OS_USERNAME}@${NFS_NIC_ETH0_PUBLIC_IP}:${1} ${2}" # &> /dev/null
  return $?
}

function bastion_remote_cli() {
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
   ssh -A \
     -o "StrictHostKeyChecking=no" \
     -o "ServerAliveInterval=60" \
     -i ${SSH_KEY_PRIVATE} \
     -p ${SSH_PORT} \
     ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP} ${2} \
     "${1}" #&> /dev/null
  return $?
}

function push_to_bastion() {
  [[ -z "${BASTION_NIC_ETH0_PUBLIC_IP}" ]] && BASTION_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${AZ_RG}" --name "${BASTION_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  scp -A -o "StrictHostKeyChecking=no" \
      -o "ServerAliveInterval=60" \
      -i ${SSH_KEY_PRIVATE} \
      -P ${SSH_PORT} ${3} \
      ${1} \
      ${BASTION_OS_USERNAME}@${BASTION_NIC_ETH0_PUBLIC_IP}:${2} #&> /dev/null
  return $?
}

step1() {
  doing "- ${FUNCNAME[0]}"
  local RETVAL=0
  local PRIORITY=0
  generate_dns_prefix AZ_AKS_DNS_PREFIX 8
  [[ -z "${K8S_CLUSTER_SUBNET_ID}" ]] && K8S_CLUSTER_SUBNET_ID=$(az network vnet subnet show --resource-group "${AZ_RG}" --vnet-name "${COMMON_VNET}" --name "${K8S_CLUSTER_SUBNET_NAME}" --query "id" -o tsv --only-show-errors)
#  [[ -z "${K8S_SERVICE_SUBNET_ID}" ]] && K8S_SERVICE_SUBNET_ID=$(az network vnet subnet show --resource-group "${AZ_RG}" --vnet-name "${COMMON_VNET}" --name "${K8S_SERVICE_SUBNET_NAME}" --query "id" -o tsv --only-show-errors)
  az aks create \
    --resource-group "${AZ_RG}" \
    --name "${AZ_AKS_CLUSTER}" \
    --kubernetes-version "${AZ_AKS_REQUIRED_VERSION}" \
    -s "${AZ_AKS_INF_NODE_TYPE}" \
    --node-osdisk-type "${AZ_AKS_NODE_DISK_TYPE}" \
    --node-osdisk-size "${AZ_AKS_NODE_OS_DISK_SIZE}" \
    --node-count "${AZ_AKS_CLUSTER_NODES}" \
    --load-balancer-sku "${AZ_AKS_NODE_LB_SKU}" \
    --load-balancer-idle-timeout 4 \
    --load-balancer-managed-outbound-ip-count ${AZ_AKS_CLUSTER_NODES} \
    --outbound-type "loadBalancer" \
    --network-plugin "${AZ_AKS_NETWORK_PLUGIN}" \
    --service-cidr "10.0.0.0/16" \
    --docker-bridge-address "172.17.0.1/16" \
    --dns-service-ip "10.0.0.16" \
    --dns-name-prefix "${AZ_AKS_DNS_PREFIX}" \
    --nodepool-name "${AZ_AKS_CLUSTER_POOL}" \
    --admin-username "${AZ_AKS_CLUSTER_ADMIN_USERNAME,,}" \
    --attach-acr "${AZ_ACR_NAME}" \
    --ssh-key-value "${SSH_KEY_PUBLIC_VALUE}" \
    --zones ${AZ_ZONES} \
    --dns-name-prefix "${AZ_AKS_DNS_PREFIX}" \
    --enable-encryption-at-host \
    --vnet-subnet-id "${K8S_CLUSTER_SUBNET_ID}" \
   --output none \
   --only-show-errors && \
  az aks get-credentials --name "${AZ_AKS_CLUSTER}" \
    --overwrite-existing \
	--resource-group "${AZ_RG}" \
	--admin \
	--output none \
	--only-show-errors
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step2() {
  doing "- ${FUNCNAME[0]}"
  local RETVAL=0
  local K8S_AD_SP_ID=""
  [[ -z "${AZ_ACR_ID}" ]] && AZ_ACR_ID=$(az acr show --resource-group "${AZ_RG}" --name "${AZ_ACR_NAME}" --query "id" --output tsv --only-show-errors)
  [[ -z "${AZ_ACR_USERNAME}" ]] && AZ_ACR_USERNAME=$(az acr credential show --resource-group "${AZ_RG}" --name "${AZ_ACR_NAME}" --query "username" --output tsv)
  [[ -z "${AZ_ACR_PASSWORD}" ]] && AZ_ACR_PASSWORD=$(az acr credential show --resource-group "${AZ_RG}" --name "${AZ_ACR_NAME}" --query "passwords[0].value" --output tsv)
  [[ -z "${K8S_AD_SP_ID}" ]] && K8S_AD_SP_ID=$(az ad sp list --filter "displayName eq '${AZ_AKS_CLUSTER}'" --query "[].id" -o tsv)
  [[ -z "${K8S_CLUSTER_SUBNET_ID}" ]] && K8S_CLUSTER_SUBNET_ID=$(az network vnet subnet show --resource-group "${AZ_RG}" --vnet-name "${COMMON_VNET}" --name "${K8S_CLUSTER_SUBNET_NAME}" --query id -o tsv )
  [[ -z "${AZ_ACR_LOGIN_IP}" ]] && AZ_ACR_LOGIN_IP=$(getent ahostsv4 ${AZ_ACR_LOGIN_URL}|head -1|awk '{print $1}')

  az aks update --resource-group "${AZ_RG}" \
    --name "${AZ_AKS_CLUSTER}" \
    --attach-acr "${AZ_ACR_NAME}" \
	--output none \
	--only-show-errors && \

  # required for load-balancer creation step8 and step9
  #az role assignment create \
  #--assignee "${K8S_AD_SP_ID}" \
  #--role "Network Contributor" \
  #--scope "${K8S_CLUSTER_SUBNET_ID}" && \

  # permit aks to pull from acr via service principal
  az role assignment create \
  --assignee "${AZ_SP_APPID}" \
  --role "acrpull" \
  --scope "${AZ_ACR_ID}" \
  --output none \
  --only-show-errors && \
  bastion_remote_cli "docker logout ${AZ_ACR_LOGIN_URL} &> /dev/null 2>&1 ; exit 0" && \
  bastion_remote_cli "az logout &> /dev/null 2>&1 ; exit 0" && \
  bastion_remote_cli "rm -R -f ~/.kube ~/.azure .cache/helm/repository &> /dev/null 2>&1 ; exit 0" && \
  bastion_remote_cli "az login --service-principal -u \"${AZ_SP_APPID}\" -p \"${AZ_SP_PASSWORD}\" --tenant \"${AZ_SP_TENANT}\"" && \
  bastion_remote_cli "az aks get-credentials --name \"${AZ_AKS_CLUSTER}\" --overwrite-existing --resource-group \"${AZ_RG}\" --admin --output none --only-show-errors" && \
  bastion_remote_cli "docker login ${AZ_ACR_LOGIN_URL} --username ${AZ_SP_APPID} --password ${AZ_SP_PASSWORD} &>/dev/null 2>&1" && \
  bastion_remote_cli "kubectl create secret docker-registry acr-secret --docker-server=\"${AZ_ACR_LOGIN_URL}\" --docker-username=\"${AZ_ACR_USERNAME}\" --docker-password=\"${AZ_ACR_PASSWORD}\" &>/dev/null" && \
  bastion_remote_cli "kubectl patch serviceaccount default -p '{\"imagePullSecrets\": [{\"name\": \"acr-secret\"}]}' &>/dev/null "
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step3() {
  doing "- ${FUNCNAME[0]} ${AZ_AKS_DM_POOL} node pool"
  local RETVAL=0
  [[ -z "${K8S_CLUSTER_SUBNET_ID}" ]] && K8S_CLUSTER_SUBNET_ID=$(az network vnet subnet show --resource-group "${AZ_RG}" --vnet-name "${COMMON_VNET}" --name "${K8S_CLUSTER_SUBNET_NAME}" --query "id" -o tsv --only-show-errors)
  az aks nodepool add --cluster-name "${AZ_AKS_CLUSTER}" \
    --name "${AZ_AKS_DM_POOL}" \
    --kubernetes-version "${AZ_AKS_REQUIRED_VERSION}" \
    --node-count "${AZ_AKS_DM_POOL_NODES}" \
    --node-vm-size "${AZ_AKS_DM_NODE_TYPE}" \
    --node-osdisk-size "${AZ_AKS_NODE_OS_DISK_SIZE}" \
    --resource-group "${AZ_RG}" \
    --enable-encryption-at-host \
    --zones ${AZ_ZONES} \
    --vnet-subnet-id "${K8S_CLUSTER_SUBNET_ID}" \
    --output none \
    --only-show-errors
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step4() {
  doing "- ${FUNCNAME[0]}"
  local RETVAL=0
#  bastion_remote_cli "az login --service-principal -u \"${AZ_SP_APPID}\" -p \"${AZ_SP_PASSWORD}\" --tenant \"${AZ_SP_TENANT}\"" && \
#  bastion_remote_cli "az aks get-credentials --name \"${AZ_AKS_CLUSTER}\" --overwrite-existing --resource-group \"${AZ_RG}\" --admin --output none --only-show-errors" && \
#  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}
  
step5() {
  doing "- ${FUNCNAME[0]} - Registry populate (skipping)"
  local RETVAL=0
  return ${RETVAL}
  [[ -z "${AZ_ACR_LOGIN_IP}" ]] && AZ_ACR_LOGIN_IP=$(getent ahostsv4 ${AZ_ACR_LOGIN_URL}|head -1|awk '{print $1}')
  [[ -z "${AZ_ACR_USERNAME}" ]] && AZ_ACR_USERNAME=$(az acr credential show --resource-group "${AZ_RG}" --name "${AZ_ACR_NAME}" --query "username" --output tsv --only-show-errors)
  [[ -z "${AZ_ACR_PASSWORD}" ]] && AZ_ACR_PASSWORD=$(az acr credential show --resource-group "${AZ_RG}" --name "${AZ_ACR_NAME}" --query "passwords[0].value" --output tsv --only-show-errors)
  bastion_remote_cli "az acr login  --name \"${AZ_ACR_NAME}\" --username \"${AZ_ACR_USERNAME}\" --password \"${AZ_ACR_PASSWORD}\" --output none --only-show-errors"
  bastion_remote_cli "cd ~/platform/ansible/install ; tar zxf halo_docker_images-${TAG}.tgz" && \
  bastion_remote_cli "cd ~/platform/ansible/install ; ./install-registry --upload --repo ${AZ_ACR_LOGIN_URL} --nodelete" && \
  bastion_remote_cli "cd ~/platform/ansible/install ; rm -R -f docker_images &> /dev/null"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step6() {
  doing "- ${FUNCNAME[0]}"
  local RETVAL=0
  local SC_TMP=""
  bastion_remote_cli "rm -R -f ~/platform &> /dev/null" && \
  drag_from_nfs "csdm/${RELEASE_ARCHIVE}" "~/${RELEASE_ARCHIVE}" && \
  bastion_remote_cli "tar zxf ~/${RELEASE_ARCHIVE} ; rm -f ~/${RELEASE_ARCHIVE} &> /dev/null" && \
  SC_TMP=$(mktemp -q -p /tmp azure.XXXXXXXX)
  cat <<EOFA > ${SC_TMP}
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${AZ_AKS_DM_SC_RWX_CLASS,,}
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: file.csi.azure.com
parameters:
  skuName: ${AZ_AKS_DM_SC_RWX_SKU}
reclaimPolicy: ${AZ_AKS_DM_SC_RWX_RECLAIM}
volumeBindingMode: Immediate
allowVolumeExpansion: ${AZ_AKS_DM_SC_RWX_AUTO_EXPAND,,}
#mountOptions:
#  - dir_mode=0640
#  - file_mode=0640
#  - uid=0
#  - gid=0
#  - mfsymlinks
#  - cache=strict # https://linux.die.net/man/8/mount.cifs
#  - nosharesock
EOFA
  push_to_bastion "${SC_TMP}" "~/platform/ansible/install/aks-${AZ_AKS_DM_SC_RWX_CLASS,,}.yaml"
  RETVAL=$?
  [[ -f "${SC_TMP}" ]] && rm -f ${SC_TMP} &> /dev/null

  SC_TMP=$(mktemp -q -p /tmp azure.XXXXXXXX)
  cat <<EOFB > ${SC_TMP}
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${AZ_AKS_DM_SC_LOCAL_CLASS,,}
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: file.csi.azure.com
parameters:
  skuName: ${AZ_AKS_DM_SC_LOCAL_SKU}
reclaimPolicy: ${AZ_AKS_DM_SC_LOCAL_RECLAIM}
volumeBindingMode: Immediate
allowVolumeExpansion: ${AZ_AKS_DM_SC_LOCAL_AUTO_EXPAND,,}
#mountOptions:
#  - dir_mode=0640
#  - file_mode=0640
#  - uid=0
#  - gid=0
#  - mfsymlinks
#  - cache=strict # https://linux.die.net/man/8/mount.cifs
#  - nosharesock
EOFB
  push_to_bastion "${SC_TMP}" "~/platform/ansible/install/aks-${AZ_AKS_DM_SC_LOCAL_CLASS,,}.yaml"
  RETVAL=$?
  [[ -f "${SC_TMP}" ]] && rm -f ${SC_TMP} &> /dev/null

  SC_TMP=$(mktemp -q -p /tmp azure.XXXXXXXX)
  cat <<EOFC > ${SC_TMP}
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${AZ_AKS_DM_SC_RWO_CLASS,,}
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: file.csi.azure.com
parameters:
  skuName: ${AZ_AKS_DM_SC_RWO_SKU}
reclaimPolicy: ${AZ_AKS_DM_SC_RWO_RECLAIM}
volumeBindingMode: Immediate
allowVolumeExpansion: ${AZ_AKS_DM_SC_RWO_AUTO_EXPAND,,}
#mountOptions:
#  - dir_mode=0640
#  - file_mode=0640
#  - uid=0
#  - gid=0
#  - mfsymlinks
#  - cache=strict # https://linux.die.net/man/8/mount.cifs
#  - nosharesock
EOFC
  push_to_bastion "${SC_TMP}" "~/platform/ansible/install/aks-${AZ_AKS_DM_SC_RWO_CLASS,,}.yaml"

  # this is not needed but worth storing the keys
  SC_TMP=$(mktemp -q -p /tmp azure.XXXXXXXX)
  cat <<EOFD > ${SC_TMP}
apiVersion: v1
kind: Secret
metadata:
  name: csdm-service-principal
  namespace: csdm
type: Opaque
data:
  tenant: $(echo -n "${AZ_SP_TENANT}"|base64 -w 0)
  username: $(echo -n "${AZ_SP_APPID}"|base64 -w 0)
  password: $(echo -n "${AZ_SP_PASSWORD}"|base64 -w 0)
EOFD
  push_to_bastion "${SC_TMP}" "~/platform/ansible/install/aks-service-principal.yaml"
  RETVAL=$?
  [[ -f "${SC_TMP}" ]] && rm -f ${SC_TMP} &> /dev/null

  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step7() {
  doing "- ${FUNCNAME[0]}"
  local RETVAL=0
  local DEFAULT_NAMESPACE=""
  [[ -z "${AZ_ACR_LOGIN_IP}" ]] && AZ_ACR_LOGIN_IP=$(getent ahostsv4 ${AZ_ACR_LOGIN_URL}|head -1|awk '{print $1}')
  bastion_remote_cli "cd ~/platform/ansible/install ; ./deploy_services.sh -x" && \
  bastion_remote_cli "cd ~/platform/ansible/install ; tar zxf k8s_helm-*.tgz &> /dev/null" && \
  bastion_remote_cli "cd ~/platform/ansible/install/ ; yq -i '.spec.storageClassName = \"${AZ_AKS_DM_SC_RWO_CLASS,,}\"' postgres-singlePVC.yaml"
  bastion_remote_cli "cd ~/platform/ansible/install/ ; yq -i '.spec.storageClassName = \"${AZ_AKS_DM_SC_RWO_CLASS,,}\"' druidSingleNodePVC.yaml"
  bastion_remote_cli "cd ~/platform/ansible/install/ ; yq -i '.spec.storageClassName = \"${AZ_AKS_DM_SC_RWX_CLASS,,}\"' druidMultiNodePVC.yaml"
  bastion_remote_cli "cd ~/platform/ansible/install/ ; yq -i '.spec.storageClassName = \"${AZ_AKS_DM_SC_RWO_CLASS,,}\"' influxPVC.yaml"
  bastion_remote_cli "cd ~/platform/ansible/install/ ; yq -i '.spec.storageClassName = \"${AZ_AKS_DM_SC_RWO_CLASS,,}\"' kafkaPVC.yaml"
  bastion_remote_cli "cd ~/platform/ansible/install/ ; yq -i '.spec.storageClassName = \"${AZ_AKS_DM_SC_RWO_CLASS,,}\"' postgres-singlePVC.yaml"
  bastion_remote_cli "cd ~/platform/ansible/install/ ; yq -i '.spec.storageClassName = \"${AZ_AKS_DM_SC_RWO_CLASS,,}\"' prometheusPVC.yaml"
  bastion_remote_cli "cd ~/platform/ansible/install/ ; yq -i '.spec.storageClassName = \"${AZ_AKS_DM_SC_RWO_CLASS,,}\"' rabbitmqPVC.yaml"
  bastion_remote_cli "cd ~/platform/ansible/install/ ; yq -i '.spec.storageClassName = \"${AZ_AKS_DM_SC_RWO_CLASS,,}\"' redisPVC.yaml"

  # container-registry tweaks - its not used but here for capability purposes
  bastion_remote_cli "kubectl create namespace container-registry"
  bastion_remote_cli "cd ~/platform/ansible/install ; cp -f registryPV_template.yaml registryPVC.yaml &> /dev/null"
  if [[ ${AZ_AKS_DM_POOL_NODES} -eq 1 ]] ; then
    bastion_remote_cli "cd ~/platform/ansible/install/ ; yq -i '.spec.storageClassName = \"${AZ_AKS_DM_SC_RWO_CLASS,,}\"' registryPVC.yaml"
    bastion_remote_cli "cd ~/platform/ansible/install/ ; yq -i '.metadata.labels.type = \"${AZ_AKS_DM_SC_RWO_CLASS,,}\"' registryPVC.yaml"
  else
    bastion_remote_cli "cd ~/platform/ansible/install/ ; yq -i '.spec.storageClassName = \"${AZ_AKS_DM_SC_RWX_CLASS,,}\"' registryPVC.yaml"
    bastion_remote_cli "cd ~/platform/ansible/install/ ; yq -i '.metadata.labels.type = \"${AZ_AKS_DM_SC_RWX_CLASS,,}\"' registryPVC.yaml"
  fi

  if [[ ${AZ_AKS_DM_POOL_NODES} -eq 1 ]] ; then
    bastion_remote_cli "rm -f ~/platform/ansible/install/druidMultiNodePVC.yaml &> /dev/null"
  else
    bastion_remote_cli "rm -f ~/platform/ansible/install/druidSingleNodePVC.yaml &> /dev/null"
  fi
  
  # patch helm image.repository within each component values.yaml
  for ((I = 0; I < ${#PRODUCT_COMPONENTS[@]}; ++I)); do
    bastion_remote_cli "cd ~/platform/ansible/install/helm && gunzip ${PRODUCT_COMPONENTS[$I]}-${TAG}.tgz && tar xf ${PRODUCT_COMPONENTS[$I]}-${TAG}.tar ${PRODUCT_COMPONENTS[$I]}/values.yaml && sed -i \"s|halo-docker-irlbel.lab|${AZ_ACR_LOGIN_URL}|g\" ${PRODUCT_COMPONENTS[$I]}/values.yaml && tar -uf ${PRODUCT_COMPONENTS[$I]}-${TAG}.tar ${PRODUCT_COMPONENTS[$I]}/values.yaml && gzip -c ${PRODUCT_COMPONENTS[$I]}-${TAG}.tar > ${PRODUCT_COMPONENTS[$I]}-${TAG}.tgz && rm -f ${PRODUCT_COMPONENTS[$I]}-${TAG}.tar &> /dev/null && rm -R -f ${PRODUCT_COMPONENTS[$I]} &> /dev/null"
  done
  bastion_remote_cli "cd ~/platform/ansible/install ; ./deploy_applications.sh -x" && \
  bastion_remote_cli "cd ~/platform/ansible/install ; kubectl apply -f csdm-namespace.yaml" && \
  DEFAULT_NAMESPACE=$(bastion_remote_cli "cd ~/platform/ansible/install ; yq \".metadata.name\" < csdm-namespace.yaml") && \
  info "Changing AKS default namespace=${DEFAULT_NAMESPACE}" && \
  bastion_remote_cli "kubectl config set-context --current --namespace=${DEFAULT_NAMESPACE}" && \
  bastion_remote_cli "cd ~/platform/ansible/install ; kubectl apply -f aks-service-principal.yaml && rm -f aks-service-principal.yaml &> /dev/null"
  
  bastion_remote_cli "cd ~/platform/ansible/install/ ; kubectl apply -f ./aks-${AZ_AKS_DM_SC_RWX_CLASS,,}.yaml" && \
  bastion_remote_cli "kubectl patch storageclass ${AZ_AKS_DM_SC_RWX_CLASS,,} -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}' &> /dev/null" && \

  bastion_remote_cli "cd ~/platform/ansible/install/ ; kubectl apply -f ./aks-${AZ_AKS_DM_SC_LOCAL_CLASS,,}.yaml" && \
  bastion_remote_cli "kubectl patch storageclass ${AZ_AKS_DM_SC_LOCAL_CLASS,,} -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}' &> /dev/null" && \

  bastion_remote_cli "cd ~/platform/ansible/install/ ; kubectl apply -f ./aks-${AZ_AKS_DM_SC_RWO_CLASS,,}.yaml" && \
  bastion_remote_cli "kubectl patch storageclass ${AZ_AKS_DM_SC_RWO_CLASS,,} -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}' &> /dev/null" && \

#
#  bastion_remote_cli "kubectl patch storageclass default -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}' &> /dev/null" && \
#  bastion_remote_cli "kubectl delete storageclass default &> /dev/null ; exit 0" && \
#
  
  bastion_remote_cli "cd ~/platform/ansible/install ; find . -mindepth 1 -maxdepth 1 -type f -name \"*PVC.yaml\" -exec kubectl apply -f {} \;"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step8() {
  doing "- ${FUNCNAME[0]}"
  local RETVAL=0
  local AKS_MC_RG=""
  local AKS_PLS_ID=""
  kubectl apply -f - <<EOF8
apiVersion: v1
kind: Service
metadata:
  name: nbi
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-resource-group: ${AZ_RG}
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
    service.beta.kubernetes.io/azure-pls-create: "true"
spec:
  type: LoadBalancer
  loadBalancerIP: ${K8S_NBI_LB_PRIVATE_IP}
  ports:
    - name: ui
      protocol: TCP
      port: ${CSDM_NBI_PORT}
      targetPort: ${CSDM_NBI_PORT}
  selector:
    app: nbi
EOF8
  RETVAL=$?
  wait_for_loadbalancer_external_ip "nbi"
  K8S_NBI_LB_PRIVATE_IP=$(kubectl get service nbi -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  info "NBI Load Balancer IP: ${K8S_NBI_LB_PRIVATE_IP}"
  AKS_MC_RG=$(az aks show --resource-group "${AZ_RG}" --name "${AZ_AKS_CLUSTER}" --query nodeResourceGroup -o tsv --only-show-errors) && \
  wait_for_private_link_service "${AKS_MC_RG}" "${AZ_AKS_CLUSTER}" "nbi" && \
  AKS_PLS_ID=$(az network private-link-service list --resource-group "${AKS_MC_RG}" --query "[-1].id" -o tsv --only-show-errors) && \
  az network private-endpoint create --resource-group "${AZ_RG}" \
    --name "${AZ_AKS_CLUSTER}serviceNBI" \
    --location "${AZ_REGION}" \
    --vnet-name "${COMMON_VNET}" \
    --subnet "${HUB_SUBNET_NAME}" \
    --private-connection-resource-id "${AKS_PLS_ID}" \
    --connection-name "${AZ_AKS_CLUSTER}connect" \
    --output none \
    --only-show-errors
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step9() {
  doing "- ${FUNCNAME[0]}"
  local RETVAL=0
  local AKS_MC_RG=""
  local AKS_PLS_ID=""
  kubectl apply -f - <<EOF9
apiVersion: v1
kind: Service
metadata:
  name: sbi
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-resource-group: ${AZ_RG}
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
    service.beta.kubernetes.io/azure-pls-create: "true"
spec:
  type: LoadBalancer
  loadBalancerIP: ${K8S_SBI_LB_PRIVATE_IP}
  ports:
    - name: netconf-callhome-tls
      protocol: TCP
      port: ${CSDM_SBI_NETCONF_CALLHOME_SSH_PORT}
      targetPort: ${CSDM_SBI_NETCONF_CALLHOME_SSH_PORT}
    - name: netconf-callhome-ssh
      protocol: TCP
      port: ${CSDM_SBI_NETCONF_CALLHOME_TLS_PORT}
      targetPort: ${CSDM_SBI_NETCONF_CALLHOME_TLS_PORT}
    - name: syslog
      protocol: UDP
      port: ${CSDM_SBI_SYSLOG_PORT}
      targetPort: ${CSDM_SBI_SYSLOG_PORT}
    - name: kafka-secure
      protocol: TCP
      port: ${CSDM_SBI_KAFKA_SECURE_PORT}
      targetPort: ${CSDM_SBI_KAFKA_SECURE_PORT}
    - name: kafka-unsecure
      protocol: TCP
      port: ${CSDM_SBI_KAFKA_UNSECURE_PORT}
      targetPort: ${CSDM_SBI_KAFKA_UNSECURE_PORT}
  selector:
    app: sbi
EOF9
  RETVAL=$?
  wait_for_loadbalancer_external_ip "sbi"
  K8S_SBI_LB_PRIVATE_IP=$(kubectl get service sbi -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  info "SBI Load Balancer IP: ${K8S_SBI_LB_PRIVATE_IP}"
  AKS_MC_RG=$(az aks show --resource-group "${AZ_RG}" --name "${AZ_AKS_CLUSTER}" --query nodeResourceGroup -o tsv --only-show-errors) && \
  wait_for_private_link_service "${AKS_MC_RG}" "${AZ_AKS_CLUSTER}" "sbi" && \
  AKS_PLS_ID=$(az network private-link-service list --resource-group "${AKS_MC_RG}" --query "[-1].id" -o tsv --only-show-errors) && \
  az network private-endpoint create --resource-group "${AZ_RG}" \
    --name "${AZ_AKS_CLUSTER}serviceSBI" \
    --location "${AZ_REGION}" \
    --vnet-name "${COMMON_VNET}" \
    --subnet "${HUB_SUBNET_NAME}" \
    --private-connection-resource-id "${AKS_PLS_ID}" \
    --connection-name "${AZ_AKS_CLUSTER}connect" \
    --output none \
    --only-show-errors
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step10() {
  doing "- ${FUNCNAME[0]} - Remote platform_config update"
  local RETVAL=0
  [[ -z "${K8S_CLUSTER_API_FQDN}" ]] && K8S_CLUSTER_API_FQDN=$(az aks show --name k8s --resource-group telco --query "fqdn" -o tsv)
  [[ -z "${K8S_CLUSTER_API_IP}" ]] && K8S_CLUSTER_API_IP=$(getent ahostsv4 ${K8S_CLUSTER_API_FQDN}|head -1|awk '{print $1}')
  #[[ -z "${AZ_AKS_CLUSTER_IP}" ]] && AZ_AKS_CLUSTER_IP=$(kubectl get svc -o "jsonpath={.items[-1].spec.clusterIP}")
  [[ -z "${AZ_ACR_LOGIN_IP}" ]] && AZ_ACR_LOGIN_IP=$(getent ahostsv4 ${AZ_ACR_LOGIN_URL}|head -1|awk '{print $1}')
  [[ -z "${NFS_NIC_ETH0_PUBLIC_IP}" ]] && NFS_NIC_ETH0_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv --only-show-errors|cut -d, -f1)
  [[ -z "${NFS_NIC_ETH0_FQDN}" ]] && NFS_NIC_ETH0_FQDN=$(az vm show --resource-group "${NFS_AZ_RG}" --name "${NFS_VM_NAME}" --show-details --query "fqdns" -o tsv --only-show-errors)
  if [[ -f "${NFS_BACKUP_KEY}" ]] ; then
    bastion_remote_cli "rm -f ~/.ssh/${NFS_BACKUP_KEY} ~/.ssh/${NFS_BACKUP_KEY}.pub &> /dev/null"
    push_to_bastion "${NFS_BACKUP_KEY}" "~/.ssh"
    push_to_bastion "${NFS_BACKUP_KEY}.pub" "~/.ssh"
  fi
  bastion_remote_cli "cp -f ~/platform/ansible/configs/platform-config.yaml.blank_singlehost ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.dmhost_user = \"${CSDM_OS_USERNAME,,}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.dmhost_user = \"${CSDM_OS_USERNAME,,}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.dmhost_group = \"${CSDM_OS_USERNAME,,}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.dmhosts.host1.dmhost_ip = \"${K8S_NBI_LB_PRIVATE_IP}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.number_of_hosts = ${AZ_AKS_DM_POOL_NODES}' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.northbound_vip = \"${K8S_NBI_LB_PRIVATE_IP}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.southbound_vip = \"${K8S_SBI_LB_PRIVATE_IP}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  #bastion_remote_cli "yq -i '.pv_backing_store = \"/backing_store\"' ~/platform/ansible/configs/platform-config.yaml" && \#
  bastion_remote_cli "yq -i '.snap_autoupdate = false' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.prometheus_enable = false' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.disable_unattended_upgrades = true' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.providesupportservices = false' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.rmd_subnets = \"${SPOKE_SUBNET_PREFIX}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.external_pv_rwo = \"${AZ_AKS_DM_SC_RWO_CLASS}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.external_pv_rwx = \"${AZ_AKS_DM_SC_RWX_CLASS}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.k8s_dns_servers = \"${K8S_DNS_SERVERS}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.local_pv = \"${AZ_AKS_DM_SC_LOCAL_CLASS}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.external_backup_host = \"${BASTION_NIC_ETH0_PUBLIC_IP}\"' ~/platform/ansible/configs/platform-config.yaml "&& \
  bastion_remote_cli "yq -i '.external_backup_user = \"${NFS_OS_USERNAME}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.external_backup_dir = \"${NFS_BACKUP_PATH}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.external_backup_key = \"/home/${CSDM_OS_USERNAME}/.ssh/${NFS_BACKUP_KEY}\"' ~/platform/ansible/configs/platform-config.yaml" && \
  bastion_remote_cli "yq -i '.global.extraOpts = \"--wait --timeout=${AZ_HELM_WAIT_TIMEOUT}\"' ~/platform/ansible/install/application_config.yaml"
  bastion_remote_cli "yq -i '.global.extraOpts = \"--wait --timeout=${AZ_HELM_WAIT_TIMEOUT}\"' ~/platform/ansible/install/service_config.yaml"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step11() {
  local RETVAL=0
  local PROMETHEUS_OPEN_PID=0
  local PROMETHEUS_GRAFANA_OPEN_PID=0
  local PROMETHEUS_ALERTMGR_OPEN_PID=0
  local CURL_PROMETHEUS=1
  local CURL_GRAFANA=1
  local CURL_ALERTMGR=1

  #PROMETHEUS_ENABLE=$(lookup_platform_config prometheus_enable)
  if [ "${PROMETHEUS_ENABLE,,}" == "true" ] ; then
    az aks get-credentials --name "${AZ_AKS_CLUSTER}" \
     --overwrite-existing \
     --resource-group "${AZ_RG}" \
     --admin \
     --output none \
     --only-show-errors
    if [ $(kubectl get namespaces -o name|grep -i "${PROMETHEUS_NAMESPACE}"|wc -l) -eq 0 ] ; then
        doing "- installing Prometheus (remote)"
        bastion_remote_cli "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts &> /dev/null"
        bastion_remote_cli "helm repo update &> /dev/null"
        EXISTS=$(kubectl get namespaces|grep "${PROMETHEUS_NAMESPACE}"|wc -l)
        [[ ${EXISTS} -ne 0 ]] && kubectl delete namespace "${PROMETHEUS_NAMESPACE}" &> /dev/null
        bastion_remote_cli "helm install prometheus prometheus-community/kube-prometheus-stack --namespace "${PROMETHEUS_NAMESPACE}" --create-namespace &> /dev/null"
    else
        doing "- Prometheus already installed"
    fi
    doing "- waiting for Prometheus service monitors"
    until [ -n "$(kubectl get servicemonitors --namespace ${PROMETHEUS_NAMESPACE}|grep -vi name)" ] ; do
      xsleep ${WAIT_SLEEP_SECONDS}
    done
    # disable prometheus monitoring of internal as on AKS not visible
    bastion_remote_cli "helm upgrade prometheus &> /dev/null \
    prometheus-community/kube-prometheus-stack --namespace \"${PROMETHEUS_NAMESPACE}\" --set kubeEtcd.enabled=false --set kubeControllerManager.enabled=false --set kubeScheduler.enabled=false &> /dev/null"
    RETVAL=$?

  # prometheus gui tests
    if [ ${RETVAL} -eq 0 ] ; then
      nohup kubectl port-forward --namespace "${PROMETHEUS_NAMESPACE}" svc/prometheus-kube-prometheus-prometheus ${PROMETHEUS_EXTERNAL_PORT} &> /dev/null &
      PROMETHEUS_OPEN_PID=$! && \
      disown ${PROMETHEUS_OPEN_PID}
      RETVAL=$?
      # test
      xsleep ${WAIT_SLEEP_SECONDS} && \
      curl --silent -o /dev/null "http://127.0.0.1:${PROMETHEUS_EXTERNAL_PORT}"
      CURL_PROMETHEUS=$?
      (kill -9 ${PROMETHEUS_OPEN_PID} 2> /dev/null)
      [[ ${CURL_PROMETHEUS} -eq 0 ]] && success "- prometheus GUI ok" || error "- prometheus GUI failed"

        nohup kubectl port-forward --namespace "${PROMETHEUS_NAMESPACE}" svc/prometheus-grafana ${PROMETHEUS_GRAFANA_EXTERNAL_PORT}:${PROMETHEUS_GRAFANA_INTERNAL_PORT} &> /dev/null &
        PROMETHEUS_GRAFANA_OPEN_PID=$! && \
        disown ${PROMETHEUS_GRAFANA_OPEN_PID}
        RETVAL=$?
        # test
        xsleep ${WAIT_SLEEP_SECONDS} && \
        curl --silent -o /dev/null "http://127.0.0.1:${PROMETHEUS_GRAFANA_EXTERNAL_PORT}"
        CURL_GRAFANA=$?
        (kill -9 ${PROMETHEUS_GRAFANA_OPEN_PID} 2> /dev/null)
        [[ ${CURL_GRAFANA} -eq 0 ]] && success "- grafana GUI ok" || error "- grafana GUI failed"

        nohup kubectl port-forward --namespace "${PROMETHEUS_NAMESPACE}" svc/prometheus-kube-prometheus-alertmanager ${PROMETHEUS_ALERTMGR_EXTERNAL_PORT} &> /dev/null &
        PROMETHEUS_ALERTMGR_OPEN_PID=$! && \
        disown ${PROMETHEUS_ALERTMGR_OPEN_PID}
        RETVAL=$?
        # test
        xsleep ${WAIT_SLEEP_SECONDS} && \
        curl --silent -o /dev/null "http://127.0.0.1:${PROMETHEUS_ALERTMGR_EXTERNAL_PORT}"
        CURL_ALERTMGR=$?
        (kill -9 ${PROMETHEUS_ALERTMGR_OPEN_PID} 2> /dev/null)
        [[ ${CURL_ALERTMGR} -eq 0 ]] && success "- alert-manager GUI ok" || error "- alert-manager GUI failed"
    fi
  else
    if [ $(kubectl get namespaces -o name|grep -i "${PROMETHEUS_NAMESPACE}"|wc -l) -gt 0 ] ; then
      helm uninstall prometheus --namespace "${PROMETHEUS_NAMESPACE}" &> /dev/null
      kubectl delete namespace "${PROMETHEUS_NAMESPACE}" &> /dev/null
      RETVAL=$?
    else
      RETVAL=0
    fi
  fi
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step12() {
  doing "- ${FUNCNAME[0]} - Services"
  local RETVAL=0
  local RECIPE=""
  [[ -z "${K8S_CLUSTER_API_FQDN}" ]] && K8S_CLUSTER_API_FQDN=$(az aks show --name k8s --resource-group telco --query "fqdn" -o tsv)
  [[ -z "${K8S_CLUSTER_API_IP}" ]] && K8S_CLUSTER_API_IP=$(getent ahostsv4 ${K8S_CLUSTER_API_FQDN}|head -1|awk '{print $1}')
  [[ -z "${AZ_ACR_LOGIN_IP}" ]] && AZ_ACR_LOGIN_IP=$(getent ahostsv4 ${AZ_ACR_LOGIN_URL}|head -1|awk '{print $1}')
  if [[ ${AZ_AKS_DM_POOL_NODES} -eq 1 ]] ; then
    RECIPE="singlenode"
  else
    RECIPE="multinode"
  fi
  bastion_remote_cli "cd ~/platform/ansible/install ; python3 deploy_services.py -vv -dr ${AZ_ACR_LOGIN_URL} -ip ${K8S_CLUSTER_API_IP} -n ${K8S_CLUSTER_API_IP} -n ${K8S_NBI_LB_PRIVATE_IP} -s ${K8S_SBI_LB_PRIVATE_IP} -r ${RECIPE} -l ~/services.log"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

step13() {
  doing "- ${FUNCNAME[0]} - Application deployment"
  [[ -z "${AZ_ACR_LOGIN_IP}" ]] && AZ_ACR_LOGIN_IP=$(getent ahostsv4 ${AZ_ACR_LOGIN_URL}|head -1|awk '{print $1}')
  local RETVAL=0
  if [[ ${AZ_AKS_DM_POOL_NODES} -eq 1 ]] ; then
    RECIPE="singlenode"
  else
    RECIPE="multinode"
  fi
  bastion_remote_cli "cd ~/platform/ansible/install ; python3 deploy_applications.py -vv -dr ${AZ_ACR_LOGIN_URL}/ -s ${K8S_SBI_LB_PRIVATE_IP} -l ~/applications.log"
  RETVAL=$?
  [[ ${RETVAL} -eq 0 ]] && success "- ${FUNCNAME[0]}" || error "- fail ${FUNCNAME[0]}"
  return ${RETVAL}
}

### main entry
login_az && \
step1 && \
step2 && \
step3 && \
step6 && \
step7 && \
step10 && \
step11 && \
step12 && \
step13 
RETVAL=$?
[[ ${RETVAL} -eq 0 ]] && success "- completed" || error "- fail"
[[ ! ${NOLOGOUT} -eq 0 ]] && logout_az
clean_tmp_files
exit ${RETVAL}
