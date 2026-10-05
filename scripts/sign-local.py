"""Keep local builds' permission identity stable when Apple Development is available."""
import os
from pathlib import Path
import re
import subprocess
import sys

app = Path(sys.argv[1])
identity = os.environ.get("LOCAL_SIGNING_IDENTITY", "")
if not identity:
    result = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                            capture_output=True, text=True, check=True)
    identities = re.findall(r'\b([A-F0-9]{40}) "Apple Development: [^"\n]+"', result.stdout)
    if len(identities) == 1:
        identity = identities[0]
    else:
        identity = "-"
        print("WARNING: ad hoc signing. Every rebuild can invalidate Microphone and Accessibility. "
              "Set LOCAL_SIGNING_IDENTITY to a valid Apple Development identity for stable local permissions.",
              file=sys.stderr)

# Developer ID distribution uses sign-release.py instead. This local build has
# no new entitlements, custom trust requirements, or permission bypasses.
subprocess.run(["codesign", "--force", "--deep", "--sign", identity,
                "--identifier", "local.mike.dictation", str(app)], check=True)
print("Local build signed with " + ("an Apple code-signing identity." if identity != "-" else "an ad hoc signature."))
