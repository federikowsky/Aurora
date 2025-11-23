/**
 * Aurora Metrics System
 * 
 * Features:
 * - Counter (monotonic increment)
 * - Gauge (arbitrary values)
 * - Histogram (value distribution)
 * - Timer (duration tracking)
 * - Thread-safe
 * - Export to JSON/Prometheus
 * 
 * Usage:
 * ---
 * auto metrics = Metrics.get();
 * auto counter = metrics.counter("requests_total", "method", "GET");
 * counter.inc();
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
 */
class Metrics
{
    private static Metrics instance;
    private static Mutex instanceMutex;
    
    private Counter[string] counters;
    private Gauge[string] gauges;
    private Histogram[string] histograms;
    private Timer[string] timers;
    private Mutex metricsMutex;
    
    static this()
    {
        instanceMutex = new Mutex();
    }
    
    static Metrics get()
    {
        synchronized (instanceMutex)
        {
            if (instance is null)
            {
                instance = new Metrics();
            }
            return instance;
        }
    }
    
    private this()
    {
        metricsMutex = new Mutex();
    }
    
    Counter counter(T...)(string name, T labelPairs)
    {
        auto key = makeKey(name, labelPairs);
        
        synchronized (metricsMutex)
        {
            if (key !in counters)
            {
                counters[key] = new Counter(name, makeLabels(labelPairs));
            }
            return counters[key];
        }
    }
    
    Gauge gauge(T...)(string name, T labelPairs)
    {
        auto key = makeKey(name, labelPairs);
        
        synchronized (metricsMutex)
        {
            if (key !in gauges)
            {
                gauges[key] = new Gauge(name, makeLabels(labelPairs));
            }
            return gauges[key];
        }
    }
    
    Histogram histogram(T...)(string name, T labelPairs)
    {
        auto key = makeKey(name, labelPairs);
        
        synchronized (metricsMutex)
        {
            if (key !in histograms)
            {
                histograms[key] = new Histogram(name, makeLabels(labelPairs));
            }
            return histograms[key];
        }
    }
    
    Timer timer(T...)(string name, T labelPairs)
    {
        auto key = makeKey(name, labelPairs);
        
        synchronized (metricsMutex)
        {
            if (key !in timers)
            {
                timers[key] = new Timer(name, makeLabels(labelPairs));
            }
            return timers[key];
        }
    }
    
    string[] collect()
    {
        synchronized (metricsMutex)
        {
            string[] result;
            
            foreach (key; counters.byKey)
            {
                result ~= key;
            }
            
            foreach (key; gauges.byKey)
            {
                result ~= key;
            }
            
            foreach (key; histograms.byKey)
            {
                result ~= key;
            }
            
            foreach (key; timers.byKey)
            {
                result ~= key;
            }
            
            return result;
        }
    }
    
    void reset()
    {
        synchronized (metricsMutex)
        {
            foreach (counter; counters)
            {
                counter.reset();
            }
            
            foreach (gauge; gauges)
            {
                gauge.reset();
            }
            
            foreach (hist; histograms)
            {
                hist.reset();
            }
            
            foreach (timer; timers)
            {
                timer.reset();
            }
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
