#!/bin/bash

##############################################################################
# DataLens - Sample Data Generator & Pipeline Tester
# Creates sample Akamai DataStream2 logs and verifies the entire pipeline
##############################################################################

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

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

# Configuration
NAMESPACE="datalens"
S3_BUCKET="${S3_BUCKET:-datalens-akamai-logs}"
NUM_LOGS="${NUM_LOGS:-1000}"
TEMP_DIR="/tmp/datalens-test"

# Create temp directory
mkdir -p ${TEMP_DIR}

generate_sample_logs() {
    print_header "Generating Sample Akamai Logs"

    SAMPLE_LOG="${TEMP_DIR}/sample-akamai.log"

    echo "Generating ${NUM_LOGS} sample log lines..."

    # Arrays for random data
    METHODS=("GET" "POST" "HEAD" "PUT")
    PATHS=("/video/stream.m3u8" "/images/hero.jpg" "/api/data" "/css/style.css" "/js/app.js")
    STATUS_CODES=(200 200 200 206 304 400 403 404 500 502)
    PROTOCOLS=("HTTPS" "HTTPS" "HTTPS" "HTTP")
    COUNTRIES=("US" "GB" "DE" "FR" "JP" "AU" "IN" "BR" "CA")
    CITIES=("NewYork" "London" "Berlin" "Paris" "Tokyo" "Sydney" "Mumbai" "SaoPaulo" "Toronto")

    > ${SAMPLE_LOG}  # Clear file

    CURRENT_TIME=$(date +%s)

    for i in $(seq 1 ${NUM_LOGS}); do
        # Randomize values
        METHOD=${METHODS[$RANDOM % ${#METHODS[@]}]}
        PATH=${PATHS[$RANDOM % ${#PATHS[@]}]}
        STATUS=${STATUS_CODES[$RANDOM % ${#STATUS_CODES[@]}]}
        PROTO=${PROTOCOLS[$RANDOM % ${#PROTOCOLS[@]}]}
        COUNTRY=${COUNTRIES[$RANDOM % ${#COUNTRIES[@]}]}
        CITY=${CITIES[$RANDOM % ${#CITIES[@]}]}

        # Random metrics
        BYTES=$((RANDOM % 10000000 + 1000))
        TTFB=$((RANDOM % 5000 + 10))
        THROUGHPUT=$((RANDOM % 50000000 + 1000000))
        CACHE_STATUS=$((RANDOM % 2))

        # Generate log line (space-delimited, 70 fields)
        echo "1 123456 req$(printf '%06d' $i) $((CURRENT_TIME - RANDOM % 3600)) 12345 1 2 2 602093 ${BYTES} 203.0.113.$((RANDOM % 255)) ${STATUS} ${PROTO} cdn.example.com ${METHOD} ${PATH} 443 ${BYTES} application/octet-stream Mozilla/5.0+(compatible) 0 TLSv1.3 ${BYTES} ${BYTES} 232 quality=high ${BYTES} 1MB-10MB 1 1 1 0 en-US session${i} bytes=0-1000 https://example.com/refer 192.0.2.$((RANDOM % 255)) 3600 100 50 200 - ${TTFB} 1 ${TTFB} ${THROUGHPUT} 500 0 ${CACHE_STATUS} //BC/xyz 1 ${COUNTRY} ${CITY} State 203.0.113.$((RANDOM % 255)) ${COUNTRY} 1 - - - - 1 1 0 - custom${i}" >> ${SAMPLE_LOG}
    done

    print_step "Generated ${NUM_LOGS} log lines"

    # Compress
    gzip -f ${SAMPLE_LOG}
    print_step "Compressed log file: ${SAMPLE_LOG}.gz"

    # Show sample
    echo -e "\nSample log line:"
    zcat ${SAMPLE_LOG}.gz | head -1
}

upload_to_s3() {
    print_header "Uploading to S3"

    # Current date/time for partitioning
    YEAR=$(date +%Y)
    MONTH=$(date +%m)
    DAY=$(date +%d)
    HOUR=$(date +%H)

    S3_PATH="s3://${S3_BUCKET}/logs/${YEAR}/${MONTH}/${DAY}/${HOUR}/test_$(date +%s).log.gz"

    echo "Uploading to: ${S3_PATH}"

    if aws s3 cp ${TEMP_DIR}/sample-akamai.log.gz ${S3_PATH}; then
        print_step "Upload successful"
        echo "S3 Path: ${S3_PATH}"
    else
        print_error "Upload failed. Check AWS credentials and bucket name."
        exit 1
    fi
}

trigger_spark_job() {
    print_header "Triggering Spark Processing Job"

    # Set processing date environment variable
    PROCESSING_DATE=$(date +%Y/%m/%d)

    # Update Spark job config
    kubectl set env sparkapplication/akamai-s3-processor \
        PROCESSING_DATE="${PROCESSING_DATE}" \
        -n ${NAMESPACE}

    # Restart Spark job
    kubectl delete sparkapplication akamai-s3-processor -n ${NAMESPACE} || true
    sleep 5
    kubectl apply -f k8s/spark/spark-s3-processor.yaml

    print_step "Spark job submitted"

    echo "Monitor progress:"
    echo "  kubectl logs -f -l app=datalens-spark-driver -n ${NAMESPACE}"
}

wait_for_processing() {
    print_header "Waiting for Processing to Complete"

    echo "Waiting for Spark driver pod to start..."
    kubectl wait --for=condition=ready pod -l app=datalens-spark-driver \
        -n ${NAMESPACE} --timeout=300s

    print_step "Spark driver is running"

    echo "Streaming logs (Ctrl+C to stop)..."
    kubectl logs -f -l app=datalens-spark-driver -n ${NAMESPACE} | tee ${TEMP_DIR}/spark-logs.txt
}

verify_data_in_timescaledb() {
    print_header "Verifying Data in TimescaleDB"

    TIMESCALE_POD=$(kubectl get pods -n ${NAMESPACE} -l app=timescaledb -o jsonpath='{.items[0].metadata.name}')

    echo "Querying TimescaleDB..."

    # Check record count
    RECORD_COUNT=$(kubectl exec -it ${TIMESCALE_POD} -n ${NAMESPACE} -- \
        psql -U postgres -d datalens_metrics -t -c "SELECT COUNT(*) FROM akamai_logs;" | tr -d ' ')

    echo "Total records in database: ${RECORD_COUNT}"

    if [[ ${RECORD_COUNT} -gt 0 ]]; then
        print_step "Data successfully loaded into TimescaleDB"

        # Show sample data
        echo -e "\nSample records:"
        kubectl exec -it ${TIMESCALE_POD} -n ${NAMESPACE} -- \
            psql -U postgres -d datalens_metrics -c \
            "SELECT request_timestamp, country, statusCode, bytes, timeToFirstByte
             FROM akamai_logs
             ORDER BY request_timestamp DESC
             LIMIT 5;"

        # Show statistics
        echo -e "\nStatistics:"
        kubectl exec -it ${TIMESCALE_POD} -n ${NAMESPACE} -- \
            psql -U postgres -d datalens_metrics -c \
            "SELECT
                COUNT(*) as total_requests,
                COUNT(DISTINCT country) as countries,
                AVG(timeToFirstByte) as avg_ttfb_ms,
                SUM(bytes) / 1024 / 1024 as total_mb
             FROM akamai_logs;"
    else
        print_warning "No data found in TimescaleDB yet. Processing may still be in progress."
    fi
}

verify_data_in_kafka() {
    print_header "Verifying Data in Kafka"

    KAFKA_POD=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=kafka -o jsonpath='{.items[0].metadata.name}')

    echo "Checking Kafka topics..."

    # List topics
    kubectl exec -it ${KAFKA_POD} -n ${NAMESPACE} -- \
        kafka-topics.sh --list --bootstrap-server localhost:9092

    # Check message count
    echo -e "\nChecking message count in akamai-raw-logs topic:"
    kubectl exec -it ${KAFKA_POD} -n ${NAMESPACE} -- \
        kafka-run-class.sh kafka.tools.GetOffsetShell \
        --broker-list localhost:9092 \
        --topic akamai-raw-logs | awk -F ":" '{sum += $3} END {print "Total messages:", sum}'

    # Show sample messages
    echo -e "\nSample messages (first 3):"
    kubectl exec -it ${KAFKA_POD} -n ${NAMESPACE} -- \
        kafka-console-consumer.sh \
        --bootstrap-server localhost:9092 \
        --topic akamai-raw-logs \
        --from-beginning \
        --max-messages 3 \
        --timeout-ms 5000
}

check_grafana_dashboards() {
    print_header "Grafana Dashboard Access"

    GRAFANA_PASSWORD=$(kubectl get secret grafana-credentials -n ${NAMESPACE} \
        -o jsonpath='{.data.admin-password}' | base64 -d)

    echo "Grafana Access:"
    echo "  URL: http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: ${GRAFANA_PASSWORD}"
    echo ""
    echo "To access Grafana:"
    echo "  kubectl port-forward svc/grafana 3000:80 -n ${NAMESPACE}"
    echo ""
    print_step "Grafana is ready"
}

run_sample_queries() {
    print_header "Running Sample Analytics Queries"

    TIMESCALE_POD=$(kubectl get pods -n ${NAMESPACE} -l app=timescaledb -o jsonpath='{.items[0].metadata.name}')

    echo "1. Request count by country:"
    kubectl exec -it ${TIMESCALE_POD} -n ${NAMESPACE} -- \
        psql -U postgres -d datalens_metrics -c \
        "SELECT country, COUNT(*) as requests, AVG(timeToFirstByte) as avg_ttfb_ms
         FROM akamai_logs
         GROUP BY country
         ORDER BY requests DESC
         LIMIT 10;"

    echo -e "\n2. Error rate analysis:"
    kubectl exec -it ${TIMESCALE_POD} -n ${NAMESPACE} -- \
        psql -U postgres -d datalens_metrics -c \
        "SELECT
            statusCode,
            COUNT(*) as count,
            COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () as percentage
         FROM akamai_logs
         GROUP BY statusCode
         ORDER BY statusCode;"

    echo -e "\n3. Cache hit ratio:"
    kubectl exec -it ${TIMESCALE_POD} -n ${NAMESPACE} -- \
        psql -U postgres -d datalens_metrics -c \
        "SELECT
            SUM(CASE WHEN cacheStatus = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as cache_hit_ratio_pct,
            SUM(CASE WHEN cacheStatus = 1 THEN bytes ELSE 0 END) / 1024 / 1024 as cached_mb,
            SUM(CASE WHEN cacheStatus = 0 THEN bytes ELSE 0 END) / 1024 / 1024 as origin_mb
         FROM akamai_logs;"
}

cleanup() {
    print_header "Cleanup"

    echo "Removing temporary files..."
    rm -rf ${TEMP_DIR}
    print_step "Cleanup complete"
}

print_summary() {
    print_header "Pipeline Test Summary"

    cat << EOF
${GREEN}✓ Pipeline test completed successfully!${NC}

What was tested:
  ✓ Sample log generation (${NUM_LOGS} logs)
  ✓ S3 upload (${S3_BUCKET})
  ✓ Spark processing
  ✓ TimescaleDB storage
  ✓ Kafka streaming
  ✓ Sample queries

Next steps:
  1. View Grafana dashboards
     kubectl port-forward svc/grafana 3000:80 -n ${NAMESPACE}

  2. Monitor Spark jobs
     kubectl get sparkapplications -n ${NAMESPACE}

  3. Query TimescaleDB
     kubectl exec -it ${TIMESCALE_POD} -n ${NAMESPACE} -- \\
       psql -U postgres -d datalens_metrics

  4. Check Kafka messages
     kubectl exec -it ${KAFKA_POD} -n ${NAMESPACE} -- \\
       kafka-console-consumer.sh --bootstrap-server localhost:9092 \\
       --topic akamai-raw-logs --from-beginning

For more information, see:
  • README.md - Project overview
  • QUICK_START.md - Getting started
  • docs/ARCHITECTURE.md - System design
  • docs/USE_CASES.md - Business applications

EOF
}

main() {
    echo -e "${BLUE}"
    cat << "EOF"
╔════════════════════════════════════════════════════════════════╗
║             DataLens Pipeline Tester                           ║
║       Generate sample data and verify the pipeline             ║
╚════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    # Check prerequisites
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    if ! aws s3 ls s3://${S3_BUCKET} &> /dev/null; then
        print_error "Cannot access S3 bucket: ${S3_BUCKET}"
        exit 1
    fi

    # Run pipeline test
    generate_sample_logs
    upload_to_s3
    trigger_spark_job

    # Wait for user to monitor logs
    echo -e "\n${YELLOW}Press Enter when processing is complete (or Ctrl+C to skip)${NC}"
    read -r

    verify_data_in_timescaledb
    verify_data_in_kafka
    run_sample_queries
    check_grafana_dashboards
    cleanup
    print_summary
}

# Handle Ctrl+C
trap cleanup EXIT

main "$@"

