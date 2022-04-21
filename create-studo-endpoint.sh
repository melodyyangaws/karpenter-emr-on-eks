#!/bin/bash

# SPDX-FileCopyrightText: Copyright 2021 Amazon.com, Inc. or its affiliates.
# SPDX-License-Identifier: MIT-0

echo "==============================================="
echo "  setup IAM roles for EMR Studio ......"
echo "==============================================="
export STUDIO_SERVICE_ROLE=${EMRCLUSTER_NAME}-StudioServiceRole
cat >/tmp/studio-trust-policy.json <<EOL
{
  "Version": "2012-10-17",
  "Statement": [ {
      "Effect": "Allow",
      "Principal": { "Service": "elasticmapreduce.amazonaws.com" },
      "Action": "sts:AssumeRole"
    } ]
}
EOL
aws iam create-policy --policy-name $STUDIO_SERVICE_ROLE-policy --policy-document file://studio-servicerole-policy.json
aws iam create-role --role-name $STUDIO_SERVICE_ROLE --assume-role-policy-document file:///tmp/studio-trust-policy.json
aws iam attach-role-policy --role-name $STUDIO_SERVICE_ROLE --policy-arn arn:aws:iam::$ACCOUNTID:policy/$STUDIO_SERVICE_ROLE-policy

export STUDIO_USER_ROLE=${EMRCLUSTER_NAME}-StudioUserRole
cat >/tmp/studio-userrole-policy.json <<EOL
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "secretsmanager:CreateSecret",
                "secretsmanager:ListSecrets",
                "emr-containers:DescribeVirtualCluster",
                "emr-containers:ListVirtualClusters",
                "emr-containers:DescribeManagedEndpoint",
                "emr-containers:ListManagedEndpoints",
                "emr-containers:CreateAccessTokenForManagedEndpoint",
                "emr-containers:DescribeJobRun",
                "emr-containers:ListJobRuns"
            ],
            "Resource": "*",
            "Effect": "Allow",
            "Sid": "AllowBasicActions"
        },
        {
            "Action": "iam:PassRole",
            "Resource": "arn:aws:iam::$ACCOUNTID:role/$STUDIO_SERVICE_ROLE",
            "Effect": "Allow",
            "Sid": "PassRolePermission"
        },
        {
            "Action": [
                "s3:ListAllMyBuckets",
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": "arn:aws:s3:::*",
            "Effect": "Allow",
            "Sid": "S3ListPermission"
        },
        {
            "Action": "s3:GetObject",
            "Resource": [
                "arn:aws:s3:::${S3BUCKET}/*",
                "arn:aws:s3:::nyc-tlc/*",
                "arn:aws:s3:::aws-logs-$ACCOUNTID-$AWS_REGION/elasticmapreduce/*"
            ],
            "Effect": "Allow",
            "Sid": "S3GetObjectPermission"
        }
    ]
}
EOL
aws iam create-policy --policy-name $STUDIO_USER_ROLE-policy --policy-document file:///tmp/studio-userrole-policy.json
aws iam create-role --role-name $STUDIO_USER_ROLE --assume-role-policy-document file:///tmp/studio-trust-policy.json
aws iam attach-role-policy --role-name $STUDIO_USER_ROLE --policy-arn arn:aws:iam::$ACCOUNTID:policy/$STUDIO_USER_ROLE-policy

echo "==============================================="
echo "  Creating service account for ALB... ......"
echo "==============================================="
vpcId=$(aws eks describe-cluster --name $EKSCLUSTER_NAME --query 'cluster.resourcesVpcConfig.vpcId' --output text)
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/iam_policy.json
aws iam create-policy --region $AWS_REGION --policy-name $EKSCLUSTER_NAME-studio-alb-policy --policy-document file://iam_policy.json

eksctl create iamserviceaccount --cluster $EKSCLUSTER_NAME --namespace kube-system --name aws-load-balancer-controller \
    --role-name "${EKSCLUSTER_NAME}-studio-alb" \
    --attach-policy-arn "arn:aws:iam::$ACCOUNTID:policy/$EKSCLUSTER_NAME-studio-alb-policy" \
    --override-existing-serviceaccounts \
    --region $AWS_REGION \
    --approve

echo "Creating ALB Service Account..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
    labels:
        app.kubernetes.io/component: controller
        app.kubernetes.io/name: aws-load-balancer-controller
    name: aws-load-balancer-controller
    namespace: kube-system
    annotations:
        eks.amazonaws.com/role-arn: "arn:aws:iam::${ACCOUNTID}:role/${EKSCLUSTER_NAME}-studio-alb"
EOF

echo "Installing the TargetGroupBinding custom resource definitions..."
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"

echo "Adding the eks-charts repository..."
helm repo add eks https://aws.github.io/eks-charts

echo "Installing the AWS Load Balancer Controller..."
helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller \
    --set clusterName=$EKSCLUSTER_NAME \
    --set region=$AWS_REGION \
    --set vpcId=$vpcId \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --debug \
    -n kube-system

echo "Verifying the ALB status..."
kubectl get deployment -n kube-system aws-load-balancer-controller

echo "Load balancer controller has been installed successfully."

echo "Creating a managed endpoint for EMR on EKS..."

openssl req -x509 -newkey rsa:1024 -keyout privateKey.pem -out certificateChain.pem -days 365 -nodes -subj '/C=US/ST=Washington/L=Seattle/O=MyOrg/OU=MyDept/CN=*.'$AWS_REGION'.compute.internal'
cp certificateChain.pem trustedCertificates.pem
export cert_ARN=$(aws acm import-certificate --certificate fileb://trustedCertificates.pem --certificate-chain fileb://certificateChain.pem --private-key fileb://privateKey.pem --tags Key=ekscluster,Value=$EKSCLUSTER_NAME --output text)

export EMR_EKS_CLUSTER_ID=$(aws emr-containers list-virtual-clusters --query "virtualClusters[?name == '$EMRCLUSTER_NAME' && state == 'RUNNING'].id" --output text)
export EMR_EKS_EXECUTION_ARN=arn:aws:iam::$ACCOUNTID:role/$EMRCLUSTER_NAME-execution-role

echo "create emr studio endpoint"
aws emr-containers create-managed-endpoint \
    --type JUPYTER_ENTERPRISE_GATEWAY \
    --virtual-cluster-id $EMR_EKS_CLUSTER_ID \
    --name emr-eks-endpoint \
    --execution-role-arn $EMR_EKS_EXECUTION_ARN \
    --release-label emr-6.5.0-latest \
    --certificate-arn $cert_ARN

aws emr-containers create-managed-endpoint \
    --type JUPYTER_ENTERPRISE_GATEWAY \
    --virtual-cluster-id $EMR_EKS_CLUSTER_ID \
    --name custom-emr-eks-endpoint \
    --execution-role-arn $EMR_EKS_EXECUTION_ARN \
    --release-label emr-6.5.0-latest \
    --certificate-arn $cert_ARN \
    --configuration-overrides '{
   "applicationConfiguration": [
            {
                "classification": "jupyter-kernel-overrides",
                "configurations": [
                    {
                        "classification": "python-kubernetes",
                        "properties": {
                            "container-image": "public.ecr.aws/myang-poc/notebook-python:6.5"
                        }
                    },
                    {
                        "classification": "spark-python-kubernetes",
                        "properties": {
                            "container-image": "public.ecr.aws/myang-poc/notebook-spark:6.5"
                        }
                    }
                ]
            }
        ]
    }'
