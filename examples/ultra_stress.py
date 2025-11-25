#!/usr/bin/env python3
"""
ULTRA Stress Test - 1M requests, try to OOM the server
"""

import socket
import threading
import time
import random
import sys
import queue
import statistics
from collections import defaultdict
import resource

# ULTRA Configuration
HOST = "127.0.0.1"
PORT = 8080
NUM_CONNECTIONS = 500       # Fewer but more aggressive
REQUESTS_PER_CONNECTION = 2000
TOTAL_REQUESTS = 1_000_000  # 1M requests!
TIMEOUT = 30

# Focus on heavy endpoints
ENDPOINTS = [
    ("/huge", 40),          # 2MB - main target
    ("/large", 30),         # 512KB
    ("/medium", 20),        # 64KB
    ("/small", 10),         # 1KB
]

POST_BODY_SIZES = [64*1024, 256*1024, 512*1024]  # 64K to 512K POST bodies

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
    connection = "keep-alive" if keep_alive else "close"
    method = "POST" if body else "GET"
    
    req = f"{method} {endpoint} HTTP/1.1\r\nHost: localhost:{PORT}\r\nConnection: {connection}\r\n"
    
    if body:
        req += f"Content-Length: {len(body)}\r\nContent-Type: application/octet-stream\r\n"
    
    req += "\r\n"
    
    if body:
        return req.encode() + body
    return req.encode()


def parse_response(sock):
    response = b""
    
    while True:
        try:
            chunk = sock.recv(1024*1024)  # 1MB chunks for huge responses
            if not chunk:
                return None, 0
            response += chunk
            
            if b"\r\n\r\n" in response:
                header_end = response.find(b"\r\n\r\n")
                header_data = response[:header_end].decode("utf-8", errors="ignore")
                
                content_length = 0
                for line in header_data.split("\r\n"):
                    if line.lower().startswith("content-length:"):
                        content_length = int(line.split(":")[1].strip())
                        break
                
                body_start = header_end + 4
                body_received = len(response) - body_start
                
                while body_received < content_length:
                    remaining = content_length - body_received
                    chunk = sock.recv(min(remaining, 1024*1024))
                    if not chunk:
                        break
                    body_received += len(chunk)
                    response += chunk
                
                status = int(header_data.split("\r\n")[0].split()[1])
                return status, content_length
                
        except socket.timeout:
            return None, 0
        except Exception:
            return None, 0
    
    return None, 0


def worker(worker_id, request_queue):
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
            
            if sock is None or requests_on_conn >= REQUESTS_PER_CONNECTION:
                if sock:
                    try: sock.close()
                    except: pass
                
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(TIMEOUT)
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1024*1024)
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4*1024*1024)
                
                try:
                    sock.connect((HOST, PORT))
                    requests_on_conn = 0
                except Exception:
                    with stats_lock:
                        stats["connection_errors"] += 1
                    request_queue.put(task)
                    sock = None
                    time.sleep(0.01)
                    continue
            
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
                
            except Exception:
                with stats_lock:
                    stats["requests_failed"] += 1
                try: sock.close()
                except: pass
                sock = None
                requests_on_conn = 0
                
        except Exception:
            with stats_lock:
                stats["requests_failed"] += 1
    
    if sock:
        try: sock.close()
        except: pass


def monitor():
    global running, start_time
    
    last_completed = 0
    last_bytes = 0
    last_time = time.time()
    
    while running:
        time.sleep(5)
        
        with stats_lock:
            completed = stats["requests_completed"]
            failed = stats["requests_failed"]
            bytes_recv = stats["bytes_received"]
            bytes_sent = stats["bytes_sent"]
            conn_errors = stats["connection_errors"]
            latencies = stats["latencies"][-10000:]
        
        now = time.time()
        elapsed = now - start_time
        interval = now - last_time
        
        rps = (completed - last_completed) / interval if interval > 0 else 0
        mbps_in = (bytes_recv - last_bytes) / 1024 / 1024 / interval if interval > 0 else 0
        
        if latencies:
            avg_lat = statistics.mean(latencies)
            p99 = sorted(latencies)[int(len(latencies) * 0.99)] if len(latencies) >= 100 else max(latencies)
        else:
            avg_lat = p99 = 0
        
        # Memory check - this process
        try:
            mem_mb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024 / 1024
        except:
            mem_mb = 0
        
        progress = completed / TOTAL_REQUESTS * 100
        
        print(f"\r[{elapsed:6.1f}s] {completed:>9,}/{TOTAL_REQUESTS:,} ({progress:5.1f}%) | "
              f"{rps:,.0f} req/s | {mbps_in:.1f} MB/s | "
              f"lat={avg_lat:.1f}ms p99={p99:.1f}ms | "
              f"err={failed} conn_err={conn_errors}", end="", flush=True)
        
        last_completed = completed
        last_bytes = bytes_recv
        last_time = now
        
        if completed + failed >= TOTAL_REQUESTS:
            break


