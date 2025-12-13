#!/bin/bash
# Ensure we are in a valid directory
cd "$HOME" || exit 1

###############################################################################
# SSH Login Helper for DStreamBolt Infrastructure
# Auto-detects IPs from Terraform or uses fallback values
###############################################################################

KEY_PATH=~/dstreambolt-access-key.pem

# Try to get IPs from Terraform
TERRAFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"
if [ -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
    DEVOPS_IP=$(cd "$TERRAFORM_DIR" && terraform output -json direct_access 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('devops_ip', ''))" 2>/dev/null || echo "13.235.238.208")
    KAFKA_IP=$(cd "$TERRAFORM_DIR" && terraform output -json direct_access 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('kafka_ip', ''))" 2>/dev/null || echo "10.0.10.248")
    INGEST_IP=$(cd "$TERRAFORM_DIR" && terraform output -json direct_access 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('ingest_ip', ''))" 2>/dev/null || echo "13.232.206.53")
    SPARK_MASTER_IP=$(cd "$TERRAFORM_DIR" && terraform output -json direct_access 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('spark_master_ip', ''))" 2>/dev/null || echo "52.66.171.95")
    SPARK_EXECUTOR_IP=$(cd "$TERRAFORM_DIR" && terraform output -json direct_access 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('spark_executor_ip', ''))" 2>/dev/null || echo "65.0.74.255")
else
    # Fallback IPs
    DEVOPS_IP="13.235.238.208"
    KAFKA_IP="10.0.10.248"
    INGEST_IP="13.232.206.53"
    SPARK_MASTER_IP="52.66.171.95"
    SPARK_EXECUTOR_IP="65.0.74.255"
fi

# If no argument, show menu
if [ -z "$1" ]; then
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║      DStreamBolt Infrastructure SSH Login                     ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Usage: $0 {role}"
    echo ""
    echo "Available roles:"
    echo ""
    echo "  devops     → $DEVOPS_IP"
    echo "               Jenkins, Grafana, MySQL, AKHQ"
    echo ""
    echo "  kafka      → $KAFKA_IP (private - via devops)"
    echo "               Kafka Broker, Zookeeper"
    echo ""
    echo "  ingest     → $INGEST_IP"
    echo "               Ingestion API Service"
    echo ""
    echo "  master     → $SPARK_MASTER_IP"
    echo "               Spark Master + Worker"
    echo ""
    echo "  executor   → $SPARK_EXECUTOR_IP"
    echo "               Spark Executor"
    echo ""
    echo "Examples:"
    echo "  $0 devops"
    echo "  $0 kafka"
    echo "  $0 master"
    exit 1
fi

case "$1" in
  devops)
    echo "→ Connecting to DevOps Node ($DEVOPS_IP)..."
    HOST="ubuntu@$DEVOPS_IP"
    ;;
  kafka)
    echo "→ Connecting to Kafka Node ($KAFKA_IP) via DevOps..."
    echo "  (Kafka is in private subnet, using DevOps as jump host)"
    ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no -t ubuntu@$DEVOPS_IP \
        "ssh -i ~/dstreambolt-access-key.pem -o StrictHostKeyChecking=no ubuntu@$KAFKA_IP"
    exit $?
    ;;
  ingest)
    echo "→ Connecting to Ingestion Node ($INGEST_IP)..."
    HOST="ubuntu@$INGEST_IP"
    ;;
  master)
    echo "→ Connecting to Spark Master ($SPARK_MASTER_IP)..."
    HOST="ubuntu@$SPARK_MASTER_IP"
    ;;
  executor)
    echo "→ Connecting to Spark Executor ($SPARK_EXECUTOR_IP)..."
    HOST="ubuntu@$SPARK_EXECUTOR_IP"
    ;;
  *)
    echo "Error: Unknown role '$1'"
    echo "Run without arguments to see available roles"
    exit 1
    ;;
esac

ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no "$HOST"
