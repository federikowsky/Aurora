# Aurora V0.5 - Solid Foundation Plan

**Data:** 3 Dicembre 2025  
**Versione Target:** V0.5.0  
**Stato:** 🚧 IN PROGRESS

---

## Executive Summary

**V0.5 "Solid Foundation"** si concentra su:
1. ✅ **Hardening critico** - Graceful shutdown, RFC compliance, reliability tests
2. 🚧 **Feature leggere** - Rate limiting, Request ID middleware
3. ❌ **Skip tool esterni** - OWASP ZAP, fuzz testing → V0.6 o V1.0

> **Obiettivo:** Rendere Aurora production-ready senza dipendenze esterne complesse.

---

## Versioni Precedenti

| Versione | Status | Contenuto |
|----------|--------|-----------|
| V0.3 | ✅ Done | Core HTTP server, multi-worker, routing, middleware, CORS, security headers |
| V0.4 | ✅ Done | Server Hooks, Exception Handlers, App fluent API |
| **V0.5** | 🚧 Current | Hardening + Feature leggere |

---

## 1. Hardening Critico

### 1.1 Graceful Shutdown Test ✅ DONE

**Priorità:** 🔴 ALTA  
**Effort:** Medio (3-4h)  
**File:** `tests/integration/graceful_shutdown_test.d`, `graceful_shutdown_test.py`

**Completato:**
- [x] Test API shutdown: `gracefulStop()`, `isShuttingDown()`
- [x] Test state machine e counters
- [x] Test `getRejectedDuringShutdown()` tracking
- [x] Framework test Python per integration testing

### 1.2 RFC 7230 Compliance - Host Header

**Priorità:** 🔴 ALTA  
**Effort:** Basso (1-2h)  
**File:** `tests/unit/http/http_test.d` (estendere)

**Requisiti:**
### 1.2 RFC 7230 Compliance - Host Header ✅ DONE

**Priorità:** 🔴 ALTA  
**Effort:** Basso (1-2h)  
**File:** `tests/unit/http/http_test.d` (Test 67-76)

**Completato:**
- [x] Host header obbligatorio per HTTP/1.1
- [x] Host header con porta esplicita
- [x] IPv6 format (`[::1]:8080`)
- [x] Multiple Host headers handling
- [x] Case sensitivity
- [x] HTTP/1.0 vs HTTP/1.1 requirements
- [x] Absolute URI handling

### 1.3 RFC 7230 Compliance - Content-Length ✅ DONE

**Priorità:** 🔴 ALTA  
**Effort:** Basso (1-2h)  
**File:** `tests/unit/http/http_test.d` (Test 77-86)

**Completato:**
- [x] Duplicate Content-Length → handled consistently
- [x] Negative Content-Length → handled
- [x] Overflow Content-Length → handled
- [x] Content-Length mismatch con body size
- [x] Content-Length con chunked encoding (mutual exclusion)
- [x] Zero Content-Length
- [x] Leading zeros
- [x] Transfer-Encoding precedence

### 1.4 Fiber Crash Isolation Test

**Priorità:** 🟡 MEDIA  
**Effort:** Medio (2-3h)  
**File:** `tests/integration/fiber_isolation_test.d`

**Requisiti:**
- [ ] Un crash in una fiber non deve crashare altre fiber
- [ ] Un crash in una fiber non deve crashare il worker
- [ ] Le risorse della fiber crashata devono essere rilasciate

### 1.5 Connection Limit Test

**Priorità:** 🟡 MEDIA  
**Effort:** Medio (2-3h)  
**File:** `tests/integration/connection_limit_test.py`

**Requisiti:**
- [ ] Testare comportamento con max_connections raggiunto
- [ ] Verificare che nuove connessioni vengano rifiutate gracefully
- [ ] Verificare recovery dopo che connessioni si liberano

---

## 2. Feature Leggere

### 2.1 Rate Limiting Middleware

**Priorità:** 🟡 MEDIA  
**Effort:** Medio (3-4h)  
**File:** `source/aurora/web/middleware/ratelimit.d`

**Design:**
```d
/// Rate limiting middleware con token bucket algorithm
struct RateLimitConfig {
    uint requestsPerSecond = 100;
    uint burstSize = 10;
    Duration windowSize = 1.seconds;
    
    // Identificatore client (default: IP)
    string function(ref Context) keyExtractor = (ref ctx) => ctx.request.remoteAddress;
}

/// Middleware factory
auto rateLimiter(RateLimitConfig config = RateLimitConfig()) {
    return (ref Context ctx, Handler next) {
        string key = config.keyExtractor(ctx);
        if (isRateLimited(key, config)) {
            ctx.status(429).header("Retry-After", "1").send("Too Many Requests");
            return;
        }
        next(ctx);
    };
}
```

**Test Cases:**
- [ ] Requests under limit pass through
- [ ] Requests over limit get 429
- [ ] Burst handling
- [ ] Window reset
- [ ] Per-client isolation
- [ ] Retry-After header

### 2.2 Request ID Middleware

**Priorità:** 🟢 BASSA  
**Effort:** Basso (1-2h)  
**File:** `source/aurora/web/middleware/requestid.d`

