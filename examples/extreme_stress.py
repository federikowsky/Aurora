#!/usr/bin/env python3
"""
EXTREME Stress Test - Push server to limits

Target: ~14GB memory usage (90% of 16GB)
- 500K requests
- Many huge payloads
- Memory-intensive POST requests
- Maximum concurrency
"""

import socket
import threading
import time
import random
import sys
import queue
import statistics
from collections import defaultdict

# EXTREME Configuration
HOST = "127.0.0.1"
PORT = 8080
NUM_CONNECTIONS = 1000      # More connections
REQUESTS_PER_CONNECTION = 500
TOTAL_REQUESTS = 500_000    # 500K requests
TIMEOUT = 60

# Heavy endpoint distribution - focus on large payloads
ENDPOINTS = [
    ("/", 10),              # minimal
    ("/small", 15),         # 1KB
    ("/medium", 25),        # 64KB
    ("/large", 30),         # 512KB
    ("/huge", 15),          # 2MB
    ("/json", 5),           # dynamic
]

# POST endpoint with body
POST_BODY_SIZES = [1024, 4096, 16384, 65536]  # 1K to 64K

WEIGHTED_ENDPOINTS = []
for endpoint, weight in ENDPOINTS:
    WEIGHTED_ENDPOINTS.extend([endpoint] * weight)

# Statistics
stats = {
    "requests_sent": 0,
    "requests_completed": 0,
    "requests_failed": 0,
    "bytes_sent": 0,
    "bytes_received": 0,
    "connection_errors": 0,
    "latencies": [],
    "per_endpoint": defaultdict(lambda: {"count": 0, "bytes": 0}),
}
stats_lock = threading.Lock()

running = True
start_time = None


def create_request(endpoint, keep_alive=True, body=None):
    """Create HTTP request."""
    connection = "keep-alive" if keep_alive else "close"
    method = "POST" if body else "GET"
    
    req = (
        f"{method} {endpoint} HTTP/1.1\r\n"
        f"Host: localhost:{PORT}\r\n"
        f"Connection: {connection}\r\n"
    )
    
    if body:
        req += f"Content-Length: {len(body)}\r\n"
        req += f"Content-Type: application/octet-stream\r\n"
    
    req += "\r\n"
    
    if body:
        return req.encode() + body
    return req.encode()


def parse_response(sock):
    """Parse HTTP response."""
    response = b""
    
    while True:
        try:
            chunk = sock.recv(65536)
            if not chunk:
                return None, 0
            response += chunk
            
            if b"\r\n\r\n" in response:
                header_end = response.find(b"\r\n\r\n")
                header_data = response[:header_end].decode("utf-8", errors="ignore")
                
                # Get content length
                content_length = 0
                for line in header_data.split("\r\n"):
                    if line.lower().startswith("content-length:"):
                        content_length = int(line.split(":")[1].strip())
                        break
                
                body_start = header_end + 4
                body_received = len(response) - body_start
                
                # Read remaining body
                while body_received < content_length:
                    remaining = content_length - body_received
                    chunk = sock.recv(min(remaining, 65536))
                    if not chunk:
                        break
                    body_received += len(chunk)
                    response += chunk
                
                # Get status
                status = int(header_data.split("\r\n")[0].split()[1])
                return status, content_length
                
        except socket.timeout:
            return None, 0
        except Exception as e:
            return None, 0
    
    return None, 0


def worker(worker_id, request_queue):
    """Worker with persistent connection."""
    global running
    
    sock = None
    requests_on_conn = 0
    
    while running:
        try:
            try:
                task = request_queue.get(timeout=0.5)
            except queue.Empty:
                continue
            
            if task is None:
                break
            
            endpoint, body = task
            
            # Create connection if needed
            if sock is None or requests_on_conn >= REQUESTS_PER_CONNECTION:
                if sock:
                    try: sock.close()
                    except: pass
                
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(TIMEOUT)
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 262144)
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 262144)
                
                try:
                    sock.connect((HOST, PORT))
                    requests_on_conn = 0
                except Exception:
                    with stats_lock:
                        stats["connection_errors"] += 1
                    request_queue.put(task)
                    sock = None
                    time.sleep(0.05)
                    continue
            
            # Send request
            start = time.perf_counter()
            try:
                req_data = create_request(endpoint, keep_alive=True, body=body)
                sock.sendall(req_data)
                
                with stats_lock:
                    stats["requests_sent"] += 1
                    stats["bytes_sent"] += len(req_data)
                
                status, body_len = parse_response(sock)
                
                if status is None:
                    raise Exception("No response")
                
                elapsed = (time.perf_counter() - start) * 1000
                
                with stats_lock:
                    stats["requests_completed"] += 1
                    stats["bytes_received"] += body_len
                    if len(stats["latencies"]) < 100000:
                        stats["latencies"].append(elapsed)
                    stats["per_endpoint"][endpoint]["count"] += 1
                    stats["per_endpoint"][endpoint]["bytes"] += body_len
                
                requests_on_conn += 1
                
            except Exception as e:
                with stats_lock:
                    stats["requests_failed"] += 1
                try: sock.close()
                except: pass
                sock = None
                requests_on_conn = 0
                
        except Exception as e:
            with stats_lock:
                stats["requests_failed"] += 1
    
    if sock:
        try: sock.close()
        except: pass


