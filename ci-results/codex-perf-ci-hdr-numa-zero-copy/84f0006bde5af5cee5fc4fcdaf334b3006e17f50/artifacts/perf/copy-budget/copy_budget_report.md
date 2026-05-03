# Aurora Zero-Copy / Copy-Budget Static Report

- Mode: `report-only`
- Status: `pass`
- Scanned files: `12`
- Findings: `71`

This report flags obvious markers only. Reviewers must still validate lifetime, ownership, and hot-path placement manually.

## Findings

| Path | Line | Pattern | Text |
| --- | ---: | --- | --- |
| `source/aurora/http/package.d` | 420 | `to_string` | `headers["Content-Length"] = content.length.to!string;` |
| `source/aurora/http/package.d` | 428 | `appender` | `auto result = appender!string();` |
| `source/aurora/http/package.d` | 432 | `to_string` | `result ~= statusCode.to!string;` |
| `source/aurora/http/url.d` | 180 | `dup_idup` | `return input.idup;` |
| `source/aurora/http/url.d` | 228 | `dup_idup` | `return input.idup;` |
| `source/aurora/http/url.d` | 315 | `dup_idup` | `return DecodeResult(input.idup, true, null);` |
| `source/aurora/http/url.d` | 322 | `gc_new` | `char[] result = new char[input.length];` |
| `source/aurora/http/url.d` | 398 | `string_concat` | `return c == '-' \|\| c == '.' \|\| c == '_' \|\| c == '~';` |
| `source/aurora/mem/arena.d` | 181 | `string_concat` | `~this()` |
| `source/aurora/mem/arena.d` | 291 | `string_concat` | `return (value + alignment - 1) & ~(alignment - 1);` |
| `source/aurora/mem/object_pool.d` | 194 | `gc_new` | `return new T();` |
| `source/aurora/mem/object_pool.d` | 199 | `gc_new` | `return new T();` |
| `source/aurora/mem/pool.d` | 231 | `string_concat` | `~this()` |
| `source/aurora/mem/pressure.d` | 603 | `gc_new` | `auto monitor = new MemoryMonitor();` |
| `source/aurora/mem/pressure.d` | 614 | `gc_new` | `auto monitor = new MemoryMonitor(config);` |
| `source/aurora/mem/pressure.d` | 624 | `gc_new` | `auto monitor = new MemoryMonitor();` |
| `source/aurora/mem/pressure.d` | 633 | `gc_new` | `auto monitor = new MemoryMonitor();` |
| `source/aurora/mem/pressure.d` | 647 | `gc_new` | `auto monitor = new MemoryMonitor(config);` |
| `source/aurora/mem/pressure.d` | 656 | `gc_new` | `auto monitor = new MemoryMonitor();` |
| `source/aurora/mem/pressure.d` | 668 | `gc_new` | `auto monitor = new MemoryMonitor();` |
| `source/aurora/mem/pressure.d` | 681 | `gc_new` | `auto monitor = new MemoryMonitor();` |
| `source/aurora/runtime/server.d` | 206 | `gc_new` | `auto heapBuf = new ubyte[body_.length + 512];` |
| `source/aurora/runtime/server.d` | 233 | `string_concat` | `auto body_ = `{"error":"` ~ message ~ `"}`;` |
| `source/aurora/runtime/server.d` | 260 | `gc_new` | `data = new ubyte[bufSize];` |
| `source/aurora/runtime/server.d` | 417 | `gc_new` | `throw new Exception("Exception handler cannot be null");` |
| `source/aurora/runtime/server.d` | 449 | `gc_new` | `throw new Exception("Exception handler cannot be null");` |
| `source/aurora/runtime/server.d` | 492 | `gc_new` | `throw new Exception("onStart hook failed: " ~ e.msg);` |
| `source/aurora/runtime/server.d` | 492 | `string_concat` | `throw new Exception("onStart hook failed: " ~ e.msg);` |
| `source/aurora/runtime/server.d` | 516 | `gc_new` | `throw new Exception("Failed to start server: " ~ e.msg);` |
| `source/aurora/runtime/server.d` | 516 | `string_concat` | `throw new Exception("Failed to start server: " ~ e.msg);` |
| `source/aurora/runtime/server.d` | 536 | `gc_new` | `workerPool = new WorkerPool(` |
| `source/aurora/runtime/server.d` | 997 | `string_concat` | `"HTTP/1.1 503 Service Unavailable\r\n" ~` |
| `source/aurora/runtime/server.d` | 998 | `string_concat` | `"Content-Type: application/json\r\n" ~` |
| `source/aurora/runtime/server.d` | 999 | `string_concat` | `"Retry-After: %d\r\n" ~` |
| `source/aurora/runtime/server.d` | 1000 | `string_concat` | `"Connection: close\r\n" ~` |
| `source/aurora/runtime/server.d` | 1001 | `string_concat` | `"Content-Length: %d\r\n" ~` |
| `source/aurora/runtime/server.d` | 1026 | `gc_new` | `if (_pool is null) _pool = new BufferPool();` |
| `source/aurora/runtime/server.d` | 1205 | `string_concat` | `"HTTP/1.1 503 Service Unavailable\r\n" ~` |
| `source/aurora/runtime/server.d` | 1206 | `string_concat` | `"Content-Type: application/json\r\n" ~` |
| `source/aurora/runtime/server.d` | 1207 | `string_concat` | `"Retry-After: %d\r\n" ~` |
| `source/aurora/runtime/server.d` | 1208 | `string_concat` | `"Connection: close\r\n" ~` |
| `source/aurora/runtime/server.d` | 1209 | `string_concat` | `"Content-Length: %d\r\n" ~` |
| `source/aurora/runtime/server.d` | 1347 | `string_concat` | `try { logError("Exception after hijack: " ~ e.msg); } catch (Exception) {}` |
| `source/aurora/runtime/server.d` | 1379 | `dup_idup` | `return stackBuf[0..len].dup;` |
| `source/aurora/runtime/server.d` | 1382 | `gc_new` | `auto heapBuf = new ubyte[body_.length + 512];` |
| `source/aurora/runtime/server.d` | 1387 | `dup_idup` | `return cast(ubyte[])"HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n".dup;` |
| `source/aurora/runtime/server.d` | 1400 | `gc_new` | `auto server = new Server(router, config);` |
| `source/aurora/runtime/server.d` | 1407 | `gc_new` | `auto server = new Server(router, config);` |
| `source/aurora/runtime/server.d` | 1416 | `gc_new` | `auto server = new Server(router, pipeline, config);` |
| `source/aurora/runtime/server.d` | 1423 | `gc_new` | `auto server = new Server(router, pipeline, config);` |
| `source/aurora/web/context.d` | 297 | `gc_new` | `throw new Exception("Connection already hijacked");` |
| `source/aurora/web/context.d` | 299 | `gc_new` | `throw new Exception("Raw connection not available");` |
| `source/aurora/web/context.d` | 323 | `gc_new` | `throw new Exception("Connection already hijacked");` |
| `source/aurora/web/context.d` | 325 | `gc_new` | `throw new Exception("Raw connection not available");` |
| `source/aurora/web/context.d` | 361 | `gc_new` | `throw new Exception("Cannot set status: connection hijacked");` |
| `source/aurora/web/context.d` | 376 | `gc_new` | `throw new Exception("Cannot set header: connection hijacked");` |
| `source/aurora/web/context.d` | 391 | `gc_new` | `throw new Exception("Cannot send response: connection hijacked");` |
| `source/aurora/web/context.d` | 406 | `gc_new` | `throw new Exception("Cannot send JSON response: connection hijacked");` |
| `source/aurora/web/router.d` | 183 | `gc_new` | `throw new Exception("Handler cannot be null for route: " ~ method ~ " " ~ path);` |
| `source/aurora/web/router.d` | 183 | `string_concat` | `throw new Exception("Handler cannot be null for route: " ~ method ~ " " ~ path);` |
| `source/aurora/web/router.d` | 192 | `gc_new` | `methodTrees[method] = new RadixNode();` |
| `source/aurora/web/router.d` | 216 | `string_concat` | `addRoute("GET", prefix ~ path, handler);` |
| `source/aurora/web/router.d` | 221 | `string_concat` | `addRoute("POST", prefix ~ path, handler);` |
| `source/aurora/web/router.d` | 226 | `string_concat` | `addRoute("PUT", prefix ~ path, handler);` |
| `source/aurora/web/router.d` | 231 | `string_concat` | `addRoute("DELETE", prefix ~ path, handler);` |
| `source/aurora/web/router.d` | 236 | `string_concat` | `addRoute("PATCH", prefix ~ path, handler);` |
| `source/aurora/web/router.d` | 322 | `gc_new` | `throw new Exception("Circular router reference detected");` |
| `source/aurora/web/router.d` | 355 | `string_concat` | `includeRouter(subRouter, visited ~ other, nextAccumulatedPrefix);` |
| `source/aurora/web/router.d` | 409 | `string_concat` | `path = "/" ~ path;` |
| `source/aurora/web/router.d` | 516 | `gc_new` | `auto newNode = new RadixNode();` |
| `source/aurora/web/router.d` | 629 | `string_concat` | `childPath ~= "/" ~ child.prefix;` |
