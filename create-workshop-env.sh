#!/bin/bash

# SPDX-FileCopyrightText: Copyright 2021 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: MIT-0

AWS_REGION=$1

export EKSCLUSTER_NAME=tfc-summit
export EMRCLUSTER_NAME=emr-on-$EKSCLUSTER_NAME
export ACCOUNTID=$(aws sts get-caller-identity --query Account --output text)
export S3TEST_BUCKET=${EMRCLUSTER_NAME}-${ACCOUNTID}-${AWS_REGION}

echo "==============================================="
echo "  install CLI tools ......"
echo "==============================================="

# Install eksctl on cloudshell
curl -s --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv -v /tmp/eksctl /usr/local/bin
echo eksctl version is $(eksctl version)

# Install kubectl on cloudshell
curl -s -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
echo kubectl version is $(kubectl version --short --client)

# Install helm on cloudshell
curl -s https://get.helm.sh/helm-v3.6.3-linux-amd64.tar.gz | tar xz -C ./ &&
    sudo mv linux-amd64/helm /usr/local/bin/helm &&
    rm -r linux-amd64
echo helm cli version is $(helm version --short)

echo "==============================================="
echo "  create Cloud9 IDE environment ......"
echo "==============================================="
aws cloud9 create-environment-ec2 --name workshop-ide --instance-type t3.medium --automatic-stop-time-minutes 60

# create S3 bucket for application
aws s3 mb s3://$S3TEST_BUCKET --region $AWS_REGION

