/+ dub.sdl:
    name "stress_client"
    libs "curl"
+/
module stress_client;

import std.stdio;
import std.datetime.stopwatch;
import std.net.curl;
import std.parallelism;
import std.range;
import core.atomic;
import core.thread;

void main()
{
    string url = "http://127.0.0.1:8080/";
    int totalRequests = 10000;
    int concurrency = 50;
    
    writeln("Starting stress test against ", url);
    writeln("Total requests: ", totalRequests);
    writeln("Concurrency: ", concurrency);
    
    shared int completed = 0;
    shared int failed = 0;
    
    auto sw = StopWatch(AutoStart.yes);
    
    // Work units
    auto work = iota(totalRequests);
    
    // Parallel processing
    foreach (i; parallel(work, concurrency))
    {
        try
        {
            auto content = get(url);
            atomicOp!"+="(completed, 1);
        }
        catch (Exception e)
        {
            atomicOp!"+="(failed, 1);
            // writeln("Request failed: ", e.msg);
        }
        
        if (completed % 1000 == 0)
        {
            writef("\rProgress: %d/%d (Failed: %d)", completed, totalRequests, failed);
            stdout.flush();
        }
    }
    
    sw.stop();
    
    writeln("\n\n=== Results ===");
    writeln("Time taken: ", sw.peek.total!"msecs", " ms");
    writeln("Requests/sec: ", cast(double)totalRequests / (sw.peek.total!"msecs" / 1000.0));
    writeln("Successful: ", completed);
    writeln("Failed: ", failed);
}
