## EMR on EKS: High performance autoscaling with Karpenter

This repository provides source code for the Karpenter workshop with EMR on EKS. 

## Infrastructure setup

Run the following scripts in [AWS CloudShell](https://us-east-1.console.aws.amazon.com/cloudshell?region=us-east-1). The default region is `us-east-1`. Change it if needed.
```bash
# download the project
git clone https://github.com/melodyyangaws/karpenter-emr-on-eks.git
cd karpenter-emr-on-eks
export AWS_REGION=us-east-1
````

The script installs CLI tools, creates a new EKS cluster, enables EMR on EKS, and installs Karpenter.
```bash
./create-workshop-env.sh $AWS_REGION
```

## Build benchmark utility docker image 
while the workshop environment setup is still running, let's build a docker image.
```bash
export ACCOUNTID=$(aws sts get-caller-identity --query Account --output text)
export ECR_URL="$ACCOUNTID.dkr.ecr.$AWS_REGION.amazonaws.com"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
aws ecr create-repository --repository-name eks-spark-benchmark --image-scanning-configuration scanOnPush=true
# get EMR on EKS base image
export SRC_ECR_URL=755674844232.dkr.ecr.us-east-1.amazonaws.com
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $SRC_ECR_URL
docker pull $SRC_ECR_URL/spark/emr-6.5.0:latest
# build image
docker build -t $ECR_URL/eks-spark-benchmark:emr6.5 -f docker/Dockerfile-benchmarkutil --build-arg SPARK_BASE_IMAGE=$SRC_ECR_URL/spark/emr-6.5.0:latest .
# push
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
docker push $ECR_URL/eks-spark-benchmark:emr6.5
```

## Run sample jobs
To monitor the autoscaling perforamcne, we need three command line windows in the [AWS CloudShell](https://us-east-1.console.aws.amazon.com/cloudshell?region=us-east-1). Go to "Actions" dropdown list -> select "Split into rows" twice.

Run the command to monitor the scaling status in a window:
```bash
watch "kubectl get pod -n emr"
```
Run the command in a 2nd window:
```bash
watch "kubectl get node --label-columns=node.kubernetes.io/instance-type,topology.kubernetes.io/zone,karpenter.sh/capacity-type"
```
Submit samples jobs in a 3rd window:

```bash
cd karpenter-emr-on-eks
export AWS_REGION=us-east-1
```
```bash
# small job with 2 executors
./example/sample-job.sh $AWS_REGION
```
```bash
# medium size job with 9 executors
./example/emr6.5-benchmark.sh $AWS_REGION
```
## Setup EMR studio with EMR on EKS
Run the script in [AWS CloudShell](https://us-east-1.console.aws.amazon.com/cloudshell?region=us-east-1).

```bash
sudo yum install -y openssl
./create-studio-endpoint.sh $AWS_REGION
````

## Clean up
```bash
./clean-up.sh $AWS_REGION
```
