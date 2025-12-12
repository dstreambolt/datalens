#!/bin/bash

KEY_PATH=~/dstreambolt-access-key.pem

DEVOPS="ubuntu@ec2-13-232-132-240.ap-south-1.compute.amazonaws.com"
KAFKA="ubuntu@10.0.10.101"
INGEST="ubuntu@ec2-3-109-132-244.ap-south-1.compute.amazonaws.com"
MASTER="ubuntu@ec2-15-206-123-221.ap-south-1.compute.amazonaws.com"
EXECUTOR="ubuntu@ec2-15-207-108-16.ap-south-1.compute.amazonaws.com"

case "$1" in
  devops)
    ssh -i "$KEY_PATH" $DEVOPS
    ;;
  kafka)
    ssh -i "$KEY_PATH" $KAFKA
    ;;
  ingest)
    ssh -i "$KEY_PATH" $INGEST
    ;;
  master)
    ssh -i "$KEY_PATH" $MASTER
    ;;
  executor)
    ssh -i "$KEY_PATH" $EXECUTOR
    ;;
  *)
    echo "Usage: login {devops|kafka|ingest|master|executor}"
    exit 1
    ;;
esac