def main():
    global running, start_time
    
    print("="*80)
    print("ULTRA STRESS TEST - 1 MILLION REQUESTS")
    print("="*80)
    print(f"Target: {HOST}:{PORT}")
    print(f"Connections: {NUM_CONNECTIONS}")
    print(f"Total Requests: {TOTAL_REQUESTS:,}")
    print(f"Focus: HUGE payloads (2MB primary, 512KB secondary)")
    print("="*80)
    
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
    
    request_queue = queue.Queue()
    
    print(f"\nGenerating {TOTAL_REQUESTS:,} requests...")
    for i in range(TOTAL_REQUESTS):
        endpoint = random.choice(WEIGHTED_ENDPOINTS)
        
        # 5% chance of POST with large body
        if random.random() < 0.05:
            body_size = random.choice(POST_BODY_SIZES)
            body = b'X' * body_size
            request_queue.put(("/echo", body))
        else:
            request_queue.put((endpoint, None))
        
        if i % 200000 == 0 and i > 0:
            print(f"  {i:,} requests queued...")
    
    for _ in range(NUM_CONNECTIONS):
        request_queue.put(None)
    
    print(f"Queue ready with {TOTAL_REQUESTS:,} requests")
    
    start_time = time.time()
    
    monitor_thread = threading.Thread(target=monitor, daemon=True)
    monitor_thread.start()
    
    print(f"\nStarting {NUM_CONNECTIONS} workers...")
    workers = []
    for i in range(NUM_CONNECTIONS):
        t = threading.Thread(target=worker, args=(i, request_queue), daemon=True)
        t.start()
        workers.append(t)
    
    print("All workers started!\n")
    
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
    
    elapsed = time.time() - start_time
    
    print("\n\n" + "="*80)
    print("FINAL REPORT - 1 MILLION REQUESTS")
    print("="*80)
    
    with stats_lock:
        completed = stats["requests_completed"]
        failed = stats["requests_failed"]
        bytes_recv = stats["bytes_received"]
        bytes_sent = stats["bytes_sent"]
        conn_errors = stats["connection_errors"]
        latencies = stats["latencies"]
        per_endpoint = dict(stats["per_endpoint"])
    
    print(f"\nDuration: {elapsed:.2f}s")
    print(f"Completed: {completed:,} ({completed/TOTAL_REQUESTS*100:.1f}%)")
    print(f"Failed: {failed:,}")
    print(f"Connection Errors: {conn_errors:,}")
    print(f"Throughput: {completed/elapsed:,.0f} req/s")
    print(f"Data IN: {bytes_recv/1024/1024/1024:.2f} GB ({bytes_recv/1024/1024/elapsed:.1f} MB/s)")
    print(f"Data OUT: {bytes_sent/1024/1024:.1f} MB")
    
    if latencies:
        sorted_lat = sorted(latencies)
        print(f"\nLatency:")
        print(f"  min={min(latencies):.2f}ms")
        print(f"  avg={statistics.mean(latencies):.2f}ms")
        print(f"  max={max(latencies):.2f}ms")
        if len(sorted_lat) >= 100:
            print(f"  p50={sorted_lat[len(sorted_lat)//2]:.2f}ms")
            print(f"  p95={sorted_lat[int(len(sorted_lat)*0.95)]:.2f}ms")
            print(f"  p99={sorted_lat[int(len(sorted_lat)*0.99)]:.2f}ms")
    
    print("\nPer-endpoint breakdown:")
    for ep, data in sorted(per_endpoint.items(), key=lambda x: x[1]["bytes"], reverse=True):
        gb = data["bytes"] / 1024 / 1024 / 1024
        print(f"  {ep}: {data['count']:,} requests, {gb:.2f} GB")
    
    print("="*80)


if __name__ == "__main__":
    main()
