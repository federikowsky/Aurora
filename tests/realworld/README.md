# Experimental load and lifecycle fixtures

This directory is outside the ordinary DUB unittest selection and CI. Its Python clients and D servers are investigation tools; their existence is not evidence of successful stress, soak, scalability or graceful shutdown validation.

Inspect each fixture and its CLI before running. The historical manual linking instructions and Makefile assume a `lib/wire` layout not provided by the current DUB dependency graph. Repair/validate the build recipe before treating these servers as runnable supported examples. Do not quote the old “expected results” table as measured performance.

Use the maintained [validation guide](../../docs/TEST_REGISTRY.md) for current checks and [benchmark guide](../../benchmarks/README.md) for measurement discipline. The [original fixture notes](https://github.com/federikowsky/Aurora/blob/3416660672229179b947e54bf4bfb650309aa38e/tests/realworld/README.md) remain historical evidence.
