#!/bin/bash

# All the variables for the deployment
subscription_name="AzureDev"

aro_name="myaro"
acr_name="myaro0000010"
workspace_name="myaroworkspace"
vnet_name="vnet-myaro"
masters_subnet="snet-masters"
workers_subnet="snet-workers"
resource_group_name="rg-myaro"
cluster_resource_group_name="rg-myaro-cluster"
location="westeurope"

# Login and set correct context
az login -o table
az account set --subscription $subscription_name -o table

resource_group_id=$(az group create -l $location -n $resource_group_name -o table --query id -o tsv)
echo $resource_group_id

# Prepare extensions and providers
az extension add --upgrade --yes --name aks-preview

# Enable features
# az feature register --namespace Microsoft.RedHatOpenShift --name preview
az provider register --namespace Microsoft.RedHatOpenShift

vnet_id=$(az network vnet create -g $resource_group_name --name $vnet_name \
  --address-prefix 10.0.0.0/22 \
  --query newVNet.id -o tsv)
echo $vnet_id

masters_subnet_id=$(az network vnet subnet create -g $resource_group_name --vnet-name $vnet_name \
  --name $masters_subnet --address-prefixes 10.0.0.0/23 \
  --service-endpoints Microsoft.ContainerRegistry \
  --query id -o tsv)
echo $masters_subnet_id

workers_subnet_id=$(az network vnet subnet create -g $resource_group_name --vnet-name $vnet_name \
  --name $workers_subnet --address-prefixes 10.0.2.0/23 \
  --service-endpoints Microsoft.ContainerRegistry \
  --query id -o tsv)
echo $workers_subnet_id

az network vnet subnet update \
  --name $masters_subnet \
  --resource-group $resource_group_name \
  --vnet-name $vnet_name \
  --disable-private-link-service-network-policies true

############################################
# Supported VM sizes:
# https://docs.microsoft.com/en-us/azure/openshift/support-policies-v4#supported-virtual-machine-sizes

az aro create -g $resource_group_name -n $aro_name \
 --vnet $vnet_name \
 --master-subnet $masters_subnet \
 --worker-subnet $workers_subnet \
 --cluster-resource-group $cluster_resource_group_name \
 --apiserver-visibility Public \
 --ingress-visibility Public \
 --master-vm-size "Standard_D8s_v3" \
 --worker-count 3 \
 --worker-vm-size "Standard_D4as_v4" \
 --worker-vm-disk-size-gb 128 

# Note: If your cluster already exist, you'll get following error message:
# Invalid --cluster-resource-group 'rg-myaro-cluster': resource group must not exist.

# No --pull-secret provided: cluster will not include samples or operators from Red Hat or from certified partners.

# Code: InvalidLinkedVNet
# Message: The provided subnet '.../snet-masters' is invalid: 
#          must not have a network security group attached.
############################################

credentials_json=$(az aro list-credentials \
  --name $aro_name \
  --resource-group $resource_group_name -o json)
kubeadmin_username=$(echo $credentials_json | jq -r .kubeadminUsername)
kubeadmin_password=$(echo $credentials_json | jq -r .kubeadminPassword)

aro_json=$(az aro show \
    --name $aro_name \
    --resource-group $resource_group_name -o json)
console_url=$(echo $aro_json | jq -r .consoleProfile.url)
apiserver_url=$(echo $aro_json | jq -r .apiserverProfile.url)

wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz -O oc.tar.gz
mkdir openshift
tar -zxvf oc.tar.gz -C openshift
sudo cp openshift/oc /usr/local/bin
/usr/local/bin/oc
oc
echo $PATH
oc login $apiserver_url -u $kubeadmin_username -p $kubeadmin_password

kubectl get nodes

# Deploy all items from demos namespace
kubectl apply -f demos/namespace.yaml
kubectl apply -f demos/deployment.yaml
kubectl apply -f demos/service.yaml

kubectl get deployment -n demos
kubectl describe deployment -n demos

pod1=$(kubectl get pod -n demos -o name | head -n 1)
echo $pod1

kubectl describe $pod1 -n demos
kubectl get service -n demos

ingressip=$(kubectl get service -n demos -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}")
echo $ingressip

curl $ingressip
# -> <html><body>Hello there!</body></html>

# Wipe out the resources
az group delete --name $resource_group_name -y
