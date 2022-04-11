export VIRTUAL_CLUSTER_ID=$(aws emr-containers list-virtual-clusters --query "virtualClusters[?name == '$EMRCLUSTER_NAME' && state == 'RUNNING'].id" --output text)
export EMR_ROLE_ARN=arn:aws:iam::$ACCOUNTID:role/$EMRCLUSTER_NAME-execution-role

aws emr-containers start-job-run \
--virtual-cluster-id ${VIRTUAL_CLUSTER_ID} \
--name sample-job \
--execution-role-arn ${EMR_ROLE_ARN} \
--release-label emr-6.5.0-latest \
--job-driver '{
  "sparkSubmitJobDriver": {
    "entryPoint": "s3://'$AWS_REGION'.elasticmapreduce/emr-containers/samples/wordcount/scripts/wordcount.py",
    "entryPointArguments": ["s3://'${S3TEST_BUCKET}'/wordcount_output"],
    "sparkSubmitParameters": "--conf spark.kubernetes.driver.label.app=spark --conf spark.kubernetes.executor.label.app=spark --conf spark.executor.instances=2 --conf spark.executor.memory=2G --conf spark.executor.cores=2 --conf spark.driver.cores=1"
  }
}'