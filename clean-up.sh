#!/bin/bash

# SPDX-FileCopyrightText: Copyright 2021 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: MIT-0

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
# delete Grafana role & policy
export G_ROLE_NAME=${EMRCLUSTER_NAME}-grafana-prometheus-servicerole
export G_POLICY_ARN=arn:aws:iam::$ACCOUNTID:policy/${G_ROLE_NAME}-policy
aws iam detach-role-policy --role-name $G_ROLE_NAME --policy-arn $G_POLICY_ARN
aws iam delete-role --role-name $G_ROLE_NAME
aws iam delete-policy --policy-arn $G_POLICY_ARN

# delete S3
aws s3 rm s3://$S3BUCKET --recursive
aws s3api delete-bucket --bucket $S3BUCKET

# delete Grafana workspace
WID=$(aws grafana list-workspaces --query "workspaces[?name=='$EMRCLUSTER_NAME'].id" --output text)
if ! [ -z "$WID" ]; then
	for id in $WID; do
		sleep 2
		echo "Delete $id"
		aws grafana delete-workspace --workspace-id $id
	done
fi
# delete Prometheus worksapce
PID=$(aws amp list-workspaces --alias $EKSCLUSTER_NAME --query workspaces[].workspaceId --output text)
if ! [ -z "$PID" ]; then
	for id in $PID; do
		sleep 2
		echo "Delete $id"
		aws amp delete-workspace --workspace-id $id
	done
fi

# delete ALB
vpcId=$(aws ec2 describe-vpcs --filters Name=tag:"karpenter.sh/discovery",Values=$EKSCLUSTER_NAME --query "Vpcs[*].VpcId" --output text)
ALB=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$vpcId'].LoadBalancerArn" --output text)
if ! [ -z "$ALB" ]; then
	for alb in $ALB; do
		sleep 2
		echo "Delete $alb"
		aws elbv2 delete-load-balancer --load-balancer-arn $alb
	done
fi
TG=$(aws elbv2 describe-target-groups --query "TargetGroups[?VpcId=='$vpcId'].TargetGroupArn" --output text)
if ! [ -z "$TG" ]; then
	for tg in $TG; do
		sleep 2
		echo "Delete Target groups $tg"
		aws elbv2 delete-target-group --target-group-arn $tg
	done
fi
# delete cloud9
env_ls=$(aws cloud9 list-environments --query environmentIds --output text)
if ! [ -z "$env_ls" ]; then
	for l in $env_ls; do
		ts=$(aws cloud9 describe-environments --environment-ids $l --query "environments[?name=='workshop-env']")
		if ! [ -z "$ts" ]; then
			aws cloud9 delete-environment --environment-id $l
		fi
	done
fi
# delete karpenter
aws cloudformation delete-stack --stack-name Karpenter-$EKSCLUSTER_NAME
# delete EKS cluster
eksctl delete cluster --name $EKSCLUSTER_NAME
# delete EMR virtual cluster & EKS cluster
export VIRTUAL_CLUSTER_ID=$(aws emr-containers list-virtual-clusters --query "virtualClusters[?name == '${EMRCLUSTER_NAME}' && state == 'RUNNING'].id" --output text)
aws emr-containers delete-virtual-cluster --id $VIRTUAL_CLUSTER_ID
