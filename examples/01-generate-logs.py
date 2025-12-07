#!/usr/bin/env python3
"""
Generate realistic access logs for observability platform
Format: Apache Combined Log Format (industry standard)
"""

import random
import time
from datetime import datetime
import os

# Realistic data for log generation
USER_AGENTS = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15',
    'okhttp/4.9.0',
    'python-requests/2.26.0',
]

ENDPOINTS = [
    '/api/v1/users',
    '/api/v1/products',
    '/api/v1/orders',
    '/api/v1/inventory',
    '/api/v1/analytics',
    '/api/v1/auth/login',
    '/api/v1/auth/logout',
    '/api/v2/search',
    '/health',
    '/metrics',
]

METHODS = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH']

STATUS_CODES = {
    200: 70,  # 70% success
    201: 10,  # 10% created
    400: 8,   # 8% bad request
    404: 5,   # 5% not found
    500: 4,   # 4% server error
    503: 3,   # 3% service unavailable
}

def generate_ip():
    """Generate realistic IP address"""
    return f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 255)}"

def weighted_choice(choices):
    """Choose status code based on weights"""
    total = sum(choices.values())
    r = random.uniform(0, total)
    upto = 0
    for key, weight in choices.items():
        if upto + weight >= r:
            return key
        upto += weight
    return list(choices.keys())[0]

def generate_log_line():
    """
    Generate single access log line in Apache Combined Log Format:
    IP - - [timestamp] "METHOD /path HTTP/1.1" status size "referer" "user-agent" response_time
    """
    ip = generate_ip()
    timestamp = datetime.now().strftime('%d/%b/%Y:%H:%M:%S %z')
    if not timestamp.endswith('00'):  # Add timezone if missing
        timestamp = datetime.now().strftime('%d/%b/%Y:%H:%M:%S +0000')

    method = random.choice(METHODS)
    endpoint = random.choice(ENDPOINTS)
    status = weighted_choice(STATUS_CODES)
    size = random.randint(200, 5000)
    user_agent = random.choice(USER_AGENTS)
    response_time = round(random.uniform(0.001, 2.5), 3)  # seconds

    # Referer (sometimes empty)
    referer = '-' if random.random() > 0.7 else f'https://app.example.com{random.choice(ENDPOINTS)}'

    log_line = f'{ip} - - [{timestamp}] "{method} {endpoint} HTTP/1.1" {status} {size} "{referer}" "{user_agent}" {response_time}'

    return log_line

def generate_logs(output_file, num_logs=1000, delay=0):
    """
    Generate multiple log lines and write to file

    Args:
        output_file: Path to output file
        num_logs: Number of log lines to generate
        delay: Delay in seconds between logs (0 for batch generation)
    """
    print(f"Generating {num_logs} access logs...")

    with open(output_file, 'w') as f:
        for i in range(num_logs):
            log_line = generate_log_line()
            f.write(log_line + '\n')

            if delay > 0:
                time.sleep(delay)

            if (i + 1) % 100 == 0:
                print(f"  Generated {i + 1}/{num_logs} logs...")

    print(f"✅ Logs written to: {output_file}")
    print(f"   File size: {os.path.getsize(output_file)} bytes")

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Generate realistic access logs')
    parser.add_argument('-o', '--output', default='access.log', help='Output file (default: access.log)')
    parser.add_argument('-n', '--num-logs', type=int, default=1000, help='Number of logs to generate (default: 1000)')
    parser.add_argument('-d', '--delay', type=float, default=0, help='Delay between logs in seconds (default: 0)')

    args = parser.parse_args()

    generate_logs(args.output, args.num_logs, args.delay)

    print(f"\nNext step: Run ./02-send-to-ingest.py to send logs to DStreamBolt")

