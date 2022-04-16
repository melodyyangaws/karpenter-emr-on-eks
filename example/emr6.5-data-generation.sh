#!/bin/bash

# set EMR virtual cluster name
export EMRCLUSTER_NAME=emr-on-tfc-summit2
export AWS_REGION=us-west-2

export ACCOUNTID=$(aws sts get-caller-identity --query Account --output text)                    
export VIRTUAL_CLUSTER_ID=$(aws emr-containers list-virtual-clusters --query "virtualClusters[?name == '$EMRCLUSTER_NAME' && state == 'RUNNING'].id" --output text)
export EMR_ROLE_ARN=arn:aws:iam::$ACCOUNTID:role/${EMRCLUSTER_NAME}-execution-role
export S3BUCKET=$EMRCLUSTER_NAME-$ACCOUNTID-$AWS_REGION
export ECR_URL="$ACCOUNTID.dkr.ecr.$AWS_REGION.amazonaws.com"

aws emr-containers start-job-run \
--virtual-cluster-id $VIRTUAL_CLUSTER_ID \
--name tpcds-benchmark-datagen \
--execution-role-arn $EMR_ROLE_ARN \
--release-label emr-6.5.0-latest \
--job-driver '{
  "sparkSubmitJobDriver": {
      "entryPoint": "local:///usr/lib/spark/examples/jars/eks-spark-benchmark-assembly-1.0.jar",
      "entryPointArguments":["s3://'$S3BUCKET'/BLOG_TPCDS-TEST-3T-partitioned2","/opt/tpcds-kit/tools","parquet","3000","200","true","true","true"],
      "sparkSubmitParameters": "--class com.amazonaws.eks.tpcds.DataGeneration --conf spark.driver.cores=10 --conf spark.driver.memory=10G  --conf spark.executor.cores=11 --conf spark.executor.memory=15G --conf spark.executor.instances=26"}}' \
--configuration-overrides '{
    "applicationConfiguration": [
      {
        "classification": "spark-defaults", 
        "properties": {
          "spark.kubernetes.container.image": "public.ecr.aws/myang-poc/benchmark:6.5",
          "spark.network.timeout": "2000s",
          "spark.executor.heartbeatInterval": "300s",
          "spark.sql.files.maxRecordsPerFile": "30000000",
          "spark.kubernetes.driver.limit.cores": "10.1",
          "spark.kubernetes.executor.limit.cores": "11.1",
          "spark.kubernetes.memoryOverheadFactor": "0.3",
              
          "spark.kubernetes.executor.podNamePrefix": "emr-eks-tpcds-generate-data",
          "spark.serializer": "org.apache.spark.serializer.KryoSerializer",
          "spark.executor.defaultJavaOptions": "-verbose:gc -XX:+UseG1GC",
          "spark.driver.defaultJavaOptions": "-XX:+UseG1GC"
        }}
    ], 
    "monitoringConfiguration": {
      "s3MonitoringConfiguration": {"logUri": "s3://'$S3BUCKET'/elasticmapreduce/emr-containers"}}}'