"""Build every exported gun (decimate -> textures -> compile). Logs to build/batch.log; a failing gun is reported
and skipped. Usage: batch.py [id ...] (default: every data/tif_gunbake/*.json)."""
import glob
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\data\tif_gunbake"
LOG = os.path.join(HERE, "build", "batch.log")
STEPS = ("gun_decimate.py", "gun_textures.py", "gun_compile.py")


def main():
    args = sys.argv[1:]
    # --lua: only rewrite the weapon definitions (after tif_gunbake_sounds); fast, models untouched.
    lua_only = "--lua" in args
    args = [a for a in args if a != "--lua"]
    ids = args or sorted(os.path.basename(f)[:-5] for f in glob.glob(os.path.join(DATA, "*.json"))
                         if not f.endswith("_sounds.json"))
    if lua_only:
        for gid in ids:
            r = subprocess.run([sys.executable, os.path.join(HERE, "gun_compile.py"), gid, "--lua-only"],
                               capture_output=True, text=True, errors="replace")
            print((r.stdout.strip() or r.stderr.strip()[-300:]), flush=True)
        return
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    ok, bad = [], []
    with open(LOG, "w") as log:
        for gid in ids:
            t0 = time.time()
            lines, failed = [], None
            for step in STEPS:
                r = subprocess.run([sys.executable, os.path.join(HERE, step), gid], capture_output=True, text=True,
                                   errors="replace")
                out = (r.stdout.strip().splitlines() or [""])[-1]
                lines.append(out)
                if r.returncode != 0:
                    failed = "%s: %s" % (step, (r.stdout + r.stderr).strip()[-600:])
                    break
            msg = "%-16s %5.0fs  %s" % (gid, time.time() - t0, "FAILED " + failed if failed else " || ".join(lines))
            print(msg, flush=True)
            log.write(msg + "\n")
            log.flush()
            (bad if failed else ok).append(gid)
        log.write("\nbuilt %d, failed %d: %s\n" % (len(ok), len(bad), ", ".join(bad)))
    print("built %d, failed %d: %s" % (len(ok), len(bad), ", ".join(bad)))


if __name__ == "__main__":
    main()
