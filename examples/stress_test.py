#!/usr/bin/env python3
"""
Aggressive Stress Test Client for Aurora Server

Features:
- Multiple concurrent connections
- Keep-alive connection pooling
- Various request types (small, medium, large, huge)
- Randomized endpoints
- Memory usage tracking
- Real-time statistics
- Gradual ramp-up to avoid thundering herd
"""

import socket
import threading
import time
import random
import sys
import os
import queue
import statistics
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed

# Configuration
HOST = "127.0.0.1"
PORT = 8080
NUM_CONNECTIONS = 500       # Concurrent persistent connections
REQUESTS_PER_CONNECTION = 200  # Requests per connection before reconnect
TOTAL_REQUESTS = 100_000    # Total requests to send
RAMP_UP_TIME = 10           # Seconds to ramp up connections
TIMEOUT = 30                # Socket timeout

# Endpoint distribution (weighted)
ENDPOINTS = [
    ("/", 30),              # 30% - minimal
    ("/small", 25),         # 25% - 1KB
    ("/medium", 20),        # 20% - 64KB
    ("/large", 15),         # 15% - 512KB
    ("/huge", 5),           # 5% - 2MB
    ("/json", 3),           # 3% - dynamic JSON
    ("/compute", 1),        # 1% - CPU intensive
    ("/headers", 1),        # 1% - many headers
]

# Build weighted endpoint list
WEIGHTED_ENDPOINTS = []
for endpoint, weight in ENDPOINTS:
    WEIGHTED_ENDPOINTS.extend([endpoint] * weight)

# Statistics
stats = {
    "requests_sent": 0,
    "requests_completed": 0,
    "requests_failed": 0,
    "bytes_received": 0,
    "connection_errors": 0,
    "latencies": [],
    "per_endpoint": defaultdict(lambda: {"count": 0, "bytes": 0, "latencies": []}),
}
stats_lock = threading.Lock()

# Control
running = True
start_time = None


def create_request(endpoint, keep_alive=True):
    """Create an HTTP/1.1 request."""
    connection = "keep-alive" if keep_alive else "close"
    return (
        f"GET {endpoint} HTTP/1.1\r\n"
        f"Host: localhost:{PORT}\r\n"
        f"Connection: {connection}\r\n"
        f"User-Agent: StressClient/1.0\r\n"
        f"\r\n"
    ).encode()


def parse_response(sock):
    """Parse HTTP response, return (status_code, body_length, headers)."""
    response = b""
    headers_done = False
    content_length = 0
    
    # Read headers
    while not headers_done:
        chunk = sock.recv(4096)
        if not chunk:
            return None, 0, {}
        response += chunk
        if b"\r\n\r\n" in response:
            headers_done = True
    
    header_end = response.find(b"\r\n\r\n")
    header_data = response[:header_end].decode("utf-8", errors="ignore")
    body_start = header_end + 4
    
    # Parse status
    first_line = header_data.split("\r\n")[0]
    status_code = int(first_line.split()[1])
    
    # Parse headers
    headers = {}
    for line in header_data.split("\r\n")[1:]:
        if ":" in line:
            key, value = line.split(":", 1)
            headers[key.strip().lower()] = value.strip()
    
    # Get content length
    content_length = int(headers.get("content-length", 0))
    
    # Read remaining body if needed
    body_received = len(response) - body_start
    while body_received < content_length:
        remaining = content_length - body_received
        chunk = sock.recv(min(remaining, 65536))
        if not chunk:
            break
        body_received += len(chunk)
    
    return status_code, content_length, headers


