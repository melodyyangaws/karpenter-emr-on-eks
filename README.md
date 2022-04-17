## EMR on EKS: High performance autoscaling with Karpenter

This repository provides source code for the Karpenter workshop with EMR on EKS. 

## Infrastructure setup

Run the following scripts in [AWS CloudShell](https://us-east-1.console.aws.amazon.com/cloudshell?region=us-east-1). The default region is `us-east-1`.
```bash
# download the project
git clone https://github.com/melodyyangaws/karpenter-emr-on-eks.git
cd kuarpenter-emr-on-eks
````

The script installs CLI tools, creates a new EKS cluster, enables EMR on EKS, and installs Karpenter.
```bash
export EKSCLUSTER_NAME=tfc-summit
export AWS_REGION=us-east-1
./create-workshop-env.sh
```

## Run sample jobs
To monitor the autoscaling perforamcne, we need two command line windows in the [AWS CloudShell](https://us-east-1.console.aws.amazon.com/cloudshell?region=us-east-1). Go to "Actions" dropdown list -> select "Split into columns"

Run the watch command in a window:
```bash
watch "kubectl get po -n emr"
```

Submit the samples jobs in a different window:

```bash
cd karpenter-emr-on-eks
export EMRCLUSTER_NAME=emr-on-tfc-summit
export AWS_REGION=us-east-1
```
```bash
# small job with 2 executors
./example/sample-job.sh
```
```bash
# medium size job with 9 executors
./emr6.5-benchmark.sh
```
## Setup EMR studio with EMR on EKS
Run the script in [AWS CloudShell](https://us-east-1.console.aws.amazon.com/cloudshell?region=us-east-1).

```bash
clusterName=tfc-summit
region=us-east-1
sudo yum install -y openssl
./create-studio-endpoint.sh
````

## Clean up
```bash
export EKSCLUSTER_NAME=tfc-summit
export AWS_REGION=us-east-1
./clean-up.sh
```
