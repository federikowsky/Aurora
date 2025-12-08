/**
 * Aurora Metrics System
 * 
 * Features:
 * - Counter (monotonic increment) - lock-free atomic
 * - Gauge (arbitrary values) - lock-free atomic
 * - Histogram (value distribution) - lock-free atomic
 * - Timer (duration tracking) - RAII-based
 * - Thread-local metric caching for hot-path performance
 * - Double-checked locking singleton
 * - Export to JSON/Prometheus
 * 
 * Architecture:
 * - Metric objects use atomic operations (lock-free hot path)
 * - Registry uses synchronized only for metric creation (cold path)
 * - Thread-local cache avoids repeated hash lookups
 * 
 * Usage:
 * ---
 * auto metrics = Metrics.get();
 * auto counter = metrics.counter("requests_total", "method", "GET");
 * counter.inc();  // Lock-free!
 * ---
 */
module aurora.metrics;

import core.atomic;
import core.sync.mutex;
import std.datetime : Clock, Duration, MonoTime;
import std.format : format;
import std.conv : to;
import std.array : appender;

/**
 * Counter - monotonically increasing metric
 */
class Counter
{
    private shared long _value = 0;
    private string name;
    private string[string] labels;
    
    this(string name, string[string] labels = null)
    {
        this.name = name;
        this.labels = labels;
    }
    
    void inc()
    {
        atomicOp!"+="(_value, 1);
    }
    
    void add(long delta)
    {
        atomicOp!"+="(_value, delta);
    }
    
    long value()
    {
        return atomicLoad(_value);
    }
    
    void reset()
    {
        atomicStore(_value, 0);
    }
}

/**
 * Gauge - arbitrary value metric
 */
class Gauge
{
    private shared double _value = 0;
    private string name;
    private string[string] labels;
    
    this(string name, string[string] labels = null)
    {
        this.name = name;
        this.labels = labels;
    }
    
    void set(double value)
    {
        atomicStore(_value, value);
    }
    
    void inc()
    {
        // Atomic double increment (use CAS)
        double oldVal, newVal;
        do
        {
            oldVal = atomicLoad(_value);
            newVal = oldVal + 1.0;
        } while (!cas(&_value, oldVal, newVal));
    }
    
    void dec()
    {
        double oldVal, newVal;
        do
        {
            oldVal = atomicLoad(_value);
            newVal = oldVal - 1.0;
        } while (!cas(&_value, oldVal, newVal));
    }
    
    double value()
    {
        return atomicLoad(_value);
    }
    
    void reset()
    {
        atomicStore(_value, 0.0);
    }
}

/**
 * Histogram - value distribution metric
 */
class Histogram
{
    private shared long _count = 0;
    private shared double _sum = 0;
    private string name;
    private string[string] labels;
    
    this(string name, string[string] labels = null)
    {
        this.name = name;
        this.labels = labels;
    }
    
    void observe(double value)
    {
        atomicOp!"+="(_count, 1);
        
        // Atomic double add
        double oldSum, newSum;
        do
        {
            oldSum = atomicLoad(_sum);
            newSum = oldSum + value;
        } while (!cas(&_sum, oldSum, newSum));
    }
    
    long count()
    {
        return atomicLoad(_count);
    }
    
    double sum()
    {
        return atomicLoad(_sum);
    }
    
    void reset()
    {
        atomicStore(_count, 0);
        atomicStore(_sum, 0.0);
    }
}

/**
 * PercentileHistogram - histogram with percentile tracking
 * 
 * Uses reservoir sampling to maintain a fixed-size sample of observations.
 * Supports calculating P50, P90, P95, P99 percentiles.
 * 
 * Thread-safe via synchronized access to reservoir.
 */
class PercentileHistogram
{
    private shared long _count = 0;
    private shared double _sum = 0;
    private string name;
    private string[string] labels;
    
    // Reservoir for percentile calculation
    private enum RESERVOIR_SIZE = 1000;
    private double[] reservoir;
    private size_t reservoirIndex = 0;
    private bool reservoirFull = false;
    private Mutex reservoirMutex;
    
    // Cached percentiles (recalculated on demand)
    private bool percentilesDirty = true;
    private double cachedP50 = 0;
    private double cachedP90 = 0;
    private double cachedP95 = 0;
    private double cachedP99 = 0;
    
    this(string name, string[string] labels = null) @trusted
    {
        this.name = name;
        this.labels = labels;
        this.reservoir = new double[RESERVOIR_SIZE];
        this.reservoirMutex = new Mutex();
    }
    
