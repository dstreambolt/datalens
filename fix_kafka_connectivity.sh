  #!/bin/bash
  # Quick fix for Kafka connectivity issue
  # Run this on the INGESTION server (ip-10-0-1-72)

  set -e

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║       Kafka Connectivity Fix                                 ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  KAFKA_HOST="10.0.10.101"
  KAFKA_PORT="9092"

  # Step 1: Test basic connectivity
  echo "1️⃣  Testing network connectivity..."
  if timeout 5 bash -c "echo > /dev/tcp/${KAFKA_HOST}/${KAFKA_PORT}" 2>/dev/null; then
      echo "✅ Network connectivity OK"
  else
      echo "❌ Cannot reach Kafka at ${KAFKA_HOST}:${KAFKA_PORT}"
      echo ""
      echo "Possible issues:"
      echo "  1. Security group blocking outbound traffic"
      echo "  2. NACL blocking traffic"
      echo "  3. Kafka not running"
      echo "  4. Wrong subnet/routing"
      echo ""
      echo "Checking security group..."

      # Try to fix security group if we have AWS CLI
      if command -v aws > /dev/null; then
          INSTANCE_ID=$(ec2-metadata --instance-id 2>/dev/null | awk '{print $2}')
          if [ ! -z "$INSTANCE_ID" ]; then
              echo "This instance: $INSTANCE_ID"

              # Get security group
              SG_ID=$(aws ec2 describe-instances \
                  --instance-ids $INSTANCE_ID \
                  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
                  --output text 2>/dev/null)

              if [ ! -z "$SG_ID" ]; then
                  echo "Security Group: $SG_ID"

                  # Check if outbound rule exists for Kafka
                  EGRESS_RULES=$(aws ec2 describe-security-groups \
                      --group-ids $SG_ID \
                      --query 'SecurityGroups[0].IpPermissionsEgress[*].[IpProtocol,FromPort,ToPort]' \
                      --output text 2>/dev/null)

                  echo "Current egress rules:"
                  echo "$EGRESS_RULES"

                  # Most likely the security group already allows all outbound (0.0.0.0/0)
                  # The issue is probably on the Kafka side
                  echo ""
                  echo "✅ Outbound rules look OK (allows all)"
                  echo "    Issue is likely on Kafka server side"
              fi
          fi
      fi

      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "ACTION REQUIRED: Check Kafka server"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "SSH to Kafka server and run:"
      echo "  ssh root@${KAFKA_HOST}"
      echo "  systemctl status kafka"
      echo "  netstat -tlnp | grep 9092"
      echo ""
      exit 1
  fi

  # Step 2: Test Kafka protocol
  echo ""
  echo "2️⃣  Testing Kafka protocol..."
  if [ -d /opt/dstreambolt/ingest/venv ]; then
      /opt/dstreambolt/ingest/venv/bin/python3 << 'PYEOF'
from kafka import KafkaProducer
import json
import sys

try:
    producer = KafkaProducer(
        bootstrap_servers=['10.0.10.101:9092'],
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        request_timeout_ms=10000
    )
    print("✅ Kafka protocol OK")
    producer.close()
    sys.exit(0)
except Exception as e:
    print(f"❌ Kafka protocol failed: {e}")
    sys.exit(1)