def monitor():
    """Monitor system and print stats."""
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
            bytes_sent = stats["bytes_sent"]
            conn_errors = stats["connection_errors"]
            latencies = stats["latencies"][-10000:]
        
        now = time.time()
        elapsed = now - start_time
        interval = now - last_time
        
        rps = (completed - last_completed) / interval if interval > 0 else 0
        mbps_out = (bytes_sent - 0) / 1024 / 1024 / elapsed if elapsed > 0 else 0
        mbps_in = (bytes_recv - last_bytes) / 1024 / 1024 / interval if interval > 0 else 0
        
        if latencies:
            avg_lat = statistics.mean(latencies)
            p99 = sorted(latencies)[int(len(latencies) * 0.99)] if len(latencies) >= 100 else max(latencies)
        else:
            avg_lat = p99 = 0
        
        # Memory check
        try:
            import resource
            mem_mb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024 / 1024
        except:
            mem_mb = 0
        
        progress = completed / TOTAL_REQUESTS * 100
        
        print(f"\r[{elapsed:6.1f}s] {completed:>7,}/{TOTAL_REQUESTS:,} ({progress:5.1f}%) | "
              f"{rps:,.0f} req/s | {mbps_in:.1f} MB/s | "
              f"lat={avg_lat:.1f}ms p99={p99:.1f}ms | "
              f"err={failed} | mem={mem_mb:.0f}MB", end="", flush=True)
        
        last_completed = completed
        last_bytes = bytes_recv
        last_time = now


def main():
    global running, start_time
    
    print("="*70)
    print("EXTREME STRESS TEST - TARGET: BREAK THE SERVER")
    print("="*70)
    print(f"Target: {HOST}:{PORT}")
    print(f"Connections: {NUM_CONNECTIONS}")
    print(f"Total Requests: {TOTAL_REQUESTS:,}")
    print(f"Focus: Large payloads (64KB-2MB)")
    print("="*70)
    
    # Wait for server
    print("\nConnecting to server...", end="", flush=True)
    for _ in range(10):
        try:
            sock = socket.socket()
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
        sys.exit(1)
    
    # Create queue
    request_queue = queue.Queue()
    
    # Generate workload
    print(f"\nGenerating {TOTAL_REQUESTS:,} requests...")
    for i in range(TOTAL_REQUESTS):
        endpoint = random.choice(WEIGHTED_ENDPOINTS)
        
        # 10% chance of POST with body
        if random.random() < 0.1:
            body_size = random.choice(POST_BODY_SIZES)
            body = b'X' * body_size
            request_queue.put(("/echo", body))
        else:
            request_queue.put((endpoint, None))
        
        if i % 100000 == 0 and i > 0:
            print(f"  {i:,} requests queued...")
    
    # Poison pills
    for _ in range(NUM_CONNECTIONS):
        request_queue.put(None)
    
    print(f"Queue ready with {TOTAL_REQUESTS:,} requests")
    
    start_time = time.time()
    
    # Start monitor
    monitor_thread = threading.Thread(target=monitor, daemon=True)
    monitor_thread.start()
    
    # Start workers fast
    print(f"\nStarting {NUM_CONNECTIONS} workers...")
    workers = []
    for i in range(NUM_CONNECTIONS):
        t = threading.Thread(target=worker, args=(i, request_queue), daemon=True)
        t.start()
        workers.append(t)
    
    print("All workers started!\n")
    
    # Wait
    try:
        while True:
            with stats_lock:
                done = stats["requests_completed"] + stats["requests_failed"]
            if done >= TOTAL_REQUESTS:
                break
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\n\nInterrupted!")
    
    running = False
    time.sleep(2)
    
    # Final report
    elapsed = time.time() - start_time
    
    print("\n\n" + "="*70)
    print("FINAL REPORT")
    print("="*70)
    
    with stats_lock:
        completed = stats["requests_completed"]
        failed = stats["requests_failed"]
        bytes_recv = stats["bytes_received"]
        bytes_sent = stats["bytes_sent"]
        latencies = stats["latencies"]
    
    print(f"\nDuration: {elapsed:.2f}s")
    print(f"Completed: {completed:,} ({completed/TOTAL_REQUESTS*100:.1f}%)")
    print(f"Failed: {failed:,}")
    print(f"Throughput: {completed/elapsed:,.0f} req/s")
    print(f"Data IN: {bytes_recv/1024/1024/1024:.2f} GB ({bytes_recv/1024/1024/elapsed:.1f} MB/s)")
    print(f"Data OUT: {bytes_sent/1024/1024:.1f} MB")
    
    if latencies:
        sorted_lat = sorted(latencies)
        print(f"\nLatency: min={min(latencies):.2f}ms, avg={statistics.mean(latencies):.2f}ms, "
              f"max={max(latencies):.2f}ms")
        if len(sorted_lat) >= 100:
            print(f"         p50={sorted_lat[len(sorted_lat)//2]:.2f}ms, "
                  f"p95={sorted_lat[int(len(sorted_lat)*0.95)]:.2f}ms, "
                  f"p99={sorted_lat[int(len(sorted_lat)*0.99)]:.2f}ms")
    
    print("="*70)


if __name__ == "__main__":
    main()
