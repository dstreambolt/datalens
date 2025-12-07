# DStreamBolt Terraform Infrastructure

Infrastructure as Code (IaC) for the DStreamBolt real-time data processing platform.

## 📁 Structure

```
terraform/
├── main.tf                 # Root Terraform configuration
├── terraform.tfvars        # Variable values (customize this)
├── deploy.sh               # Automated deployment script
├── .terraform/             # Terraform plugins and state
├── .terraform.lock.hcl     # Dependency lock file
├── terraform.tfstate       # Current infrastructure state
├── modules/                # Reusable infrastructure modules
│   ├── networking/         # VPC, subnets, security groups
│   ├── ingest/             # Ingestion instance
│   ├── kafka/              # Kafka broker instance
│   ├── compute/            # Spark cluster instance
│   ├── devops/             # DevOps tools instance
│   └── alb/                # Application Load Balancer
└── user_data/              # EC2 initialization scripts
    ├── ingest.sh           # Ingestion service setup
    ├── kafka.sh            # Kafka broker setup
    ├── compute.sh          # Spark cluster setup
    └── devops.sh           # Jenkins, Grafana, AKHQ, MySQL
```

## 🚀 Quick Start

### Prerequisites

- AWS CLI configured with credentials
- Terraform v1.13.5 or later
- SSH key pair at `~/dstreambolt-access-key.pem`

### Deploy

```bash
# 1. Navigate to terraform directory
cd terraform

# 2. Initialize Terraform
terraform init

# 3. Review and customize terraform.tfvars
vim terraform.tfvars

# 4. Plan deployment
terraform plan -out=tfplan

# 5. Deploy (takes ~15-20 minutes)
terraform apply tfplan
```

**Or use automated script:**
```bash
./deploy.sh
```

## 📝 Configuration

### terraform.tfvars

Edit this file to customize your deployment:

```hcl
# Project Configuration
project_name = "dstreambolt"
environment  = "production"
aws_region   = "ap-south-1"

# SSH Access
key_name = "dstreambolt-access-key"

# Instance Types (use t3.micro for free tier)
instance_type_ingest  = "t3.micro"
instance_type_kafka   = "t3.micro"
instance_type_compute = "t3.micro"
instance_type_devops  = "t3.small"  # Needs more resources

# Database
mysql_root_password = "YourSecurePassword123!"

# Networking
vpc_cidr = "10.0.0.0/16"
availability_zones = ["ap-south-1a", "ap-south-1b"]

# Domain (optional)
# domain = "dstreambolt.example.com"
```

## 🏗️ Modules

### 1. Networking Module

**Location**: `modules/networking/`

Creates the network foundation:
- VPC with public and private subnets
- Internet Gateway and NAT Gateway
- Security groups for all services
- Route tables

**Outputs:**
- `vpc_id`
- `public_subnet_ids`
- `private_subnet_ids`
- `security_group_ids`

### 2. Ingestion Module

**Location**: `modules/ingest/`

Deploys the ingestion service:
- EC2 instance in public subnet
- Flask application with mTLS
- Kafka producer
- MySQL metrics tracking

**User Data**: `user_data/ingest.sh`

### 3. Kafka Module

**Location**: `modules/kafka/`

Deploys Kafka broker:
- EC2 instance in private subnet
- Kafka broker + ZooKeeper
- Topic auto-creation enabled

**User Data**: `user_data/kafka.sh`

### 4. Compute Module

**Location**: `modules/compute/`

Deploys Spark cluster:
- EC2 instance in private subnet
- Spark Master + Worker (same node)
- History Server

**User Data**: `user_data/compute.sh`

### 5. DevOps Module

**Location**: `modules/devops/`

Deploys DevOps tools:
- EC2 instance in public subnet
- Jenkins (port 8081)
- AKHQ Kafka Manager (port 8080)
- Grafana (port 3000)
- MySQL database (port 3306)

**User Data**: `user_data/devops.sh`

### 6. ALB Module

**Location**: `modules/alb/`

Application Load Balancer:
- HTTPS listener with mTLS
- Target groups for all services
- Health checks
- Custom landing page

