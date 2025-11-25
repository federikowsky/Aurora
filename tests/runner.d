module tests.runner;

import std.stdio;
import core.runtime;
import core.stdc.stdlib : exit;

void main()
{
    writeln("=== Aurora Test Suite ===\n");

    // Run all unittests
    auto result = runModuleUnitTests();

    if (result)
    {
        writeln("\n✅ All tests passed!");
    }
    else
    {
        writeln("\n❌ Some tests failed");
        exit(1);
    }
}
