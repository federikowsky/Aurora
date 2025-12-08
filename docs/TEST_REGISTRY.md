# Aurora Test Registry

**Versione:** V0.5.0 "Solid Foundation"  
**Ultimo Aggiornamento:** 4 Dicembre 2025  
**Totale Test Cases:** 540+  
**Test Modules:** 31  
**Coverage Media:** 87%

---

## Indice

1. [Riepilogo Test Suite](#1-riepilogo-test-suite)
2. [Unit Tests](#2-unit-tests)
3. [Integration Tests](#3-integration-tests)
4. [Stress Tests](#4-stress-tests)
5. [Real-World Tests](#5-real-world-tests)
6. [Coverage per Modulo](#6-coverage-per-modulo)
7. [Matrice Test vs Requisiti](#7-matrice-test-vs-requisiti)
8. [Changelog Test](#8-changelog-test)

---

## 1. Riepilogo Test Suite

### 1.1 Statistiche Generali

| Metrica | Valore |
|---------|--------|
| File di test totali | 31 |
| Test cases (D) | 540+ |
| Test cases (Python) | 11 |
| LOC test | ~10,200 |
| LOC sorgente | ~8,400 |
| Rapporto test/source | 1.21:1 |

### 1.2 Distribuzione per Categoria

| Categoria | File | Test Cases | % Totale |
|-----------|------|------------|----------|
| Unit Tests | 23 | 480+ | 87% |
| Integration Tests | 6 | 60+ | 11% |
| Stress Tests | 1 | 15 | 2% |
| Real-World/Load | 4 | ~10 | <1% |

### 1.3 V0.5 New Tests

| File | Test Cases | Category |
|------|------------|----------|
| `ratelimit_test.d` | 25 | Middleware |
| `requestid_test.d` | 25 | Middleware |
| `percentile_test.d` | 25 | Metrics |
| `graceful_shutdown_test.d` | 10 | Integration |
| `fiber_isolation_test.d` | 20 | Integration |
| `connection_limits_test.d` | 20 | Integration |
| `logger_test.d` | 20 | Re-enabled |
| `validation_test.d` | 20 | Re-enabled |

---

## 2. Unit Tests

### 2.1 HTTP Module (`tests/unit/http/`)

#### `http_test.d` - 106 test cases

| # | Test Name | Categoria | Descrizione |
|---|-----------|-----------|-------------|
| 1-10 | Request Parsing | Parsing | GET, POST, headers, body |
| 11-20 | Response Building | Response | Status codes, headers, body |
| 21-30 | Edge Cases | Robustezza | Malformed requests, empty fields |
| 31-41 | Header Handling | Headers | Case-insensitive, duplicates |
| 42-55 | **HTTP Smuggling** | **Security** | OWASP WSTG-INPV-15 |
| 56-66 | Response Methods | API | buildInto, estimateSize, getters |
| 67-76 | **RFC 7230** | **Compliance** | Host + Content-Length validation |
| 77-86 | **RFC 7230** | **Compliance** | Transfer-Encoding, body handling |
| 87-96 | **WSTG-INPV-03** | **Security** | HTTP Verb Tampering |
| 97-106 | **WSTG-INPV-04** | **Security** | HTTP Parameter Pollution |

**RFC 7230 Host Header Tests (67-71):**

| # | Test | Descrizione |
|---|------|-------------|
| 67 | `missing Host header rejected HTTP/1.1` | HTTP/1.1 richiede Host |
| 68 | `multiple Host headers rejected` | Solo un Host consentito |
| 69 | `Host with port accepted` | `host:8080` valido |
| 70 | `empty Host header rejected` | Host vuoto non valido |
| 71 | `Host header case insensitive` | `host:` = `Host:` |

**RFC 7230 Content-Length Tests (72-76):**

| # | Test | Descrizione |
|---|------|-------------|
| 72 | `negative Content-Length rejected` | CL < 0 non valido |
| 73 | `non-numeric Content-Length rejected` | CL deve essere numerico |
| 74 | `duplicate Content-Length rejected` | Solo un CL consentito |
| 75 | `Content-Length matches body` | CL deve corrispondere |
| 76 | `Transfer-Encoding with CL rejected` | TE+CL non consentiti |

**OWASP WSTG-INPV-03 HTTP Verb Tampering Tests (87-96):** ✨ NEW (V0.5)

| # | Test | Descrizione |
|---|------|-------------|
| 87 | `Unknown HTTP method rejected` | Metodi custom rifiutati |
| 88 | `Method case sensitivity - lowercase` | `get` rifiutato |
| 89 | `Mixed case method rejected` | `GeT` rifiutato |
| 90 | `X-HTTP-Method-Override header parsing` | Header override riconosciuto |
| 91 | `X-Method-Override header parsing` | Variante X-Method-Override |
| 92 | `DEBUG method rejected` | Metodo IIS DEBUG rifiutato |
| 93 | `TRACE method parsed` | TRACE gestito (XST awareness) |
| 94 | `TRACK method rejected` | Metodo MS-specific rifiutato |
| 95 | `Method with null byte rejected` | Null byte injection prevenuta |
| 96 | `Very long method name rejected` | DoS via long method prevenuto |

**OWASP WSTG-INPV-04 HTTP Parameter Pollution Tests (97-106):** ✨ NEW (V0.5)

| # | Test | Descrizione |
|---|------|-------------|
| 97 | `Duplicate query parameters` | `id=1&id=2&id=3` preservato |
| 98 | `Mixed case parameter names` | `ID=1&id=2&Id=3` preservato |
| 99 | `URL encoded duplicate parameters` | `id=1&%69%64=2` preservato |
| 100 | `Array-style parameters` | `ids[]=1&ids[]=2` preservato |
| 101 | `Query and body parameter conflict` | Query vs body separati |
| 102 | `Null byte in parameter value` | Null byte preservato per sanitize |
| 103 | `Parameter without value` | `admin&debug` valido |
| 104 | `Empty parameter value` | `admin=&debug=` valido |
| 105 | `Semicolon as parameter separator` | `id=1;admin=true` preservato |
| 106 | `Multiple equals signs in value` | `token=abc==` preservato |
| Segment Extraction | 5 | Path segment parsing |
| Performance | 5 | Matching speed benchmarks |

#### `context_test.d` - 30 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Basic Operations | 8 | Create, request/response access |
| Storage (Inline) | 6 | set/get/has/remove (≤4 entries) |
| Storage (Overflow) | 6 | Heap allocation (>4 entries) |
| Helper Methods | 5 | status(), header(), send(), json() |
| Performance | 5 | Creation <100ns, access <10ns |

#### `middleware_test.d` - 15 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Chain Execution | 5 | Sequential middleware |
| Short-circuit | 3 | Early response |
| Error Handling | 4 | Exception propagation |
| Context Sharing | 3 | Storage between middleware |

#### `error_test.d` - 15 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Error Types | 5 | 4xx, 5xx creation |
| Error Response | 5 | JSON/HTML formatting |
| Stack Trace | 3 | Debug mode info |
| Custom Errors | 2 | User-defined errors |

#### `security_test.d` - 21 test cases ✨ NEW

| # | Test | Header | Descrizione |
|---|------|--------|-------------|
| 1-3 | CSP | Content-Security-Policy | Directive validation |
| 4-6 | HSTS | Strict-Transport-Security | max-age, includeSubDomains |
| 7-9 | X-Frame | X-Frame-Options | DENY, SAMEORIGIN |
| 10-12 | X-Content-Type | X-Content-Type-Options | nosniff |
| 13-15 | X-XSS | X-XSS-Protection | 1; mode=block |
| 16-18 | Referrer | Referrer-Policy | strict-origin |
| 19-21 | Integration | All Headers | Combined security headers |

#### `cors_test.d` - 20 test cases ✨ NEW

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Preflight | 5 | OPTIONS requests |
| Origin Validation | 5 | Allowed/denied origins |
| Headers | 5 | CORS response headers |
| Credentials | 3 | withCredentials support |
| Edge Cases | 2 | Malformed origins |

#### `logger_test.d` - 20 test cases ✨ NEW (V0.5)

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Creation | 3 | LoggerMiddleware, custom log function |
| Logging Behavior | 5 | Method, path, status logging |
| Format Tests | 3 | SIMPLE, JSON, COLORED formats |
| Null Safety | 2 | Null request/response handling |
| Duration | 1 | Duration measurement |
| Error Handling | 1 | Exception logging |
| Color Settings | 2 | Enable/disable colors |
| HTTP Methods | 3 | POST, PUT, DELETE logging |

#### `validation_test.d` - 20 test cases ✨ NEW (V0.5)

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| validateJSON | 8 | Simple, nested, bool, array schemas |
| Middleware Creation | 3 | ValidationMiddleware, helper |
| Exception | 1 | ValidationException creation |
| Middleware Config | 2 | Custom error message |
| Array Validation | 2 | Empty array, wrong element type |
| Edge Cases | 4 | Extra fields, null context, unicode |

#### `ratelimit_test.d` - 25 test cases ✨ NEW (V0.5)

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Basic Rate Limiting | 5 | Within limit, exceeded, burst |
| Token Bucket | 5 | Token consumption, refill |
| Response Codes | 3 | 429 Too Many Requests |
| Headers | 3 | Retry-After, X-RateLimit-* |
| Per-Client | 5 | IP extraction, X-Forwarded-For |
| Custom Keys | 2 | API key, custom extractor |
| Edge Cases | 2 | Empty IP, malformed headers |

#### `requestid_test.d` - 25 test cases ✨ NEW (V0.5)

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Basic Functionality | 5 | Creation, UUID generation |
| ID Preservation | 5 | Existing ID, validation |
| Custom Config | 4 | Header name, storage key, generator |
| Validation | 6 | UUID format, alphanumeric, length |
| Pipeline Integration | 3 | Middleware chain, availability |
| Factory Functions | 2 | requestIdMiddleware() variants |

---

### 2.3 Metrics Module (`tests/unit/metrics/`)

#### `metrics_test.d` - 25 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Counter | 5 | Increment, reset |
| Gauge | 5 | Set, increment, decrement |
| Histogram | 5 | Observe, buckets |
| Registry | 5 | Get/create metrics |
| Prometheus Export | 5 | Format, labels |

#### `percentile_test.d` - 25 test cases ✨ NEW (V0.5)

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Basic Operations | 5 | Create, observe, count, sum |
| Percentile Calculation | 5 | P50, P90, P95, P99, custom |
| Edge Cases | 5 | Single value, empty, reset |
| Registry Integration | 3 | Metrics.percentileHistogram() |
| Prometheus Export | 3 | Format with quantile labels |
| Latency Patterns | 2 | Typical usage, skewed data |
| Thread Safety | 2 | Concurrent observations |

---

### 2.4 Memory Module (`tests/unit/mem/`)

#### `buffer_pool_test.d` - 36 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Allocation | 10 | acquire/release |
| Pool Sizing | 8 | Growth, shrink |
| Thread Safety | 8 | Concurrent access |
| Performance | 10 | Throughput benchmarks |

#### `arena_test.d` - 18 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Basic Alloc | 6 | allocate, deallocate |
| Reset | 4 | Arena reset |
| Alignment | 4 | Memory alignment |
| Overflow | 4 | Capacity handling |

#### `object_pool_test.d` - 16 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Object Lifecycle | 6 | Create, reuse, destroy |
| Pool Management | 5 | Size, capacity |
| Thread Safety | 5 | Concurrent access |

---

### 2.4 Runtime Module (`tests/unit/runtime/`) ✨ NEW

#### `hooks_test.d` - 30+ test cases ✨ NEW (V0.4)

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| StartHook Registration | 4 | Single, multiple, ordering |
| StopHook Registration | 4 | Single, multiple, ordering |
| ErrorHook Registration | 4 | Single, multiple, context |
| RequestHook Registration | 4 | Single, multiple, context modify |
| ResponseHook Registration | 4 | Single, multiple, context modify |
| Hook Execution | 6 | Order preservation, empty hooks |
| Edge Cases | 4+ | Null handlers, exception in hooks |

**Coverage**: 100%

---

### 2.5 App Module (`tests/unit/`) ✨ NEW

#### `app_test.d` - 12 test cases ✨ NEW (V0.4)

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Fluent API | 5 | onStart, onStop, onError, onRequest, onResponse |
| Exception Handlers | 4 | addExceptionHandler, hasExceptionHandler |
| Routing | 2 | get, post methods |
| Edge Cases | 1 | Empty app |

**Coverage**: 85%+

---

### 2.6 Other Modules

#### `config_test.d` - 15 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Loading | 5 | File, env, defaults |
| Validation | 5 | Required fields, types |
| Merging | 5 | Override precedence |

#### `logger_test.d` - 26 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Log Levels | 6 | DEBUG, INFO, WARN, ERROR |
| Formatting | 8 | Timestamp, context |
| Output | 6 | Console, file |
| Performance | 6 | Async logging |

#### `metrics_test.d` - 25 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Counters | 8 | Increment, reset |
| Gauges | 6 | Set, get |
| Histograms | 6 | Buckets, percentiles |
| Export | 5 | Prometheus format |

#### `server_config_test.d` - 17 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Defaults | 5 | Default values |
| Validation | 6 | Port, workers, limits |
| Builder | 6 | Fluent configuration |

#### `json_test.d` - 6 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Serialize | 3 | Struct to JSON |
| Deserialize | 3 | JSON to struct |

#### `validation_test.d` - 6 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Required | 2 | Non-null validation |
| Range | 2 | Min/max validation |
| Pattern | 2 | Regex validation |

---

## 3. Integration Tests

### `graceful_shutdown_test.d` - 10 test cases ✨ NEW (V0.5)

| # | Test | Descrizione |
|---|------|-------------|
| 1-2 | Signal Handling | SIGTERM, SIGINT response |
| 3-4 | In-Flight Requests | Request completion before shutdown |
| 5-6 | Timeout Behavior | Shutdown timeout, forced termination |
| 7-8 | State Transitions | Running → Stopping → Stopped |
| 9-10 | Cleanup | Resource release, socket cleanup |

### `fiber_isolation_test.d` - 20 test cases ✨ NEW (V0.5)

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Request Isolation | 5 | Fiber-per-request isolation |
| Crash Containment | 5 | Exception doesn't crash server |
| State Isolation | 5 | No data leakage between requests |
| Recovery | 5 | Fiber pool recovery after error |

### `connection_limits_test.d` - 20 test cases ✨ NEW (V0.5)

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Max Connections | 5 | Connection limit enforcement |
| Graceful Rejection | 5 | 503 Service Unavailable |
| Connection Stats | 5 | Active connections API |
| Connection Reuse | 5 | Keep-alive behavior |

### `server_integration_test.d` - 20 test cases

| # | Test | Categoria | Descrizione |
|---|------|-----------|-------------|
| 1-5 | Server Lifecycle | Core | Start, stop, restart |
| 6-8 | Request Handling | Core | HTTP request flow |
| 9-11 | Middleware Pipeline | Core | Chain execution |
| 12-14 | ResponseBuffer | Memory | Buffer management |
| 15-17 | Graceful Shutdown | Reliability | In-flight completion |
| 18-20 | Server Stats | Monitoring | Request counting |

### `basic_flow_test.d` - 10 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Request Flow | 5 | End-to-end request |
| Response Flow | 5 | Response building |

### `performance_test.d` - 10 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Throughput | 5 | RPS measurement |
| Latency | 5 | Response time |

### `network_test.py` - 6 test cases

| Test | Descrizione |
|------|-------------|
| test_header_size_limit | 431 Request Header Fields Too Large |
| test_body_size_limit | 413 Payload Too Large |
| test_malformed_request | 400 Bad Request |
| test_timeout | Connection timeout handling |
| test_keepalive | Connection reuse |
| test_concurrent | Concurrent connections |

### `test_multiworker.py` - 5 test cases

| Test | Descrizione |
|------|-------------|
| test_multiworker_startup | Worker spawning |
| test_concurrent_requests | 2400+ RPS |
| test_worker_distribution | Load balancing |
| test_worker_crash_recovery | Resilience |
| test_graceful_shutdown | Clean shutdown |

### `fiber_isolation_test.py` - 10 test cases ✨ NEW (V0.5)

| Test | Descrizione |
|------|-------------|
| test_concurrent_requests | Multiple simultaneous requests |
| test_crash_isolation | Single request crash containment |
| test_memory_isolation | No shared state leakage |
| test_recovery | Server continues after error |
| test_performance | No isolation overhead |

### `graceful_shutdown_test.py` - 5 test cases ✨ NEW (V0.5)

| Test | Descrizione |
|------|-------------|
| test_sigterm_handling | SIGTERM triggers shutdown |
| test_inflight_completion | Requests complete before exit |
| test_timeout | Forced shutdown after timeout |
| test_clean_exit | Exit code 0 on success |

---

## 4. Stress Tests

### `crash_test.d` - 15 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Memory Pressure | 5 | High allocation |
| Concurrency | 5 | Race conditions |
| Resource Exhaustion | 5 | File handles, sockets |

---

## 5. Real-World Tests

### Load Testing Scripts

| File | Tipo | Descrizione |
|------|------|-------------|
| `spike_test.py` | Spike | Picchi improvvisi di traffico |
| `sustained_load.py` | Soak | Carico costante prolungato |
| `gradual_stress.py` | Ramp | Incremento graduale |
| `endpoint_mix.py` | Mix | Scenario realistico multi-endpoint |

---

## 6. Coverage per Modulo

### 6.1 Moduli ≥80% (Production Ready)

| Modulo | Coverage | Test File |
|--------|----------|-----------|
| `runtime/hooks.d` | 100% | hooks_test.d | ✨ NEW
| `web/middleware/security.d` | 100% | security_test.d |
| `web/context.d` | 100% | context_test.d |
| `schema/exceptions.d` | 100% | validation_test.d |
| `metrics/package.d` | 95% | metrics_test.d |
| `web/error.d` | 92% | error_test.d |
| `schema/validation.d` | 91% | validation_test.d |
| `http/package.d` | 89% | http_test.d |
| `web/router.d` | 89% | router_test.d |
| `mem/arena.d` | 86% | arena_test.d |
| `app.d` | 85% | app_test.d | ✨ NEW
| `mem/object_pool.d` | 84% | object_pool_test.d |
| `mem/pool.d` | 83% | buffer_pool_test.d |
| `config/package.d` | 81% | config_test.d |
| `schema/json.d` | 81% | json_test.d |
| `web/middleware/package.d` | 81% | middleware_test.d |
| `logging/package.d` | 80% | logger_test.d |

### 6.2 Moduli <80% (Monitorati)

| Modulo | Coverage | Note | Piano |
|--------|----------|------|-------|
| `web/middleware/cors.d` | 63% | Security middleware | Accettabile |
| `http/util.d` | 62% | Utility functions | Non critico |
| `web/middleware/logger.d` | 46% | Logging middleware | Non critico |
| `runtime/server.d` | 19% | Integration tested | test_multiworker.py |
| `web/middleware/validation.d` | 0% | Template | Opzionale |

---

## 7. Matrice Test vs Requisiti

### 7.1 OWASP WSTG Compliance

| WSTG-ID | Requisito | Test File | Status |
|---------|-----------|-----------|--------|
| WSTG-INPV-15 | HTTP Smuggling | http_test.d #42-55 | ✅ |
| WSTG-INPV-17 | Host Header Injection | http_test.d #50-51 | ✅ |
| WSTG-CONF-06 | HTTP Methods | router_test.d | ✅ |
| WSTG-CONF-12 | Security Headers | security_test.d | ✅ |

### 7.2 RFC Compliance

| RFC | Requisito | Test | Status |
|-----|-----------|------|--------|
| RFC 7230 | HTTP/1.1 Message Syntax | http_test.d | ⚠️ Parziale |
| RFC 7231 | HTTP/1.1 Semantics | http_test.d | ⚠️ Parziale |
| RFC 7234 | Caching | - | ❌ Non testato |
| RFC 7235 | Authentication | - | N/A (app-level) |

### 7.3 Security Headers

| Header | Test | Status |
|--------|------|--------|
| Content-Security-Policy | security_test.d #1-3 | ✅ |
| Strict-Transport-Security | security_test.d #4-6 | ✅ |
| X-Frame-Options | security_test.d #7-9 | ✅ |
| X-Content-Type-Options | security_test.d #10-12 | ✅ |
| X-XSS-Protection | security_test.d #13-15 | ✅ |
| Referrer-Policy | security_test.d #16-18 | ✅ |

### 7.4 Performance Baselines

| Metrica | Target | Actual | Test |
|---------|--------|--------|------|
| RPS | >1000 | 2400+ | test_multiworker.py |
| p50 Latency | <5ms | ~0.4ms | performance_test.d |
| Memory/req | <1KB | TBD | - |

---

## 8. Changelog Test

### V0.4.0 (26 Gennaio 2025) ✨ NEW

**Aggiunti:**
- `hooks_test.d` - 30+ test per Server Hooks (onStart, onStop, onError, onRequest, onResponse)
- `app_test.d` - 12 test per App API (fluent hooks, exception handlers)

**Nuovi Moduli Testati:**
- `aurora.runtime.hooks` - 100% coverage
- `aurora.app` - 85%+ coverage (integration)

**Nuove Funzionalità V0.4:**
- Server lifecycle hooks
- Typed exception handlers with hierarchy resolution
- Fluent App API for extensibility

**Totale Nuovi Test Cases:** +48

---

### V0.3.0 (3 Dicembre 2025)

**Aggiunti:**
- `security_test.d` - 21 test per security headers
- `cors_test.d` - 20 test per CORS middleware
- HTTP Smuggling tests (#42-55) in `http_test.d`
- Server integration tests (#12-20) in `server_integration_test.d`
- Context edge cases (#21-30) in `context_test.d`

**Miglioramenti Coverage:**
- `security.d`: 0% → 100% (+100)
- `context.d`: 73% → 100% (+27)
- `http/package.d`: 49% → 89% (+40)
- `cors.d`: 39% → 63% (+24)

**Totale:** +96 test cases

### V0.2.x

- Initial test suite
- ~336 test cases

---

## Appendice: Come Aggiungere Test

### Template Unit Test (D)

```d
// tests/unit/<module>/<module>_test.d

module tests.unit.<module>.<module>_test;

import unit_threaded;
import aurora.<module>;

@("descriptive test name")
unittest
{
    // Arrange
    auto sut = SystemUnderTest();
    
    // Act
    auto result = sut.doSomething();
    
    // Assert
    result.shouldEqual(expected);
}
```

### Template Integration Test (Python)

```python
# tests/integration/test_<feature>.py

import requests
import pytest

def test_feature_happy_path():
    """Test description"""
    response = requests.get("http://localhost:18888/endpoint")
    assert response.status_code == 200

def test_feature_error_case():
    """Test error handling"""
    response = requests.get("http://localhost:18888/invalid")
    assert response.status_code == 404
```

### Naming Convention

- Unit tests: `<module>_test.d`
- Integration tests: `<feature>_integration_test.d` o `test_<feature>.py`
- Stress tests: `<scenario>_stress_test.d`

---

*Documento generato il 3 Dicembre 2025*
