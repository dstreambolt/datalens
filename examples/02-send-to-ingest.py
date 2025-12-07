#!/usr/bin/env python3
"""
DStreamBolt Log Ingestion Client
Supports batch and streaming modes with gzip compression.
"""

import gzip
import json
import os
import sys
import time
import argparse
import requests
from datetime import datetime

def parse_apache_log_line(line):
    """Parse Apache Combined Log Format line into JSON"""
    try:
        parts = line.strip().split('"')
        pre = parts[0].split()
        ip = pre[0]
        timestamp = pre[3][1:]  # remove [
        method, endpoint, _ = parts[1].split()
        status_size = parts[2].strip().split()
        status = int(status_size[0])
        size = int(status_size[1])
        referer = parts[3]
        user_agent = parts[5]
        response_time = float(parts[6].strip())
        dt = datetime.strptime(timestamp.split()[0], '%d/%b/%Y:%H:%M:%S')
        timestamp_iso = dt.isoformat() + "Z"
        return {
            "ip": ip,
            "timestamp": timestamp_iso,
            "method": method,
            "endpoint": endpoint,
            "status": status,
            "size": size,
            "referer": referer,
            "user_agent": user_agent,
            "response_time": response_time
        }
    except Exception as e:
        print(f"⚠️  Failed to parse line: {line.strip()} -> {e}")
        return None

def convert_log_file_to_json(input_file):
    logs_json = []
    with open(input_file, 'r') as f:
        for line in f:
            parsed = parse_apache_log_line(line)
            if parsed:
                logs_json.append(parsed)
    return logs_json

def gzip_bytes(data_bytes):
    return gzip.compress(data_bytes)

def send_to_ingest(alb_url, json_data_bytes, verify_ssl=True):
    """Send gzipped JSON to the ingestion endpoint"""
    # Remove trailing /ingest if already included to prevent double /ingest
    alb_url = alb_url.rstrip('/')
    if alb_url.endswith('/ingest'):
        url = alb_url
    else:
        url = f"{alb_url}/ingest"

    headers = {'Content-Type': 'application/gzip', 'Content-Encoding': 'gzip'}

    try:
        response = requests.post(url, data=json_data_bytes, headers=headers, timeout=30, verify=verify_ssl)
        return response
    except requests.exceptions.SSLError as e:
        print(f"❌ SSL Error: {e}")
        sys.exit(1)
    except requests.exceptions.ConnectionError as e:
        print(f"❌ Connection Error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        sys.exit(1)

def batch_mode(alb_url, log_file, verify_ssl=True):
    print(f"📦 Batch mode: converting {log_file} to JSON...")
    logs_json = convert_log_file_to_json(log_file)
    if not logs_json:
        print("⚠️  No valid logs to send")
        return
    data_bytes = gzip_bytes(json.dumps(logs_json).encode('utf-8'))
    print(f"   Sending {len(logs_json)} logs ({len(data_bytes)} bytes gzipped)...")
    response = send_to_ingest(alb_url, data_bytes, verify_ssl)
    print(f"📤 Response: HTTP {response.status_code}")
    print(response.text)

def stream_mode(alb_url, log_file, batch_size=100, delay=1.0, verify_ssl=True):
    print(f"📡 Streaming mode: {batch_size} lines per batch, {delay}s delay")
    with open(log_file, 'r') as f:
        lines = f.readlines()
    total_batches = (len(lines) + batch_size - 1) // batch_size
    print(f"   Total lines: {len(lines)}, total batches: {total_batches}")

    for i in range(0, len(lines), batch_size):
        batch_num = i // batch_size + 1
        batch_lines = lines[i:i+batch_size]
        logs_json = [p for line in batch_lines if (p := parse_apache_log_line(line)) is not None]
        if not logs_json:
            continue
        data_bytes = gzip_bytes(json.dumps(logs_json).encode('utf-8'))
        print(f"   Sending batch {batch_num}/{total_batches} ({len(logs_json)} logs)...", end=' ')
        response = send_to_ingest(alb_url, data_bytes, verify_ssl)
        if response.status_code in [200,201]:
            print("✅ Sent")
        else:
            print(f"❌ Failed (HTTP {response.status_code})")
            print(response.text)
        if batch_num < total_batches:
            time.sleep(delay)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Send logs to DStreamBolt ingestion service")
    parser.add_argument("log_file", help="Apache log file to send")
    parser.add_argument("--alb-url", required=True, help="DStreamBolt ALB URL (do not include /ingest)")
    parser.add_argument("--mode", choices=['batch','stream'], default='batch', help="Send mode")
    parser.add_argument("--batch-size", type=int, default=100, help="Lines per batch (stream mode)")
    parser.add_argument("--delay", type=float, default=1.0, help="Delay between batches (stream mode)")
    parser.add_argument("--no-verify", action="store_true", help="Disable SSL verification")
    args = parser.parse_args()

    verify_ssl = not args.no_verify

    print("╔════════════════════════════════════════╗")
    print("║       DStreamBolt Log Ingestion       ║")
    print("╚════════════════════════════════════════╝")
    print(f"Target: {args.alb_url}")
    print(f"Mode: {args.mode}")
    print(f"SSL Verification: {'Enabled' if verify_ssl else 'Disabled'}\n")

    if args.mode == 'batch':
        batch_mode(args.alb_url, args.log_file, verify_ssl)
    else:
        stream_mode(args.alb_url, args.log_file, args.batch_size, args.delay, verify_ssl)