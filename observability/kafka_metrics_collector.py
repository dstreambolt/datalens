#!/usr/bin/env python3
"""
Kafka Metrics Collector for DStreamBolt
Collects topic, consumer lag, and broker metrics every minute
Deploy this on the Kafka node (10.0.10.101)
"""
import subprocess
import json
import pymysql
from datetime import datetime
import time
import os
import sys

# Configuration
KAFKA_HOME = os.getenv('KAFKA_HOME', '/opt/kafka')
KAFKA_BROKER = os.getenv('KAFKA_BROKER', 'localhost:9092')
MYSQL_HOST = os.getenv('MYSQL_HOST', '10.0.1.61')
MYSQL_USER = os.getenv('MYSQL_USER', 'dstreambolt')
MYSQL_PASS = os.getenv('MYSQL_PASS', 'DStreamBolt2025!')
MYSQL_DB = os.getenv('MYSQL_DB', 'dstreambolt_metrics')
COLLECTION_INTERVAL = int(os.getenv('COLLECTION_INTERVAL', '60'))  # seconds

def get_db_connection():
    """Get MySQL connection"""
    try:
        return pymysql.connect(
            host=MYSQL_HOST,
            user=MYSQL_USER,
            password=MYSQL_PASS,
            database=MYSQL_DB,
            autocommit=True
        )
    except Exception as e:
        print(f"❌ MySQL connection failed: {e}")
        return None

