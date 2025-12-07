#!/usr/bin/env python3
"""
Send gzipped log bundles to DStreamBolt ingestion service
Supports batch and streaming modes
"""

import requests
import gzip
import os
import sys
import time
from pathlib import Path

def gzip_file(input_file):
    """Compress file with gzip"""
    output_file = input_file + '.gz'

    with open(input_file, 'rb') as f_in:
        with gzip.open(output_file, 'wb') as f_out:
            f_out.writelines(f_in)

    return output_file

def send_bundle(alb_url, gzipped_file, cert_files=None, verify_ssl=True):
    """
    Send gzipped bundle to ingestion service

    Args:
        alb_url: DStreamBolt ALB URL
        gzipped_file: Path to .gz file
        cert_files: Tuple of (cert_path, key_path) for mTLS
        verify_ssl: Whether to verify SSL (False for self-signed certs)

    Returns:
        Response object
    """
    url = f"{alb_url.rstrip('/')}/ingest"

    with open(gzipped_file, 'rb') as f:
        data = f.read()

    headers = {
        'Content-Type': 'application/gzip',
        'Content-Encoding': 'gzip',
    }

    # Prepare request kwargs
    request_kwargs = {
        'data': data,
        'headers': headers,
        'timeout': 30,
    }

    # Add mTLS certificates if provided
    if cert_files:
        cert_path, key_path = cert_files
        if os.path.exists(cert_path) and os.path.exists(key_path):
            request_kwargs['cert'] = (cert_path, key_path)
        else:
            print(f"⚠️  Warning: Certificate files not found, proceeding without mTLS")

    # SSL verification
    request_kwargs['verify'] = verify_ssl

    try:
        response = requests.post(url, **request_kwargs)
        return response
    except requests.exceptions.SSLError as e:
        print(f"❌ SSL Error: {e}")
        print(f"   Try with --no-verify flag for self-signed certificates")
        sys.exit(1)
    except requests.exceptions.ConnectionError as e:
        print(f"❌ Connection Error: {e}")
        print(f"   Is the DStreamBolt ingestion service running?")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

def send_batch(alb_url, log_file, cert_files=None, verify_ssl=True):
    """Send entire log file as single bundle"""
    print(f"📦 Sending batch bundle...")

    # Gzip the file
    print(f"   Compressing {log_file}...")
    gzipped = gzip_file(log_file)

    original_size = os.path.getsize(log_file)
    compressed_size = os.path.getsize(gzipped)
    compression_ratio = (1 - compressed_size / original_size) * 100

    print(f"   Original: {original_size} bytes")
    print(f"   Compressed: {compressed_size} bytes ({compression_ratio:.1f}% reduction)")

    # Send to ingestion service
    print(f"   Sending to {alb_url}/ingest...")
    start_time = time.time()

    response = send_bundle(alb_url, gzipped, cert_files, verify_ssl)

    elapsed = time.time() - start_time

    if response.status_code == 201:
        print(f"✅ Success! HTTP {response.status_code}")
        print(f"   Response time: {elapsed:.2f}s")
        if response.text:
            print(f"   Response: {response.text}")
    else:
        print(f"❌ Failed! HTTP {response.status_code}")
        print(f"   Response: {response.text}")
        sys.exit(1)

    # Cleanup
    os.remove(gzipped)
    print(f"   Cleaned up {gzipped}")

def send_streaming(alb_url, log_file, batch_size=100, delay=1.0, cert_files=None, verify_ssl=True):
    """
    Send logs in smaller batches (streaming mode)

    Args:
        alb_url: DStreamBolt ALB URL
        log_file: Path to log file
        batch_size: Number of log lines per bundle
        delay: Seconds to wait between batches
        cert_files: mTLS certificate files
        verify_ssl: Whether to verify SSL
    """
    print(f"📡 Streaming mode: {batch_size} lines per bundle, {delay}s delay")

    with open(log_file, 'r') as f:
        logs = f.readlines()

    total_batches = (len(logs) + batch_size - 1) // batch_size
    print(f"   Total logs: {len(logs)}")
    print(f"   Total batches: {total_batches}")
    print()

    for i in range(0, len(logs), batch_size):
        batch_num = i // batch_size + 1
        batch = logs[i:i + batch_size]

        # Create temp file for this batch
        temp_file = f'/tmp/batch_{batch_num}.log'
        with open(temp_file, 'w') as f:
            f.writelines(batch)

        # Gzip the batch
        gzipped = gzip_file(temp_file)

        # Send to ingestion service
        print(f"📤 Batch {batch_num}/{total_batches} ({len(batch)} lines)...", end=' ')

        try:
            response = send_bundle(alb_url, gzipped, cert_files, verify_ssl)

            if response.status_code == 201:
                print(f"✅ Sent")
            else:
                print(f"❌ Failed (HTTP {response.status_code})")
        except Exception as e:
            print(f"❌ Error: {e}")

        # Cleanup
        os.remove(temp_file)
        os.remove(gzipped)

        # Wait before next batch
        if batch_num < total_batches:
            time.sleep(delay)

    print(f"\n✅ Streaming complete! Sent {total_batches} batches")

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Send gzipped logs to DStreamBolt')
    parser.add_argument('log_file', help='Log file to send')
    parser.add_argument('--alb-url', required=True, help='DStreamBolt ALB URL (e.g., https://alb-dns)')
    parser.add_argument('--mode', choices=['batch', 'stream'], default='batch',
                       help='Sending mode: batch (all at once) or stream (incremental)')
    parser.add_argument('--batch-size', type=int, default=100,
                       help='Lines per bundle in stream mode (default: 100)')
    parser.add_argument('--delay', type=float, default=1.0,
                       help='Seconds between batches in stream mode (default: 1.0)')
    parser.add_argument('--cert', help='Path to client certificate (.pem)')
    parser.add_argument('--key', help='Path to client private key (.pem)')
    parser.add_argument('--no-verify', action='store_true',
                       help='Disable SSL verification (for self-signed certs)')

    args = parser.parse_args()

    # Validate log file exists
    if not os.path.exists(args.log_file):
        print(f"❌ Error: Log file not found: {args.log_file}")
        sys.exit(1)

    # Prepare cert files
    cert_files = None
    if args.cert and args.key:
        cert_files = (args.cert, args.key)

    verify_ssl = not args.no_verify

    print("╔════════════════════════════════════════════════════════════════╗")
    print("║          DStreamBolt Log Ingestion Client                     ║")
    print("╚════════════════════════════════════════════════════════════════╝")
    print()
    print(f"Target: {args.alb_url}")
    print(f"Mode: {args.mode}")
    print(f"SSL Verification: {'Enabled' if verify_ssl else 'Disabled'}")
    print(f"mTLS: {'Enabled' if cert_files else 'Disabled'}")
    print()

    if args.mode == 'batch':
        send_batch(args.alb_url, args.log_file, cert_files, verify_ssl)
    else:
        send_streaming(args.alb_url, args.log_file, args.batch_size, args.delay, cert_files, verify_ssl)

    print()
    print("Next step: Check logs in Kafka and metrics in Grafana")

