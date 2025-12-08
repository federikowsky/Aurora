# Aurora Framework Roadmap

> **Current Version**: 1.0.0  
> **Last Updated**: 2025-12-07

This document outlines planned features for future Aurora releases. These features are **not implemented** in the current version.

---

## v1.1 - Performance Optimizations

### Memory Allocator Integration
- **mimalloc** (Microsoft, version ≥ 2.1)
- High-performance allocator with thread-local caching
- Linked as system allocator replacement
- **Rationale**: Superior fragmentation behavior, O(1) allocations, excellent multi-thread scaling

### Hashing Optimization
- **xxHash** (version ≥ 0.8)
- Non-cryptographic hash for routing, caching
- Custom D binding
- **Rationale**: xxHash3 offers 30GB/s+ throughput, ideal for hot paths

### Utility Enhancements
- Hash utilities (xxHash integration)
- SIMD wrappers for manual vectorization
- High-resolution timing utilities

---

## v1.2 - Extended Networking

### aurora.net.* Package
Reserved for additional network protocols:
- WebSocket support (aurora.net.websocket)
- Server-Sent Events (aurora.net.sse)
- Raw TCP/UDP abstractions (aurora.net.socket)
- Network utilities (aurora.net.util)

---

## v1.3 - Framework Extensions

### aurora.ext.* Package
Optional framework extensions:
- Template engines (aurora.ext.templates)
- Session management (aurora.ext.sessions)
- File upload handling (aurora.ext.uploads)
- Static file serving (aurora.ext.static)

---

## v2.0 - Enterprise Features

Features planned for major version 2:
- Dependency Injection
- Database Integration (ORM, query builder)
- OpenAPI/Swagger auto-generation
- Authentication & Authorization (JWT, OAuth2, RBAC)
- Background Jobs & Task Queue
- Advanced CLI Tool (code generation, scaffolding)
- GraphQL support
- Event System & Event Sourcing
- API Versioning
- Multi-Tenancy
- HTTP/2 full implementation

---

## Contributing

If you'd like to contribute to any roadmap items, please:
1. Check the [GitHub Issues](https://github.com/federikowsky/Aurora/issues) for existing discussions
2. Open a new issue to discuss your approach
3. Submit a pull request with your implementation

---

*This roadmap is subject to change based on community feedback and priorities.*
