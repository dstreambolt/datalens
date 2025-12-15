#!/bin/bash

##############################################################################
# DataLens - Complete Deployment Script
# Deploys DataLens platform on Kubernetes for processing Akamai logs from S3
##############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="datalens"
AWS_REGION="${AWS_REGION:-us-east-1}"
S3_BUCKET="${S3_BUCKET:-datalens-akamai-logs}"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io/datalens}"

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_step() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    print_step "kubectl found: $(kubectl version --client --short)"

    # Check helm
    if ! command -v helm &> /dev/null; then
        print_error "helm not found. Please install Helm 3."
        exit 1
    fi
    print_step "helm found: $(helm version --short)"

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "docker not found. Please install Docker."
        exit 1
    fi
    print_step "docker found: $(docker --version)"

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_warning "aws CLI not found. S3 operations may not work."
    else
        print_step "aws CLI found: $(aws --version)"
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi
    print_step "Kubernetes cluster connection verified"
}

create_namespace() {
    print_header "Creating Namespace"

    kubectl apply -f k8s/namespace.yaml
    print_step "Namespace '${NAMESPACE}' created"
}

setup_secrets() {
    print_header "Setting Up Secrets"

    # AWS Credentials
    if [[ -z "${AWS_ACCESS_KEY_ID}" || -z "${AWS_SECRET_ACCESS_KEY}" ]]; then
        print_warning "AWS credentials not found in environment."
        read -p "Enter AWS Access Key ID: " AWS_ACCESS_KEY_ID
        read -sp "Enter AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
        echo
    fi

    kubectl create secret generic aws-credentials \
        --from-literal=access-key="${AWS_ACCESS_KEY_ID}" \
        --from-literal=secret-key="${AWS_SECRET_ACCESS_KEY}" \
        --namespace=${NAMESPACE} \
        --dry-run=client -o yaml | kubectl apply -f -

    print_step "AWS credentials configured"

    # TimescaleDB Password
    TIMESCALE_PASSWORD=$(openssl rand -base64 32)
    kubectl create secret generic timescaledb-credentials \
        --from-literal=password="${TIMESCALE_PASSWORD}" \
        --namespace=${NAMESPACE} \
        --dry-run=client -o yaml | kubectl apply -f -

    print_step "TimescaleDB credentials created"

    # Grafana Password
    GRAFANA_PASSWORD=$(openssl rand -base64 16)
    kubectl create secret generic grafana-credentials \
        --from-literal=admin-user=admin \
        --from-literal=admin-password="${GRAFANA_PASSWORD}" \
        --namespace=${NAMESPACE} \
        --dry-run=client -o yaml | kubectl apply -f -

    print_step "Grafana credentials created (user: admin, password: ${GRAFANA_PASSWORD})"
}

apply_configmaps() {
    print_header "Applying ConfigMaps"

    # Update S3 bucket in configmap
    sed -i.bak "s|datalens-akamai-logs|${S3_BUCKET}|g" k8s/configmaps.yaml
    sed -i.bak "s|us-east-1|${AWS_REGION}|g" k8s/configmaps.yaml

    kubectl apply -f k8s/configmaps.yaml
    print_step "ConfigMaps applied"

    # Restore original file
    mv k8s/configmaps.yaml.bak k8s/configmaps.yaml 2>/dev/null || true
}

install_spark_operator() {
    print_header "Installing Spark Operator"

    helm repo add spark-operator https://googlecloudplatform.github.io/spark-on-k8s-operator
    helm repo update

    helm upgrade --install spark-operator spark-operator/spark-operator \
        --namespace ${NAMESPACE} \
        --set webhook.enable=true \
        --set sparkJobNamespace=${NAMESPACE}

    print_step "Spark Operator installed"
}

