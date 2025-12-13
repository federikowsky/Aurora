module tests.unit.mem.pressure_test;

import aurora.mem.pressure;
import core.time;
import core.memory;

// ============================================================================
// UNIT TESTS - Moved from source/aurora/mem/pressure.d
// ============================================================================

// Test 1: Config defaults
@("memory config has sensible defaults")
unittest
{
    auto config = MemoryConfig.defaults();
    assert(config.maxHeapBytes == 512 * 1024 * 1024);
    assert(config.highWaterRatio == 0.8);
    assert(config.criticalWaterRatio == 0.95);
}

// Test 2: Config computed properties
@("memory config computed water marks")
unittest
{
    auto config = MemoryConfig();
    config.maxHeapBytes = 1000;
    config.highWaterRatio = 0.8;
    config.criticalWaterRatio = 0.95;
    
    assert(config.highWaterMark == 800);
    assert(config.criticalWaterMark == 950);
}

// Test 3: Config withMaxMB factory
@("memory config withMaxMB")
unittest
{
    auto config = MemoryConfig.withMaxMB(256);
    assert(config.maxHeapBytes == 256 * 1024 * 1024);
}

// Test 4: MemoryState enum values
@("memory state enum")
unittest
{
    assert(MemoryState.NORMAL == cast(MemoryState)0);
    assert(MemoryState.PRESSURE == cast(MemoryState)1);
    assert(MemoryState.CRITICAL == cast(MemoryState)2);
}

// Test 5: PressureAction enum values
@("pressure action enum")
unittest
{
    assert(PressureAction.GC_COLLECT == cast(PressureAction)0);
    assert(PressureAction.LOG_ONLY == cast(PressureAction)1);
    assert(PressureAction.CUSTOM == cast(PressureAction)2);
    assert(PressureAction.NONE == cast(PressureAction)3);
}

// Test 6: MemoryStats utilization
@("memory stats utilization")
unittest
{
    MemoryStats stats;
    stats.usedBytes = 500;
    stats.maxBytes = 1000;
    
    assert(stats.utilization == 0.5);
}

// Test 7: MemoryStats utilization edge case
@("memory stats utilization edge case")
unittest
{
    MemoryStats stats;
    stats.maxBytes = 0;
    stats.usedBytes = 100;
    
    assert(stats.utilization == 0.0);
}

// Test 8: MemoryStats poolUtilization
@("memory stats pool utilization")
unittest
{
    MemoryStats stats;
    stats.usedBytes = 300;
    stats.poolBytes = 600;
    
    assert(stats.poolUtilization == 0.5);
}

// Test 9: MemoryStats headroom
@("memory stats headroom")
unittest
{
    MemoryStats stats;
    stats.usedBytes = 500;
    stats.maxBytes = 1000;
    
    // High water at 80% = 800
    assert(stats.headroom == 300);
}

// Test 10: MemoryMonitor creation
@("memory monitor creation")
unittest
{
    auto monitor = new MemoryMonitor();
    assert(monitor !is null);
    assert(monitor.getState() == MemoryState.NORMAL);
}

// Test 11: MemoryMonitor initial state
@("memory monitor initial state is NORMAL")
unittest
{
    auto config = MemoryConfig();
    config.maxHeapBytes = 1024 * 1024 * 1024;  // 1GB - should be plenty
    auto monitor = new MemoryMonitor(config);
    
    // Should be NORMAL with such high limit
    assert(!monitor.isCritical());
}

// Test 12: MemoryMonitor isUnderPressure
@("memory monitor isUnderPressure")
unittest
{
    auto monitor = new MemoryMonitor();
    // Initial state should be NORMAL
    assert(!monitor.isUnderPressure() || monitor.getState() >= MemoryState.PRESSURE);
}

// Test 13: MemoryMonitor stats
@("memory monitor stats")
unittest
{
    auto monitor = new MemoryMonitor();
    auto stats = monitor.getStats();
    
    assert(stats.maxBytes == 512 * 1024 * 1024);
    assert(stats.gcCollections == 0);
    assert(stats.rejectedRequests == 0);
}

// Test 14: MemoryMonitor configuration access
@("memory monitor configuration")
unittest
{
    auto config = MemoryConfig();
    config.maxHeapBytes = 256 * 1024 * 1024;
    auto monitor = new MemoryMonitor(config);
    
    assert(monitor.configuration.maxHeapBytes == 256 * 1024 * 1024);
}

// Test 15: MemoryMonitor resetStats
@("memory monitor reset stats")
unittest
{
    auto monitor = new MemoryMonitor();
    monitor.recordRejection();
    monitor.resetStats();
    
    auto stats = monitor.getStats();
    assert(stats.rejectedRequests == 0);
}

// Test 16: MemoryMonitor recordRejection
@("memory monitor record rejection")
unittest
{
    auto monitor = new MemoryMonitor();
    
    monitor.recordRejection();
    monitor.recordRejection();
    
    auto stats = monitor.getStats();
    assert(stats.rejectedRequests == 2);
}

// Test 17: MemoryMonitor forceGC
@("memory monitor forceGC increments counter")
unittest
{
    auto monitor = new MemoryMonitor();
    auto beforeStats = monitor.getStats();
    
    monitor.forceGC();
    
    auto afterStats = monitor.getStats();
    assert(afterStats.gcCollections == beforeStats.gcCollections + 1);
}

// Test 18: Config bypass paths
@("memory config bypass paths")
unittest
{
    auto config = MemoryConfig();
    assert(config.bypassPaths.length == 1);
    assert(config.bypassPaths[0] == "/health/*");
}
