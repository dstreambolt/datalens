#!/usr/bin/env python3
"""
Continuous Log Generator and Sender
Generates realistic access logs and sends them to the ingestion endpoint every 30 seconds
"""

import time
import random
import gzip
import json
import sys
import argparse
from datetime import datetime
import requests
from io import BytesIO

# Disable SSL warnings for self-signed certificates
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class LogGenerator:
    """Generate realistic web server access logs"""

    def __init__(self):
        self.ips = [
            f"{random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}"
            for _ in range(100)
        ]

        self.endpoints = [
            "/api/v1/users", "/api/v1/products", "/api/v1/orders",
            "/api/v1/auth/login", "/api/v1/auth/logout", "/api/v1/inventory",
            "/api/v1/analytics", "/api/v2/search", "/health", "/metrics",
            "/api/v1/payments", "/api/v1/shipping", "/api/v1/returns",
            "/api/v1/reviews", "/api/v1/wishlist", "/api/v1/cart"
        ]

        self.methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]

        self.user_agents = [
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            "Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15",
            "python-requests/2.26.0",
            "okhttp/4.9.0",
            "Apache-HttpClient/4.5.13"
        ]

        self.referers = [
            "https://app.example.com/dashboard",
            "https://app.example.com/products",
            "https://app.example.com/api/v1/orders",
            "https://app.example.com/api/v1/analytics",
            "https://app.example.com/api/v1/inventory",
            "-"
        ]

        self.status_distribution = {
            200: 85,  # 85% success
            201: 5,   # 5% created
            204: 2,   # 2% no content
            400: 3,   # 3% bad request
            401: 2,   # 2% unauthorized
            404: 2,   # 2% not found
            500: 1    # 1% server error
        }

    def generate_log_line(self):
        """Generate a single log line"""
        ip = random.choice(self.ips)
        timestamp = datetime.now().strftime("%d/%b/%Y:%H:%M:%S +0000")
        method = random.choice(self.methods)
        endpoint = random.choice(self.endpoints)

        # Status code based on distribution
        status = random.choices(
            list(self.status_distribution.keys()),
            weights=list(self.status_distribution.values())
        )[0]

        size = random.randint(200, 5000)
        referer = random.choice(self.referers)
        user_agent = random.choice(self.user_agents)
        response_time = round(random.uniform(0.05, 2.5), 3)

        return f'{ip} - - [{timestamp}] "{method} {endpoint} HTTP/1.1" {status} {size} "{referer}" "{user_agent}" {response_time}'

    def generate_batch(self, count=1000):
        """Generate a batch of log lines"""
        return [self.generate_log_line() for _ in range(count)]


class IngestClient:
    """Send logs to the ingestion endpoint"""

    def __init__(self, url, verify_ssl=True):
        self.url = url
        self.verify_ssl = verify_ssl
        self.session = requests.Session()

    def send_logs(self, log_lines):
        """Compress and send logs to ingestion endpoint"""
        try:
            # Create gzipped JSON payload
            log_data = "\n".join(log_lines)

            # Gzip the data
            buffer = BytesIO()
            with gzip.GzipFile(fileobj=buffer, mode='wb') as gz:
                gz.write(log_data.encode('utf-8'))
            compressed_data = buffer.getvalue()

            # Send to ingestion endpoint
            headers = {
                'Content-Type': 'application/gzip',
                'Content-Encoding': 'gzip'
            }

            start_time = time.time()
            response = self.session.post(
                self.url,
                data=compressed_data,
                headers=headers,
                verify=self.verify_ssl,
                timeout=30
            )
            elapsed = time.time() - start_time

            return {
                'success': response.status_code == 201,
                'status_code': response.status_code,
                'elapsed': elapsed,
                'compressed_size': len(compressed_data),
                'original_size': len(log_data),
                'compression_ratio': len(log_data) / len(compressed_data) if compressed_data else 0,
                'response': response.text[:200] if response.text else ''
            }

        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }


def main():
    parser = argparse.ArgumentParser(description='Continuous log generator and sender')
    parser.add_argument('--url',
                        default='https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest',
                        help='Ingestion endpoint URL')
    parser.add_argument('--interval', type=int, default=30,
                        help='Interval in seconds between batches (default: 30)')
    parser.add_argument('--batch-size', type=int, default=1000,
                        help='Number of log lines per batch (default: 1000)')
    parser.add_argument('--no-verify', action='store_true',
                        help='Disable SSL certificate verification')
    parser.add_argument('--max-batches', type=int, default=0,
                        help='Maximum number of batches to send (0 = unlimited)')

    args = parser.parse_args()

    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("🚀 DStreamBolt Continuous Log Generator")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"\nConfiguration:")
    print(f"  Endpoint:     {args.url}")
    print(f"  Interval:     {args.interval} seconds")
    print(f"  Batch Size:   {args.batch_size} log lines")
    print(f"  SSL Verify:   {not args.no_verify}")
    print(f"  Max Batches:  {'Unlimited' if args.max_batches == 0 else args.max_batches}")
    print(f"\nPress Ctrl+C to stop\n")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

    generator = LogGenerator()
    client = IngestClient(args.url, verify_ssl=not args.no_verify)

    batch_count = 0
    total_logs = 0
    total_success = 0
    total_failed = 0

    try:
        while True:
            batch_count += 1

            # Generate logs
            print(f"[{datetime.now().strftime('%H:%M:%S')}] 📝 Generating batch #{batch_count} ({args.batch_size} logs)...", end=' ')
            log_lines = generator.generate_batch(args.batch_size)
            print("✅")

            # Send to ingestion
            print(f"[{datetime.now().strftime('%H:%M:%S')}] 📤 Sending to ingestion endpoint...", end=' ')
            result = client.send_logs(log_lines)

            if result['success']:
                total_logs += args.batch_size
                total_success += 1
                print(f"✅ {result['status_code']}")
                print(f"    ├─ Size: {result['original_size']:,} bytes → {result['compressed_size']:,} bytes (ratio: {result['compression_ratio']:.2f}x)")
                print(f"    ├─ Time: {result['elapsed']:.2f}s")
                print(f"    └─ Total: {total_logs:,} logs sent, {total_success} batches successful")
            else:
                total_failed += 1
                print(f"❌ FAILED")
                if 'status_code' in result:
                    print(f"    ├─ Status: {result['status_code']}")
                    print(f"    └─ Response: {result['response']}")
                else:
                    print(f"    └─ Error: {result.get('error', 'Unknown error')}")
                print(f"    Total failures: {total_failed}")

            print()

            # Check if we've reached max batches
            if args.max_batches > 0 and batch_count >= args.max_batches:
                print(f"✅ Reached maximum batches ({args.max_batches}). Stopping.")
                break

            # Wait for next interval
            print(f"⏳ Waiting {args.interval} seconds until next batch...\n")
            time.sleep(args.interval)

    except KeyboardInterrupt:
        print("\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("⛔ Stopped by user")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print(f"\n📊 Final Statistics:")
        print(f"  Total Batches:  {batch_count}")
        print(f"  Total Logs:     {total_logs:,}")
        print(f"  Successful:     {total_success}")
        print(f"  Failed:         {total_failed}")
        print(f"  Success Rate:   {(total_success * 100 / batch_count) if batch_count > 0 else 0:.1f}%")
        print()


if __name__ == '__main__':
    main()

