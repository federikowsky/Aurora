# Aurora Test Registry

**Versione:** V0.4.0  
**Ultimo Aggiornamento:** 26 Gennaio 2025  
**Totale Test Cases:** 480+  
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
| File di test totali | 27 |
| Test cases (D) | 480 |
| Test cases (Python) | 11 |
| LOC test | ~9,500 |
| LOC sorgente | ~8,200 |
| Rapporto test/source | 1.16:1 |

### 1.2 Distribuzione per Categoria

| Categoria | File | Test Cases | % Totale |
|-----------|------|------------|----------|
| Unit Tests | 19 | 419 | 85% |
| Integration Tests | 4 | 40+ | 8% |
| Stress Tests | 1 | 15 | 3% |
| Real-World/Load | 4 | ~10 | 2% |
| E2E (Python) | 2 | 11 | 2% |

---

## 2. Unit Tests

### 2.1 HTTP Module (`tests/unit/http/`)

#### `http_test.d` - 66 test cases

| # | Test Name | Categoria | Descrizione |
|---|-----------|-----------|-------------|
| 1-10 | Request Parsing | Parsing | GET, POST, headers, body |
| 11-20 | Response Building | Response | Status codes, headers, body |
| 21-30 | Edge Cases | Robustezza | Malformed requests, empty fields |
| 31-41 | Header Handling | Headers | Case-insensitive, duplicates |
| 42-55 | **HTTP Smuggling** | **Security** | OWASP WSTG-INPV-15 |
| 56-66 | Response Methods | API | buildInto, estimateSize, getters |

**Test HTTP Smuggling (42-55):**

| # | Test | OWASP | Descrizione |
|---|------|-------|-------------|
| 42 | `duplicate content length rejected` | WSTG-INPV-15 | Doppio Content-Length |
| 43 | `conflicting content lengths rejected` | WSTG-INPV-15 | Content-Length conflittuali |
| 44 | `transfer encoding with content length` | WSTG-INPV-15 | TE + CL simultanei |
| 45 | `chunked transfer encoding rejected` | WSTG-INPV-15 | Chunked TE non supportato |
| 46 | `multiple transfer encodings rejected` | WSTG-INPV-15 | TE multipli |
| 47 | `obfuscated transfer encoding rejected` | WSTG-INPV-15 | TE offuscato |
| 48 | `crlf injection in header value rejected` | WSTG-INPV-15 | CRLF injection |
| 49 | `null byte in header rejected` | WSTG-INPV-15 | Null byte injection |
| 50 | `host header injection rejected` | WSTG-INPV-17 | Host manipulation |
| 51 | `multiple host headers rejected` | WSTG-INPV-17 | Doppio Host |
| 52 | `invalid http version rejected` | RFC 7230 | Versione HTTP invalida |
| 53 | `http 0.9 rejected` | Security | HTTP/0.9 non supportato |
| 54 | `negative content length rejected` | Security | Content-Length negativo |
| 55 | `overflow content length rejected` | Security | Content-Length overflow |

---

### 2.2 Web Module (`tests/unit/web/`)

#### `router_test.d` - 35 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Basic Routing | 10 | GET, POST, PUT, DELETE, PATCH |
| Path Parameters | 8 | `:id`, `:name`, multiple params |
| Wildcard Routes | 5 | `*`, catch-all |
| Route Priority | 5 | Static vs dynamic |
| Edge Cases | 7 | Empty path, trailing slash |

#### `router_pattern_test.d` - 25 test cases

| Categoria | # Test | Descrizione |
|-----------|--------|-------------|
| Pattern Matching | 10 | Exact, prefix, suffix |
| Regex Patterns | 5 | Custom regex constraints |
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

---

### 2.3 Memory Module (`tests/unit/mem/`)

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

### `server_integration_test.d` - 20 test cases ✨ UPDATED

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
