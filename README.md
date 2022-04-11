## EMR on EKS: High performance autoscaling with Karpenter

This repository provides source code for the Karpenter workshop with EMR on EKS. 

## Prerequisite

- eksctl is installed
```bash
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv -v /tmp/eksctl /usr/local/bin
eksctl version
```
- Update AWS CLI to the latest (requires aws cli version >= 2.1.14) on macOS. Check out the [link](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) for Linux or Windows
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg ./AWSCLIV2.pkg -target /
aws --version
rm AWSCLIV2.pkg
```
- Install kubectl on MacOS, check out the [link](https://kubernetes.io/docs/tasks/tools/) for Linux or Windows.
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl && export PATH=/usr/local/bin:$PATH
sudo chown root: /usr/local/bin/kubectl
kubectl version --short --client
```
- Helm CLI
```bash
curl -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
helm version --short
```
- [Install Docker on Mac](https://docs.docker.com/desktop/mac/install/), check out [other options](https://docs.docker.com/desktop/#download-and-install) for different OS.
```bash
brew cask install docker
docker --version
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
# stay in the project root directory
cd emr-on-eks-benchmark

# Login to ECR
ECR_URL=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL

# get EMR on EKS base image
export SRC_ECR_URL=755674844232.dkr.ecr.us-east-1.amazonaws.com
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $SRC_ECR_URL
docker pull $SRC_ECR_URL/spark/emr-6.5.0:latest

# Custom an image on top of the EMR Spark
docker build -t $ECR_URL/eks-spark-benchmark:emr6.5 -f docker/benchmark-util/Dockerfile --build-arg SPARK_BASE_IMAGE=$SRC_ECR_URL/spark/emr-6.5.0:latest .
#Finally, push it to ECR. Replace the default docker images in [examples](./examples) if needed:
aws ecr create-repository --repository-name eks-spark-benchmark --image-scanning-configuration scanOnPush=true
# benchmark utility image based on EMR Spark runtime
docker push $ECR_URL/eks-spark-benchmark:emr6.5
```

## Run Job via Karpenter
```bash
# set EMR virtual cluster name, change the region if needed
export EMRCLUSTER_NAME=emr-on-tfc-summit
export AWS_REGION=us-east-1
./emr6.5-benchmark.sh
```
## Run ML training via Karpenter