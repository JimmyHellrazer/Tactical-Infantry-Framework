"""Scan infil/dismount SEAnims: length, root travel, speed at the end, notetracks.
usage: python -I infil_scan.py <tools_dir> <names_file> <regex> <anim_root> [<anim_root> ...]"""
import sys, re, os, math
sys.path.insert(0, sys.argv[1])
from cod_anim_prep import read_seanim

names = [l.strip() for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
rx = re.compile(sys.argv[3])
roots = sys.argv[4:]

def find(n):
    for r in roots:
        p = os.path.join(r, n + ".seanim")
        if os.path.exists(p):
            return p

def sample(keys, f):
    if not keys:
        return None
    prev = keys[0]
    for k in keys:
        if k[0] >= f:
            if k[0] == prev[0]:
                return k[1]
            t = (f - prev[0]) / (k[0] - prev[0])
            return [a + (b - a) * t for a, b in zip(prev[1], k[1])]
        prev = k
    return keys[-1][1]

for n in names:
    if not rx.search(n):
        continue
    p = find(n)
    if not p:
        print(f"{n:60s} MISSING")
        continue
    try:
        a = read_seanim(p)
    except Exception as e:
        print(f"{n:60s} ERR {e}")
        continue
    fps, fr = a["fps"] or 30, max(1, a["frames"])
    dur = fr / fps
    b = a["bones"]
    root = None
    for cand in ("tag_origin", "j_mainroot"):
        if cand in b and b[cand].get("loc"):
            root = cand
            break
    travel = endspd = drop = 0
    if root:
        k = b[root]["loc"]
        s, e = sample(k, 0), sample(k, fr - 1)
        travel = math.hypot(e[0] - s[0], e[1] - s[1]) / 2.54
        drop = (e[2] - s[2]) / 2.54
        w = max(2, int(fps * 0.2))
        e0 = sample(k, max(0, fr - 1 - w))
        endspd = math.hypot(e[0] - e0[0], e[1] - e0[1]) / 2.54 / (w / fps)
    keyn = ("finish", "code_move", "start_aim", "motion_warp_end", "ws_raise", "free_look", "land", "unhook", "detach")
    notes = " ".join(f"{x[1]}@{x[0] / fps:.1f}" for x in a["notes"] if x[1].startswith(keyn))[:120]
    print(f"{n:60s} {dur:5.1f}s root={root or '-':10s} travel={travel:6.0f} drop={drop:6.0f} end={endspd:5.0f}u/s {notes}")
