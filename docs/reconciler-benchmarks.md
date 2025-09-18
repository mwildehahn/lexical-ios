# Reconciler Benchmark Baselines

This document tracks baseline performance metrics for the legacy reconciler on representative documents. Use the `ReconcilerBenchmarkHarness` XCTest helper (`ReconcilerPerformanceTests.swift`) to regenerate numbers whenever reconciler logic changes.

## How to Re-run

1. Run the targeted XCTest filter to generate metrics:
   ```sh
   swift test --filter ReconcilerPerformanceTests/testGeneratesBaselineSnapshot
   ```
2. Copy the emitted metrics from the debugger/console if you add logging, or instrument the test to print results while iterating on performance.
3. Update the tables below with the latest metrics.

## Baseline Snapshot (legacy reconciler)

| Document Size | Paragraphs | Nodes Visited | Dirty Nodes | Inserted Characters | Deleted Characters | Duration (s) |
| ------------- | ---------- | ------------- | ----------- | ------------------- | ------------------ | ------------ |
| Small         | _pending_  | _pending_     | _pending_   | _pending_           | _pending_          | _pending_    |
| Medium        | _pending_  | _pending_     | _pending_   | _pending_           | _pending_          | _pending_    |
| Large         | _pending_  | _pending_     | _pending_   | _pending_           | _pending_          | _pending_    |

Record results per branch so future optimization attempts have a point of comparison, and commit updates alongside any performance-affecting changes.
