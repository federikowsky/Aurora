#!/usr/bin/env python3
"""
Endpoint Mix Test Client

Tests server with realistic endpoint distribution:
- Different response sizes
- JSON vs text responses
- Parameter extraction
- Compute-heavy endpoints

Usage:
    python3 endpoint_mix.py --host 127.0.0.1 --port 8080 --requests 50000
"""

import socket
import threading
import time
import statistics
import argparse
import random
from collections import defaultdict

# Realistic endpoint distribution
ENDPOINTS = [
    ("/", 40),              # 40% - homepage/API root
    ("/json", 25),          # 25% - JSON API calls
    ("/small", 15),         # 15% - small resources
    ("/echo/test123", 10),  # 10% - parameterized routes
    ("/medium", 5),         # 5% - medium content
    ("/compute", 3),        # 3% - CPU-intensive
    ("/large", 2),          # 2% - large files
]

# Build weighted list
WEIGHTED_ENDPOINTS = []
for endpoint, weight in ENDPOINTS:
    WEIGHTED_ENDPOINTS.extend([endpoint] * weight)


class EndpointStats:
    def __init__(self):
        self.lock = threading.Lock()
        self.stats = defaultdict(lambda: {'count': 0, 'latencies': [], 'bytes': 0, 'errors': 0})
    
    def record(self, endpoint, latency, bytes_recv, success):
        with self.lock:
            s = self.stats[endpoint]
            if success:
                s['count'] += 1
                s['latencies'].append(latency)
                s['bytes'] += bytes_recv
            else:
                s['errors'] += 1
    
    def get_stats(self):
        with self.lock:
            return dict(self.stats)


def worker(host, port, stats, num_requests, progress, progress_lock):
    """Worker making mixed endpoint requests"""
    sock = None
    
    for _ in range(num_requests):
        endpoint = random.choice(WEIGHTED_ENDPOINTS)
        
        try:
            if sock is None:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                sock.settimeout(10)
                sock.connect((host, port))
            
            start = time.perf_counter()
            request = f"GET {endpoint} HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n"
            sock.sendall(request.encode())
            
            response = sock.recv(65536)  # Larger buffer for big responses
            latency = (time.perf_counter() - start) * 1000
            
            if response:
                stats.record(endpoint, latency, len(response), True)
            else:
                stats.record(endpoint, 0, 0, False)
                sock.close()
                sock = None
                
        except Exception:
            stats.record(endpoint, 0, 0, False)
            if sock:
                try:
                    sock.close()
                except:
                    pass
                sock = None
        
        with progress_lock:
            progress[0] += 1
    
    if sock:
        try:
            sock.close()
        except:
            pass


def format_bytes(n):
    for unit in ['B', 'KB', 'MB', 'GB']:
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}TB"


def run_endpoint_test(host, port, num_requests, concurrency):
    """Run endpoint mix test"""
    print(f"\n{'=' * 80}")
    print(f"  ENDPOINT MIX TEST")
    print(f"  Target: {host}:{port}")
    print(f"  Requests: {num_requests:,}, Concurrency: {concurrency}")
    print(f"{'=' * 80}\n")
    
    # Check server
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect((host, port))
        sock.close()
    except:
        print(f"[ERROR] Cannot connect to {host}:{port}")
        return
    
    stats = EndpointStats()
    progress = [0]
    progress_lock = threading.Lock()
    
    # Distribute requests among workers
    requests_per_worker = num_requests // concurrency
    
    print(f"[*] Starting {concurrency} workers...")
    start_time = time.time()
    
    threads = [
        threading.Thread(target=worker, 
                        args=(host, port, stats, requests_per_worker, progress, progress_lock))
        for _ in range(concurrency)
    ]
    
    for t in threads:
        t.start()
    
    # Progress reporting
    while any(t.is_alive() for t in threads):
        time.sleep(1)
        with progress_lock:
            pct = 100 * progress[0] / num_requests
            elapsed = time.time() - start_time
            rate = progress[0] / elapsed if elapsed > 0 else 0
            print(f"\r  Progress: {progress[0]:,}/{num_requests:,} ({pct:.1f}%) - {rate:.0f} req/s", end="")
    
    for t in threads:
        t.join()
    
    elapsed = time.time() - start_time
    
    # Report
    print(f"\n\n{'=' * 80}")
    print(f"  RESULTS (Total: {elapsed:.2f}s)")
    print(f"{'=' * 80}")
    
    all_stats = stats.get_stats()
    total_reqs = sum(s['count'] for s in all_stats.values())
    total_errs = sum(s['errors'] for s in all_stats.values())
    total_bytes = sum(s['bytes'] for s in all_stats.values())
    
    print(f"\n{'Endpoint':<20} {'Count':<10} {'Errors':<8} {'Bytes':<12} {'Latency (p50/p99)':<25}")
    print("-" * 80)
    
    for endpoint, s in sorted(all_stats.items(), key=lambda x: -x[1]['count']):
        lats = s['latencies']
        if lats:
            sorted_lats = sorted(lats)
            p50 = statistics.median(sorted_lats)
            p99 = sorted_lats[int(len(sorted_lats) * 0.99)] if len(sorted_lats) > 100 else sorted_lats[-1]
            lat_str = f"{p50:.2f}ms / {p99:.2f}ms"
        else:
            lat_str = "N/A"
        
        print(f"{endpoint:<20} {s['count']:<10} {s['errors']:<8} {format_bytes(s['bytes']):<12} {lat_str:<25}")
    
    print("-" * 80)
    print(f"{'TOTAL':<20} {total_reqs:<10} {total_errs:<8} {format_bytes(total_bytes):<12}")
    
    # Summary
    print(f"\n  Throughput: {total_reqs/elapsed:,.0f} req/s")
    print(f"  Bandwidth:  {total_bytes/elapsed/1024/1024:.2f} MB/s")
    print(f"  Error Rate: {100*total_errs/(total_reqs+total_errs):.3f}%")
    print(f"{'=' * 80}")


def main():
    parser = argparse.ArgumentParser(description="Endpoint Mix Test Client")
    parser.add_argument("--host", default="127.0.0.1", help="Server host")
    parser.add_argument("--port", type=int, default=8080, help="Server port")
    parser.add_argument("--requests", type=int, default=50000, help="Total requests")
    parser.add_argument("--concurrency", type=int, default=100, help="Concurrent workers")
    args = parser.parse_args()
    
    run_endpoint_test(args.host, args.port, args.requests, args.concurrency)


if __name__ == "__main__":
    main()
