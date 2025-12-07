#!/usr/bin/env python3
"""
Kafka Consumer - Read logs from DStreamBolt Kafka topic
Demonstrates consuming and displaying logs
"""

from kafka import KafkaConsumer
import json
import sys
from datetime import datetime

def consume_logs(kafka_bootstrap, topic='dstreambolt-logs', group_id='log-consumer'):
    """
    Consume logs from Kafka topic

    Args:
        kafka_bootstrap: Kafka broker address (e.g., 10.0.10.101:9092)
        topic: Kafka topic name
        group_id: Consumer group ID
    """
    print("╔════════════════════════════════════════════════════════════════╗")
    print("║          DStreamBolt Kafka Consumer                           ║")
    print("╚════════════════════════════════════════════════════════════════╝")
    print()
    print(f"Kafka Broker: {kafka_bootstrap}")
    print(f"Topic: {topic}")
    print(f"Consumer Group: {group_id}")
    print()
    print("Connecting to Kafka...")

    try:
        consumer = KafkaConsumer(
            topic,
            bootstrap_servers=[kafka_bootstrap],
            group_id=group_id,
            auto_offset_reset='earliest',  # Start from beginning
            enable_auto_commit=True,
            value_deserializer=lambda x: x.decode('utf-8'),
            consumer_timeout_ms=10000  # Exit after 10s of no messages
        )

        print(f"✅ Connected to Kafka")
        print(f"📥 Consuming messages from topic '{topic}'...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print()

        message_count = 0

        for message in consumer:
            message_count += 1

            # Parse the log line
            log_line = message.value

            # Display message metadata
            print(f"Message #{message_count}")
            print(f"  Partition: {message.partition}")
            print(f"  Offset: {message.offset}")
            print(f"  Timestamp: {datetime.fromtimestamp(message.timestamp/1000)}")
            print(f"  Log: {log_line}")
            print()

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print(f"✅ Consumed {message_count} messages")

        consumer.close()

    except Exception as e:
        print(f"❌ Error: {e}")
        print()
        print("Troubleshooting:")
        print("  1. Is Kafka running? ssh to kafka instance and check: sudo systemctl status kafka")
        print("  2. Is the broker address correct? Check with: terraform output")
        print("  3. Can you reach Kafka? Try from DevOps instance (has network access)")
        sys.exit(1)

def tail_logs(kafka_bootstrap, topic='dstreambolt-logs', group_id='log-tailer'):
    """
    Tail logs in real-time (like 'tail -f')

    Args:
        kafka_bootstrap: Kafka broker address
        topic: Kafka topic name
        group_id: Consumer group ID
    """
    print("╔════════════════════════════════════════════════════════════════╗")
    print("║          DStreamBolt Kafka Tail (Real-time)                   ║")
    print("╚════════════════════════════════════════════════════════════════╝")
    print()
    print(f"Kafka Broker: {kafka_bootstrap}")
    print(f"Topic: {topic}")
    print()
    print("Tailing logs (Ctrl+C to stop)...")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print()

    try:
        consumer = KafkaConsumer(
            topic,
            bootstrap_servers=[kafka_bootstrap],
            group_id=group_id,
            auto_offset_reset='latest',  # Only new messages
            enable_auto_commit=True,
            value_deserializer=lambda x: x.decode('utf-8')
        )

        for message in consumer:
            timestamp = datetime.fromtimestamp(message.timestamp/1000).strftime('%Y-%m-%d %H:%M:%S')
            print(f"[{timestamp}] {message.value}")

    except KeyboardInterrupt:
        print()
        print("✅ Stopped tailing")
        consumer.close()
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Consume logs from DStreamBolt Kafka')
    parser.add_argument('--kafka', required=True, help='Kafka bootstrap server (e.g., 10.0.10.101:9092)')
    parser.add_argument('--topic', default='dstreambolt-logs', help='Kafka topic (default: dstreambolt-logs)')
    parser.add_argument('--group', default='log-consumer', help='Consumer group ID (default: log-consumer)')
    parser.add_argument('--tail', action='store_true', help='Tail mode: show only new messages (like tail -f)')

    args = parser.parse_args()

    if args.tail:
        tail_logs(args.kafka, args.topic, args.group)
    else:
        consume_logs(args.kafka, args.topic, args.group)

    print()
    print("Next step: Run Spark job to process logs (03-spark-processor.py)")

