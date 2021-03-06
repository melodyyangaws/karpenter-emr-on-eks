export VIRTUAL_CLUSTER_ID=$(aws emr-containers list-virtual-clusters --query "virtualClusters[?name == '$EMRCLUSTER_NAME' && state == 'RUNNING'].id" --output text)
export EMR_ROLE_ARN=arn:aws:iam::$ACCOUNTID:role/$EMRCLUSTER_NAME-execution-role

aws emr-containers start-job-run \
  --virtual-cluster-id ${VIRTUAL_CLUSTER_ID} \
  --name sample-on-ca \
  --execution-role-arn ${EMR_ROLE_ARN} \
  --release-label emr-6.5.0-latest \
  --job-driver '{
  "sparkSubmitJobDriver": {
    "entryPoint": "s3://'$AWS_REGION'.elasticmapreduce/emr-containers/samples/wordcount/scripts/wordcount.py",
    "entryPointArguments": ["s3://'${S3BUCKET}'/wordcount_output_ca"],
    "sparkSubmitParameters": "--conf spark.executor.instances=2 --conf spark.executor.memory=2G --conf spark.executor.cores=1 --conf spark.driver.cores=1"
  }}' \
  --configuration-overrides '{
  "applicationConfiguration": [
      {
        "classification": "spark-defaults",
        "properties": {
          "spark.kubernetes.node.selector.app": "caspark",
          "spark.kubernetes.node.selector.topology.kubernetes.io/zone": "'${AWS_REGION}'b",

          "spark.ui.prometheus.enabled":"true",
          "spark.executor.processTreeMetrics.enabled":"true",
          "spark.kubernetes.driver.annotation.prometheus.io/scrape":"true",
          "spark.kubernetes.driver.annotation.prometheus.io/path":"/metrics/executors/prometheus/",
          "spark.kubernetes.driver.annotation.prometheus.io/port":"4040",
          "spark.kubernetes.driver.service.annotation.prometheus.io/scrape":"true",
          "spark.kubernetes.driver.service.annotation.prometheus.io/path":"/metrics/driver/prometheus/",
          "spark.kubernetes.driver.service.annotation.prometheus.io/port":"4040",
          "spark.metrics.conf.*.sink.prometheusServlet.class":"org.apache.spark.metrics.sink.PrometheusServlet",
          "spark.metrics.conf.*.sink.prometheusServlet.path":"/metrics/driver/prometheus/",
          "spark.metrics.conf.master.sink.prometheusServlet.path":"/metrics/master/prometheus/",
          "spark.metrics.conf.applications.sink.prometheusServlet.path":"/metrics/applications/prometheus/"
        }
    }]
  }'
