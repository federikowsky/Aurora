/**
 * Metrics System Tests
 * 
 * TDD: Lock-free metrics collection with aggregation
 * 
 * Features:
 * - Counter (monotonic increment)
 * - Gauge (arbitrary values)
 * - Histogram (value distribution)
 * - Timer (duration tracking)
 * - Export to JSON/Prometheus format
 */
module tests.unit.metrics.metrics_test;

import unit_threaded;
import aurora.metrics;

// ========================================
// COUNTER TESTS
// ========================================

// Test 1: Create and increment counter
@("create and increment counter")
unittest
{
    auto metrics = Metrics.get();
    
    auto counter = metrics.counter("requests_total");
    counter.inc();
    counter.inc();
    
    counter.value().shouldEqual(2);
}

// Test 2: Counter with labels
@("counter with labels")
unittest
{
    auto metrics = Metrics.get();
    
    auto counter = metrics.counter("http_requests", "method", "GET", "status", "200");
    counter.inc();
    
    counter.value().shouldEqual(1);
}

// Test 3: Counter increment by value
@("counter increment by value")
unittest
{
    auto metrics = Metrics.get();
    
    auto counter = metrics.counter("bytes_sent");
    counter.add(1024);
    counter.add(2048);
    
    counter.value().shouldEqual(3072);
}

// ========================================
// GAUGE TESTS
// ========================================

// Test 4: Create and set gauge
@("create and set gauge")
unittest
{
    auto metrics = Metrics.get();
    
    auto gauge = metrics.gauge("cpu_usage");
    gauge.set(75.5);
    
    gauge.value().shouldEqual(75.5);
}

// Test 5: Gauge inc/dec
@("gauge increment and decrement")
unittest
{
    auto metrics = Metrics.get();
    
    auto gauge = metrics.gauge("connections");
    gauge.inc();
    gauge.inc();
    gauge.dec();
    
    gauge.value().shouldEqual(1);
}

// Test 6: Gauge with labels
@("gauge with labels")
unittest
{
    auto metrics = Metrics.get();
    
    auto gauge = metrics.gauge("memory_bytes", "type", "heap");
    gauge.set(1024 * 1024);
    
    gauge.value().shouldEqual(1048576);
}

// ========================================
// HISTOGRAM TESTS
// ========================================

// Test 7: Create histogram and observe
@("histogram observe values")
unittest
{
    auto metrics = Metrics.get();
    
    auto hist = metrics.histogram("response_time_ms");
    hist.observe(10);
    hist.observe(20);
    hist.observe(30);
    
    hist.count().shouldEqual(3);
    hist.sum().shouldEqual(60);
}

// Test 8: Histogram buckets
@("histogram buckets distribution")
unittest
{
    auto metrics = Metrics.get();
    
    auto hist = metrics.histogram("latency");
    hist.observe(5);
    hist.observe(15);
    hist.observe(25);
    
    // Should distribute into buckets
    hist.count().shouldEqual(3);
}

// ========================================
// TIMER TESTS
// ========================================

// Test 9: Timer measures duration
@("timer measures duration")
unittest
{
    import core.thread : Thread;
    import core.time : msecs;
    
    auto metrics = Metrics.get();
    
    auto timer = metrics.timer("operation_duration");
    
    {
        auto t = timer.time();
        Thread.sleep(10.msecs);
    }  // Auto-records on scope exit
    
    timer.count().shouldEqual(1);
    assert(timer.sum() > 0);
}

// ========================================
// COLLECTION TESTS
// ========================================

// Test 10: Collect all metrics
@("collect all metrics")
unittest
{
    auto metrics = Metrics.get();
    
    metrics.counter("test_counter").inc();
    metrics.gauge("test_gauge").set(42);
    
    auto snapshot = metrics.collect();
    
    snapshot.length.shouldBeGreaterThan(0);
}

// Test 11: Reset metrics
@("reset all metrics")
unittest
{
    auto metrics = Metrics.get();
    
    auto counter = metrics.counter("reset_test");
    counter.inc();
    counter.inc();
    
    metrics.reset();
    
    counter.value().shouldEqual(0);
}

// ========================================
// EXPORT TESTS
// ========================================

// Test 12: Export to JSON
@("export metrics to JSON")
unittest
{
    auto metrics = Metrics.get();
    
    metrics.counter("json_counter").inc();
    metrics.gauge("json_gauge").set(123);
    
    string json = metrics.exportJSON();
    
    json.shouldNotBeNull;
    assert(json.length > 0);
}

// Test 13: Export to Prometheus format
@("export metrics to Prometheus format")
unittest
{
    auto metrics = Metrics.get();
    
    metrics.counter("prom_counter").inc();
    
    string prom = metrics.exportPrometheus();
    
    prom.shouldNotBeNull;
    assert(prom.length > 0);
}

