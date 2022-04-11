clusterName=${1}
region=${2}
vpcId=${3}

echo "Download IAM policies AWS Load Balancer Controller..."

curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/iam_policy.json

echo "Creating AWS Load Balancer Controller IAM Policy..."

loadBalancerPolicyARN=`(aws iam create-policy --region $region \
--policy-name EMREKSWorkshop-AWSLoadBalancerControllerIAMPolicy \
--policy-document file://iam_policy.json | jq -r '.Policy.Arn')`

echo "Load Balancer Controller IAM Policy ARN: "$loadBalancerPolicyARN

echo "Creating Kubernetes service account IAM role..."

eksctl create iamserviceaccount \
--cluster=$clusterName \
--namespace=kube-system \
--name=aws-load-balancer-controller \
--attach-policy-arn=$loadBalancerPolicyARN \
--override-existing-serviceaccounts \
--region $region \
--approve

cluster=`(echo $clusterName | cut -d- -f1)`
roleArn=`(aws iam list-roles | grep "eksctl-${cluster}" | grep "Arn" | sed 's/ //g' | cut -d'"' -f4)`
#roleArn=`(aws iam list-roles | jq -r '.Roles[] | select(.RoleName|test("eksctl-$clusterName")).Arn')`

echo "Service Account Role is created, ARN: ":$roleArn

cat <<EOF > aws-load-balancer-controller.yaml
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

echo "Creating Service Account..."

kubectl apply -f aws-load-balancer-controller.yaml

echo "Installing the TargetGroupBinding custom resource definitions..."

kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"

echo "Adding the eks-charts repository..."

helm repo add eks https://aws.github.io/eks-charts

echo "Installing the AWS Load Balancer Controller..."

helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller \
--set clusterName=$clusterName \
--set region=$region \
--set vpcId=$vpcId \
--set serviceAccount.create=false \
--set serviceAccount.name=aws-load-balancer-controller \
-n kube-system

echo "Verifying the controller status..."
kubectl get deployment -n kube-system aws-load-balancer-controller

echo "Load balancer controller has been installed successfully."