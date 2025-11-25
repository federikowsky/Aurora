#!/usr/bin/env python3
"""
MEMORY STRESS TEST - Try to make the server consume lots of memory
by sending many large POST bodies and requesting huge responses
"""

import socket
import threading
import time
import random
import subprocess
import sys

HOST = "127.0.0.1"
PORT = 8080

# Memory-focused settings
NUM_CONNECTIONS = 200  # Moderate connections
REQUESTS_PER_CONNECTION = 500
TOTAL_REQUESTS = 100_000  # 100K focused requests

# Focus on memory consumption
POST_BODY_SIZE = 512 * 1024  # 512KB POST bodies
POST_RATIO = 0.3  # 30% POST requests with large bodies

stats = {
    "completed": 0,
    "failed": 0,
    "bytes_in": 0,
    "bytes_out": 0,
}
lock = threading.Lock()
start_time = None
running = True


def get_server_memory():
    """Get server memory usage in MB."""
    try:
        result = subprocess.run(
            ["ps", "-o", "rss=", "-p", 
             subprocess.check_output(["pgrep", "-f", "production_server"]).decode().strip().split()[0]],
            capture_output=True, text=True
        )
        return int(result.stdout.strip()) / 1024  # KB to MB
    except:
        return 0


def worker(worker_id):
    global running
    
    sock = None
    requests_done = 0
    
    while running and requests_done < REQUESTS_PER_CONNECTION:
        try:
            if sock is None:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(30)
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                sock.connect((HOST, PORT))
            
            # Decide request type
            if random.random() < POST_RATIO:
                # POST with large body
                body = b'M' * POST_BODY_SIZE
                request = (
                    f"POST /echo HTTP/1.1\r\n"
                    f"Host: localhost\r\n"
                    f"Content-Length: {len(body)}\r\n"
                    f"Connection: keep-alive\r\n\r\n"
                ).encode() + body
            else:
                # GET huge response
                endpoints = ["/huge", "/huge", "/large", "/medium"]
                ep = random.choice(endpoints)
                request = (
                    f"GET {ep} HTTP/1.1\r\n"
                    f"Host: localhost\r\n"
                    f"Connection: keep-alive\r\n\r\n"
                ).encode()
            
            sock.sendall(request)
            
            with lock:
                stats["bytes_out"] += len(request)
            
            # Read response
            response = b""
            content_length = None
            
            while True:
                chunk = sock.recv(1024*1024)  # 1MB buffer
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
            
            with lock:
                stats["completed"] += 1
                stats["bytes_in"] += len(response)
            
            requests_done += 1
            
        except Exception as e:
            with lock:
                stats["failed"] += 1
            if sock:
                try: sock.close()
                except: pass
                sock = None
            time.sleep(0.1)
    
    if sock:
        try: sock.close()
        except: pass


def monitor():
    global running, start_time
    
    last_completed = 0
    peak_memory = 0
    
    while running:
        time.sleep(5)
        
        with lock:
            completed = stats["completed"]
            failed = stats["failed"]
            bytes_in = stats["bytes_in"]
            bytes_out = stats["bytes_out"]
        
        elapsed = time.time() - start_time
        rps = (completed - last_completed) / 5
        mem = get_server_memory()
        if mem > peak_memory:
            peak_memory = mem
        
        total = completed + failed
        progress = total / TOTAL_REQUESTS * 100
        
        print(f"\r[{elapsed:5.0f}s] {completed:>7,}/{TOTAL_REQUESTS:,} ({progress:5.1f}%) | "
              f"{rps:5.0f} req/s | "
              f"IN:{bytes_in/1024/1024/1024:.2f}GB OUT:{bytes_out/1024/1024:.0f}MB | "
              f"SERVER MEM: {mem:.0f}MB (peak: {peak_memory:.0f}MB) | "
              f"err={failed}", end="", flush=True)
        
        last_completed = completed
        
        if total >= TOTAL_REQUESTS:
            break


def main():
    global start_time, running
    
    print("="*80)
    print("MEMORY STRESS TEST - Focus on Server Memory Usage")
    print("="*80)
    print(f"Target: {HOST}:{PORT}")
    print(f"Connections: {NUM_CONNECTIONS}")
    print(f"Requests: {TOTAL_REQUESTS:,}")
    print(f"POST body size: {POST_BODY_SIZE/1024}KB")
    print(f"POST ratio: {POST_RATIO*100}%")
    print(f"Focus: /huge (2MB) and /large (512KB) responses + large POST bodies")
    print("="*80)
    
    # Check server
    initial_mem = get_server_memory()
    print(f"\nServer initial memory: {initial_mem:.0f}MB")
    
    print("Connecting...", end="", flush=True)
    try:
        s = socket.socket()
        s.settimeout(2)
        s.connect((HOST, PORT))
        s.close()
        print(" OK!")
    except:
        print(" FAILED!")
        sys.exit(1)
    
    start_time = time.time()
    
    # Start monitor
    mon = threading.Thread(target=monitor, daemon=True)
    mon.start()
    
    print(f"\nStarting {NUM_CONNECTIONS} workers...")
    
    threads = []
    for i in range(NUM_CONNECTIONS):
        t = threading.Thread(target=worker, args=(i,), daemon=True)
        t.start()
        threads.append(t)
    
    print("Workers started!\n")
    
    # Wait for completion or timeout
    try:
        while True:
            with lock:
                done = stats["completed"] + stats["failed"]
            if done >= TOTAL_REQUESTS:
                break
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\n\nInterrupted!")
    
    running = False
    time.sleep(2)
    
    elapsed = time.time() - start_time
    final_mem = get_server_memory()
    
    print("\n\n" + "="*80)
    print("MEMORY STRESS TEST RESULTS")
    print("="*80)
    print(f"\nDuration: {elapsed:.2f}s")
    print(f"Completed: {stats['completed']:,}")
    print(f"Failed: {stats['failed']:,}")
    print(f"Throughput: {stats['completed']/elapsed:,.0f} req/s")
    print(f"\nData Transfer:")
    print(f"  IN (responses): {stats['bytes_in']/1024/1024/1024:.2f} GB")
    print(f"  OUT (requests): {stats['bytes_out']/1024/1024:.0f} MB")
    print(f"\nServer Memory:")
    print(f"  Initial: {initial_mem:.0f} MB")
    print(f"  Final: {final_mem:.0f} MB")
    print(f"  Change: {final_mem - initial_mem:+.0f} MB")
    print("="*80)


if __name__ == "__main__":
    main()