deploy_kafka() {
    print_header "Deploying Kafka"

    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update

    helm upgrade --install kafka bitnami/kafka \
        --namespace ${NAMESPACE} \
        --set persistence.enabled=true \
        --set persistence.size=20Gi \
        --set replicaCount=3 \
        --set defaultReplicationFactor=2 \
        --set offsetsTopicReplicationFactor=2 \
        --set transactionStateLogReplicationFactor=2 \
        --set zookeeper.enabled=true

    print_step "Kafka cluster deployed"

    # Wait for Kafka to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kafka \
        --namespace=${NAMESPACE} --timeout=300s

    print_step "Kafka is ready"
}

deploy_timescaledb() {
    print_header "Deploying TimescaleDB"

    helm repo add timescale https://charts.timescale.com
    helm repo update

    helm upgrade --install timescaledb timescale/timescaledb-single \
        --namespace ${NAMESPACE} \
        --set persistentVolumes.data.size=50Gi \
        --set resources.requests.memory=2Gi \
        --set resources.requests.cpu=1 \
        --set secrets.credentialsSecretName=timescaledb-credentials

    print_step "TimescaleDB deployed"

    # Wait for TimescaleDB to be ready
    kubectl wait --for=condition=ready pod -l app=timescaledb \
        --namespace=${NAMESPACE} --timeout=300s

    print_step "TimescaleDB is ready"
}

deploy_minio() {
    print_header "Deploying MinIO (S3-compatible storage)"

    helm repo add minio https://charts.min.io/
    helm repo update

    helm upgrade --install minio minio/minio \
        --namespace ${NAMESPACE} \
        --set persistence.enabled=true \
        --set persistence.size=100Gi \
        --set replicas=4 \
        --set mode=distributed \
        --set resources.requests.memory=1Gi

    print_step "MinIO deployed"
}

deploy_grafana() {
    print_header "Deploying Grafana"

    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update

    helm upgrade --install grafana grafana/grafana \
        --namespace ${NAMESPACE} \
        --set persistence.enabled=true \
        --set persistence.size=10Gi \
        --set admin.existingSecret=grafana-credentials \
        --set admin.userKey=admin-user \
        --set admin.passwordKey=admin-password

    print_step "Grafana deployed"
}

build_spark_image() {
    print_header "Building Spark Docker Image"

    docker build -t ${DOCKER_REGISTRY}/spark-py:3.5.0 -f Dockerfile.spark .

    print_step "Spark image built"

    if [[ "${PUSH_IMAGES}" == "true" ]]; then
        docker push ${DOCKER_REGISTRY}/spark-py:3.5.0
        print_step "Spark image pushed to registry"
    else
        print_warning "Image not pushed. Set PUSH_IMAGES=true to push."
    fi
}

deploy_spark_jobs() {
    print_header "Deploying Spark Jobs"

    kubectl apply -f k8s/spark/spark-s3-processor.yaml

    print_step "Spark S3 Processor deployed"
}

create_kafka_topics() {
    print_header "Creating Kafka Topics"

    # Get Kafka pod name
    KAFKA_POD=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=kafka -o jsonpath='{.items[0].metadata.name}')

    # Create topics
    kubectl exec -it ${KAFKA_POD} -n ${NAMESPACE} -- kafka-topics.sh \
        --create --if-not-exists \
        --bootstrap-server localhost:9092 \
        --topic akamai-raw-logs \
        --partitions 6 \
        --replication-factor 2

    kubectl exec -it ${KAFKA_POD} -n ${NAMESPACE} -- kafka-topics.sh \
        --create --if-not-exists \
        --bootstrap-server localhost:9092 \
        --topic akamai-processed-metrics \
        --partitions 3 \
        --replication-factor 2

    kubectl exec -it ${KAFKA_POD} -n ${NAMESPACE} -- kafka-topics.sh \
        --create --if-not-exists \
        --bootstrap-server localhost:9092 \
        --topic akamai-alerts \
        --partitions 1 \
        --replication-factor 2

    print_step "Kafka topics created"
}

