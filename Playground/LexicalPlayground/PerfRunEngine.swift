/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import QuartzCore
import UIKit

/// A lightweight, non-blocking runner that executes a fixed number of iterations by
/// chunking work across display frames. It runs steps on the main thread (required by
/// UIKit/TextKit) but yields between chunks to keep the UI responsive.
final class PerfRunEngine {
  struct Config {
    /// Target time budget per frame spent executing steps (milliseconds).
    let frameBudgetMs: Double
    /// Hard cap on number of steps per frame to avoid long loops when steps are very cheap.
    let maxStepsPerFrame: Int
    /// Minimum steps per frame to ensure progress when steps are extremely slow.
    let minStepsPerFrame: Int
    /// Optional soft deadline (seconds) to stop a run as failed if exceeded.
    let softDeadlineSeconds: TimeInterval?
    static let `default` = Config(frameBudgetMs: 10.0, maxStepsPerFrame: 12, minStepsPerFrame: 1, softDeadlineSeconds: nil)
  }

  enum State { case idle, running, cancelled, finished }

  private var displayLink: CADisplayLink?
  private var cfg: Config = .default
  private var total: Int = 0
  private var completed: Int = 0
  private var state: State = .idle
  private var startedAt: CFTimeInterval = 0
  private var lastStepDurationMs: Double = 0

  // Callbacks
  private var step: (() -> Void)?
  private var onProgress: ((Int, Int, Double) -> Void)? // completed, total, lastStepMs
  private var onFinish: ((Bool) -> Void)? // success
  private var shouldRunTick: (() -> Bool)?

  init() {}

  func cancel() {
    guard state == .running else { return }
    state = .cancelled
    teardownLink()
    onFinish?(false)
    clear()
  }

  func run(totalIterations: Int,
           config: Config = .default,
           step: @escaping () -> Void,
           onProgress: @escaping (Int, Int, Double) -> Void,
           onFinish: @escaping (Bool) -> Void,
           shouldRunThisTick: (() -> Bool)? = nil) {
    guard state != .running else { return }
    self.cfg = config
    self.total = max(0, totalIterations)
    self.completed = 0
    self.step = step
    self.onProgress = onProgress
    self.onFinish = onFinish
    self.shouldRunTick = shouldRunThisTick
    self.state = .running
    self.startedAt = CACurrentMediaTime()
    self.lastStepDurationMs = 0

    let link = CADisplayLink(target: self, selector: #selector(tick))
    // On iOS 15+, prefer a lower frame rate for heavy runs to give
    // main-thread time to process layout and keep scrolling responsive.
    if #available(iOS 15.0, *) {
      // 30fps preferred with 60fps upper bound; system may adjust as needed.
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 30)
    }
    // Use common run loop mode so it ticks during scrolls and UI interactions
    link.add(to: .main, forMode: .common)
    self.displayLink = link
  }

  @objc private func tick() {
    guard state == .running else { return }
    if total == 0 { finish(success: true); return }

    if let gate = shouldRunTick, gate() == false {
      // Skip doing work this frame to keep UI responsive
      onProgress?(completed, total, lastStepDurationMs)
      return
    }

    if let deadline = cfg.softDeadlineSeconds {
      let elapsed = CACurrentMediaTime() - startedAt
      if elapsed > deadline { finish(success: false); return }
    }

    let frameStart = CACurrentMediaTime()
    let budget = cfg.frameBudgetMs / 1000.0 // seconds
    var did = 0

    while state == .running && completed < total {
      let s = CACurrentMediaTime()
      // Steps must execute on main due to UIKit/TextKit; we are already on main via CADisplayLink
      step?()
      let e = CACurrentMediaTime()
      lastStepDurationMs = max(0, (e - s) * 1000.0)
      completed += 1; did += 1

      // Stop if we hit step cap for this frame
      if did >= cfg.maxStepsPerFrame { break }
      // Stop if we exceeded frame budget (keep some headroom)
      if (e - frameStart) >= budget { break }
      // Ensure we always do at least minStepsPerFrame
      if did < cfg.minStepsPerFrame { continue }
    }

    onProgress?(completed, total, lastStepDurationMs)
    if completed >= total { finish(success: true) }
  }

  private func finish(success: Bool) {
    guard state == .running else { return }
    state = .finished
    teardownLink()
    onFinish?(success)
    clear()
  }

  private func teardownLink() { displayLink?.invalidate(); displayLink = nil }
  private func clear() {
    step = nil; onProgress = nil; onFinish = nil
    total = 0; completed = 0; lastStepDurationMs = 0
  }
}