def collect_topic_metrics():
    """Collect metrics for all Kafka topics"""
    try:
        # List all topics
        result = subprocess.run(
            [f"{KAFKA_HOME}/bin/kafka-topics.sh",
             "--bootstrap-server", KAFKA_BROKER,
             "--list"],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            print(f"⚠️  Failed to list topics: {result.stderr}")
            return 0

        topics = [t.strip() for t in result.stdout.strip().split('\n') if t.strip()]

        if not topics:
            print("ℹ️  No topics found")
            return 0

        conn = get_db_connection()
        if not conn:
            return 0

        cursor = conn.cursor()
        topics_collected = 0

        for topic in topics:
            try:
                # Get topic description
                result = subprocess.run(
                    [f"{KAFKA_HOME}/bin/kafka-topics.sh",
                     "--bootstrap-server", KAFKA_BROKER,
                     "--describe",
                     "--topic", topic],
                    capture_output=True,
                    text=True,
                    timeout=10
                )

                if result.returncode != 0:
                    continue

                # Parse partition count
                lines = result.stdout.strip().split('\n')
                partition_count = len([l for l in lines if 'Partition:' in l or '\tPartition:' in l])

                # Get replication factor from first partition line
                replication_factor = 1
                for line in lines:
                    if 'ReplicationFactor:' in line:
                        parts = line.split('ReplicationFactor:')
                        if len(parts) > 1:
                            try:
                                replication_factor = int(parts[1].split()[0])
                            except:
                                pass
                        break

                # Insert metrics
                cursor.execute("""
                    INSERT INTO kafka_topic_metrics 
                    (topic, partition_count, replication_factor)
                    VALUES (%s, %s, %s)
                """, (topic, partition_count, replication_factor))

                topics_collected += 1

            except Exception as e:
                print(f"⚠️  Failed to collect metrics for topic {topic}: {e}")
                continue

        conn.close()
        print(f"✅ Collected metrics for {topics_collected}/{len(topics)} topics")
        return topics_collected

    except Exception as e:
        print(f"❌ Failed to collect topic metrics: {e}")
        return 0

def collect_consumer_lag():
    """Collect consumer lag metrics for all consumer groups"""
    try:
        # List all consumer groups
        result = subprocess.run(
            [f"{KAFKA_HOME}/bin/kafka-consumer-groups.sh",
             "--bootstrap-server", KAFKA_BROKER,
             "--list"],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            print(f"⚠️  Failed to list consumer groups: {result.stderr}")
            return 0

        groups = [g.strip() for g in result.stdout.strip().split('\n') if g.strip()]

        if not groups:
            print("ℹ️  No consumer groups found")
            return 0

        conn = get_db_connection()
        if not conn:
            return 0

        cursor = conn.cursor()
        lag_records = 0

        for group in groups:
            try:
                # Get group details
                result = subprocess.run(
                    [f"{KAFKA_HOME}/bin/kafka-consumer-groups.sh",
                     "--bootstrap-server", KAFKA_BROKER,
                     "--describe",
                     "--group", group],
                    capture_output=True,
                    text=True,
                    timeout=10
                )

                if result.returncode != 0:
                    continue

                lines = result.stdout.strip().split('\n')

                # Skip header line
                for line in lines[1:]:
                    parts = line.split()

                    # Expected format: GROUP TOPIC PARTITION CURRENT-OFFSET LOG-END-OFFSET LAG ...
                    if len(parts) >= 6:
                        try:
                            topic = parts[1]
                            partition = int(parts[2])
                            current_offset = int(parts[3]) if parts[3].isdigit() else 0
                            log_end_offset = int(parts[4]) if parts[4].isdigit() else 0
                            lag = int(parts[5]) if parts[5].isdigit() else 0

                            cursor.execute("""
                                INSERT INTO kafka_consumer_lag
                                (consumer_group, topic, partition_id, current_offset, log_end_offset, lag)
                                VALUES (%s, %s, %s, %s, %s, %s)
                            """, (group, topic, partition, current_offset, log_end_offset, lag))

                            lag_records += 1

                        except (ValueError, IndexError) as e:
                            continue

            except Exception as e:
                print(f"⚠️  Failed to collect lag for group {group}: {e}")
                continue

        conn.close()
        print(f"✅ Collected {lag_records} lag records from {len(groups)} consumer groups")
        return lag_records

    except Exception as e:
        print(f"❌ Failed to collect consumer lag: {e}")
        return 0

def collect_broker_metrics():
    """Collect basic broker metrics"""
    try:
        conn = get_db_connection()
        if not conn:
            return 0

        cursor = conn.cursor()

        # For now, just log that broker is up
        # In production, you'd use JMX to get detailed metrics
        cursor.execute("""
            INSERT INTO kafka_broker_metrics 
            (broker_id, broker_host, active_connections)
            VALUES (%s, %s, %s)
        """, (1, KAFKA_BROKER, 1))

        conn.close()
        print("✅ Collected broker metrics")
        return 1

    except Exception as e:
        print(f"❌ Failed to collect broker metrics: {e}")
        return 0

def main():
    """Main collection loop"""
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("🔍 Kafka Metrics Collector Starting")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"Kafka Broker: {KAFKA_BROKER}")
    print(f"MySQL Host: {MYSQL_HOST}")
    print(f"Collection Interval: {COLLECTION_INTERVAL}s")
    print()

    # Test connections
    print("Testing connections...")

    # Test Kafka
    try:
        result = subprocess.run(
            [f"{KAFKA_HOME}/bin/kafka-broker-api-versions.sh",
             "--bootstrap-server", KAFKA_BROKER],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            print("✅ Kafka connection OK")
        else:
            print(f"⚠️  Kafka connection issue: {result.stderr}")
    except Exception as e:
        print(f"❌ Cannot connect to Kafka: {e}")
        sys.exit(1)

    # Test MySQL
    conn = get_db_connection()
    if conn:
        print("✅ MySQL connection OK")
        conn.close()
    else:
        print("❌ Cannot connect to MySQL")
        sys.exit(1)

    print()
    print("🚀 Starting metric collection...")
    print()

    iteration = 0

    while True:
        try:
            iteration += 1
            timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            print(f"[{timestamp}] Collection #{iteration}")
            print("─" * 50)

            # Collect all metrics
            topics = collect_topic_metrics()
            lag_records = collect_consumer_lag()
            brokers = collect_broker_metrics()

            print(f"📊 Summary: {topics} topics, {lag_records} lag records, {brokers} brokers")
            print()

            # Sleep until next collection
            time.sleep(COLLECTION_INTERVAL)

        except KeyboardInterrupt:
            print()
            print("👋 Shutting down gracefully...")
            break
        except Exception as e:
            print(f"❌ Error in collection loop: {e}")
            time.sleep(COLLECTION_INTERVAL)

if __name__ == "__main__":
    main()

