/**
 * Percentile Histogram Tests
 *
 * Tests for Aurora's P99 latency tracking:
 * - Percentile calculations (P50, P90, P95, P99)
 * - Reservoir sampling
 * - Thread safety
 * - Prometheus export format
 */
module tests.unit.metrics.percentile_test;

import unit_threaded;
import aurora.metrics;
import core.time;
import core.thread;

// ============================================================================
// BASIC PERCENTILE HISTOGRAM TESTS
// ============================================================================

// Test 1: PercentileHistogram can be created
@("PercentileHistogram can be created")
unittest
{
    auto hist = new PercentileHistogram("test_latency");
    hist.shouldNotBeNull;
}

// Test 2: Initial values are zero
@("PercentileHistogram initial values are zero")
unittest
{
    auto hist = new PercentileHistogram("test");
    
    hist.count().shouldEqual(0);
    hist.sum().shouldEqual(0);
    hist.mean().shouldEqual(0);
    hist.p50().shouldEqual(0);
    hist.p99().shouldEqual(0);
}

// Test 3: observe increments count
@("observe increments count")
unittest
{
    auto hist = new PercentileHistogram("test");
    
    hist.observe(100);
    hist.observe(200);
    hist.observe(300);
    
    hist.count().shouldEqual(3);
}

// Test 4: observe accumulates sum
@("observe accumulates sum")
unittest
{
    auto hist = new PercentileHistogram("test");
    
    hist.observe(100);
    hist.observe(200);
    hist.observe(300);
    
    hist.sum().shouldEqual(600);
}

// Test 5: mean is calculated correctly
@("mean is calculated correctly")
unittest
{
    auto hist = new PercentileHistogram("test");
    
    hist.observe(100);
    hist.observe(200);
    hist.observe(300);
    
    hist.mean().shouldEqual(200);
}

// ============================================================================
// PERCENTILE CALCULATION TESTS
// ============================================================================

// Test 6: P50 (median) calculation
@("P50 median calculation")
unittest
{
    auto hist = new PercentileHistogram("test");
    
    // Observe values 1-100
    foreach (i; 1 .. 101)
        hist.observe(cast(double)i);
    
    // P50 should be around 50
    auto p50 = hist.p50();
    p50.shouldBeGreaterThan(45);
    assert(p50 < 55, "P50 should be less than 55");
}

// Test 7: P90 calculation
@("P90 calculation")
unittest
{
    auto hist = new PercentileHistogram("test");
    
    // Observe values 1-100
    foreach (i; 1 .. 101)
        hist.observe(cast(double)i);
    
    // P90 should be around 90
    auto p90 = hist.p90();
    p90.shouldBeGreaterThan(85);
    assert(p90 < 95, "P90 should be less than 95");
}

// Test 8: P95 calculation
@("P95 calculation")
unittest
{
    auto hist = new PercentileHistogram("test");
    
    // Observe values 1-100
    foreach (i; 1 .. 101)
        hist.observe(cast(double)i);
    
    // P95 should be around 95
    auto p95 = hist.p95();
    p95.shouldBeGreaterThan(90);
    assert(p95 < 100, "P95 should be less than 100");
}

// Test 9: P99 calculation
@("P99 calculation")
unittest
{
    auto hist = new PercentileHistogram("test");
    
    // Observe values 1-100
    foreach (i; 1 .. 101)
        hist.observe(cast(double)i);
    
    // P99 should be around 99
    auto p99 = hist.p99();
    p99.shouldBeGreaterThan(95);
    assert(p99 < 101, "P99 should be less than 101");
}

// Test 10: Custom percentile calculation
@("custom percentile calculation")
unittest
{
    auto hist = new PercentileHistogram("test");
    
    // Observe values 1-100
    foreach (i; 1 .. 101)
        hist.observe(cast(double)i);
    
    // P75 should be around 75
    auto p75 = hist.percentile(75);
    p75.shouldBeGreaterThan(70);
    assert(p75 < 80, "P75 should be less than 80");
}

