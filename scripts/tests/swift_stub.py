#!/usr/bin/env python3
"""Swift command double for validation-runner contracts; never builds or tests."""

import json
import os
from pathlib import Path
import sys
import time

arguments = sys.argv[1:]
phase = ("build" if arguments[0] == "build" else "discovery" if "list" in arguments
         else "client" if "--no-parallel" in arguments else "bounded")
with Path(os.environ["RUNNER_CALLS"]).open("a") as output:
    output.write(json.dumps({"arguments": arguments, "phase": phase,
                             "interop": os.environ.get("OPALFUSION_EC_INTEROP")}) + "\n")
scenario = os.environ.get("RUNNER_SCENARIO", "")
if scenario == "fail-" + phase:
    sys.exit({"build": 17, "discovery": 18, "client": 19, "bounded": 20}[phase])
if scenario == "slow-" + phase:
    time.sleep(1)
if scenario == "slow-each" and phase != "build":
    time.sleep(1.5)
if phase == "discovery":
    listing = json.loads(Path(os.environ["RUNNER_DISCOVERY"]).read_text())
    print("\n".join(listing))
