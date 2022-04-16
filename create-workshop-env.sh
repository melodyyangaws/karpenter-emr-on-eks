#!/bin/bash

# SPDX-FileCopyrightText: Copyright 2021 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: MIT-0

# export EKSCLUSTER_NAME=tfc-summit
# export AWS_REGION=us-east-1

export EMRCLUSTER_NAME=emr-on-$EKSCLUSTER_NAME
export ROLE_NAME=${EMRCLUSTER_NAME}-execution-role
export ACCOUNTID=$(aws sts get-caller-identity --query Account --output text)
export S3TEST_BUCKET=${EMRCLUSTER_NAME}-${ACCOUNTID}-${AWS_REGION}


echo "==============================================="
echo "  install CLI tools ......"
echo "==============================================="

# Install eksctl on cloud9/cloudshell
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv -v /tmp/eksctl /usr/local/bin
eksctl version

# Install kubectl on cloud9/cloudshell
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --short --client


# Install helm on cloud9/cloudshell
wget https://get.helm.sh/helm-v3.6.3-linux-amd64.tar.gz
tar -xvf helm-v3.6.3-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm
helm version --short


echo "==============================================="
echo "  setup IAM roles ......"
echo "==============================================="

# create S3 bucket for application
 aws s3 mb s3://$S3TEST_BUCKET --region $AWS_REGION 
 # --create-bucket-configuration LocationConstraint=$AWS_REGION

# Create a job execution role 
cat > /tmp/job-execution-policy.json <<EOL
{
    "Version": "2012-10-17",
    "Statement": [ 
        {
            "Effect": "Allow",
            "Action": ["s3:PutObject","s3:DeleteObject","s3:GetObject","s3:ListBucket"],
            "Resource": [
              "arn:aws:s3:::${S3TEST_BUCKET}",
              "arn:aws:s3:::${S3TEST_BUCKET}/*",
              "arn:aws:s3:::*.elasticmapreduce",
              "arn:aws:s3:::*.elasticmapreduce/*",
              "arn:aws:s3:::nyc-tlc",
              "arn:aws:s3:::nyc-tlc/*",
              "arn:aws:s3:::blogpost-sparkoneks-us-east-1/blog/BLOG_TPCDS-TEST-3T-partitioned/*",
              "arn:aws:s3:::blogpost-sparkoneks-us-east-1"
            ]
        }, 
        {
            "Effect": "Allow",
            "Action": [ "logs:PutLogEvents", "logs:CreateLogStream", "logs:DescribeLogGroups", "logs:DescribeLogStreams", "logs:CreateLogGroup" ],
            "Resource": [ "arn:aws:logs:*:*:*" ]
        }
    ]
}
EOL

cat > /tmp/trust-policy.json <<EOL
{
  "Version": "2012-10-17",
  "Statement": [ {
      "Effect": "Allow",
      "Principal": { "Service": "eks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    } ]
}
EOL

aws iam create-policy --policy-name $ROLE_NAME-policy --policy-document file:///tmp/job-execution-policy.json
aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file:///tmp/trust-policy.json
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::$ACCOUNTID:policy/$ROLE_NAME-policy

echo "==============================================="
echo "  Create EKS Cluster ......"
echo "==============================================="


cat <<EOF | eksctl create cluster -f - 
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${EKSCLUSTER_NAME}
  region: ${AWS_REGION}
  version: "1.21"
  tags:
    karpenter.sh/discovery: ${EKSCLUSTER_NAME}
    for-use-with-amazon-emr-managed-policies: true
managedNodeGroups:
  - instanceType: m5.large
    amiFamily: AmazonLinux2
    name: ${EKSCLUSTER_NAME}-ng
    desiredCapacity: 1
    minSize: 1
    maxSize: 2
vpc:
  clusterEndpoints:
      publicAccess: true
      privateAccess: true  
availabilityZones: ["${AWS_REGION}a","${AWS_REGION}b"]
iam:
  withOIDC: true
cloudWatch: 
 clusterLogging:
   enableTypes: ["*"]
EOF
# eksctl create cluster -f k-eksctl-cluster.yaml
aws eks update-kubeconfig --name $EKSCLUSTER_NAME --region $AWS_REGION

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

echo "==============================================="
echo "  Install Karpenter to EKS ......"
echo "==============================================="
# create node and node instance role
TEMPOUT=$(mktemp)
curl -fsSL https://karpenter.sh/docs/getting-started/getting-started-with-eksctl/cloudformation.yaml > $TEMPOUT \
&& aws cloudformation deploy \
  --stack-name Karpenter-${EKSCLUSTER_NAME} \
  --template-file ${TEMPOUT} \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ClusterName=${EKSCLUSTER_NAME}

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
  --role-only \
  --approve

export KARPENTER_IAM_ROLE_ARN="arn:aws:iam::${ACCOUNTID}:role/${EKSCLUSTER_NAME}-karpenter"
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true

# Install
helm repo add karpenter https://charts.karpenter.sh
helm repo update
helm upgrade --install karpenter karpenter/karpenter --namespace karpenter \
  --create-namespace --version 0.8.1 \
  --set serviceAccount.create=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${KARPENTER_IAM_ROLE_ARN} \
  --set clusterName=${EKSCLUSTER_NAME} \
  --set clusterEndpoint=$(aws eks describe-cluster --name ${EKSCLUSTER_NAME} --query "cluster.endpoint" --output json) \
  --set aws.defaultInstanceProfile=KarpenterNodeInstanceProfile-${EKSCLUSTER_NAME} \
  --wait \
  --debug


echo "==============================================="
echo "  Create a default Karpenter Provisioner ......"
echo "==============================================="

curl https://raw.githubusercontent.com/melodyyangaws/karpenter-emr-on-eks/main/provisioner.yaml | kubectl apply -f -
