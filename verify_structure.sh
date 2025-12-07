#!/bin/bash

# DStreamBolt Repository Structure Verification Script
# Verifies the reorganized structure is complete and correct

set -e

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   DStreamBolt Repository Structure Verification               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

# Function to check if file/directory exists
check_exists() {
    if [ -e "$1" ]; then
        echo -e "${GREEN}✓${NC} $1"
    else
        echo -e "${RED}✗${NC} $1 (MISSING)"
        ((ERRORS++))
    fi
}

# Function to check file size
check_file_size() {
    if [ -f "$1" ]; then
        SIZE=$(wc -l < "$1" 2>/dev/null || echo "0")
        if [ "$SIZE" -gt "$2" ]; then
            echo -e "${GREEN}✓${NC} $1 (${SIZE} lines)"
        else
            echo -e "${YELLOW}⚠${NC} $1 (${SIZE} lines - expected > $2)"
        fi
    else
        echo -e "${RED}✗${NC} $1 (NOT FOUND)"
        ((ERRORS++))
    fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. ROOT STRUCTURE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_exists "README.md"
check_exists ".gitignore"
check_exists "REORGANIZATION_SUMMARY.md"
check_exists "ingestion"
check_exists "computations"
check_exists "terraform"
check_exists "examples"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. INGESTION DIRECTORY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_file_size "ingestion/app.py" 200
check_file_size "ingestion/README.md" 100
check_exists "ingestion/requirements.txt"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. COMPUTATIONS DIRECTORY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_file_size "computations/spark_processor.py" 200
check_file_size "computations/README.md" 100
check_exists "computations/requirements.txt"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. TERRAFORM DIRECTORY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_exists "terraform/main.tf"
check_exists "terraform/terraform.tfvars"
check_exists "terraform/deploy.sh"
check_file_size "terraform/README.md" 100
check_exists "terraform/modules"
check_exists "terraform/user_data"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. TERRAFORM MODULES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_exists "terraform/modules/networking"
check_exists "terraform/modules/ingest"
check_exists "terraform/modules/kafka"
check_exists "terraform/modules/compute"
check_exists "terraform/modules/devops"
check_exists "terraform/modules/alb"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. USER DATA SCRIPTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_file_size "terraform/user_data/ingest.sh" 50
check_file_size "terraform/user_data/kafka.sh" 50
check_file_size "terraform/user_data/compute.sh" 50
check_file_size "terraform/user_data/devops.sh" 50
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "7. EXAMPLES DIRECTORY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_exists "examples/01-generate-logs.py"
check_exists "examples/02-send-to-ingest.py"
check_exists "examples/03-kafka-consumer.py"
check_exists "examples/04-spark-processor.py"
check_file_size "examples/README.md" 200
check_exists "examples/requirements.txt"
check_exists "examples/grafana-dashboard.json"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "8. PYTHON SYNTAX CHECK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_python_syntax() {
    if python3 -m py_compile "$1" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $1 (valid syntax)"
    else
        echo -e "${RED}✗${NC} $1 (syntax error)"
        ((ERRORS++))
    fi
}

check_python_syntax "ingestion/app.py"
check_python_syntax "computations/spark_processor.py"
check_python_syntax "examples/01-generate-logs.py"
check_python_syntax "examples/02-send-to-ingest.py"
check_python_syntax "examples/03-kafka-consumer.py"
check_python_syntax "examples/04-spark-processor.py"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "9. DOCUMENTATION COMPLETENESS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

count_lines() {
    wc -l < "$1" 2>/dev/null || echo "0"
}

ROOT_README=$(count_lines "README.md")
INGESTION_README=$(count_lines "ingestion/README.md")
COMPUTATIONS_README=$(count_lines "computations/README.md")
TERRAFORM_README=$(count_lines "terraform/README.md")
EXAMPLES_README=$(count_lines "examples/README.md")

TOTAL_DOCS=$((ROOT_README + INGESTION_README + COMPUTATIONS_README + TERRAFORM_README + EXAMPLES_README))

echo "Root README:        ${ROOT_README} lines"
echo "Ingestion README:   ${INGESTION_README} lines"
echo "Computations README: ${COMPUTATIONS_README} lines"
echo "Terraform README:   ${TERRAFORM_README} lines"
echo "Examples README:    ${EXAMPLES_README} lines"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TOTAL DOCUMENTATION: ${TOTAL_DOCS} lines"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "10. SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ ALL CHECKS PASSED!${NC}"
    echo ""
    echo "Repository structure is complete and correct."
    echo "Total documentation: ${TOTAL_DOCS} lines"
    echo ""
    echo "Next steps:"
    echo "  1. Review the structure: ls -la"
    echo "  2. Read REORGANIZATION_SUMMARY.md"
    echo "  3. Deploy: cd terraform && ./deploy.sh"
    exit 0
else
    echo -e "${RED}✗ FOUND ${ERRORS} ERROR(S)${NC}"
    echo ""
    echo "Please review the errors above and fix them."
    exit 1
fi