// ============================================================================
// EDGE CASES
// ============================================================================

// Test 11: Single observation
@("single observation percentiles")
unittest
{
    auto hist = new PercentileHistogram("test");
    
    hist.observe(42);
    
    // All percentiles should be 42 with single value
    hist.p50().shouldEqual(42);
    hist.p99().shouldEqual(42);
}

// Test 12: Two observations
@("two observations percentiles")
unittest
{
    auto hist = new PercentileHistogram("test");
    
    hist.observe(10);
    hist.observe(90);
    
    // P50 should be closer to 10 or exact 10 (depending on impl)
    auto p50 = hist.p50();
    (p50 == 10 || p50 == 90).shouldBeTrue;
}

// Test 13: Reset clears everything
@("reset clears everything")
unittest
{
    auto hist = new PercentileHistogram("test");
    
    foreach (i; 0 .. 100)
        hist.observe(cast(double)i);
    
    hist.count().shouldBeGreaterThan(0);
    
    hist.reset();
    
    hist.count().shouldEqual(0);
    hist.sum().shouldEqual(0);
    hist.p50().shouldEqual(0);
    hist.p99().shouldEqual(0);
}

// Test 14: Invalid percentile returns 0
@("invalid percentile returns 0")
unittest
{
    auto hist = new PercentileHistogram("test");
    
    hist.observe(100);
    
    hist.percentile(-10).shouldEqual(0);
    hist.percentile(110).shouldEqual(0);
}

// Test 15: Reservoir overflow (more than 1000 samples)
@("reservoir handles overflow")
unittest
{
    auto hist = new PercentileHistogram("test");
    
    // Observe more than reservoir size
    foreach (i; 0 .. 2000)
        hist.observe(cast(double)i);
    
    hist.count().shouldEqual(2000);
    
    // Percentiles should still work (on recent 1000)
    auto p50 = hist.p50();
    p50.shouldBeGreaterThan(0);
}

// ============================================================================
// METRICS REGISTRY INTEGRATION
// ============================================================================

// Test 16: Can get percentileHistogram from Metrics
@("Metrics.percentileHistogram creates histogram")
unittest
{
    auto metrics = Metrics.get();
    
    auto hist = metrics.percentileHistogram("request_latency_ms");
    hist.shouldNotBeNull;
}

// Test 17: Same name returns same histogram
@("same name returns same histogram")
unittest
{
    auto metrics = Metrics.get();
    
    auto hist1 = metrics.percentileHistogram("latency_same");
    auto hist2 = metrics.percentileHistogram("latency_same");
    
    hist1.observe(100);
    hist2.count().shouldEqual(1);
}

// Test 18: Labels create different histograms
@("labels create different histograms")
unittest
{
    auto metrics = Metrics.get();
    
    auto hist1 = metrics.percentileHistogram("latency", "endpoint", "/api");
    auto hist2 = metrics.percentileHistogram("latency", "endpoint", "/health");
    
    hist1.observe(100);
    hist2.observe(200);
    
    hist1.sum().shouldEqual(100);
    hist2.sum().shouldEqual(200);
}

// ============================================================================
// PROMETHEUS EXPORT TESTS
// ============================================================================

// Test 19: toPrometheus format is correct
@("toPrometheus format is correct")
unittest
{
    import std.string : indexOf;
    
    auto hist = new PercentileHistogram("http_latency");
    
    hist.observe(10);
    hist.observe(20);
    hist.observe(30);
    
    auto prom = hist.toPrometheus();
    
    // Should contain TYPE declaration
    assert(prom.indexOf("# TYPE http_latency histogram") >= 0, "Should have TYPE");
    
    // Should contain count and sum
    assert(prom.indexOf("http_latency_count 3") >= 0, "Should have count");
    assert(prom.indexOf("http_latency_sum") >= 0, "Should have sum");
    
    // Should contain quantiles
    assert(prom.indexOf("quantile=\"0.5\"") >= 0, "Should have P50 quantile");
    assert(prom.indexOf("quantile=\"0.99\"") >= 0, "Should have P99 quantile");
}

