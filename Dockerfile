# // Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# // SPDX-License-Identifier: MIT-0

ARG SPARK_BASE_IMAGE=755674844232.dkr.ecr.us-east-1.amazonaws.com/notebook-spark/emr-6.5.0:latest

FROM $SPARK_BASE_IMAGE

USER emr-notebook
RUN source /home/emr-notebook/venv/bin/activate && \
    python3 -m pip install --upgrade pip && \
    python3 -m pip install --upgrade sagemaker
    
USER hadoop:hadoop