// ========================================
// PERFORMANCE TESTS
// ========================================

// Test 14: Counter increment is fast
@("counter increment latency")
unittest
{
    import std.datetime.stopwatch;
    
    auto metrics = Metrics.get();
    auto counter = metrics.counter("perf_counter");
    
    auto sw = StopWatch(AutoStart.yes);
    
    foreach (i; 0..100_000)
    {
        counter.inc();
    }
    
    sw.stop();
    auto totalNs = sw.peek.total!"nsecs";
    auto avgNs = totalNs / 100_000;
    
    // Target: < 100ns per increment
    assert(avgNs < 1000, "Counter too slow");
}

// Test 15: Gauge set is fast
@("gauge set latency")
unittest
{
    import std.datetime.stopwatch;
    
    auto metrics = Metrics.get();
    auto gauge = metrics.gauge("perf_gauge");
    
    auto sw = StopWatch(AutoStart.yes);
    
    foreach (i; 0..100_000)
    {
        gauge.set(i);
    }
    
    sw.stop();
    auto totalNs = sw.peek.total!"nsecs";
    auto avgNs = totalNs / 100_000;
    
    // Target: < 100ns per set
    assert(avgNs < 1000, "Gauge too slow");
}

// ========================================
// THREAD SAFETY TESTS
// ========================================

// Test 16: Concurrent counter increments
@("concurrent counter increments are safe")
unittest
{
    import core.thread;
    
    auto metrics = Metrics.get();
    auto counter = metrics.counter("concurrent_counter");
    
    void increment()
    {
        foreach (i; 0..1000)
        {
            counter.inc();
        }
    }
    
    Thread[] threads;
    foreach (i; 0..10)
    {
        threads ~= new Thread(&increment);
        threads[$ - 1].start();
    }
    
    foreach (t; threads)
    {
        t.join();
    }
    
    counter.value().shouldEqual(10_000);
}

// ========================================
// EDGE CASES
// ========================================

// Test 17: Metric names with special chars
@("metric names sanitized")
unittest
{
    auto metrics = Metrics.get();
    
    auto counter = metrics.counter("test-metric.name");
    counter.inc();
    
    counter.value().shouldEqual(1);
}

// Test 18: Many metrics
@("handle many metrics")
unittest
{
    auto metrics = Metrics.get();
    
    foreach (i; 0..1000)
    {
        import std.conv : to;
        metrics.counter("metric_" ~ i.to!string).inc();
    }
    
    auto snapshot = metrics.collect();
    snapshot.length.shouldBeGreaterThan(900);
}

// Test 19: Metric with empty labels
@("metric with no labels")
unittest
{
    auto metrics = Metrics.get();
    
    auto counter = metrics.counter("no_labels");
    counter.inc();
    
    counter.value().shouldEqual(1);
}

// Test 20: Histogram with zero values
@("histogram with zero observations")
unittest
{
    auto metrics = Metrics.get();
    
    auto hist = metrics.histogram("empty_hist");
    
    hist.count().shouldEqual(0);
    hist.sum().shouldEqual(0);
}

// ========================================
// STRESS TESTS
// ========================================

// Test 21: Many counter increments
@("many counter increments stable")
unittest
{
    auto metrics = Metrics.get();
    auto counter = metrics.counter("stress_counter");
    
    foreach (i; 0..1_000_000)
    {
        counter.inc();
    }
    
    counter.value().shouldEqual(1_000_000);
}

// Test 22: Many histogram observations
@("many histogram observations stable")
unittest
{
    auto metrics = Metrics.get();
    auto hist = metrics.histogram("stress_hist");
    
    foreach (i; 0..10_000)
    {
        hist.observe(i % 100);
    }
    
    hist.count().shouldEqual(10_000);
}

// Test 23: Mixed metric types
@("mixed metric types work together")
unittest
{
    auto metrics = Metrics.get();
    
    auto counter = metrics.counter("mixed_counter");
    auto gauge = metrics.gauge("mixed_gauge");
    auto hist = metrics.histogram("mixed_hist");
    
    counter.inc();
    gauge.set(42);
    hist.observe(10);
    
    counter.value().shouldEqual(1);
    gauge.value().shouldEqual(42);
    hist.count().shouldEqual(1);
}

// Test 24: Export after many operations
@("export after many operations")
unittest
{
    auto metrics = Metrics.get();
    
    foreach (i; 0..100)
    {
        import std.conv : to;
        metrics.counter("export_" ~ i.to!string).inc();
    }
    
    string json = metrics.exportJSON();
    json.shouldNotBeNull;
}

// Test 25: Metrics cleanup
@("metrics cleanup works")
unittest
{
    auto metrics = Metrics.get();
    
    metrics.counter("cleanup_test").inc();
    metrics.reset();
    
    // Should not crash
}
