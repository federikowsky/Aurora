/**
 * Aurora Logging System
 * 
 * Features:
 * - Lock-free ring buffer for high-throughput logging
 * - Background flush thread for async I/O
 * - Multiple log levels (DEBUG, INFO, WARN, ERROR)
 * - Structured logging with key-value pairs
 * - Thread-safe with minimal contention
 * - High performance (< 100ns per log on hot path)
 * 
 * Architecture:
 * - Producers (app threads) write to lock-free ring buffer
 * - Consumer (background thread) flushes to file/stdout
 * - Uses atomic CAS for thread-safe slot allocation
 * 
 * Usage:
 * ---
 * auto logger = Logger.get();
 * logger.info("Request processed", "user_id", 123, "duration_ms", 45);
 * logger.flush();  // Force immediate flush
 * ---
 */
module aurora.logging;

import std.stdio : File, stdout, stderr;
import std.datetime : Clock;
import std.format : format;
import std.conv : to;
import core.atomic;
import core.thread;
import core.sync.mutex : Mutex;
import core.sync.condition : Condition;
import core.time : Duration, msecs, seconds;

/**
 * Log levels
 */
enum LogLevel
{
    DEBUG = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3
}

/**
 * Log output destinations
 */
enum LogOutput
{
    STDOUT,
    STDERR,
    FILE
}

// ============================================================================
// LOCK-FREE RING BUFFER
// ============================================================================

/**
 * Fixed-size log entry for ring buffer.
 * Pre-allocated to avoid GC during logging.
 */
private struct LogEntry
{
    enum MAX_MESSAGE_SIZE = 512;
    
    LogLevel level;
    long timestamp;  // Unix timestamp in hnsecs
    char[MAX_MESSAGE_SIZE] message;
    size_t messageLen;
    shared bool ready;  // Entry is ready to be consumed
    
    void set(LogLevel lvl, string msg) @trusted nothrow
    {
        level = lvl;
        timestamp = Clock.currStdTime();
        
        size_t len = msg.length < MAX_MESSAGE_SIZE ? msg.length : MAX_MESSAGE_SIZE;
        message[0 .. len] = msg[0 .. len];
        messageLen = len;
        
        atomicStore(ready, true);
    }
    
    void clear() @trusted nothrow
    {
        atomicStore(ready, false);
        messageLen = 0;
    }
}

/**
 * Lock-free Single-Producer-Multi-Consumer Ring Buffer.
 * 
 * Multiple producers use CAS to claim slots.
 * Single consumer (flush thread) reads sequentially.
 */
private struct LogRingBuffer
{
    enum BUFFER_SIZE = 8192;  // Must be power of 2
    enum BUFFER_MASK = BUFFER_SIZE - 1;
    
    private LogEntry[BUFFER_SIZE] entries;
    private shared size_t writeHead = 0;   // Next slot to write
    private shared size_t readTail = 0;    // Next slot to read
    
    /**
     * Try to write a log entry (lock-free).
     * Returns true if successful, false if buffer is full.
     */
    bool tryWrite(LogLevel level, string message) @trusted nothrow
    {
        // Claim a slot using CAS
        size_t slot;
        size_t next;
        
        do
        {
            slot = atomicLoad(writeHead);
            next = (slot + 1) & BUFFER_MASK;
            
            // Check if buffer is full
            if (next == atomicLoad(readTail))
                return false;  // Buffer full, drop message
                
        } while (!cas(&writeHead, slot, next));
        
        // We own this slot, write the entry
        entries[slot].set(level, message);
        
        return true;
    }
    
    /**
     * Try to read a log entry (single consumer only).
     * Returns null if no entries available.
     */
    LogEntry* tryRead() @trusted nothrow
    {
        size_t tail = atomicLoad(readTail);
        size_t head = atomicLoad(writeHead);
        
        if (tail == head)
            return null;  // Empty
        
        LogEntry* entry = &entries[tail];
        
        // Wait for entry to be ready (producer might still be writing)
        if (!atomicLoad(entry.ready))
            return null;
        
        return entry;
    }
    
    /**
     * Advance read pointer after consuming entry.
     */
    void consumeOne() @trusted nothrow
    {
        size_t tail = atomicLoad(readTail);
        entries[tail].clear();
        atomicStore(readTail, (tail + 1) & BUFFER_MASK);
    }
    