def worker(worker_id, request_queue, result_queue):
    """Worker thread that maintains a persistent connection."""
    global running
    
    sock = None
    requests_on_connection = 0
    
    while running:
        try:
            # Get next request with timeout
            try:
                endpoint = request_queue.get(timeout=1)
            except queue.Empty:
                continue
            
            if endpoint is None:  # Poison pill
                break
            
            # Create/recreate connection if needed
            if sock is None or requests_on_connection >= REQUESTS_PER_CONNECTION:
                if sock:
                    try:
                        sock.close()
                    except:
                        pass
                
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(TIMEOUT)
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                
                try:
                    sock.connect((HOST, PORT))
                    requests_on_connection = 0
                except Exception as e:
                    with stats_lock:
                        stats["connection_errors"] += 1
                    request_queue.put(endpoint)  # Re-queue the request
                    sock = None
                    time.sleep(0.1)
                    continue
            
            # Send request
            start = time.perf_counter()
            try:
                sock.sendall(create_request(endpoint, keep_alive=True))
                
                with stats_lock:
                    stats["requests_sent"] += 1
                
                # Receive response
                status, body_len, headers = parse_response(sock)
                
                if status is None:
                    raise Exception("Connection closed by server")
                
                elapsed = (time.perf_counter() - start) * 1000  # ms
                
                with stats_lock:
                    stats["requests_completed"] += 1
                    stats["bytes_received"] += body_len
                    stats["latencies"].append(elapsed)
                    stats["per_endpoint"][endpoint]["count"] += 1
                    stats["per_endpoint"][endpoint]["bytes"] += body_len
                    stats["per_endpoint"][endpoint]["latencies"].append(elapsed)
                
                requests_on_connection += 1
                
            except Exception as e:
                with stats_lock:
                    stats["requests_failed"] += 1
                
                # Close and recreate connection on error
                try:
                    sock.close()
                except:
                    pass
                sock = None
                requests_on_connection = 0
                time.sleep(0.01)
        
        except Exception as e:
            with stats_lock:
                stats["requests_failed"] += 1
    
    # Cleanup
    if sock:
        try:
            sock.close()
        except:
            pass


def stats_printer():
    """Print statistics every few seconds."""
    global running, start_time
    
    last_completed = 0
    last_bytes = 0
    last_time = time.time()
    
    while running:
        time.sleep(5)
        
        with stats_lock:
            completed = stats["requests_completed"]
            failed = stats["requests_failed"]
            sent = stats["requests_sent"]
            bytes_recv = stats["bytes_received"]
            conn_errors = stats["connection_errors"]
            latencies = stats["latencies"][-1000:] if stats["latencies"] else []
        
        now = time.time()
        elapsed = now - start_time
        interval = now - last_time
        
        # Calculate rates
        rps = (completed - last_completed) / interval if interval > 0 else 0
        mbps = (bytes_recv - last_bytes) / 1024 / 1024 / interval if interval > 0 else 0
        
        # Calculate latency stats
        if latencies:
            avg_lat = statistics.mean(latencies)
            p50 = statistics.median(latencies)
            p99 = sorted(latencies)[int(len(latencies) * 0.99)] if len(latencies) >= 100 else max(latencies)
        else:
            avg_lat = p50 = p99 = 0
        
        # Get memory usage
        try:
            import resource
            mem_mb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024 / 1024
        except:
            mem_mb = 0
        
        print(f"\n{'='*60}")
        print(f"[{elapsed:.1f}s] STRESS TEST STATISTICS")
        print(f"{'='*60}")
        print(f"Requests: {completed:,} completed, {failed:,} failed, {sent:,} sent")
        print(f"Progress: {completed/TOTAL_REQUESTS*100:.1f}% ({completed:,}/{TOTAL_REQUESTS:,})")
        print(f"Rate: {rps:,.1f} req/s, {mbps:.2f} MB/s")
        print(f"Data: {bytes_recv/1024/1024:.2f} MB received")
        print(f"Latency: avg={avg_lat:.2f}ms, p50={p50:.2f}ms, p99={p99:.2f}ms")
        print(f"Errors: {conn_errors} connection errors")
        print(f"Client Memory: {mem_mb:.1f} MB")
        print(f"{'='*60}")
        
        last_completed = completed
        last_bytes = bytes_recv
        last_time = now


