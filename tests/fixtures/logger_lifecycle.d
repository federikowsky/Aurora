module logger_lifecycle;
import aurora.logging : Logger;
import core.thread : Thread;
import core.atomic : atomicLoad, atomicStore, atomicOp;
import std.exception : enforce;

// Separate processes exercise module teardown; an in-process unittest cannot.
private __gshared Logger[8] instances;
private shared uint ready;
private shared bool go;
void main(string[] args)
{
    enforce(args.length == 2, "expected lifecycle mode");
    if (args[1] == "unused") return;
    if (args[1] == "workers")
    {
        Thread[8] threads;
        foreach (i; 0 .. threads.length)
        {
            threads[i] = (size_t index) {
                return new Thread({
                atomicOp!"+="(ready, 1);
                while (!atomicLoad(go)) Thread.yield();
                instances[index] = Logger.get();
                instances[index].info("worker marker");
                });
            }(i);
        }
        foreach (thread; threads) thread.start();
        while (atomicLoad(ready) != threads.length) Thread.yield();
        atomicStore(go, true);
        foreach (thread; threads) thread.join();
        foreach (instance; instances)
            enforce(instance is Logger.get(), "different process-wide logger");
    }
    auto logger = Logger.get();
    logger.info("final marker");
    if (args[1] == "explicit") logger.shutdown();
}
