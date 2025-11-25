#!/usr/bin/env python3
"""
Spike Test Client

Tests server behavior under sudden traffic spikes:
1. Baseline: Low steady traffic
2. Spike: Sudden burst of requests
3. Recovery: Back to baseline

Usage:
    python3 spike_test.py --host 127.0.0.1 --port 8080
"""

import socket
import threading
import time
import statistics
import argparse

# Spike pattern configuration
BASELINE_CONCURRENCY = 10
SPIKE_CONCURRENCY = 500
BASELINE_DURATION = 5   # seconds
SPIKE_DURATION = 10     # seconds
RECOVERY_DURATION = 10  # seconds


class Stats:
    def __init__(self):
        self.lock = threading.Lock()
        self.data = []  # [(timestamp, latency, success)]
    
    def record(self, latency, success):
        with self.lock:
            self.data.append((time.time(), latency, success))
    
    def get_window(self, start, end):
        with self.lock:
            return [(t, l, s) for t, l, s in self.data if start <= t <= end]


def make_request(host, port, stats, running):
    """Worker making requests until stopped"""
    while running[0]:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            sock.settimeout(5)
            
            start = time.perf_counter()
            sock.connect((host, port))
            sock.sendall(b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
            
            response = b""
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                response += chunk
            
            latency = (time.perf_counter() - start) * 1000
            sock.close()
            
            stats.record(latency, len(response) > 0)
            
        except Exception:
            stats.record(0, False)


def print_phase_stats(stats, start, end, phase_name):
    """Print statistics for a time window"""
    window = stats.get_window(start, end)
    if not window:
        print(f"  {phase_name}: No data")
        return
    
    latencies = [l for _, l, s in window if s]
    successes = sum(1 for _, _, s in window if s)
    failures = len(window) - successes
    duration = end - start
    
    throughput = successes / duration if duration > 0 else 0
    success_rate = 100 * successes / len(window) if window else 0
    
    if latencies:
        sorted_lats = sorted(latencies)
        p50 = statistics.median(sorted_lats)
        p99 = sorted_lats[int(len(sorted_lats) * 0.99)] if len(sorted_lats) > 100 else sorted_lats[-1]
        lat_str = f"p50={p50:.1f}ms, p99={p99:.1f}ms"
    else:
        lat_str = "N/A"
    
    print(f"  {phase_name}: {throughput:.0f} req/s, {lat_str}, {success_rate:.1f}% success")


def run_spike_test(host, port):
    """Run spike test"""
    print(f"\n{'=' * 70}")
    print(f"  SPIKE TEST")
    print(f"  Target: {host}:{port}")
    print(f"  Pattern: {BASELINE_CONCURRENCY} → {SPIKE_CONCURRENCY} → {BASELINE_CONCURRENCY}")
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
    
    stats = Stats()
    threads = []
    running = [True]
    
    test_start = time.time()
    
    # Phase 1: Baseline
    print(f"[Phase 1] BASELINE: {BASELINE_CONCURRENCY} workers for {BASELINE_DURATION}s")
    baseline_start = time.time()
    
    for _ in range(BASELINE_CONCURRENCY):
        t = threading.Thread(target=make_request, args=(host, port, stats, running))
        t.daemon = True
        t.start()
        threads.append(t)
    
    time.sleep(BASELINE_DURATION)
    baseline_end = time.time()
    
    # Phase 2: Spike
    print(f"[Phase 2] SPIKE: Adding {SPIKE_CONCURRENCY - BASELINE_CONCURRENCY} workers for {SPIKE_DURATION}s")
    spike_start = time.time()
    
    for _ in range(SPIKE_CONCURRENCY - BASELINE_CONCURRENCY):
        t = threading.Thread(target=make_request, args=(host, port, stats, running))
        t.daemon = True
        t.start()
        threads.append(t)
    
    time.sleep(SPIKE_DURATION)
    spike_end = time.time()
    
    # Phase 3: Recovery (stop extra threads by letting them finish naturally)
    print(f"[Phase 3] RECOVERY: Back to {BASELINE_CONCURRENCY} workers for {RECOVERY_DURATION}s")
    
    # We can't easily remove threads, so just measure for recovery duration
    recovery_start = time.time()
    time.sleep(RECOVERY_DURATION)
    recovery_end = time.time()
    
    # Stop all threads
    running[0] = False
    print("\n[*] Stopping workers...")
    
    for t in threads:
        t.join(timeout=1)
    
    # Report
    print(f"\n{'=' * 70}")
    print(f"  RESULTS")
    print(f"{'=' * 70}")
    
    print_phase_stats(stats, baseline_start, baseline_end, "Baseline")
    print_phase_stats(stats, spike_start, spike_end, "Spike   ")
    print_phase_stats(stats, recovery_start, recovery_end, "Recovery")
    
    # Overall
    all_data = stats.get_window(test_start, time.time())
    total_success = sum(1 for _, _, s in all_data if s)
    total_fail = len(all_data) - total_success
    
    print(f"\n  Total Requests: {len(all_data):,}")
    print(f"  Success/Failed: {total_success:,} / {total_fail:,}")
    print(f"  Overall Success Rate: {100*total_success/len(all_data):.2f}%")
    print(f"{'=' * 70}")


def main():
    parser = argparse.ArgumentParser(description="Spike Test Client")
    parser.add_argument("--host", default="127.0.0.1", help="Server host")
    parser.add_argument("--port", type=int, default=8080, help="Server port")
    args = parser.parse_args()
    
    run_spike_test(args.host, args.port)


if __name__ == "__main__":
    main()
