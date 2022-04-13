clusterName=tfc-summit
region=us-east-1
vpcId=`aws eks describe-cluster --name $clusterName --query 'cluster.resourcesVpcConfig.vpcId' --output text`

echo "Creating service account for ALB..."

curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/iam_policy.json
loadBalancerPolicyARN=$(aws iam create-policy --region $region --policy-name EMREKSWorkshop-AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json | jq -r '.Policy.Arn')

eksctl create iamserviceaccount \
--cluster=$clusterName \
--namespace=kube-system \
--name=aws-load-balancer-controller \
--attach-policy-arn=$loadBalancerPolicyARN \
--override-existing-serviceaccounts \
--region $region \
--approve

cluster=`(echo $clusterName | cut -d- -f1)`
roleArn=`(aws iam list-roles | grep "eksctl-$cluster" | grep "Arn" | sed 's/ //g' | cut -d'"' -f4)`

echo "Creating ALB Service Account..."
kubectl apply -f - << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
    labels:
        app.kubernetes.io/component: controller
        app.kubernetes.io/name: aws-load-balancer-controller
    name: aws-load-balancer-controller
    namespace: kube-system
    annotations:
        eks.amazonaws.com/role-arn: $roleArn
EOF

echo "Installing the TargetGroupBinding custom resource definitions..."

kubectl apply -k "github.com/aws/eks-charts/stable/aws-load                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               -balancer-controller//crds?ref=master"

echo "Adding the eks-charts repository..."

helm repo add eks https://aws.github.io/eks-charts

echo "Installing the AWS Load Balancer Controller..."

helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller \
--set clusterName=$clusterName \
--set region=$region \
--set vpcId=$vpcId \
--set serviceAccount.create=false \
--set serviceAccount.name=aws-load-balancer-controller \
--debug \
-n kube-system

echo "Verifying the ALB status..."
kubectl get deployment -n kube-system aws-load-balancer-controller

echo "Load balancer controller has been installed successfully."

echo "Creating a managed endpoint for EMR on EKS..."

openssl req -x509 -newkey rsa:1024 -keyout privateKey.pem -out certificateChain.pem -days 365 -nodes -subj '/C=US/ST=Washington/L=Seattle/O=MyOrg/OU=MyDept/CN=*.'$region'.compute.internal'
cp certificateChain.pem trustedCertificates.pem
export cert_ARN=$(aws acm import-certificate --certificate fileb://trustedCertificates.pem --certificate-chain fileb://certificateChain.pem --private-key fileb://privateKey.pem --output text)

export EMRCLUSTER_NAME=emr-on-$clusterName
export ACCOUNTID=$(aws sts get-caller-identity --query Account --output text)                    
export EMR_EKS_CLUSTER_ID=$(aws emr-containers list-virtual-clusters --query "virtualClusters[?name == '$EMRCLUSTER_NAME' && state == 'RUNNING'].id" --output text)
export EMR_EKS_EXECUTION_ARN=arn:aws:iam::$ACCOUNTID:role/$EMRCLUSTER_NAME-execution-role

aws emr-containers create-managed-endpoint \
--type JUPYTER_ENTERPRISE_GATEWAY \
--virtual-cluster-id $EMR_EKS_CLUSTER_ID \
--name emr-eks-endpoint \
--execution-role-arn $EMR_EKS_EXECUTION_ARN \
--release-label emr-6.5.0-latest \
--certificate-arn $cert_ARN