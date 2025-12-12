#!/bin/bash

###############################################################################
# DStreamBolt Infrastructure Deployment Script
# Unified deployment script for all infrastructure components
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

log_success() {
    echo -e "${GREEN}✅ ${NC}$1"
}

log_error() {
    echo -e "${RED}❌ ${NC}$1"
}

log_warning() {
    echo -e "${YELLOW}⚠️  ${NC}$1"
}

show_usage() {
    cat << EOF
╔══════════════════════════════════════════════════════════════╗
║        DStreamBolt Infrastructure Deployment                 ║
╚══════════════════════════════════════════════════════════════╝

Usage: $0 [COMMAND] [OPTIONS]

Commands:
  init              Initialize Terraform
  plan              Plan infrastructure changes
  apply             Apply infrastructure changes
  destroy           Destroy infrastructure
  output            Show Terraform outputs
  validate          Validate Terraform configuration

  deploy-ingest     Deploy ingestion service
  deploy-spark      Deploy Spark jobs

  setup-jenkins     Configure Jenkins jobs
  setup-grafana     Setup Grafana dashboards
  setup-secrets     Configure AWS Secrets Manager

  check-services    Check status of all services
  logs              View logs from services

Options:
  -h, --help        Show this help message
  -v, --verbose     Verbose output
  -y, --yes         Auto-approve (skip confirmation)

Examples:
  $0 init                    # Initialize Terraform
  $0 plan                    # Plan changes
  $0 apply -y                # Apply without confirmation
  $0 deploy-ingest          # Deploy ingestion service
  $0 check-services         # Check all service status

EOF
    exit 0
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()

    command -v terraform >/dev/null 2>&1 || missing+=("terraform")
    command -v aws >/dev/null 2>&1 || missing+=("aws")
    command -v ssh >/dev/null 2>&1 || missing+=("ssh")

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Terraform operations
terraform_init() {
    log_info "Initializing Terraform..."
    cd "$PROJECT_ROOT/terraform"
    terraform init
    log_success "Terraform initialized"
}

terraform_plan() {
    log_info "Planning infrastructure changes..."
    cd "$PROJECT_ROOT/terraform"
    terraform plan -out=tfplan
    log_success "Plan saved to tfplan"
}

terraform_apply() {
    log_info "Applying infrastructure changes..."
    cd "$PROJECT_ROOT/terraform"

    if [ "$AUTO_APPROVE" = "true" ]; then
        terraform apply -auto-approve tfplan
    else
        terraform apply tfplan
    fi

    log_success "Infrastructure deployed successfully"
}

terraform_destroy() {
    log_warning "This will destroy all infrastructure!"
    read -p "Are you sure? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        log_info "Destroy cancelled"
        exit 0
    fi

    cd "$PROJECT_ROOT/terraform"
    terraform destroy
    log_success "Infrastructure destroyed"
}

terraform_output() {
    cd "$PROJECT_ROOT/terraform"
    terraform output
}

terraform_validate() {
    log_info "Validating Terraform configuration..."
    cd "$PROJECT_ROOT/terraform"
    terraform validate
    log_success "Configuration is valid"
}

# Service operations
check_services() {
    log_info "Checking service status..."

    cd "$PROJECT_ROOT/terraform"
    DEVOPS_IP=$(terraform output -raw devops_ip 2>/dev/null || echo "")

    if [ -z "$DEVOPS_IP" ]; then
        log_error "Could not get DevOps IP from Terraform outputs"
        exit 1
    fi

    log_info "DevOps Node: $DEVOPS_IP"

    ssh -i ~/dstreambolt-access-key.pem -o StrictHostKeyChecking=no ubuntu@$DEVOPS_IP << 'EOFCHECK'
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Service Status Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

services=("jenkins" "grafana-server" "nginx" "akhq" "mysql")

for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        echo "✅ $service: Running"
    else
        echo "❌ $service: Not running"
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
EOFCHECK

    log_success "Service check complete"
}

# Main script
main() {
    if [ $# -eq 0 ]; then
        show_usage
    fi

    # Parse global options
    AUTO_APPROVE=false
    VERBOSE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -y|--yes)
                AUTO_APPROVE=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    COMMAND=$1
    shift || true

    case $COMMAND in
        init)
            check_prerequisites
            terraform_init
            ;;
        plan)
            check_prerequisites
            terraform_plan
            ;;
        apply)
            check_prerequisites
            terraform_apply
            ;;
        destroy)
            check_prerequisites
            terraform_destroy
            ;;
        output)
            terraform_output
            ;;
        validate)
            terraform_validate
            ;;
        check-services)
            check_services
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_usage
            ;;
    esac
}

main "$@"

