#!/usr/bin/env python3
"""
FINAL COMPREHENSIVE BENCHMARK
Tests all aspects of server performance
"""

import socket
import threading
import time
import statistics
import subprocess
import sys

HOST = "127.0.0.1"
PORT = 8080


def get_server_memory():
    try:
        result = subprocess.run(
            ["ps", "-o", "rss=", "-p", 
             subprocess.check_output(["pgrep", "-f", "production_server"]).decode().strip().split()[0]],
            capture_output=True, text=True
        )
        return int(result.stdout.strip()) / 1024
    except:
        return 0


def benchmark_endpoint(name, endpoint, num_requests, concurrency, use_keepalive=True):
    """Run a benchmark for a specific endpoint."""
    
    stats = {
        "completed": 0,
        "failed": 0,
        "latencies": [],
        "bytes": 0,
    }
    lock = threading.Lock()
    
    requests_per_thread = num_requests // concurrency
    
    def worker():
        nonlocal stats
        sock = None
        
        for _ in range(requests_per_thread):
            try:
                if sock is None or not use_keepalive:
                    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    sock.settimeout(10)
                    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                    sock.connect((HOST, PORT))
                
                conn = "keep-alive" if use_keepalive else "close"
                request = f"GET {endpoint} HTTP/1.1\r\nHost: localhost\r\nConnection: {conn}\r\n\r\n".encode()
                
                start = time.perf_counter()
                sock.sendall(request)
                
                response = b""
                content_length = None
                
                while True:
                    chunk = sock.recv(1024*1024)
                    if not chunk:
                        break
                    response += chunk
                    
                    if content_length is None and b"\r\n\r\n" in response:
                        header_end = response.find(b"\r\n\r\n")
                        header = response[:header_end].decode(errors="ignore")
                        for line in header.split("\r\n"):
                            if line.lower().startswith("content-length:"):
                                content_length = int(line.split(":")[1])
                                break
                    
                    if content_length is not None:
                        body_start = response.find(b"\r\n\r\n") + 4
                        if len(response) - body_start >= content_length:
                            break
                
                elapsed = (time.perf_counter() - start) * 1000
                
                with lock:
                    stats["completed"] += 1
                    stats["bytes"] += len(response)
                    if len(stats["latencies"]) < 10000:
                        stats["latencies"].append(elapsed)
                
                if not use_keepalive:
                    sock.close()
                    sock = None
                    
            except Exception as e:
                with lock:
                    stats["failed"] += 1
                if sock:
                    try: sock.close()
                    except: pass
                    sock = None
        
        if sock:
            try: sock.close()
            except: pass
    
    start_time = time.time()
    
    threads = []
    for _ in range(concurrency):
        t = threading.Thread(target=worker)
        t.start()
        threads.append(t)
    
    for t in threads:
        t.join()
    
    elapsed = time.time() - start_time
    
    rps = stats["completed"] / elapsed if elapsed > 0 else 0
    
    latencies = stats["latencies"]
    if latencies:
        sorted_lat = sorted(latencies)
        avg_lat = statistics.mean(latencies)
        p50 = sorted_lat[len(sorted_lat)//2]
        p99 = sorted_lat[int(len(sorted_lat)*0.99)] if len(sorted_lat) >= 100 else max(sorted_lat)
    else:
        avg_lat = p50 = p99 = 0
    
    print(f"  {name:20} | {stats['completed']:>8,} reqs | {rps:>10,.0f} req/s | "
          f"{stats['bytes']/1024/1024:>7.1f} MB | "
          f"lat: avg={avg_lat:>6.1f}ms p50={p50:>6.1f}ms p99={p99:>6.1f}ms | "
          f"fail={stats['failed']}")
    
    return {
        "name": name,
        "completed": stats["completed"],
        "failed": stats["failed"],
        "rps": rps,
        "bytes": stats["bytes"],
        "avg_lat": avg_lat,
        "p50": p50,
        "p99": p99,
    }


def main():
    print("="*100)
    print("AURORA HTTP SERVER - COMPREHENSIVE BENCHMARK")
    print("="*100)
    
    initial_mem = get_server_memory()
    print(f"\nServer Memory: {initial_mem:.0f} MB")
    
    # Verify server is up
    try:
        s = socket.socket()
        s.settimeout(2)
        s.connect((HOST, PORT))
        s.close()
        print("Server: ONLINE\n")
    except:
        print("Server: OFFLINE")
        sys.exit(1)
    
    results = []
    
    print("-"*100)
    print("TEST 1: Throughput (keep-alive enabled)")
    print("-"*100)
    
    # High throughput tests
    results.append(benchmark_endpoint("Minimal (/)", "/", 100000, 100, True))
    results.append(benchmark_endpoint("Small (1KB)", "/small", 50000, 100, True))
    results.append(benchmark_endpoint("Medium (64KB)", "/medium", 20000, 100, True))
    results.append(benchmark_endpoint("Large (512KB)", "/large", 5000, 50, True))
    results.append(benchmark_endpoint("Huge (2MB)", "/huge", 2000, 20, True))
    
    print()
    print("-"*100)
    print("TEST 2: Connection overhead (no keep-alive)")
    print("-"*100)
    
    results.append(benchmark_endpoint("No-KA Minimal", "/", 10000, 50, False))
    results.append(benchmark_endpoint("No-KA Medium", "/medium", 5000, 50, False))
    
    print()
    print("-"*100)
    print("TEST 3: High concurrency")
    print("-"*100)
    
    results.append(benchmark_endpoint("500 concurrent", "/", 50000, 500, True))
    
    final_mem = get_server_memory()
    
    print()
    print("="*100)
    print("SUMMARY")
    print("="*100)
    
    total_requests = sum(r["completed"] for r in results)
    total_bytes = sum(r["bytes"] for r in results)
    max_rps = max(r["rps"] for r in results)
    min_avg_lat = min(r["avg_lat"] for r in results if r["avg_lat"] > 0)
    
    print(f"\nTotal Requests Processed: {total_requests:,}")
    print(f"Total Data Transferred: {total_bytes/1024/1024/1024:.2f} GB")
    print(f"Peak Throughput: {max_rps:,.0f} req/s")
    print(f"Best Average Latency: {min_avg_lat:.2f} ms")
    print(f"\nServer Memory:")
    print(f"  Initial: {initial_mem:.0f} MB")
    print(f"  Final: {final_mem:.0f} MB")
    print(f"  Change: {final_mem - initial_mem:+.0f} MB")
    print("="*100)


if __name__ == "__main__":
    main()
