#!/bin/bash

# Step 5: Initialize master node
lsmod | grep br_netfilter
sudo systemctl enable kubelet
sudo kubeadm config images pull

MASTER_IP=$(hostname -I | cut -d' ' -f1)

sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --control-plane-endpoint=$MASTER_IP

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl cluster-info

# Step 6: Install network plugin on Master
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
sleep 5
kubectl get nodes -o wide

# Deploy Kubernetes Dashboard
#kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended.yaml
wget https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended.yaml
mv recommended.yaml kubernetes-dashboard-deployment.yml
sed -i -z 's/  selector:\n    k8s-app: kubernetes-dashboard/  selector:\n    k8s-app: kubernetes-dashboard\n  type: NodePort/' kubernetes-dashboard-deployment.yml
kubectl apply -f kubernetes-dashboard-deployment.yml
sleep 5
kubectl get deployments -n kubernetes-dashboard
kubectl get pods -n kubernetes-dashboard
kubectl get service -n kubernetes-dashboard

################################################################################
SA_NAME="kube-admin"

# Create Admin service account
echo "
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SA_NAME
  namespace: kube-system
" > admin-sa.yml
kubectl apply -f admin-sa.yml

# Create a Cluster Role Binding
echo "
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $SA_NAME
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: $SA_NAME
    namespace: kube-system
" > admin-rbac.yml
kubectl apply -f admin-rbac.yml

# Obtain admin user token
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep ${SA_NAME} | awk '{print $1}')

# Obtain Kubeconfig file
# The script returns a kubeconfig for the service account given
# you need to have kubectl on PATH with the context set to the cluster you want to create the config for

DASHBOARD_PORT=$(kubectl get service -n kubernetes-dashboard | grep kubernetes-dashboard | grep -o -P '(?<=443:).*(?=/TCP)')

# Cosmetics for the created config
clusterName=kubernetes
# your server address goes here get it via `kubectl cluster-info`
server=https://$MASTER_IP:$DASHBOARD_PORT/
# the Namespace and ServiceAccount name that is used for the config
namespace=kube-system
serviceAccount=$SA_NAME

################################################################################
# actual script starts
set -o errexit

secretName=$(kubectl --namespace $namespace get serviceAccount $serviceAccount -o jsonpath='{.secrets[0].name}')
ca=$(kubectl --namespace $namespace get secret/$secretName -o jsonpath='{.data.ca\.crt}')
token=$(kubectl --namespace $namespace get secret/$secretName -o jsonpath='{.data.token}' | base64 --decode)

echo "
---
apiVersion: v1
kind: Config
clusters:
  - name: ${clusterName}
    cluster:
      certificate-authority-data: ${ca}
      server: ${server}
contexts:
  - name: ${serviceAccount}@${clusterName}
    context:
      cluster: ${clusterName}
      namespace: ${serviceAccount}
      user: ${serviceAccount}
users:
  - name: ${serviceAccount}
    user:
      token: ${token}
current-context: ${serviceAccount}@${clusterName}
" > kubeconfig.yaml

################################################################################
# configure Grafana
# Step 1: Clone kube-prometheus project
# Use git command to clone kube-prometheus project to your local system:
cd ..

git clone https://github.com/prometheus-operator/kube-prometheus.git
# Navigate to the kube-prometheus directory:
cd kube-prometheus

# Step 2: Create monitoring namespace, CustomResourceDefinitions & operator pod
# Create a namespace and required CustomResourceDefinitions:
kubectl create -f manifests/setup
# The namespace created with CustomResourceDefinitions is named monitoring:
kubectl get ns monitoring
# Confirm that Prometheus operator pods are running:
kubectl get pods -n monitoring

# Step 3: Deploy Prometheus Monitoring Stack on Kubernetes
# Once you confirm the Prometheus operator is running you can go ahead and deploy Prometheus monitoring stack.
kubectl create -f manifests/
# Give it few seconds and the pods should start coming online. This can be checked with the commands below:
kubectl get pods -n monitoring
# To list all the services created you’ll run the command:
kubectl get svc -n monitoring

cd ../K8s_setup

# # Step 4: Access Prometheus, Grafana, and Alertmanager dashboards
# # Method 1
# # Grafana Dashboard
# # Username: admin | Password: admin
# kubectl --namespace monitoring port-forward svc/grafana 3000
# # Prometheus Dashboard
# kubectl --namespace monitoring port-forward svc/prometheus-k8s 9090
# # Alert Manager Dashboard
# # For Dashboard Alert Manager Dashboard:
# kubectl --namespace monitoring port-forward svc/alertmanager-main 9093
# 
# # Method 2
# # Update inside spec section
# spec:
#   type: NodePort
# # Prometheus:
KUBE_EDITOR="sed -i s/ClusterIP/NodePort/g" kubectl --namespace monitoring edit svc/prometheus-k8s
# # Alertmanager:
KUBE_EDITOR="sed -i s/ClusterIP/NodePort/g" kubectl --namespace monitoring edit svc/alertmanager-main
# # Grafana:
KUBE_EDITOR="sed -i s/ClusterIP/NodePort/g" kubectl --namespace monitoring edit svc/grafana
# # Confirm that the each of the services have a Node Port assigned:
kubectl -n monitoring get svc  | grep NodePort

################################################################################

echo "
MASTER_IP=$(hostname -I | cut -d' ' -f1)

DASHBOARD_PORT=$(kubectl get service -n kubernetes-dashboard | grep NodePort | grep dashboard | grep -o -P '(?<=443:).*(?=/TCP)')
ALERTMANAGER_PORT=$(kubectl get service -n monitoring | grep NodePort | grep alertmanager | grep -o -P '(?<=:).*(?=/TCP)')
GRAFANA_PORT=$(kubectl get service -n monitoring | grep NodePort | grep grafana | grep -o -P '(?<=:).*(?=/TCP)')
PROMETHEUS_PORT=$(kubectl get service -n monitoring | grep NodePort | grep prometheus | grep -o -P '(?<=:).*(?=/TCP)')

echo Dadhboard: '  ' https://$MASTER_IP:$DASHBOARD_PORT/
echo Alertmanager:   http://$MASTER_IP:$ALERTMANAGER_PORT/
echo Grafana: '    ' http://$MASTER_IP:$GRAFANA_PORT/
echo Prometheus: ' ' http://$MASTER_IP:$PROMETHEUS_PORT/
" > get_servers.sh
sudo chmod +x get_servers.sh

echo "
kubeadm token create --print-join-command >> join_command
sed -i '1s;^;sudo ;' join_command
cat join_command
" > get_join_command.sh
sudo chmod +x get_join_command.sh
################################################################################

echo ======================================================================================
cat kubeconfig.yaml
echo ======================================================================================
echo Command to join nodes:
./get_join_command.sh
echo ======================================================================================
./get_servers.sh
echo ======================================================================================