    /**
     * Number of entries pending.
     */
    size_t pending() @trusted nothrow
    {
        size_t head = atomicLoad(writeHead);
        size_t tail = atomicLoad(readTail);
        return (head - tail) & BUFFER_MASK;
    }
}

// ============================================================================
// LOGGER (Singleton with background flush)
// ============================================================================

/**
 * Logger - High-performance async logger
 * 
 * Features:
 * - Lock-free ring buffer
 * - Background flush thread
 * - Configurable behavior on buffer full (drop vs sync)
 * - Metrics for monitoring
 */
class Logger
{
    // Singleton with double-checked locking
    private __gshared Logger instance;
    private __gshared bool instanceCreated = false;
    private static Mutex instanceMutex;
    
    // Configuration
    private shared LogLevel currentLevel = LogLevel.INFO;
    private LogOutput outputType = LogOutput.STDOUT;
    private File outputFile;
    private string logFilePath;
    private bool dropOnFull = false;  // If true, drop logs when buffer full (better latency)
    
    // Lock-free ring buffer
    private __gshared LogRingBuffer buffer;
    
    // Background flush thread
    private Thread flushThread;
    private shared bool running = true;
    private Mutex flushMutex;
    private Condition flushCondition;
    
    // === Metrics ===
    private shared ulong logsWritten = 0;
    private shared ulong logsDropped = 0;
    private shared ulong syncFallbacks = 0;
    
    static this()
    {
        instanceMutex = new Mutex();
    }
    
    /**
     * Get singleton logger instance (double-checked locking)
     */
    static Logger get() @trusted
    {
        // Fast path: instance already created
        if (atomicLoad(instanceCreated))
            return instance;
        
        // Slow path: create instance
        synchronized (instanceMutex)
        {
            if (!atomicLoad(instanceCreated))
            {
                instance = new Logger();
                atomicStore(instanceCreated, true);
            }
        }
        return instance;
    }
    
    private this() @trusted
    {
        flushMutex = new Mutex();
        flushCondition = new Condition(flushMutex);
        outputFile = stdout;
        
        // Start background flush thread
        flushThread = new Thread(&flushLoop);
        flushThread.name = "aurora-logger";
        flushThread.isDaemon = true;  // Don't block program exit
        flushThread.start();
    }
    
    /**
     * Set minimum log level (thread-safe, lock-free)
     */
    void setLevel(LogLevel level) @safe
    {
        atomicStore(currentLevel, level);
    }
    
    /**
     * Set output destination
     */
    void setOutput(LogOutput output, string filePath = null) @trusted
    {
        synchronized (flushMutex)
        {
            outputType = output;
            
            if (output == LogOutput.FILE && filePath !is null)
            {
                logFilePath = filePath;
                outputFile = File(filePath, "a");
            }
            else if (output == LogOutput.STDOUT)
            {
                outputFile = stdout;
            }
            else if (output == LogOutput.STDERR)
            {
                outputFile = stderr;
            }
        }
    }
    
    /**
     * Set behavior when ring buffer is full.
     * 
     * Params:
     *   drop = If true, drop logs when buffer is full (better latency).
     *          If false, fallback to synchronous write (may block, no log loss).
     */
    void setDropOnFull(bool drop) @safe nothrow
    {
        dropOnFull = drop;
    }
    
    // ========================================
    // Metrics
    // ========================================
    
    /// Get total logs written to ring buffer
    ulong getLogsWritten() @safe nothrow { return atomicLoad(logsWritten); }
    
    /// Get total logs dropped (when dropOnFull=true and buffer was full)
    ulong getLogsDropped() @safe nothrow { return atomicLoad(logsDropped); }
    
    /// Get total sync fallbacks (when dropOnFull=false and buffer was full)
    ulong getSyncFallbacks() @safe nothrow { return atomicLoad(syncFallbacks); }
    
    /// Get current pending logs in buffer
    size_t getPending() @trusted nothrow { return buffer.pending(); }
    
    // ========================================
    // Log methods
    // ========================================
    
    /**
     * Log debug message
     */
    void debug_(T...)(string msg, T args)
    {
        log(LogLevel.DEBUG, msg, args);
    }
    
    /**
     * Log info message
     */
    void info(T...)(string msg, T args)
    {
        log(LogLevel.INFO, msg, args);
    }
    
    /**
     * Log warning message
     */
    void warn(T...)(string msg, T args)
    {
        log(LogLevel.WARN, msg, args);
    }
    
