#!/usr/bin/env python3
"""
Sustained Load Test Client

Runs continuous load for extended periods to detect:
- Memory leaks
- Performance degradation over time
- Stability issues

Usage:
    python3 sustained_load.py --host 127.0.0.1 --port 8080 --duration 60
"""

import socket
import threading
import time
import statistics
import argparse
import sys
import os

# Configuration
CONCURRENCY = 100
REPORT_INTERVAL = 5  # seconds

class IntervalStats:
    def __init__(self):
        self.completed = 0
        self.failed = 0
        self.latencies = []
        self.bytes_received = 0
        self.lock = threading.Lock()
    
    def record(self, success, latency, bytes_recv):
        with self.lock:
            if success:
                self.completed += 1
                self.latencies.append(latency)
                self.bytes_received += bytes_recv
            else:
                self.failed += 1
    
    def reset(self):
        with self.lock:
            stats = {
                'completed': self.completed,
                'failed': self.failed,
                'latencies': self.latencies.copy(),
                'bytes': self.bytes_received
            }
            self.completed = 0
            self.failed = 0
            self.latencies = []
            self.bytes_received = 0
            return stats


def worker(host, port, stats, running):
    """Worker thread making continuous requests"""
    sock = None
    
    while running[0]:
        try:
            # Create/reconnect socket
            if sock is None:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                sock.settimeout(10)
                sock.connect((host, port))
            
            # Make request
            start = time.perf_counter()
            request = b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n"
            sock.sendall(request)
            
            response = sock.recv(4096)
            elapsed = (time.perf_counter() - start) * 1000
            
            if response:
                stats.record(True, elapsed, len(response))
            else:
                stats.record(False, 0, 0)
                sock.close()
                sock = None
                
        except Exception as e:
            stats.record(False, 0, 0)
            if sock:
                try:
                    sock.close()
                except:
                    pass
                sock = None
    
    if sock:
        try:
            sock.close()
        except:
            pass


def format_bytes(n):
    """Format bytes to human readable"""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def run_sustained_test(host, port, duration, concurrency):
    """Run sustained load test"""
    print(f"\n{'=' * 70}")
    print(f"  SUSTAINED LOAD TEST")
    print(f"  Target: {host}:{port}")
    print(f"  Duration: {duration}s, Concurrency: {concurrency}")
    print(f"{'=' * 70}\n")
    
    # Check server
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect((host, port))
        sock.close()
    except:
        print(f"[ERROR] Cannot connect to {host}:{port}")
        return
    
    stats = IntervalStats()
    running = [True]
    total_completed = 0
    total_failed = 0
    total_bytes = 0
    all_latencies = []
    
    # Start workers
    threads = [
        threading.Thread(target=worker, args=(host, port, stats, running))
        for _ in range(concurrency)
    ]
    
    print(f"[*] Starting {concurrency} workers...")
    for t in threads:
        t.daemon = True
        t.start()
    
    print(f"[*] Running for {duration} seconds...\n")
    
    start_time = time.time()
    interval_start = start_time
    interval_num = 0
    
    print(f"{'Time':<10} {'Requests':<12} {'Throughput':<15} {'Latency (p50/p99)':<25} {'Data':<12}")
    print("-" * 75)
    
    try:
        while time.time() - start_time < duration:
            time.sleep(REPORT_INTERVAL)
            interval_num += 1
            
            interval_stats = stats.reset()
            interval_duration = time.time() - interval_start
            interval_start = time.time()
            
            completed = interval_stats['completed']
            failed = interval_stats['failed']
            latencies = interval_stats['latencies']
            bytes_recv = interval_stats['bytes']
            
            total_completed += completed
            total_failed += failed
            total_bytes += bytes_recv
            all_latencies.extend(latencies)
            
            throughput = completed / interval_duration if interval_duration > 0 else 0
            
            if latencies:
                sorted_lats = sorted(latencies)
                p50 = statistics.median(sorted_lats)
                p99 = sorted_lats[int(len(sorted_lats) * 0.99)] if len(sorted_lats) > 100 else sorted_lats[-1]
                lat_str = f"{p50:.2f}ms / {p99:.2f}ms"
            else:
                lat_str = "N/A"
            
            elapsed = int(time.time() - start_time)
            print(f"{elapsed:>6}s    {completed:<12} {throughput:>10.0f}/s    {lat_str:<25} {format_bytes(bytes_recv):<12}")
            
            if failed > completed * 0.1:  # >10% failure rate
                print(f"[WARNING] High failure rate: {failed}/{completed+failed} ({100*failed/(completed+failed):.1f}%)")
    
    except KeyboardInterrupt:
        print("\n[*] Interrupted by user")
    
    # Stop workers
    running[0] = False
    print("\n[*] Stopping workers...")
    
    for t in threads:
        t.join(timeout=2)
    
    # Final report
    elapsed = time.time() - start_time
    
    print(f"\n{'=' * 70}")
    print(f"  FINAL REPORT")
    print(f"{'=' * 70}")
    print(f"Duration:        {elapsed:.1f} seconds")
    print(f"Total Requests:  {total_completed:,}")
    print(f"Failed:          {total_failed:,}")
    print(f"Success Rate:    {100*total_completed/(total_completed+total_failed):.2f}%")
    print(f"Avg Throughput:  {total_completed/elapsed:,.0f} req/s")
    print(f"Data Received:   {format_bytes(total_bytes)}")
    
    if all_latencies:
        sorted_lats = sorted(all_latencies)
        n = len(sorted_lats)
        print(f"\nLatency Distribution:")
        print(f"  Min:    {min(sorted_lats):.3f}ms")
        print(f"  Mean:   {statistics.mean(sorted_lats):.3f}ms")
        print(f"  Median: {statistics.median(sorted_lats):.3f}ms")
        print(f"  P95:    {sorted_lats[int(n*0.95)]:.3f}ms")
        print(f"  P99:    {sorted_lats[int(n*0.99)]:.3f}ms")
        print(f"  Max:    {max(sorted_lats):.3f}ms")
    
    print(f"{'=' * 70}")


def main():
    parser = argparse.ArgumentParser(description="Sustained Load Test Client")
    parser.add_argument("--host", default="127.0.0.1", help="Server host")
    parser.add_argument("--port", type=int, default=8080, help="Server port")
    parser.add_argument("--duration", type=int, default=60, help="Test duration in seconds")
    parser.add_argument("--concurrency", type=int, default=CONCURRENCY, help="Number of concurrent workers")
    args = parser.parse_args()
    
    run_sustained_test(args.host, args.port, args.duration, args.concurrency)


if __name__ == "__main__":
    main()