**Design:**
```d
/// Request ID middleware - aggiunge X-Request-ID a ogni request/response
auto requestIdMiddleware(string headerName = "X-Request-ID") {
    return (ref Context ctx, Handler next) {
        // Usa ID esistente o genera nuovo
        string requestId = ctx.request.header(headerName);
        if (requestId.empty) {
            requestId = generateUUID();
        }
        
        // Salva nel context per logging
        ctx.set("request_id", requestId);
        
        // Aggiungi alla response
        ctx.header(headerName, requestId);
        
        next(ctx);
    };
}
```

**Test Cases:**
- [ ] Genera UUID se non presente
- [ ] Preserva ID esistente se presente in request
- [ ] ID disponibile nel context
- [ ] ID presente nella response

### 2.3 P99 Latency Tracking

**Priorità:** 🟡 MEDIA  
**Effort:** Medio (2-3h)  
**File:** `source/aurora/metrics/package.d` (estendere)

**Requisiti:**
- [ ] Tracking p50, p90, p95, p99 latency
- [ ] Histogram con bucket configurabili
- [ ] Export Prometheus format
- [ ] Reset periodico (es. ogni minuto)

---

## 3. Riabilitare Test Disabilitati

### 3.1 Security Tests in middleware.disabled/

**Priorità:** 🔴 ALTA  
**Effort:** Basso (30min-1h)  
**Azione:** Spostare da `middleware.disabled/` a `middleware/`

**File da riabilitare:**
- [ ] `security_test.d` → già attivo? verificare
- [ ] `validation_test.d`
- [ ] `cors_test.d.disabled` → rimuovere .disabled
- [ ] `logger_test.d.disabled` → rimuovere .disabled

---

## 4. Documentazione

### 4.1 Aggiornare PRODUCTION_READINESS_AUDIT.md

**Priorità:** 🟢 BASSA  
**Effort:** Basso (1h)

**Azioni:**
- [ ] Aggiornare a V0.5
- [ ] Aggiornare metriche (test cases, coverage)
- [ ] Aggiornare gap analysis con test implementati
- [ ] Aggiornare checklist pre-production

### 4.2 Creare docs/CHANGELOG.md

**Priorità:** 🟢 BASSA  
**Effort:** Basso (30min)

---

## 5. Task Breakdown

### Fase 1: Hardening Critico (Settimana 1)

| # | Task | Effort | Status |
|---|------|--------|--------|
| 1.1 | Graceful shutdown test | 3-4h | ⬜ TODO |
| 1.2 | RFC Host header tests | 1-2h | ⬜ TODO |
| 1.3 | RFC Content-Length tests | 1-2h | ⬜ TODO |
| 1.4 | Fiber crash isolation test | 2-3h | ⬜ TODO |
| 1.5 | Connection limit test | 2-3h | ⬜ TODO |
| 1.6 | Riabilitare middleware.disabled/* | 1h | ⬜ TODO |

### Fase 2: Feature Leggere (Settimana 2)

| # | Task | Effort | Status |
|---|------|--------|--------|
| 2.1 | Rate limiting middleware | 3-4h | ⬜ TODO |
| 2.2 | Request ID middleware | 1-2h | ⬜ TODO |
| 2.3 | P99 latency tracking | 2-3h | ⬜ TODO |

### Fase 3: Documentazione (Fine)

| # | Task | Effort | Status |
|---|------|--------|--------|
| 3.1 | Aggiornare PRODUCTION_READINESS_AUDIT.md | 1h | ⬜ TODO |
| 3.2 | Aggiornare TEST_REGISTRY.md | 30min | ⬜ TODO |
| 3.3 | Creare CHANGELOG.md | 30min | ⬜ TODO |

---

## 6. Criteri di Completamento V0.5

### Must Have (Release Blocker)
- [ ] Graceful shutdown testato e funzionante
- [ ] RFC 7230 compliance per Host e Content-Length
- [ ] Tutti i test in middleware.disabled/ riabilitati e passanti
- [ ] Rate limiting middleware implementato

### Should Have
- [ ] Fiber crash isolation testato
- [ ] Connection limit testato
- [ ] Request ID middleware
- [ ] P99 latency tracking

### Nice to Have
- [ ] Documentazione completa aggiornata
- [ ] CHANGELOG.md

---

## 7. Metriche Target V0.5

| Metrica | V0.4 | Target V0.5 |
|---------|------|-------------|
| Test cases | 480+ | 520+ |
| Coverage media | 87% | 88%+ |
| Moduli ≥80% coverage | 17 | 19 |
| RFC compliance tests | Parziale | Completo |
| Middleware disponibili | 5 | 7 |

---

## 8. Dipendenze e Rischi

### Dipendenze
- Nessuna dipendenza esterna nuova
- Tutti i test implementabili con tool esistenti

### Rischi
| Rischio | Probabilità | Impatto | Mitigazione |
|---------|-------------|---------|-------------|
| Graceful shutdown complesso | Media | Alto | Iniziare con test semplici |
| Rate limiting performance | Bassa | Medio | Usare strutture dati efficienti |
| Test disabilitati broken | Bassa | Basso | Fix incrementali |

---

## 9. Post V0.5 (Roadmap)

### V0.6 - Advanced Testing
- OWASP ZAP integration
- Fuzz testing setup
- Soak test 24h
- Property-based testing

### V0.7 - Advanced Features
- WebSocket support
- HTTP/2 (se richiesto)
- Background jobs

### V1.0 - Production Release
- Full OWASP compliance
- Benchmark suite completa
- Documentation completa
- Security audit

---

*Piano creato il 26 Gennaio 2025*
