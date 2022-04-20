## EMR on EKS: High performance autoscaling with Karpenter

This repository provides source code for the Karpenter workshop with EMR on EKS. 

## Infrastructure setup

Run the following scripts in [AWS CloudShell](https://us-east-1.console.aws.amazon.com/cloudshell?region=us-east-1). The default region is `us-east-1`. Change it if needed.
```bash
# download the project
git clone https://github.com/melodyyangaws/karpenter-emr-on-eks.git
cd kuarpenter-emr-on-eks
export AWS_REGION=us-east-1
````

The script installs CLI tools, creates a new EKS cluster, enables EMR on EKS, and installs Karpenter.
```bash
./create-workshop-env.sh $AWS_REGION
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
