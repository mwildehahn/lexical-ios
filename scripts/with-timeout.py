#!/usr/bin/env python3
"""
with-timeout.py — Run a command with idle and hard timeouts, streaming output.

- Idle timeout: if no new output is seen for N seconds, the process is killed.
- Hard timeout: regardless of output, kill after N seconds.

Exit codes:
 0   command succeeded
 124 timed out (idle or hard)
 non-zero passthrough of the child process exit code otherwise

Usage:
  python3 scripts/with-timeout.py --idle 120 --hard 1800 -- <command> [args...]

Notes:
 - Starts the child in its own process group, and kills the whole group on timeout.
 - Streams stdout/stderr live so CI logs remain verbose (no -quiet).
"""

import argparse
import os
import selectors
import signal
import subprocess
import sys
import time


def kill_tree(proc: subprocess.Popen, sig=signal.SIGKILL):
    try:
        # Kill the whole process group we created for the child
        os.killpg(proc.pid, sig)
    except ProcessLookupError:
        pass


def run_with_timeouts(cmd, idle_sec: int, hard_sec: int) -> int:
    start = time.time()
    last = start

    # Start child in its own process group so we can kill subprocess tree
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=1,
        text=True,
        preexec_fn=os.setsid,
    )

    sel = selectors.DefaultSelector()
    if proc.stdout:
        sel.register(proc.stdout, selectors.EVENT_READ)
    if proc.stderr:
        sel.register(proc.stderr, selectors.EVENT_READ)

    timed_out = False

    try:
        while True:
            if hard_sec and (time.time() - start) > hard_sec:
                timed_out = True
                print("\n🔥 TIMEOUT: hard limit exceeded — killing process…", file=sys.stderr)
                break

            # Wait up to 1s for any new output
            events = sel.select(timeout=1.0)
            if events:
                for key, _ in events:
                    line = key.fileobj.readline()
                    if line:
                        last = time.time()
                        # Preserve stream origin
                        if key.fileobj is proc.stdout:
                            sys.stdout.write(line)
                            sys.stdout.flush()
                        else:
                            sys.stderr.write(line)
                            sys.stderr.flush()
                # Check if process ended
                if proc.poll() is not None:
                    break
            else:
                # No IO this tick — check idle timeout
                if idle_sec and (time.time() - last) > idle_sec:
                    timed_out = True
                    print("\n🔥 TIMEOUT: idle limit exceeded — killing process…", file=sys.stderr)
                    break
                if proc.poll() is not None:
                    break
    finally:
        sel.close()

    if timed_out and proc.poll() is None:
        try:
            # First try SIGTERM for grace, then SIGKILL
            os.killpg(proc.pid, signal.SIGTERM)
            # Give it a moment to exit
            for _ in range(10):
                if proc.poll() is not None:
                    break
                time.sleep(0.2)
            if proc.poll() is None:
                kill_tree(proc, signal.SIGKILL)
        except Exception:
            kill_tree(proc, signal.SIGKILL)

    # Drain remaining output to not lose tail logs
    try:
        out, err = proc.communicate(timeout=3)
        if out:
            sys.stdout.write(out)
        if err:
            sys.stderr.write(err)
    except Exception:
        pass

    if timed_out:
        return 124
    return proc.returncode or 0


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--idle", dest="idle", type=int, default=0, help="Idle timeout in seconds (0=disabled)")
    ap.add_argument("--hard", dest="hard", type=int, default=0, help="Hard timeout in seconds (0=disabled)")
    ap.add_argument("--", dest="dashdash", nargs=argparse.REMAINDER)
    args, unknown = ap.parse_known_args()

    # Split after --
    cmd = None
    if args.dashdash:
        # Remove the leading -- if present
        dd = args.dashdash
        if dd and dd[0] == "--":
            dd = dd[1:]
        cmd = dd

    if not cmd:
        # If argparse didn’t capture via --, try remaining argv
        # Find the first -- and take the rest
        if "--" in sys.argv:
            idx = sys.argv.index("--")
            cmd = sys.argv[idx + 1 :]
    if not cmd:
        print("Usage: with-timeout.py --idle <sec> --hard <sec> -- <command> [args…]", file=sys.stderr)
        return 2

    rc = run_with_timeouts(cmd, idle_sec=args.idle, hard_sec=args.hard)
    sys.exit(rc)


if __name__ == "__main__":
    main()