// Test 20: exportPrometheus includes percentile histograms
@("exportPrometheus includes percentile histograms")
unittest
{
    import std.string : indexOf;
    
    auto metrics = Metrics.get();
    
    auto hist = metrics.percentileHistogram("api_latency_prom");
    hist.observe(100);
    
    auto exported = metrics.exportPrometheus();
    
    // Should include our histogram
    assert(exported.indexOf("api_latency_prom") >= 0, "Should include histogram");
}

// ============================================================================
// LATENCY TRACKING PATTERN TEST
// ============================================================================

// Test 21: Typical latency tracking pattern
@("typical latency tracking pattern")
unittest
{
    auto metrics = Metrics.get();
    auto latency = metrics.percentileHistogram("handler_latency_ms", "handler", "getUser");
    
    // Simulate some request latencies (in ms)
    double[] latencies = [5, 8, 12, 15, 20, 25, 30, 45, 80, 150];
    
    foreach (lat; latencies)
        latency.observe(lat);
    
    // Check basic stats
    latency.count().shouldEqual(10);
    latency.mean().shouldBeGreaterThan(0);
    
    // P50 should be around 22.5 (median of sorted list)
    auto p50 = latency.p50();
    p50.shouldBeGreaterThan(10);
    assert(p50 < 40, "P50 should be less than 40");
    
    // P99 should be high (near the top of the range)
    auto p99 = latency.p99();
    p99.shouldBeGreaterThan(50);  // At least in the upper half
}

// Test 22: Thread safety - concurrent observations
@("thread safety concurrent observations")
unittest
{
    auto hist = new PercentileHistogram("concurrent_test");
    
    // Spawn multiple threads
    Thread[] threads;
    foreach (t; 0 .. 4)
    {
        threads ~= new Thread({
            foreach (i; 0 .. 100)
            {
                hist.observe(cast(double)i);
            }
        });
    }
    
    foreach (thread; threads)
        thread.start();
    
    foreach (thread; threads)
        thread.join();
    
    // Should have all 400 observations
    hist.count().shouldEqual(400);
}

// Test 23: Distribution skew detection
@("distribution skew detection")
unittest
{
    auto hist = new PercentileHistogram("skewed");
    
    // Most requests are fast (1-10ms)
    foreach (i; 0 .. 95)
        hist.observe(5);
    
    // But a few are slow (100-500ms)
    foreach (i; 0 .. 5)
        hist.observe(200);
    
    // P50 should be low (around 5)
    auto p50 = hist.p50();
    p50.shouldEqual(5);
    
    // P99 should be high (around 200)
    auto p99 = hist.p99();
    p99.shouldEqual(200);
}

// Test 24: Mean vs P50 comparison
@("mean vs P50 comparison for skewed data")
unittest
{
    auto hist = new PercentileHistogram("mean_vs_p50");
    
    // 9 fast requests
    foreach (i; 0 .. 9)
        hist.observe(10);
    
    // 1 very slow request
    hist.observe(1000);
    
    // Mean is affected by outlier
    auto mean = hist.mean();
    mean.shouldBeGreaterThan(100);  // (9*10 + 1000) / 10 = 109
    
    // P50 is robust to outlier
    auto p50 = hist.p50();
    p50.shouldEqual(10);
}

// Test 25: Empty histogram edge case
@("empty histogram returns zeros")
unittest
{
    auto hist = new PercentileHistogram("empty");
    
    hist.count().shouldEqual(0);
    hist.sum().shouldEqual(0);
    hist.mean().shouldEqual(0);
    hist.p50().shouldEqual(0);
    hist.p90().shouldEqual(0);
    hist.p95().shouldEqual(0);
    hist.p99().shouldEqual(0);
    hist.percentile(50).shouldEqual(0);
}