## 📤 Outputs

After deployment, Terraform provides:

```bash
# Get all outputs
terraform output

# Get specific output
terraform output alb_url
terraform output -json credentials
```

**Key Outputs:**
- `alb_url` - Load Balancer URL
- `landing_page_url` - Landing page
- `service_endpoints` - All service URLs
- `direct_access` - Direct instance IPs
- `credentials` - Login credentials (sensitive)

## 🔄 Common Operations

### View Current State

```bash
terraform show
terraform state list
```

### Update Infrastructure

```bash
# Make changes to .tf files
terraform plan
terraform apply
```

### Destroy Specific Resource

```bash
terraform destroy -target=module.ingest
```

### Import Existing Resources

```bash
terraform import module.ingest.aws_instance.ingest i-1234567890abcdef0
```

### Refresh State

```bash
terraform refresh
```

## 🐛 Troubleshooting

### Terraform Init Fails

```bash
# Clear cache and reinitialize
rm -rf .terraform
terraform init
```

### State Lock Error

```bash
# If you're sure no one else is running Terraform:
terraform force-unlock <lock-id>
```

### Resource Already Exists

```bash
# Import existing resource
terraform import <resource_address> <resource_id>

# Or remove from state and recreate
terraform state rm <resource_address>
terraform apply
```

### Apply Fails Midway

```bash
# Review what was created
terraform state list

# Continue from where it failed
terraform apply
```

## 🔐 Security

### Sensitive Data

**Never commit these files:**
- `terraform.tfvars` (contains passwords)
- `terraform.tfstate` (contains sensitive data)
- `*.pem` (SSH keys)
- `.terraform/` (plugins and cache)

**Add to .gitignore:**
```
*.tfstate
*.tfstate.backup
*.tfvars
.terraform/
*.pem
tfplan
```

### Secrets Management

Sensitive values are stored in:
- AWS Secrets Manager (certificates, passwords)
- Terraform state (encrypted recommended)

### Best Practices

1. Use remote state with S3 + DynamoDB locking
2. Enable state encryption
3. Use IAM roles instead of access keys
4. Rotate credentials regularly
5. Enable CloudTrail for audit logs

## 📊 Cost Estimation

Before applying:

```bash
# Use Terraform Cloud or Infracost
terraform plan -out=tfplan
infracost breakdown --path=tfplan
```

**Current Setup:**
- 4 EC2 instances (t3.micro + t3.small): ~$15-20/month
- ALB: ~$16/month
- NAT Gateway: ~$32/month
- **Total: ~$60-70/month**

**Free Tier Eligible:**
- 3 x t3.micro instances: $0/month (12 months free)
- Reduces cost to ~$50/month

## 🔄 CI/CD Integration

### GitHub Actions

```yaml
name: Terraform Deploy

on:
  push:
    branches: [main]
    paths:
      - 'terraform/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: hashicorp/setup-terraform@v2
      
      - name: Terraform Init
        run: terraform init
        working-directory: ./terraform
      
      - name: Terraform Plan
        run: terraform plan
        working-directory: ./terraform
      
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: terraform apply -auto-approve
        working-directory: ./terraform
```

### Jenkins Pipeline

```groovy
pipeline {
    agent any
    stages {
        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    sh 'terraform init'
                }
            }
        }
        stage('Terraform Plan') {
            steps {
                dir('terraform') {
                    sh 'terraform plan -out=tfplan'
                }
            }
        }
        stage('Terraform Apply') {
            steps {
                dir('terraform') {
                    sh 'terraform apply tfplan'
                }
            }
        }
    }
}
```

## 📚 Additional Resources

- [Terraform Documentation](https://www.terraform.io/docs)
- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Best Practices Guide](https://www.terraform-best-practices.com/)

## 🆘 Support

For issues:
1. Check Terraform logs
2. Review AWS Console
3. Verify credentials and permissions
4. Check module documentation

## 📄 License

Part of DStreamBolt Platform

---

**Maintained by**: DStreamBolt Team  
**Last Updated**: December 7, 2025

