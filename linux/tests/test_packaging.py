"""Exercise the generated launcher without requiring Debian packaging tools."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class PackagingTests(unittest.TestCase):
    def test_installed_launcher_uses_the_distro_python(self) -> None:
        script = Path(__file__).resolve().parents[1] / "packaging" / "build-deb.sh"
        launcher = script.read_text().split("<<'LAUNCHER'\n", 1)[1].split("\nLAUNCHER", 1)[0]
        # Retain the tiny launch fixture for inspection, in keeping with artifact safety.
        directory = Path(tempfile.mkdtemp(prefix="molapp-launcher-test-"))
        shadow_python = directory / "python3"
        shadow_python.write_text("#!/bin/sh\nexit 87\n")
        shadow_python.chmod(0o755)
        (directory / "molapp.py").write_text(
            "import sys; print(sys.executable); print(sys.argv[1:])\n"
        )
        result = subprocess.run(
            ["/bin/sh", "-c", launcher, "molapp", "file with spaces.pdb"],
            cwd=directory,
            env={**os.environ, "PATH": f"{directory}:{os.environ.get('PATH', '')}"},
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        system_python = subprocess.check_output(
            ["/usr/bin/python3", "-c", "import sys; print(sys.executable)"], text=True
        ).strip()
        self.assertEqual(result.stdout.splitlines(), [system_python, "['file with spaces.pdb']"])


if __name__ == "__main__":
    unittest.main()