initialize_timescaledb() {
    print_header "Initializing TimescaleDB Schema"

    # Get TimescaleDB pod
    TIMESCALE_POD=$(kubectl get pods -n ${NAMESPACE} -l app=timescaledb -o jsonpath='{.items[0].metadata.name}')

    # Create database schema
    kubectl exec -it ${TIMESCALE_POD} -n ${NAMESPACE} -- psql -U postgres -d datalens_metrics <<EOF
-- Create extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Create main table for Akamai logs
CREATE TABLE IF NOT EXISTS akamai_logs (
    request_timestamp TIMESTAMPTZ NOT NULL,
    reqId TEXT,
    cp INTEGER,
    cliIP INET,
    statusCode INTEGER,
    bytes BIGINT,
    reqMethod TEXT,
    reqPath TEXT,
    reqHost TEXT,
    country TEXT,
    city TEXT,
    timeToFirstByte BIGINT,
    throughput BIGINT,
    cacheStatus INTEGER,
    is_error INTEGER,
    is_cache_hit INTEGER,
    processing_timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- Convert to hypertable
SELECT create_hypertable('akamai_logs', 'request_timestamp', if_not_exists => TRUE);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_akamai_country ON akamai_logs(country, request_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_akamai_status ON akamai_logs(statusCode, request_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_akamai_cache ON akamai_logs(cacheStatus, request_timestamp DESC);

-- Create continuous aggregate for hourly metrics
CREATE MATERIALIZED VIEW IF NOT EXISTS akamai_hourly_metrics
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', request_timestamp) AS hour,
    country,
    COUNT(*) as request_count,
    SUM(bytes) as total_bytes,
    AVG(timeToFirstByte) as avg_ttfb,
    AVG(throughput) as avg_throughput,
    SUM(is_error) as error_count,
    SUM(is_cache_hit) as cache_hits
FROM akamai_logs
GROUP BY hour, country;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO datalens;
EOF

    print_step "TimescaleDB schema initialized"
}

print_access_info() {
    print_header "Access Information"

    echo -e "${GREEN}Grafana:${NC}"
    echo "  kubectl port-forward svc/grafana 3000:80 -n ${NAMESPACE}"
    echo "  Then access: http://localhost:3000"
    echo "  Username: admin"
    GRAFANA_PASS=$(kubectl get secret grafana-credentials -n ${NAMESPACE} -o jsonpath='{.data.admin-password}' | base64 -d)
    echo "  Password: ${GRAFANA_PASS}"
    echo

    echo -e "${GREEN}Spark UI:${NC}"
    echo "  kubectl port-forward svc/spark-ui 4040:4040 -n ${NAMESPACE}"
    echo "  Then access: http://localhost:4040"
    echo

    echo -e "${GREEN}Kafka:${NC}"
    echo "  Internal: kafka-headless.${NAMESPACE}.svc.cluster.local:9092"
    echo

    echo -e "${GREEN}TimescaleDB:${NC}"
    echo "  Internal: timescaledb.${NAMESPACE}.svc.cluster.local:5432"
    echo "  Database: datalens_metrics"
    echo "  User: datalens"
    TIMESCALE_PASS=$(kubectl get secret timescaledb-credentials -n ${NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)
    echo "  Password: ${TIMESCALE_PASS}"
}

main() {
    echo -e "${BLUE}"
    cat << "EOF"
╔════════════════════════════════════════════════════════════════╗
║                      DataLens Deployment                       ║
║           Akamai DataStream2 Analytics Platform                ║
╚════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    check_prerequisites
    create_namespace
    setup_secrets
    apply_configmaps
    install_spark_operator
    deploy_kafka
    deploy_timescaledb
    deploy_minio
    deploy_grafana
    create_kafka_topics
    initialize_timescaledb
    build_spark_image
    deploy_spark_jobs

    print_header "Deployment Complete!"
    print_access_info

    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ DataLens platform deployed successfully!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Run main function
main "$@"