    /// Record an observation
    void observe(double value) @trusted
    {
        atomicOp!"+="(_count, 1);
        
        // Atomic double add for sum
        double oldSum, newSum;
        do
        {
            oldSum = atomicLoad(_sum);
            newSum = oldSum + value;
        } while (!cas(&_sum, oldSum, newSum));
        
        // Add to reservoir (thread-safe)
        synchronized (reservoirMutex)
        {
            reservoir[reservoirIndex] = value;
            reservoirIndex = (reservoirIndex + 1) % RESERVOIR_SIZE;
            if (reservoirIndex == 0)
                reservoirFull = true;
            percentilesDirty = true;
        }
    }
    
    /// Get total count
    long count()
    {
        return atomicLoad(_count);
    }
    
    /// Get sum of all observations
    double sum()
    {
        return atomicLoad(_sum);
    }
    
    /// Get mean (average)
    double mean()
    {
        auto c = count();
        if (c == 0) return 0;
        return sum() / c;
    }
    
    /// Get P50 (median)
    double p50() @trusted
    {
        calculatePercentiles();
        return cachedP50;
    }
    
    /// Get P90
    double p90() @trusted
    {
        calculatePercentiles();
        return cachedP90;
    }
    
    /// Get P95
    double p95() @trusted
    {
        calculatePercentiles();
        return cachedP95;
    }
    
    /// Get P99
    double p99() @trusted
    {
        calculatePercentiles();
        return cachedP99;
    }
    
    /// Get arbitrary percentile (0-100)
    double percentile(double p) @trusted
    {
        if (p < 0 || p > 100) return 0;
        
        synchronized (reservoirMutex)
        {
            auto sampleSize = reservoirFull ? RESERVOIR_SIZE : reservoirIndex;
            if (sampleSize == 0) return 0;
            
            auto sorted = reservoir[0 .. sampleSize].dup;
            import std.algorithm : sort;
            sorted.sort();
            
            auto idx = cast(size_t)((p / 100.0) * (sampleSize - 1));
            return sorted[idx];
        }
    }
    
    /// Reset the histogram
    void reset() @trusted
    {
        atomicStore(_count, 0);
        atomicStore(_sum, 0.0);
        
        synchronized (reservoirMutex)
        {
            reservoirIndex = 0;
            reservoirFull = false;
            percentilesDirty = true;
            cachedP50 = cachedP90 = cachedP95 = cachedP99 = 0;
        }
    }
    
    /// Export as Prometheus format
    string toPrometheus() @trusted
    {
        import std.format : format;
        import std.array : appender;
        
        auto result = appender!string();
        
        result ~= format("# TYPE %s histogram\n", name);
        result ~= format("%s_count %d\n", name, count());
        result ~= format("%s_sum %g\n", name, sum());
        
        // Percentile quantiles (Prometheus style)
        calculatePercentiles();
        result ~= format("%s{quantile=\"0.5\"} %g\n", name, cachedP50);
        result ~= format("%s{quantile=\"0.9\"} %g\n", name, cachedP90);
        result ~= format("%s{quantile=\"0.95\"} %g\n", name, cachedP95);
        result ~= format("%s{quantile=\"0.99\"} %g\n", name, cachedP99);
        
        return result.data;
    }
    
    private void calculatePercentiles() @trusted
    {
        synchronized (reservoirMutex)
        {
            if (!percentilesDirty) return;
            
            auto sampleSize = reservoirFull ? RESERVOIR_SIZE : reservoirIndex;
            if (sampleSize == 0)
            {
                cachedP50 = cachedP90 = cachedP95 = cachedP99 = 0;
                percentilesDirty = false;
                return;
            }
            
            auto sorted = reservoir[0 .. sampleSize].dup;
            import std.algorithm : sort;
            sorted.sort();
            
            cachedP50 = sorted[cast(size_t)(0.50 * (sampleSize - 1))];
            cachedP90 = sorted[cast(size_t)(0.90 * (sampleSize - 1))];
            cachedP95 = sorted[cast(size_t)(0.95 * (sampleSize - 1))];
            cachedP99 = sorted[cast(size_t)(0.99 * (sampleSize - 1))];
            
            percentilesDirty = false;
        }
    }
}

/**
 * Timer scope - RAII timer that records on destruction
 */
struct TimerScope
{
    private Histogram* hist;
    private MonoTime start;
    
    this(Histogram* h)
    {
        hist = h;
        start = MonoTime.currTime;
    }
    
    ~this()
    {
        auto end = MonoTime.currTime;
        auto duration = end - start;
        hist.observe(duration.total!"msecs");
    }
}

