#!/usr/bin/env python3
"""
BOMB TEST - Try to exhaust server resources with concurrent connections
and sustained heavy load
"""

import socket
import threading
import time
import random
import sys
import os

HOST = "127.0.0.1"
PORT = 8080

# Aggressive settings
NUM_THREADS = 2000  # 2000 concurrent threads
REQUESTS_PER_THREAD = 1000
TOTAL_REQUESTS = NUM_THREADS * REQUESTS_PER_THREAD  # 2M requests!

stats = {
    "completed": 0,
    "failed": 0,
    "bytes": 0,
}
lock = threading.Lock()
start_time = None


def aggressive_worker(thread_id):
    """Aggressive worker - open/close connections rapidly."""
    global stats
    
    for i in range(REQUESTS_PER_THREAD):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            sock.connect((HOST, PORT))
            
            # Random endpoint
            endpoints = ["/", "/small", "/medium", "/large"]
            ep = random.choice(endpoints)
            
            request = f"GET {ep} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
            sock.sendall(request.encode())
            
            # Read response
            response = b""
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                response += chunk
                if b"\r\n\r\n" in response:
                    # Check content length
                    try:
                        header = response.split(b"\r\n\r\n")[0].decode()
                        for line in header.split("\r\n"):
                            if line.lower().startswith("content-length:"):
                                cl = int(line.split(":")[1])
                                body_start = response.find(b"\r\n\r\n") + 4
                                while len(response) - body_start < cl:
                                    more = sock.recv(65536)
                                    if not more:
                                        break
                                    response += more
                                break
                    except:
                        pass
                    break
            
            sock.close()
            
            with lock:
                stats["completed"] += 1
                stats["bytes"] += len(response)
                
        except Exception as e:
            with lock:
                stats["failed"] += 1
            try: sock.close()
            except: pass
        
        # Small delay to prevent complete chaos
        if i % 100 == 0:
            time.sleep(0.001)


def monitor():
    global start_time
    last_completed = 0
    
    while True:
        time.sleep(5)
        with lock:
            completed = stats["completed"]
            failed = stats["failed"]
            bytes_recv = stats["bytes"]
        
        elapsed = time.time() - start_time
        rps = (completed - last_completed) / 5
        total = completed + failed
        progress = total / TOTAL_REQUESTS * 100
        
        print(f"\r[{elapsed:.0f}s] {completed:,}/{TOTAL_REQUESTS:,} ({progress:.1f}%) | "
              f"{rps:.0f} req/s | {bytes_recv/1024/1024:.0f} MB | "
              f"fail={failed:,}", end="", flush=True)
        
        last_completed = completed
        
        if total >= TOTAL_REQUESTS:
            break


def main():
    global start_time
    
    print("="*70)
    print("BOMB TEST - 2000 CONCURRENT THREADS x 1000 REQUESTS EACH")
    print("="*70)
    print(f"Target: {HOST}:{PORT}")
    print(f"Threads: {NUM_THREADS:,}")
    print(f"Total Requests: {TOTAL_REQUESTS:,}")
    print("Strategy: Rapid connection open/close (NO keep-alive)")
    print("="*70)
    
    # Check server
    print("\nConnecting...", end="", flush=True)
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
    
    print(f"\nLaunching {NUM_THREADS} threads...")
    
    threads = []
    for i in range(NUM_THREADS):
        t = threading.Thread(target=aggressive_worker, args=(i,), daemon=True)
        threads.append(t)
    
    # Start all threads as fast as possible
    for t in threads:
        t.start()
    
    print("All threads launched!\n")
    
    # Wait for completion
    for t in threads:
        t.join()
    
    elapsed = time.time() - start_time
    
    print("\n\n" + "="*70)
    print("BOMB TEST RESULTS")
    print("="*70)
    print(f"Duration: {elapsed:.2f}s")
    print(f"Completed: {stats['completed']:,}")
    print(f"Failed: {stats['failed']:,}")
    print(f"Success Rate: {stats['completed']/(stats['completed']+stats['failed'])*100:.1f}%")
    print(f"Throughput: {stats['completed']/elapsed:,.0f} req/s")
    print(f"Data: {stats['bytes']/1024/1024:.1f} MB")
    print("="*70)


if __name__ == "__main__":
    main()