echo "==============================================="
echo "  setup IAM roles for EMR on EKS ......"
echo "==============================================="
# Create a job execution role
export ROLE_NAME=${EMRCLUSTER_NAME}-execution-role
cat >/tmp/trust-policy.json <<EOL
{
  "Version": "2012-10-17",
  "Statement": [ {
      "Effect": "Allow",
      "Principal": { "Service": "eks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    } ]
}
EOL
sed -i -- 's/{S3TEST_BUCKET}/'$S3TEST_BUCKET'/g' iam/job-execution-policy.json
aws iam create-policy --policy-name $ROLE_NAME-policy --policy-document file://iam/job-execution-policy.json
aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file:///tmp/trust-policy.json
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::$ACCOUNTID:policy/$ROLE_NAME-policy

echo "==============================================="
echo "  Create Grafana Role and workspace ......"
echo "==============================================="
export GRA_ROLE_NAME=${EMRCLUSTER_NAME}-grafana-prometheus-servicerole
cat >/tmp/grafana-prometheus-trust-policy.json <<EOL
{
    "Version": "2012-10-17",
    "Statement": [ 
    {
        "Effect": "Allow",
        "Principal": {
            "Service": "grafana.amazonaws.com"
        },
        "Action": "sts:AssumeRole",
        "Condition": {
            "StringEquals": {
                "aws:SourceAccount": "$ACCOUNTID"
            },
            "StringLike": {
                "aws:SourceArn": "arn:aws:grafana:$AWS_REGION:$ACCOUNTID:/workspaces/*"
            }
        }
    }]
}
EOL
aws iam create-policy --policy-name $GRA_ROLE_NAME-policy --policy-document file://iam/grafana-prometheus-policy.json
aws iam create-role --role-name $GRA_ROLE_NAME --assume-role-policy-document file:///tmp/grafana-prometheus-trust-policy.json
aws iam attach-role-policy --role-name $GRA_ROLE_NAME --policy-arn arn:aws:iam::$ACCOUNTID:policy/$GRA_ROLE_NAME-policy
ws=$(aws grafana list-workspaces --query "workspaces[?name=='$EMRCLUSTER_NAME'].id")
if [ -z "$ws" ]; then
    aws grafana create-workspace --account-access-type CURRENT_ACCOUNT --authentication-providers AWS_SSO \
        --permission-type SERVICE_MANAGED --workspace-data-sources PROMETHEUS --workspace-name $EMRCLUSTER_NAME \
        --workspace-role-arn "arn:aws:iam::${ACCOUNTID}:role/$GRA_ROLE_NAME"
fi

echo "==============================================="
echo "  Create EKS Cluster ......"
echo "==============================================="
sed -i -- 's/{AWS_REGION}/'$AWS_REGION'/g' ekscluster-config.yaml
sed -i -- 's/{EKSCLUSTER_NAME}/'$EKSCLUSTER_NAME'/g' ekscluster-config.yaml
sed -i -- 's/{ACCOUNTID}/'$ACCOUNTID'/g' ekscluster-config.yaml
eksctl create cluster -f ekscluster-config.yaml
aws eks update-kubeconfig --name $EKSCLUSTER_NAME --region $AWS_REGION

echo "==============================================="
echo "  Install Cluster Autoscaler (CA) to EKS ......"
echo "==============================================="
sed -i -- 's/{AWS_REGION}/'$AWS_REGION'/g' helm/autoscaler-values.yaml
sed -i -- 's/{EKSCLUSTER_NAME}/'$EKSCLUSTER_NAME'/g' helm/autoscaler-values.yaml
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm install nodescaler autoscaler/cluster-autoscaler -n kube-system -f helm/autoscaler-values.yaml --debug

echo "====================================================="
echo "  Install Prometheus to EKS for monitroing ......"
echo "====================================================="
kubectl create namespace prometheus
# eksctl create iamserviceaccount \
#     --cluster ${EKSCLUSTER_NAME} --namespace prometheus --name amp-iamproxy-ingest-service-account \
#     --role-name "${EKSCLUSTER_NAME}-prometheus-ingest" \
#     --attach-policy-arn "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess" \
#     --role-only \
#     --approve

export WORKSPACE_ID=$(aws amp create-workspace --alias $EKSCLUSTER_NAME --query workspaceId --output text)
export INGEST_ROLE_ARN="arn:aws:iam::${ACCOUNTID}:role/${EKSCLUSTER_NAME}-prometheus-ingest"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add kube-state-metrics https://kubernetes.github.io/kube-state-metrics
helm repo update
sed -i -- 's/{AWS_REGION}/'$AWS_REGION'/g' helm/prometheus_values.yaml
sed -i -- 's/{ACCOUNTID}/'$ACCOUNTID'/g' helm/prometheus_values.yaml
sed -i -- 's/{WORKSPACE_ID}/'$WORKSPACE_ID'/g' helm/prometheus_values.yaml
sed -i -- 's/{EKSCLUSTER_NAME}/'$EKSCLUSTER_NAME'/g' helm/prometheus_values.yaml
helm install prometheus prometheus-community/prometheus -n prometheus -f helm/prometheus_values.yaml --debug

echo "==============================================="
echo "  Install Karpenter to EKS ......"
echo "==============================================="
# kubectl create namespace karpenter
# create IAM role and launch template
CONTROLPLANE_SG=$(aws eks describe-cluster --name $EKSCLUSTER_NAME --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)
DNS_IP=$(kubectl get svc -n kube-system | grep kube-dns | awk '{print $3}')
API_SERVER=$(aws eks describe-cluster --region ${AWS_REGION} --name ${EKSCLUSTER_NAME} --query 'cluster.endpoint' --output text)
B64_CA=$(aws eks describe-cluster --region ${AWS_REGION} --name ${EKSCLUSTER_NAME} --query 'cluster.certificateAuthority.data' --output text)
aws cloudformation deploy \
    --stack-name Karpenter-${EKSCLUSTER_NAME} \
    --template-file karpenter-cfn.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides "ClusterName=$EKSCLUSTER_NAME" "EKSClusterSgId=$CONTROLPLANE_SG" "APIServerURL=$API_SERVER" "B64ClusterCA=$B64_CA" "EKSDNS=$DNS_IP"

eksctl create iamidentitymapping \
    --username system:node:{{EC2PrivateDNSName}} \
    --cluster "${EKSCLUSTER_NAME}" \
    --arn "arn:aws:iam::${ACCOUNTID}:role/KarpenterNodeRole-${EKSCLUSTER_NAME}" \
    --group system:bootstrappers \
    --group system:nodes

# controller role
eksctl create iamserviceaccount \
    --cluster "${EKSCLUSTER_NAME}" --name karpenter --namespace karpenter \
    --role-name "${EKSCLUSTER_NAME}-karpenter" \
    --attach-policy-arn "arn:aws:iam::${ACCOUNTID}:policy/KarpenterControllerPolicy-${EKSCLUSTER_NAME}" \
    --approve

# aws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true
export KARPENTER_IAM_ROLE_ARN="arn:aws:iam::${ACCOUNTID}:role/${EKSCLUSTER_NAME}-karpenter"
helm repo add karpenter https://charts.karpenter.sh
helm upgrade --install karpenter karpenter/karpenter --namespace karpenter --version 0.8.1 \
    --set serviceAccount.create=false --set serviceAccount.name=karpenter --set clusterName=${EKSCLUSTER_NAME} --set clusterEndpoint=${API_SERVER} \
    --debug

sed -i -- 's/{AWS_REGION}/'$AWS_REGION'/g' k-provisioner.yaml
sed -i -- 's/{EKSCLUSTER_NAME}/'$EKSCLUSTER_NAME'/g' k-provisioner.yaml
kubectl apply -f k-provisioner.yaml

echo "==============================================="
echo "  Enable EMR on EKS ......"
echo "==============================================="
kubectl create namespace emr
eksctl create iamidentitymapping --cluster $EKSCLUSTER_NAME --namespace emr --service-name "emr-containers"
aws emr-containers update-role-trust-policy --cluster-name $EKSCLUSTER_NAME --namespace emr --role-name $ROLE_NAME

# Create emr virtual cluster
aws emr-containers create-virtual-cluster --name $EMRCLUSTER_NAME \
    --container-provider '{
        "id": "'$EKSCLUSTER_NAME'",
        "type": "EKS",
        "info": { "eksInfo": { "namespace":"'emr'" } }
    }'