/**
 * Timer - duration tracking metric (wrapper around Histogram)
 */
class Timer
{
    private Histogram hist;
    
    this(string name, string[string] labels = null)
    {
        hist = new Histogram(name, labels);
    }
    
    TimerScope time()
    {
        return TimerScope(&hist);
    }
    
    long count()
    {
        return hist.count();
    }
    
    double sum()
    {
        return hist.sum();
    }
    
    void reset()
    {
        hist.reset();
    }
}

/**
 * Metrics - singleton metrics registry
 * 
 * Uses double-checked locking for singleton and thread-local caching
 * to minimize lock contention on hot paths.
 */
class Metrics
{
    // Double-checked locking singleton
    private __gshared Metrics instance;
    private __gshared bool instanceCreated = false;
    private static Mutex instanceMutex;
    
    // Thread-local cache for fast metric access
    private static Counter[string] tlCounterCache;
    private static Gauge[string] tlGaugeCache;
    private static Histogram[string] tlHistogramCache;
    private static Timer[string] tlTimerCache;
    
    // Global metric storage (accessed under lock only for creation)
    private __gshared Counter[string] counters;
    private __gshared Gauge[string] gauges;
    private __gshared Histogram[string] histograms;
    private __gshared Timer[string] timers;
    private __gshared Mutex metricsMutex;
    
    static this()
    {
        instanceMutex = new Mutex();
    }
    
    /**
     * Get singleton instance (double-checked locking)
     */
    static Metrics get() @trusted
    {
        // Fast path: already created
        if (atomicLoad(instanceCreated))
            return instance;
        
        // Slow path: create under lock
        synchronized (instanceMutex)
        {
            if (!atomicLoad(instanceCreated))
            {
                instance = new Metrics();
                atomicStore(instanceCreated, true);
            }
        }
        return instance;
    }
    
    private this() @trusted
    {
        metricsMutex = new Mutex();
    }
    
    /**
     * Get or create a counter.
     * Uses thread-local cache for hot path performance.
     */
    Counter counter(T...)(string name, T labelPairs)
    {
        auto key = makeKey(name, labelPairs);
        
        // Fast path: check thread-local cache
        if (auto cached = key in tlCounterCache)
            return *cached;
        
        // Slow path: check global registry (under lock)
        Counter result;
        synchronized (metricsMutex)
        {
            if (auto existing = key in counters)
            {
                result = *existing;
            }
            else
            {
                result = new Counter(name, makeLabels(labelPairs));
                counters[key] = result;
            }
        }
        
        // Cache for future use
        tlCounterCache[key] = result;
        return result;
    }
    
    /**
     * Get or create a gauge.
     * Uses thread-local cache for hot path performance.
     */
    Gauge gauge(T...)(string name, T labelPairs)
    {
        auto key = makeKey(name, labelPairs);
        
        // Fast path: check thread-local cache
        if (auto cached = key in tlGaugeCache)
            return *cached;
        
        // Slow path: check global registry
        Gauge result;
        synchronized (metricsMutex)
        {
            if (auto existing = key in gauges)
            {
                result = *existing;
            }
            else
            {
                result = new Gauge(name, makeLabels(labelPairs));
                gauges[key] = result;
            }
        }
        
        tlGaugeCache[key] = result;
        return result;
    }
    
    /**
     * Get or create a histogram.
     * Uses thread-local cache for hot path performance.
     */
    Histogram histogram(T...)(string name, T labelPairs)
    {
        auto key = makeKey(name, labelPairs);
        
        // Fast path: check thread-local cache
        if (auto cached = key in tlHistogramCache)
            return *cached;
        
        // Slow path: check global registry
        Histogram result;
        synchronized (metricsMutex)
        {
            if (auto existing = key in histograms)
            {
                result = *existing;
            }
            else
            {
                result = new Histogram(name, makeLabels(labelPairs));
                histograms[key] = result;
            }
        }
        
        tlHistogramCache[key] = result;
        return result;
    }
    
    /**
     * Get or create a percentile histogram.
     * Uses thread-local cache for hot path performance.
     */
    private static PercentileHistogram[string] tlPercentileCache;
    private __gshared PercentileHistogram[string] percentileHistograms;
    
