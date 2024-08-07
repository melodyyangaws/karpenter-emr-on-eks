## EMR on EKS: High performance autoscaling with Karpenter

This repository provides source code for the Karpenter workshop with EMR on EKS. For the workshop purpose, we will run Karpenter in AZ-a, and Cluster Autoscaler in AZ-b. Each job will be submitted twice, ie. one per AZ. However, this is not a recommended design for a real-world workload.

See the reference architecture as below:

![](/workshop-diagram.png)

## 1. Infrastructure setup

### Prerequisite
- eksctl >= 0.143.0
- Helm CLI >= 3.2.1 
- kubectl >= 1.26.4 
- AWS Cli >= 2.11.23

Run the following scripts in [AWS CloudShell](https://us-east-1.console.aws.amazon.com/cloudshell?region=us-east-1). The default region is `us-east-1`. **Change it on your console if needed**.
```bash
# download the project
git clone https://github.com/melodyyangaws/karpenter-emr-on-eks.git
cd karpenter-emr-on-eks
echo $AWS_REGION
````

The script install CLI tools, creates a new EKS cluster, enables EMR on EKS, and installs Karpenter.
```bash
./install_cli.sh
./provision/create-workshop-env.sh $AWS_REGION
```

## 2. Build a custom docker image
While the environment setup is still running, let's build a custom EMR on EKS docker image via the ["workshop-ide" in AWS Cloud9](https://console.aws.amazon.com/cloud9).
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
docker logout public.ecr.aws
docker pull public.ecr.aws/myang-poc/benchmark:emr6.5
# tag image
docker tag public.ecr.aws/myang-poc/benchmark:emr6.5 $ECR_URL/eks-spark-benchmark:emr6.5 
# push
docker push $ECR_URL/eks-spark-benchmark:emr6.5
```

## 3. Test with sample Spark jobs
To analyse the autoscaling performance, we use [Amazon Managed Service for Prometheus (AMP)](https://aws.amazon.com/prometheus/) to ingest Spark metrics and use an [Amazon Managed Grafana](https://aws.amazon.com/grafana/) dashboard to visualize. 

**Download the [Grafana setup](./setup_grafana_dashboard.pdf) instruction to get your dashboard ready. Ensure you have pushed the download button from the github. The dashbaord template file can be found in the [Data on EKS project](https://raw.githubusercontent.com/awslabs/data-on-eks/main/analytics/terraform/emr-eks-karpenter/emr-grafana-dashboard/emr-eks-grafana-dashboard.json)**

To monitor the autoscaling status in real time, go to your [AWS CloudShell](https://us-east-1.console.aws.amazon.com/cloudshell?region=us-east-1). Click on the "Actions" button -> select "New tab" twice. Note: the default region is `us-east-1`. **Change it on the CloudShell console if necessary**.

Watch a job pod's autoscaling status in a command line window (nothing returns at the start):
```bash
watch -n1 "kubectl get pod -n emr"
```
Observe EC2/node autoscaling status in a 2nd tab. By design, Cluster Autoscaler schedules EC2/node in ZONE "b" , and Karpenter schedules ZONE "a" node.
```bash
watch -n1 "kubectl get node --label-columns=node.kubernetes.io/instance-type,karpenter.sh/capacity-type,eks.amazonaws.com/capacityType,topology.kubernetes.io/zone,app"
```
Submit jobs in a 3rd window. The suffix 'ca' represents Cluster Autoscaler. 
We have two types of Spark test jobs:
- [wordcount app with 2 executors](example/sample-job-karpenter.sh): read from EMR on EKS sample S3 bucket in your region and output the newly created S3 bucket.
- [SparkSQL benchmark app with 47 executors](example/emr6.5-benchmark-karpenter.sh): source data is in `us-east-1` and the benchmark result will output to a newly created S3.
```bash
cd karpenter-emr-on-eks
./install_cli.sh
```
```bash
# run a job on existing nodes. No autoscaling is triggered at the node level.
./example/sample-job-ca.sh
./example/sample-job-karpenter.sh
```
Monitor the job progress in your pod's autoscaling status window. 

Submit a medium size job (47 executors) once the previous job is completed.
```bash
./example/emr6.5-benchmark-ca.sh
./example/emr6.5-benchmark-karpenter.sh
```
Observe autoscaling status in real time by examining other tabs in Cloudshell. The scope of the workshop is to compare the autoscaling performance, not to benchmark a Spark job.  Check out the next section, and don't wait for the job to be finished. 

<!-- (OPTINAL) Submit the same job again while the first pair is still running, in order to force exceeding the max Spot instance limit in your account. Observe which scaling tool has a better performance in this case.
```bash
./example/emr6.5-benchmark-ca.sh
./example/emr6.5-benchmark-karpenter.sh
```-->

## 4. Observe in Grafana Dashboard
Go to [Amazon Grafana console](https://us-east-1.console.aws.amazon.com/grafana/home?region=us-east-1#/workspaces), and open the EMR on EKS dashboard created earlier. The metrics may take 1 minute to show up after a job is submitted.

Expand the first graph `Pod State Timelines`, choose different ids (EMR on EKS job ID) from the Job ID dropdown list. Let's observe the job spin-up time and node autoscaling performance. You can locate Job IDs from your [EMR console](https://console.aws.amazon.com/elasticmapreduce/home?region=us-east-1#virtual-cluster-list:).

To learn how to read the graph, check out the `Appendix section` at the end of the [Grafana setup instruction](./setup_grafana_dashboard.pdf).

<!-- ## 5. Setup EMR studio with EMR on EKS (coming soon)
Run the script in [AWS CloudShell](https://us-east-1.console.aws.amazon.com/cloudshell?region=us-east-1).

```bash
sudo yum install -y openssl
./provision/create-studio-endpoint.sh
```` -->

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
