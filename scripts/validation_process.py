"""Run validation subprocesses with bounded, process-group-local cleanup."""

import os
import signal
import subprocess
import time


class ValidationInterrupted(Exception):
    def __init__(self, signum):
        self.signum = signum
        super().__init__(f"interrupted by signal {signum}")


class ValidationTimeout(Exception):
    pass


class ValidationProcess:
    def __init__(self, environment):
        self.environment = environment
        self.active = None
        self.handlers = {}
        self.launching = False
        self.pending_signal = None

    def __enter__(self):
        for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            self.handlers[signum] = signal.signal(signum, self.interrupt)
        return self

    def __exit__(self, *_):
        try:
            self.cleanup()
        finally:
            for signum, handler in self.handlers.items():
                signal.signal(signum, handler)

    def interrupt(self, signum, _frame):
        if self.launching:
            self.pending_signal = signum
            return
        raise ValidationInterrupted(signum)

    def run(self, command, *, deadline=None, capture=False):
        if deadline is not None and time.monotonic() >= deadline:
            raise ValidationTimeout("60-second post-build budget exhausted")
        # A new session keeps signals away from the caller and unrelated work.
        try:
            self.launching = True
            try:
                self.active = subprocess.Popen(
                    command, env=self.environment, start_new_session=True,
                    stdout=subprocess.PIPE if capture else None, text=True,
                )
            finally:
                self.launching = False
            if self.pending_signal is not None:
                raise ValidationInterrupted(self.pending_signal)
            remaining = None if deadline is None else max(0, deadline - time.monotonic())
            output, _ = self.active.communicate(timeout=remaining)
            result = self.active.returncode
            if result:
                raise subprocess.CalledProcessError(result, command)
            if deadline is not None and time.monotonic() > deadline:
                raise ValidationTimeout("60-second post-build budget exhausted")
            self.active = None
            return output
        except subprocess.TimeoutExpired as error:
            self.cleanup()
            raise ValidationTimeout("60-second post-build budget exhausted") from error
        except BaseException:
            self.cleanup()
            raise

    def cleanup(self):
        process = self.active
        if process is None:
            return
        self.active = None
        # Repeated interrupts must not abandon the owned process group.
        saved = {s: signal.signal(s, signal.SIG_IGN) for s in self.handlers}
        try:
            end = time.monotonic() + 5
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                process.wait(timeout=max(0, end - time.monotonic()))
                return
            # Reserve time to reap a process that needs SIGKILL.
            grace_end = end - 0.2
            while time.monotonic() < grace_end:
                process.poll()
                try:
                    os.killpg(process.pid, 0)
                except ProcessLookupError:
                    break
                time.sleep(min(0.05, max(0, grace_end - time.monotonic())))
            else:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            process.wait(timeout=max(0, end - time.monotonic()))
        finally:
            if process.stdout is not None:
                process.stdout.close()
            for signum, handler in saved.items():
                signal.signal(signum, handler)