    PercentileHistogram percentileHistogram(T...)(string name, T labelPairs)
    {
        auto key = makeKey(name, labelPairs);
        
        // Fast path: check thread-local cache
        if (auto cached = key in tlPercentileCache)
            return *cached;
        
        // Slow path: check global registry
        PercentileHistogram result;
        synchronized (metricsMutex)
        {
            if (auto existing = key in percentileHistograms)
            {
                result = *existing;
            }
            else
            {
                result = new PercentileHistogram(name, makeLabels(labelPairs));
                percentileHistograms[key] = result;
            }
        }
        
        tlPercentileCache[key] = result;
        return result;
    }
    
    /**
     * Get or create a timer.
     * Uses thread-local cache for hot path performance.
     */
    Timer timer(T...)(string name, T labelPairs)
    {
        auto key = makeKey(name, labelPairs);
        
        // Fast path: check thread-local cache
        if (auto cached = key in tlTimerCache)
            return *cached;
        
        // Slow path: check global registry
        Timer result;
        synchronized (metricsMutex)
        {
            if (auto existing = key in timers)
            {
                result = *existing;
            }
            else
            {
                result = new Timer(name, makeLabels(labelPairs));
                timers[key] = result;
            }
        }
        
        tlTimerCache[key] = result;
        return result;
    }
    
    /**
     * Collect all metric names.
     */
    string[] collect()
    {
        synchronized (metricsMutex)
        {
            string[] result;
            
            foreach (key; counters.byKey)
                result ~= key;
            
            foreach (key; gauges.byKey)
                result ~= key;
            
            foreach (key; histograms.byKey)
                result ~= key;
            
            foreach (key; timers.byKey)
                result ~= key;
            
            return result;
        }
    }
    
    /**
     * Reset all metrics.
     */
    void reset()
    {
        synchronized (metricsMutex)
        {
            foreach (counter; counters)
                counter.reset();
            
            foreach (gauge; gauges)
                gauge.reset();
            
            foreach (hist; histograms)
                hist.reset();
            
            foreach (timer; timers)
                timer.reset();
            
            foreach (phist; percentileHistograms)
                phist.reset();
        }
    }
    
    string exportJSON()
    {
        auto result = appender!string();
        result ~= "{\"metrics\":[";
        
        synchronized (metricsMutex)
        {
            bool first = true;
            
            foreach (name, counter; counters)
            {
                if (!first) result ~= ",";
                result ~= format(`{"type":"counter","name":"%s","value":%d}`,
                    name, counter.value());
                first = false;
            }
            
            foreach (name, gauge; gauges)
            {
                if (!first) result ~= ",";
                result ~= format(`{"type":"gauge","name":"%s","value":%g}`,
                    name, gauge.value());
                first = false;
            }
            
            foreach (name, hist; histograms)
            {
                if (!first) result ~= ",";
                result ~= format(`{"type":"histogram","name":"%s","count":%d,"sum":%g}`,
                    name, hist.count(), hist.sum());
                first = false;
            }
        }
        
        result ~= "]}";
        return result.data;
    }
    
    string exportPrometheus()
    {
        auto result = appender!string();
        
        synchronized (metricsMutex)
        {
            foreach (name, counter; counters)
            {
                result ~= format("# TYPE %s counter\n", name);
                result ~= format("%s %d\n", name, counter.value());
            }
            
            foreach (name, gauge; gauges)
            {
                result ~= format("# TYPE %s gauge\n", name);
                result ~= format("%s %g\n", name, gauge.value());
            }
            
            foreach (name, hist; histograms)
            {
                result ~= format("# TYPE %s histogram\n", name);
                result ~= format("%s_count %d\n", name, hist.count());
                result ~= format("%s_sum %g\n", name, hist.sum());
            }
            
            // Percentile histograms with quantiles
            foreach (name, phist; percentileHistograms)
            {
                result ~= phist.toPrometheus();
            }
        }
        
        return result.data;
    }
    
    // Private helpers
    
    private string makeKey(T...)(string name, T labelPairs)
    {
        if (labelPairs.length == 0)
            return name;
        
        auto result = appender!string();
        result ~= name;
        result ~= "{";
        
        static foreach (i; 0 .. labelPairs.length / 2)
        {
            static if (i > 0)
                result ~= ",";
            
            result ~= to!string(labelPairs[i * 2]);
            result ~= "=";
            result ~= to!string(labelPairs[i * 2 + 1]);
        }
        
        result ~= "}";
        return result.data;
    }
    
    private string[string] makeLabels(T...)(T labelPairs)
    {
        string[string] labels;
        
        static foreach (i; 0 .. labelPairs.length / 2)
        {
            labels[to!string(labelPairs[i * 2])] = to!string(labelPairs[i * 2 + 1]);
        }
        
        return labels;
    }
}
