## EMR on EKS: High performance autoscaling with Karpenter

This repository provid(es source code for the Karpenter workshop with EMR on EKS. 

## Prerequisite

Install the following tools in [AWS CloudShell](https://us-east-1.console.aws.amazon.com/cloudshell/).
- eksctl
```bash
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv -v /tmp/eksctl /usr/local/bin
eksctl version
```
- AWS CLI version >= 2.1.14
- kubectl  - Check out the [link](https://kubernetes.io/docs/tasks/tools/) for MacOS or Windows, if run the workshop on a local machine.
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --short --client
```
- Helm CLI
```bash
wget https://get.helm.sh/helm-v3.6.3-linux-amd64.tar.gz
tar -xvf helm-v3.6.3-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm
helm version --short
```

## Infrastructure setup

The script creates a new EKS cluster, enables EMR on EKS and builds a private ECR for a docker image. Change the region if needed.
```bash
export EKSCLUSTER_NAME=tfc-summit
export AWS_REGION=us-east-1
./create-workshop-env.sh
```
## Build benchmark utility docker image
Build the image based on a different Spark image, for example [EMR Spark runtime](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/docker-custom-images-tag.html), run the command:
```bash
# Login to ECR
ECR_URL=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL

# get EMR on EKS base image
export SRC_ECR_URL=755674844232.dkr.ecr.us-east-1.amazonaws.com
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $SRC_ECR_URL
docker pull $SRC_ECR_URL/notebook-spark/emr-6.5.0:latest
docker pull $SRC_ECR_URL/notebook-python/emr-6.5.0:latest

# Custom an image on top of the EMR Spark
docker build -t $ECR_URL/notebook-spark:emr6.5 --build-arg SPARK_BASE_IMAGE=$SRC_ECR_URL/notebook-spark/emr-6.5.0:latest .
#Finally, push it to ECR. Replace the default docker images in [examples](./examples) if needed:
aws ecr create-repository --repository-name notebook-spark --image-scanning-configuration scanOnPush=true
# benchmark utility image based on EMR Spark runtime
docker push $ECR_URL/notebook-spark:emr6.5

# Custom an image on top of the EMR Spark
docker build -t $ECR_URL/notebook-python:emr6.5 --build-arg SPARK_BASE_IMAGE=$SRC_ECR_URL/notebook-python/emr-6.5.0:latest .
#Finally, push it to ECR. Replace the default docker images in [examples](./examples) if needed:
aws ecr create-repository --repository-name notebook-python --image-scanning-configuration scanOnPush=true
# benchmark utility image based on EMR Spark runtime
docker push $ECR_URL/notebook-python:emr6.5
```

## Run Job via Karpenter
```bash
# set EMR virtual cluster name, change the region if needed
export EMRCLUSTER_NAME=emr-on-tfc-summit
export AWS_REGION=us-east-1
./emr6.5-benchmark.sh
```
## Run ML training via Karpenter