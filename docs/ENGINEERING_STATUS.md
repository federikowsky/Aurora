# Engineering status — 2026-09-27

Aurora is undergoing evidence-based validation. Feature availability is not a
production-readiness guarantee. The first-party ecosystem includes Wire,
FastjsonD and aurora-websocket; defects belong with the component that owns the
contract.

This maintenance branch fixes response-buffer capacity handling in Aurora and
pins Wire's fix for overlapping request lifetimes. Input bytes remain borrowed;
parser state is held exclusively until its request is released. Reusing a parser
never permits resetting another live request. Wire documents native allocations
separately from D-GC allocation and supports explicitly owned parser reuse.

Local validation uses Linux x86-64, LDC 1.42.0 and DUB 1.41.0. It includes buffer
canaries in debug/release, parser lifetime tests, Aurora's automated suite and
HTTP framing probes. This does not establish portable performance or complete
HTTP compliance. Changes must be published in dependency order: Wire first,
then Aurora with its exact dependency pin.

Wire is now publicly available at `ced07d5c2c07b1c459b62e4e28e1612df2095ae2`.
Its tree `981b673ddaf8f789664a6fc85079374af3bb38aa` is identical to the locally
validated candidate `1b9761e47877dde3c349a1f308b0edd0d9d16fde`; only commit
metadata differs. Both DUB manifests pin the public revision. Historical
measurements retain their original revision identifiers.

Remaining release blockers observed on the base revision include response
headers discarded by the runtime, connection ownership after deferred hijack,
subrouter middleware not reaching dispatch, inaccurate multi-worker counters,
in-flight admission lifetime, and logger shutdown. Worker busy-waiting and
startup/join coordination also require correction. These paths are unchanged by
this maintenance branch; passing the focused tests does not close them.

Performance claims must name the path, payload, concurrency, compiler, GC/native
allocation scope and raw evidence. The routed request still allocates D-GC
memory. Current shared-VM HTTP measurements are diagnostic, not release gates.

The local 1 KiB response comparison has an unresolved tail-latency signal:
across seven paired fresh-process trials, candidate p99 was higher in six.
Median per-trial p99 was 4.952 ms for the base and 7.558 ms for the candidate;
p99.9 was 8.203 ms and 16.106 ms. Attribution to either fix is unverified.
The capacity and parser-lease changes remain correctness candidates, not a
claim of performance equivalence. Before release, isolate the two changes and
measure native parser allocation under the same offered load.

A subsequent 16-trial factorial experiment separated capacity and Wire changes,
using four balanced blocks, 5-second warm-up and 10-second measurements. Its p99
effects do not support a consistent Wire-only explanation of the earlier tail
signal. The capacity main contrast was negative for throughput and positive for
CPU/request in all four blocks; causality remains unverified. Different trial
durations prevent pooling these observations with the earlier series. Both sets
of raw results are retained; performance equivalence is still not established.
