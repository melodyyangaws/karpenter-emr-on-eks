#!/bin/bash

# SPDX-FileCopyrightText: Copyright 2021 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: MIT-0

AWS_REGION=$1

export EKSCLUSTER_NAME=tfc-summit
export EMRCLUSTER_NAME=emr-on-$EKSCLUSTER_NAME
export ACCOUNTID=$(aws sts get-caller-identity --query Account --output text)
export S3BUCKET=${EMRCLUSTER_NAME}-${ACCOUNTID}-${AWS_REGION}

echo "export AWS_REGION=${AWS_REGION}" | tee -a ~/.bash_profile
echo "export EKSCLUSTER_NAME=tfc-summit" | tee -a ~/.bash_profile
echo "export EMRCLUSTER_NAME=$EMRCLUSTER_NAME" | tee -a ~/.bash_profile
echo "export ACCOUNTID=${ACCOUNTID}" | tee -a ~/.bash_profile
echo "export S3BUCKET=${S3BUCKET}" | tee -a ~/.bash_profile
source ~/.bash_profile

echo "==============================================="
echo "  create Cloud9 IDE environment ......"
echo "==============================================="
aws cloud9 create-environment-ec2 --name workshop-ide --instance-type t3.medium
# need the subnet id only if no default VPC exists in the AWS account.
# subnetid=$(aws ec2 describe-subnets --filters Name=tag:karpenter.sh/discovery,Values=$EKSCLUSTER_NAME Name=tag:kubernetes.io/role/elb,Values=1 --query "Subnets[].SubnetId" --output text | cut -f1)
# aws cloud9 create-environment-ec2 --name workshop-ide --instance-type t3.medium --subnet-id $subnetid

# create S3 bucket for application
aws s3 mb s3://$S3BUCKET --region $AWS_REGION
aws s3 sync example/pod-template s3://$S3BUCKET/pod-template

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
sed -i -- 's/{S3BUCKET}/'$S3BUCKET'/g' iam/job-execution-policy.json
aws iam create-policy --policy-name $ROLE_NAME-policy --policy-document file://iam/job-execution-policy.json
aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file:///tmp/trust-policy.json
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::$ACCOUNTID:policy/$ROLE_NAME-policy

echo "==============================================="
echo "  Create EKS Cluster ......"
echo "==============================================="
sed -i -- 's/{AWS_REGION}/'$AWS_REGION'/g' provision/ekscluster-config.yaml
sed -i -- 's/{EKSCLUSTER_NAME}/'$EKSCLUSTER_NAME'/g' provision/ekscluster-config.yaml
sed -i -- 's/{ACCOUNTID}/'$ACCOUNTID'/g' provision/ekscluster-config.yaml
eksctl create cluster -f provision/ekscluster-config.yaml
aws eks update-kubeconfig --name $EKSCLUSTER_NAME --region $AWS_REGION

echo "==============================================="
echo "  Install Cluster Autoscaler (CA) to EKS ......"
echo "==============================================="
sed -i -- 's/{AWS_REGION}/'$AWS_REGION'/g' helm/autoscaler-values.yaml
sed -i -- 's/{EKSCLUSTER_NAME}/'$EKSCLUSTER_NAME'/g' helm/autoscaler-values.yaml
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm upgrade --install nodescaler autoscaler/cluster-autoscaler -n kube-system -f helm/autoscaler-values.yaml

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
    --template-file karpenter/karpenter-cfn.yaml \
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
helm upgrade --install karpenter karpenter/karpenter --namespace karpenter --version 0.16.3 \
    --set serviceAccount.create=false --set serviceAccount.name=karpenter --set nodeSelector.app=ops \
    --set clusterName=${EKSCLUSTER_NAME} --set clusterEndpoint=${API_SERVER}

sed -i -- 's/{AWS_REGION}/'$AWS_REGION'/g' karpenter/k-provisioner.yaml
sed -i -- 's/{EKSCLUSTER_NAME}/'$EKSCLUSTER_NAME'/g' karpenter/k-provisioner.yaml
kubectl apply -f karpenter/k-provisioner.yaml
#turn off debug mode
kubectl patch configmap config-logging -n karpenter --patch '{"data":{"loglevel.controller":"info"}}'

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

amp=$(aws amp list-workspaces --query "workspaces[?alias=='$EKSCLUSTER_NAME'].workspaceId" --output text)
if [ -z "$amp" ]; then
    echo "Creating a new prometheus workspace..."
    export WORKSPACE_ID=$(aws amp create-workspace --alias $EKSCLUSTER_NAME --query workspaceId --output text)
else
    echo "A prometheus workspace already exists"
    export WORKSPACE_ID=$amp
fi
export INGEST_ROLE_ARN="arn:aws:iam::${ACCOUNTID}:role/${EKSCLUSTER_NAME}-prometheus-ingest"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add kube-state-metrics https://kubernetes.github.io/kube-state-metrics
helm repo update
sed -i -- 's/{AWS_REGION}/'$AWS_REGION'/g' helm/prometheus_values.yaml
sed -i -- 's/{ACCOUNTID}/'$ACCOUNTID'/g' helm/prometheus_values.yaml
sed -i -- 's/{WORKSPACE_ID}/'$WORKSPACE_ID'/g' helm/prometheus_values.yaml
sed -i -- 's/{EKSCLUSTER_NAME}/'$EKSCLUSTER_NAME'/g' helm/prometheus_values.yaml
helm upgrade --install prometheus prometheus-community/prometheus -n prometheus -f helm/prometheus_values.yaml

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

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