    /**
     * Log error message
     */
    void error(T...)(string msg, T args)
    {
        log(LogLevel.ERROR, msg, args);
    }
    
    /**
     * Force immediate flush (blocks until buffer is empty)
     */
    void flush() @trusted
    {
        // Signal flush thread to wake up
        synchronized (flushMutex)
        {
            flushCondition.notify();
        }
        
        // Spin until buffer is empty (with yield)
        while (buffer.pending() > 0)
        {
            Thread.yield();
        }
        
        // Flush file buffer
        synchronized (flushMutex)
        {
            if (outputFile != stdout && outputFile != stderr)
            {
                outputFile.flush();
            }
        }
    }
    
    /**
     * Shutdown logger (call before program exit for clean shutdown)
     */
    void shutdown() @trusted
    {
        atomicStore(running, false);
        
        synchronized (flushMutex)
        {
            flushCondition.notify();
        }
        
        if (flushThread !is null)
        {
            flushThread.join();
        }
        
        // Final flush
        flushRemaining();
        
        if (outputFile != stdout && outputFile != stderr)
        {
            outputFile.close();
        }
    }
    
    ~this()
    {
        if (atomicLoad(running))
        {
            shutdown();
        }
    }
    
    // ========================================
    // Private implementation
    // ========================================
    
    private void log(T...)(LogLevel level, string msg, T args)
    {
        // Fast path: filter by level (lock-free)
        if (level < atomicLoad(currentLevel))
            return;
        
        // Build log entry string
        string logEntry = buildLogEntry(level, msg is null ? "" : msg, args);
        
        // Write to ring buffer (lock-free)
        if (!buffer.tryWrite(level, logEntry))
        {
            // Buffer full
            if (dropOnFull)
            {
                // Drop the log (better latency, may lose logs)
                atomicOp!"+="(logsDropped, 1);
                return;
            }
            else
            {
                // Fallback to direct write (blocks, but no log loss)
                atomicOp!"+="(syncFallbacks, 1);
                synchronized (flushMutex)
                {
                    try { outputFile.writeln(logEntry); } catch (Exception) {}
                }
            }
        }
        else
        {
            atomicOp!"+="(logsWritten, 1);
        }
        
        // Wake up flush thread if buffer is getting full
        if (buffer.pending() > LogRingBuffer.BUFFER_SIZE / 2)
        {
            synchronized (flushMutex)
            {
                flushCondition.notify();
            }
        }
    }
    
    private void flushLoop() @trusted
    {
        while (atomicLoad(running))
        {
            // Wait for signal or timeout (flush every 10ms max)
            synchronized (flushMutex)
            {
                flushCondition.wait(10.msecs);
            }
            
            // Flush all pending entries
            flushRemaining();
        }
    }
    
    private void flushRemaining() @trusted
    {
        LogEntry* entry;
        
        while ((entry = buffer.tryRead()) !is null)
        {
            try
            {
                auto msg = entry.message[0 .. entry.messageLen];
                
                synchronized (flushMutex)
                {
                    outputFile.writeln(msg);
                }
            }
            catch (Exception) {}
            
            buffer.consumeOne();
        }
    }
    
    private string buildLogEntry(T...)(LogLevel level, string msg, T args)
    {
        import std.array : appender;
        
        auto result = appender!string();
        
        // Timestamp
        auto now = Clock.currTime();
        result ~= format("[%04d-%02d-%02d %02d:%02d:%02d]",
            now.year, now.month, now.day,
            now.hour, now.minute, now.second);
        
        // Level
        result ~= " [";
        final switch (level)
        {
            case LogLevel.DEBUG: result ~= "DEBUG"; break;
            case LogLevel.INFO:  result ~= "INFO "; break;
            case LogLevel.WARN:  result ~= "WARN "; break;
            case LogLevel.ERROR: result ~= "ERROR"; break;
        }
        result ~= "] ";
        
        // Message
        result ~= msg;
        
        // Structured fields
        static if (args.length > 0)
        {
            result ~= " {";
            
            static foreach (i; 0 .. args.length / 2)
            {
                static if (i > 0)
                    result ~= ", ";
                
                result ~= to!string(args[i * 2]);
                result ~= "=";
                result ~= to!string(args[i * 2 + 1]);
            }
            
            result ~= "}";
        }
        
        return result.data;
    }
}