def final_report():
    """Print final statistics."""
    elapsed = time.time() - start_time
    
    print("\n" + "="*70)
    print("FINAL STRESS TEST REPORT")
    print("="*70)
    
    with stats_lock:
        completed = stats["requests_completed"]
        failed = stats["requests_failed"]
        bytes_recv = stats["bytes_received"]
        conn_errors = stats["connection_errors"]
        latencies = stats["latencies"]
        per_endpoint = dict(stats["per_endpoint"])
    
    print(f"\nDuration: {elapsed:.2f} seconds")
    print(f"\nRequests:")
    print(f"  Total Completed: {completed:,}")
    print(f"  Total Failed: {failed:,}")
    print(f"  Success Rate: {completed/(completed+failed)*100:.2f}%" if (completed+failed) > 0 else "  Success Rate: N/A")
    print(f"  Throughput: {completed/elapsed:,.2f} req/s")
    
    print(f"\nData Transfer:")
    print(f"  Total Received: {bytes_recv/1024/1024:.2f} MB")
    print(f"  Bandwidth: {bytes_recv/1024/1024/elapsed:.2f} MB/s")
    
    if latencies:
        print(f"\nLatency (ms):")
        print(f"  Min: {min(latencies):.2f}")
        print(f"  Max: {max(latencies):.2f}")
        print(f"  Mean: {statistics.mean(latencies):.2f}")
        print(f"  Median: {statistics.median(latencies):.2f}")
        if len(latencies) >= 100:
            sorted_lat = sorted(latencies)
            print(f"  P90: {sorted_lat[int(len(sorted_lat)*0.9)]:.2f}")
            print(f"  P95: {sorted_lat[int(len(sorted_lat)*0.95)]:.2f}")
            print(f"  P99: {sorted_lat[int(len(sorted_lat)*0.99)]:.2f}")
    
    print(f"\nConnection Errors: {conn_errors}")
    
    print("\nPer-Endpoint Statistics:")
    print("-" * 50)
    print(f"{'Endpoint':<15} {'Count':>10} {'MB':>10} {'Avg Lat':>10}")
    print("-" * 50)
    for endpoint in sorted(per_endpoint.keys()):
        data = per_endpoint[endpoint]
        avg_lat = statistics.mean(data["latencies"]) if data["latencies"] else 0
        print(f"{endpoint:<15} {data['count']:>10,} {data['bytes']/1024/1024:>10.2f} {avg_lat:>10.2f}ms")
    
    print("="*70)


def main():
    global running, start_time
    
    print("="*60)
    print("AURORA STRESS TEST CLIENT")
    print("="*60)
    print(f"Target: {HOST}:{PORT}")
    print(f"Connections: {NUM_CONNECTIONS}")
    print(f"Total Requests: {TOTAL_REQUESTS:,}")
    print(f"Requests/Connection: {REQUESTS_PER_CONNECTION}")
    print("="*60)
    
    # Wait for server
    print("\nWaiting for server...", end="", flush=True)
    for _ in range(30):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(1)
            sock.connect((HOST, PORT))
            sock.close()
            print(" OK!")
            break
        except:
            print(".", end="", flush=True)
            time.sleep(1)
    else:
        print(" FAILED!")
        print("Server not responding. Exiting.")
        sys.exit(1)
    
    # Create request queue
    request_queue = queue.Queue()
    result_queue = queue.Queue()
    
    # Pre-populate queue with requests
    print(f"\nQueuing {TOTAL_REQUESTS:,} requests...")
    for _ in range(TOTAL_REQUESTS):
        endpoint = random.choice(WEIGHTED_ENDPOINTS)
        request_queue.put(endpoint)
    
    # Add poison pills for workers
    for _ in range(NUM_CONNECTIONS):
        request_queue.put(None)
    
    start_time = time.time()
    
    # Start stats printer
    stats_thread = threading.Thread(target=stats_printer, daemon=True)
    stats_thread.start()
    
    # Start workers with gradual ramp-up
    print(f"\nRamping up {NUM_CONNECTIONS} workers over {RAMP_UP_TIME}s...")
    workers = []
    delay_per_worker = RAMP_UP_TIME / NUM_CONNECTIONS
    
    for i in range(NUM_CONNECTIONS):
        t = threading.Thread(target=worker, args=(i, request_queue, result_queue), daemon=True)
        t.start()
        workers.append(t)
        if i < NUM_CONNECTIONS - 1:
            time.sleep(delay_per_worker)
    
    print(f"All {NUM_CONNECTIONS} workers started!")
    
    # Wait for completion
    try:
        while True:
            with stats_lock:
                completed = stats["requests_completed"]
                failed = stats["requests_failed"]
            
            if completed + failed >= TOTAL_REQUESTS:
                break
            
            time.sleep(0.5)
    
    except KeyboardInterrupt:
        print("\n\nInterrupted by user!")
    
    running = False
    
    # Wait for workers
    print("\nWaiting for workers to finish...")
    for t in workers:
        t.join(timeout=5)
    
    final_report()


if __name__ == "__main__":
    main()
