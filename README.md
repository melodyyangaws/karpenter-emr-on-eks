## EMR on EKS: High performance autoscaling with Karpenter

This repository provides source code for the Karpenter workshop with EMR on EKS. For the workshop purpose, we will run Karpenter in AZ-a, and Cluster Autoscaler in AZ-b. Each jobs will be submitted twice, ie. one per AZ. 

See the reference architecture as below:

![](/workshop-diagram.png)

## 1. Infrastructure setup

Run the following scripts in [AWS CloudShell](https://us-east-1.console.aws.amazon.com/cloudshell?region=us-east-1). The default region is `us-east-1`. Change it if needed.
```bash
# download the project
git clone https://github.com/melodyyangaws/karpenter-emr-on-eks.git
cd karpenter-emr-on-eks
export AWS_REGION=us-east-1
````

The script install CLI tools, creates a new EKS cluster, enables EMR on EKS, and installs Karpenter.
```bash
./install_cli.sh
./provision/create-workshop-env.sh $AWS_REGION
```

## 2. Build a custom docker image
While the environment setup is still running, let's build a docker image via the ["workshop-ide" in AWS Cloud9](https://console.aws.amazon.com/cloud9).
```bash
export ACCOUNTID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=$(curl http://169.254.169.254/latest/meta-data/placement/region)
export ECR_URL="$ACCOUNTID.dkr.ecr.$AWS_REGION.amazonaws.com"
# remove existing images to save disk space
docker rmi $(docker images -a | awk {'print $3'}) -f
# create ECR repo
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
aws ecr create-repository --repository-name eks-spark-benchmark --image-scanning-configuration scanOnPush=true
# get image
docker pull public.ecr.aws/myang-poc/benchmark:6.5
# tag image
docker tag public.ecr.aws/myang-poc/benchmark:6.5 $ECR_URL/eks-spark-benchmark:emr6.5 
# push
docker push $ECR_URL/eks-spark-benchmark:emr6.5
```

## 3. Test with sample Spark jobs
To analyse the autoscaling perforamcne, we use [Amazon Managed Service for Prometheus (AMP)](https://aws.amazon.com/prometheus/) to ingest Spark metrics and use an [Amazon Managed Grafana](https://aws.amazon.com/grafana/) dashboard to visualize. 

**Follow the [grafana setup](./setup_grafana_dashboard.pdf) instruction to get your dashboard ready.**

To monitor the autoscaling status in real time, go back to your [AWS CloudShell](https://us-east-1.console.aws.amazon.com/cloudshell?region=us-east-1). Click on the "Actions" dropdown button -> select "Split into rows" twice. Note the default region is `us-east-1`. Change it to a different region if your infra setup wasn't in the default one.

Watch job pods autoscaling status in a command line window (nothing returns at the beginning):
```bash
watch -n1 "kubectl get pod -n emr"
```
Monitor EC2 instance autoscaling status in a 2nd window. Empty "CAPACITY-TYPE" means the autoscaling was scheduled by Cluster Autoscaler, otherwise by Karpenter.
```bash
watch -n1 "kubectl get node --label-columns=node.kubernetes.io/instance-type,topology.kubernetes.io/zone,karpenter.sh/capacity-type"
```
Submit jobs in a 3rd window. The suffix 'ca' represents Cluster Autoscaler.
```bash
cd karpenter-emr-on-eks
./install_cli.sh
```
```bash
# small job with 2 executors
./example/sample-job-ca.sh
./example/sample-job-karpenter.sh
```
```bash
# medium size job with 47 executors
./example/emr6.5-benchmark-ca.sh
./example/emr6.5-benchmark-karpenter.sh
```
## 4. Setup EMR studio with EMR on EKS (coming soon)
Run the script in [AWS CloudShell](https://us-east-1.console.aws.amazon.com/cloudshell?region=us-east-1).

```bash
sudo yum install -y openssl
./provision/create-studio-endpoint.sh
````

## 5. Clean up
```bash
./install_cli.sh
./clean-up.sh
```
Go to ["workshop-ide" AWS Cloud9](https://console.aws.amazon.com/cloud9), delete the ECR:
```bash
export ECR_URL="$ACCOUNTID.dkr.ecr.$AWS_REGION.amazonaws.com"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
aws ecr delete-repository --repository-name eks-spark-benchmark --force
```
