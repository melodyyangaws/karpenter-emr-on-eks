#!/bin/bash

# SPDX-FileCopyrightText: Copyright 2021 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: MIT-0

# Define params
export EKSCLUSTER_NAME=tfc-summit
export AWS_REGION=us-east-1
export EMRCLUSTER_NAME=emr-on-$EKSCLUSTER_NAME
export ACCOUNTID=$(aws sts get-caller-identity --query Account --output text)

# delete EMR on EKS IAM role & policy
export ROLE_NAME=${EMRCLUSTER_NAME}-execution-role
export POLICY_ARN=arn:aws:iam::$ACCOUNTID:policy/${ROLE_NAME}-policy
aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $POLICY_ARN
aws iam delete-role --role-name $ROLE_NAME
aws iam delete-policy --policy-arn $POLICY_ARN
# delete Karpenter role
export K_ROLE_NAME=${EKSCLUSTER_NAME}-karpenter
export K_POLICY_ARN=arn:aws:iam::$ACCOUNTID:policy/KarpenterControllerPolicy-${EKSCLUSTER_NAME}
aws iam detach-role-policy --role-name $K_ROLE_NAME --policy-arn $K_POLICY_ARN
aws iam delete-role --role-name $K_ROLE_NAME
aws iam delete-policy --policy-arn $K_POLICY_ARN


# delete EMR virtual cluster & EKS cluster
export VIRTUAL_CLUSTER_ID=$(aws emr-containers list-virtual-clusters --query "virtualClusters[?name == '${EMRCLUSTER_NAME}' && state == 'RUNNING'].id" --output text)
aws emr-containers delete-virtual-cluster --id $VIRTUAL_CLUSTER_ID

# delete S3
export S3TEST_BUCKET=${EMRCLUSTER_NAME}-${ACCOUNTID}-${AWS_REGION}
aws s3 rm s3://$S3TEST_BUCKET --recursive
aws s3api delete-bucket --bucket $S3TEST_BUCKET

aws cloudformation delete-stack --stack-name Karpenter-$EKSCLUSTER_NAME
eksctl delete cluster --name $EKSCLUSTER_NAME