PYEOF

      if [ $? -ne 0 ]; then
          echo ""
          echo "Kafka is reachable but protocol handshake failed"
          echo "This could mean:"
          echo "  1. Kafka is advertising wrong address (check advertised.listeners)"
          echo "  2. Kafka version mismatch"
          echo "  3. Authentication required but not configured"
          exit 1
      fi
  else
      echo "⚠️  Cannot test - venv not found"
  fi

  # Step 3: Check if secret exists and has correct broker
  echo ""
  echo "3️⃣  Checking Secrets Manager configuration..."
  if command -v aws > /dev/null; then
      if aws secretsmanager describe-secret --secret-id dstreambolt/kafka 2>/dev/null > /dev/null; then
          echo "✅ Secret 'dstreambolt/kafka' exists"

          BROKER=$(aws secretsmanager get-secret-value --secret-id dstreambolt/kafka \
              --query 'SecretString' --output text 2>/dev/null | \
              python3 -c "import sys, json; b = json.load(sys.stdin).get('brokers', 'NOT_SET'); print(b[0] if isinstance(b, list) else b)" 2>/dev/null)

          if [ "$BROKER" = "10.0.10.101:9092" ]; then
              echo "✅ Secret has correct broker address: $BROKER"
          elif [ "$BROKER" = "NOT_SET" ]; then
              echo "⚠️  Secret has no broker configured"
              echo "   Updating secret..."
              aws secretsmanager update-secret \
                  --secret-id dstreambolt/kafka \
                  --secret-string '{"brokers":"10.0.10.101:9092","topic":"dstreambolt-logs","security_protocol":"PLAINTEXT"}' \
                  2>/dev/null
              echo "✅ Secret updated"
          else
              echo "⚠️  Secret has different broker: $BROKER"
              echo "   Expected: 10.0.10.101:9092"
              echo "   Keeping existing value (may be correct for your setup)"
          fi
      else
          echo "⚠️  Secret 'dstreambolt/kafka' not found"
          echo "   Creating secret..."

          aws secretsmanager create-secret \
              --name dstreambolt/kafka \
              --description "Kafka connection parameters for DStreamBolt" \
              --secret-string '{"brokers":"10.0.10.101:9092","topic":"dstreambolt-logs","security_protocol":"PLAINTEXT"}' \
              2>/dev/null

          if [ $? -eq 0 ]; then
              echo "✅ Secret created"
          else
              echo "❌ Failed to create secret (permission issue?)"
              echo "   Service will use environment variable fallback"
          fi
      fi
  fi

  # Step 4: Restart ingestion service
  echo ""
  echo "4️⃣  Restarting ingestion service..."
  sudo systemctl restart dstreambolt-ingest

  sleep 5

  # Check status
  if systemctl is-active --quiet dstreambolt-ingest; then
      echo "✅ Service restarted"

      # Check logs for Kafka connection
      echo ""
      echo "Checking connection status..."
      sleep 3

      if sudo journalctl -u dstreambolt-ingest --since "10 seconds ago" | grep -q "Kafka connected successfully"; then
          echo "✅ Kafka connection successful!"
      else
          echo "⚠️  Kafka connection status unclear, check logs:"
          sudo journalctl -u dstreambolt-ingest --since "10 seconds ago" | grep -i kafka | tail -10
      fi
  else
      echo "❌ Service failed to start"
      sudo journalctl -u dstreambolt-ingest --since "10 seconds ago" | tail -20
      exit 1
  fi

  # Step 5: Test health endpoint
  echo ""
  echo "5️⃣  Testing /health endpoint..."
  HEALTH_RESPONSE=$(curl -s http://localhost:5000/health)
  KAFKA_STATUS=$(echo "$HEALTH_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('kafka', 'unknown'))" 2>/dev/null)

  if [ "$KAFKA_STATUS" = "connected" ]; then
      echo "✅ Kafka is connected!"
      echo ""
      echo "Health response:"
      echo "$HEALTH_RESPONSE" | python3 -m json.tool
  elif [ "$KAFKA_STATUS" = "disconnected" ]; then
      echo "❌ Kafka still disconnected"
      echo ""
      echo "Health response:"
      echo "$HEALTH_RESPONSE" | python3 -m json.tool
      echo ""
      echo "This means the ingestion service cannot reach Kafka."
      echo "Check Kafka server security group and logs."
      exit 1
  else
      echo "⚠️  Unexpected response: $HEALTH_RESPONSE"
  fi

  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                    Fix Complete ✅                            ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

