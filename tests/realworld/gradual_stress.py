#!/usr/bin/env python3
"""
Gradual Stress Test Client

Performs incremental load testing:
1. Starts with low concurrency
2. Gradually increases workers
3. Measures throughput/latency at each level
4. Detects breaking points

Usage:
    python3 gradual_stress.py --host 127.0.0.1 --port 8080
    python3 gradual_stress.py --compare  # Compare multi-core vs single-core
"""

import socket
import threading
import time
import statistics
import argparse
import sys
from collections import defaultdict

# Configuration
WARMUP_REQUESTS = 1000
REQUESTS_PER_LEVEL = 10000
CONCURRENCY_LEVELS = [1, 5, 10, 25, 50, 100, 200, 500]
TIMEOUT = 10

class StressResult:
    def __init__(self):
        self.completed = 0
        self.failed = 0
        self.latencies = []
        self.bytes_received = 0
        self.start_time = None
        self.end_time = None
    
    @property
    def duration(self):
        if self.start_time and self.end_time:
            return self.end_time - self.start_time
        return 0
    
    @property
    def throughput(self):
        if self.duration > 0:
            return self.completed / self.duration
        return 0
    
    @property
    def success_rate(self):
        total = self.completed + self.failed
        return (self.completed / total * 100) if total > 0 else 0
    
    def latency_stats(self):
        if not self.latencies:
            return {}
        sorted_lats = sorted(self.latencies)
        n = len(sorted_lats)
        return {
            'min': min(sorted_lats),
            'max': max(sorted_lats),
            'mean': statistics.mean(sorted_lats),
            'median': statistics.median(sorted_lats),
            'p90': sorted_lats[int(n * 0.90)] if n > 10 else sorted_lats[-1],
            'p95': sorted_lats[int(n * 0.95)] if n > 20 else sorted_lats[-1],
            'p99': sorted_lats[int(n * 0.99)] if n > 100 else sorted_lats[-1],
        }


