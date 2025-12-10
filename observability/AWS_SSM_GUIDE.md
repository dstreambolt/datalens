# AWS SSM Quick Reference for DStreamBolt

## 🔐 Why AWS SSM Instead of SSH?

**Benefits:**
- ✅ No SSH keys needed
- ✅ No open SSH ports (port 22)
- ✅ Session activity logged in CloudTrail
- ✅ Works with private instances
- ✅ Better security compliance

## 📋 Prerequisites

### 1. Install AWS Session Manager Plugin

**macOS:**
```bash
# Using Homebrew
brew install --cask session-manager-plugin

# OR manual download
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip" -o "sessionmanager-bundle.zip"
unzip sessionmanager-bundle.zip
sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin
```

**Verify Installation:**
```bash
session-manager-plugin
# Should show: The Session Manager plugin is installed successfully!
```

### 2. Ensure Instance Has SSM Agent

All AWS instances should have SSM agent pre-installed. If not:

```bash
# Ubuntu/Debian
sudo snap install amazon-ssm-agent --classic
sudo systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
sudo systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
```

### 3. IAM Role for EC2

Instance must have IAM role with policy: `AmazonSSMManagedInstanceCore`

Check if instance is registered:
```bash
aws ssm describe-instance-information \
    --region ap-south-1 \
    --filters "Key=InstanceIds,Values=i-0bdf20dd0b5e1cc81"
```

## 🚀 Common Commands

### Connect to Kafka Instance
```bash
aws ssm start-session \
    --target i-0bdf20dd0b5e1cc81 \
    --region ap-south-1
```

### Run Single Command
```bash
aws ssm send-command \
    --region ap-south-1 \
    --instance-ids i-0bdf20dd0b5e1cc81 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo systemctl status kafka-metrics-collector"]' \
    --output text
```

### Copy File via S3
```bash
# Upload to S3
aws s3 cp local_file.py s3://temp-bucket/local_file.py --region ap-south-1

# Download on instance
aws ssm send-command \
    --region ap-south-1 \
    --instance-ids i-0bdf20dd0b5e1cc81 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["aws s3 cp s3://temp-bucket/local_file.py /opt/"]'
```

### Get Command Output
```bash
# Send command and get command ID
COMMAND_ID=$(aws ssm send-command \
    --region ap-south-1 \
    --instance-ids i-0bdf20dd0b5e1cc81 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["uptime"]' \
    --query "Command.CommandId" \
    --output text)

# Wait a moment
sleep 2

# Get output
aws ssm get-command-invocation \
    --region ap-south-1 \
    --command-id $COMMAND_ID \
    --instance-id i-0bdf20dd0b5e1cc81 \
    --query "StandardOutputContent" \
    --output text
```

## 🎯 DStreamBolt Specific Commands

### Check Kafka Collector Status
```bash
aws ssm send-command \
    --region ap-south-1 \
    --instance-ids i-0bdf20dd0b5e1cc81 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo systemctl status kafka-metrics-collector --no-pager"]' \
    --output text
```

### View Collector Logs
```bash
# Start SSM session first
aws ssm start-session --target i-0bdf20dd0b5e1cc81 --region ap-south-1

# Then in session:
tail -f /var/log/dstreambolt/kafka-metrics.log
```

### Restart Collector
```bash
aws ssm send-command \
    --region ap-south-1 \
    --instance-ids i-0bdf20dd0b5e1cc81 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo systemctl restart kafka-metrics-collector"]'
```

### Check Kafka is Running
```bash
aws ssm send-command \
    --region ap-south-1 \
    --instance-ids i-0bdf20dd0b5e1cc81 \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=[
        "sudo systemctl status kafka --no-pager",
        "/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list"
    ]'
```

## 🔍 Troubleshooting SSM

### "TargetNotConnected" Error
```bash
# Check instance is online
aws ssm describe-instance-information \
    --region ap-south-1 \
    --filters "Key=InstanceIds,Values=i-0bdf20dd0b5e1cc81"

# Check SSM agent on instance
sudo systemctl status snap.amazon-ssm-agent.amazon-ssm-agent
```

### "AccessDenied" Error
- Check your AWS credentials: `aws sts get-caller-identity`
- Verify instance has SSM IAM role
- Check IAM policy includes `ssm:StartSession`

### Instance Not Appearing in SSM
1. Install/restart SSM agent on instance
2. Attach IAM role with `AmazonSSMManagedInstanceCore`
3. Wait 5-10 minutes for registration
4. Check agent logs: `/var/log/amazon/ssm/amazon-ssm-agent.log`

## 📚 Useful SSM Documents

- `AWS-RunShellScript` - Run shell commands
- `AWS-InstallApplication` - Install software
- `AWS-ConfigureAWSPackage` - Install AWS packages
- `AWS-UpdateSSMAgent` - Update SSM agent

## 🔗 Resources

- [Install Session Manager Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- [SSM Agent Installation](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-install-ssm-agent.html)
- [IAM Permissions for SSM](https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-create-iam-instance-profile.html)

---

**For DStreamBolt deployment, see:** `DEPLOYMENT_INSTRUCTIONS.md`