def make_request(host, port, path="/"):
    """Make HTTP request, return (success, latency_ms, bytes)"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.settimeout(TIMEOUT)
        
        start = time.perf_counter()
        sock.connect((host, port))
        
        request = f"GET {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n"
        sock.sendall(request.encode())
        
        response = b""
        while True:
            chunk = sock.recv(8192)
            if not chunk:
                break
            response += chunk
        
        elapsed = (time.perf_counter() - start) * 1000
        sock.close()
        
        return True, elapsed, len(response)
    except Exception as e:
        return False, 0, 0


def stress_test(host, port, concurrency, num_requests, path="/"):
    """Run stress test with given concurrency"""
    result = StressResult()
    lock = threading.Lock()
    request_queue = list(range(num_requests))
    queue_lock = threading.Lock()
    
    def worker():
        while True:
            with queue_lock:
                if not request_queue:
                    return
                request_queue.pop()
            
            success, latency, bytes_recv = make_request(host, port, path)
            
            with lock:
                if success:
                    result.completed += 1
                    result.latencies.append(latency)
                    result.bytes_received += bytes_recv
                else:
                    result.failed += 1
    
    result.start_time = time.time()
    
    threads = [threading.Thread(target=worker) for _ in range(concurrency)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    
    result.end_time = time.time()
    return result


def run_gradual_test(host, port, name="Server"):
    """Run gradual stress test with increasing concurrency"""
    print(f"\n{'=' * 70}")
    print(f"  GRADUAL STRESS TEST: {name}")
    print(f"  Target: {host}:{port}")
    print(f"{'=' * 70}\n")
    
    # Check server is up
    try:
        success, _, _ = make_request(host, port, "/health")
        if not success:
            print(f"[ERROR] Cannot connect to {host}:{port}")
            return None
    except:
        print(f"[ERROR] Server not responding at {host}:{port}")
        return None
    
    # Warmup
    print(f"[*] Warming up with {WARMUP_REQUESTS} requests...")
    stress_test(host, port, 10, WARMUP_REQUESTS)
    print("[*] Warmup complete\n")
    
    # Results storage
    results = {}
    
    print(f"{'Concurrency':<12} {'Requests':<10} {'Throughput':<15} {'Latency (ms)':<40} {'Success':<10}")
    print(f"{'':<12} {'':<10} {'(req/s)':<15} {'mean / p50 / p95 / p99':<40} {'Rate':<10}")
    print("-" * 90)
    
    for concurrency in CONCURRENCY_LEVELS:
        result = stress_test(host, port, concurrency, REQUESTS_PER_LEVEL)
        results[concurrency] = result
        
        stats = result.latency_stats()
        print(f"{concurrency:<12} {result.completed:<10} {result.throughput:>10.0f}/s     "
              f"{stats.get('mean', 0):>6.2f} / {stats.get('median', 0):>6.2f} / "
              f"{stats.get('p95', 0):>6.2f} / {stats.get('p99', 0):>6.2f}      "
              f"{result.success_rate:>6.2f}%")
    
    print("-" * 90)
    
    # Find peak throughput
    peak_concurrency = max(results.keys(), key=lambda c: results[c].throughput)
    peak_result = results[peak_concurrency]
    
    print(f"\n[PEAK] Concurrency={peak_concurrency}: {peak_result.throughput:.0f} req/s")
    
    return results


def compare_servers(multi_host, multi_port, single_host, single_port):
    """Compare multi-core vs single-core performance"""
    print("\n" + "=" * 70)
    print("  SERVER COMPARISON: Multi-Core vs Single-Core")
    print("=" * 70)
    
    multi_results = run_gradual_test(multi_host, multi_port, "Multi-Core (8 workers)")
    single_results = run_gradual_test(single_host, single_port, "Single-Core (1 worker)")
    
    if not multi_results or not single_results:
        print("[ERROR] Could not complete comparison")
        return
    
    # Comparison table
    print("\n" + "=" * 70)
    print("  COMPARISON SUMMARY")
    print("=" * 70)
    print(f"\n{'Concurrency':<12} {'Multi-Core':<18} {'Single-Core':<18} {'Speedup':<10}")
    print(f"{'':<12} {'(req/s)':<18} {'(req/s)':<18} {'':<10}")
    print("-" * 60)
    
    for c in CONCURRENCY_LEVELS:
        if c in multi_results and c in single_results:
            m_tp = multi_results[c].throughput
            s_tp = single_results[c].throughput
            speedup = m_tp / s_tp if s_tp > 0 else 0
            print(f"{c:<12} {m_tp:>12.0f}/s     {s_tp:>12.0f}/s     {speedup:>6.2f}x")
    
    print("-" * 60)
    
    # Peak comparison
    m_peak_c = max(multi_results.keys(), key=lambda c: multi_results[c].throughput)
    s_peak_c = max(single_results.keys(), key=lambda c: single_results[c].throughput)
    m_peak = multi_results[m_peak_c].throughput
    s_peak = single_results[s_peak_c].throughput
    
    print(f"\nPeak Multi-Core:   {m_peak:>10.0f} req/s @ {m_peak_c} workers")
    print(f"Peak Single-Core:  {s_peak:>10.0f} req/s @ {s_peak_c} workers")
    print(f"Max Speedup:       {m_peak/s_peak:>10.2f}x")


def main():
    parser = argparse.ArgumentParser(description="Gradual Stress Test Client")
    parser.add_argument("--host", default="127.0.0.1", help="Server host")
    parser.add_argument("--port", type=int, default=8080, help="Server port")
    parser.add_argument("--compare", action="store_true", 
                        help="Compare multi-core (8080) vs single-core (8081)")
    args = parser.parse_args()
    
    if args.compare:
        compare_servers("127.0.0.1", 8080, "127.0.0.1", 8081)
    else:
        run_gradual_test(args.host, args.port)


if __name__ == "__main__":
    main()
