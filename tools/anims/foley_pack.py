"""Pack the MW19 foley TIF uses (K:\\SOUNDSmw19\\foley) into the TIF addon as mono .ogg, and write the key -> count
table the client reads (lua/tif/npc/sh_foley_data.lua). Keys are folders under sound/tif/foley/, files 1..n.ogg.

  step/<surf>/<walk|run|sprint>_<l|r>   jump/<surf>   land/<surf>      footsteps (npc versions where MW has them)
  prone/<surf>                          going down onto the ground
  mvmt/<vest>/<creep|walk|run|sprint>_<pre|post>, mvmt/<vest>/prone_pre   gear / cloth with each step
  accent                                gear rattle accents
  rattle/<large|medium|small|launcher>, rattle/land                       weapon rattle
  fall/<surf>/<head|limb_lrg|limb_sm|torso>                               body falls
  drop/<type>/<surf>                    a weapon hitting the ground
  stance/<vest>/<down|up|prone|prone_up>, mantle/<vest>/<32|48|56><over|up>
"""
import os, re, subprocess, sys, shutil
from collections import defaultdict

SRC = r"K:\SOUNDSmw19\foley"
ADDON = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\tactical_infantry_framework"
OUT = os.path.join(ADDON, "sound", "tif", "foley")
DATA = os.path.join(ADDON, "lua", "tif", "npc", "sh_foley_data.lua")
FF = r"C:\Users\fnafa\AppData\Local\Medal\recorder-2647.3706.1\ffmpeg7.exe"

groups = defaultdict(list)
def add(key, path): groups[key].append(path)

# footsteps
foot = os.path.join(SRC, "foot")
for surf in os.listdir(foot):
    d = os.path.join(foot, surf)
    if not os.path.isdir(d) or surf in ("ceiling", "heavy", "damage", "metal_ladder", "metal_ladder_solid", "wood_ladder"):
        continue
    npc = os.path.join(d, "npc")
    src = npc if os.path.isdir(npc) else d
    for f in sorted(os.listdir(src)):
        if not f.endswith(".wav"): continue
        b = f[:-4]
        m = re.match(r"step_(walk|run|sprint)_[a-z_]+?_(l|r)(_npc)?_\d+$", b)
        if m: add(f"step/{surf}/{m.group(1)}_{m.group(2)}", os.path.join(src, f)); continue
        m = re.match(r"step_(jump|land)_[a-z_]+?(_npc)?_\d+$", b)
        if m: add(f"{m.group(1)}/{surf}", os.path.join(src, f))
    # water_knee / waist have no l / r: their walk set for both feet
    if surf in ("water_knee", "water_waist"):
        for f in sorted(os.listdir(d)):
            m = re.match(r"step_(walk|run|sprint)_" + surf + r"_\d+\.wav$", f)
            if m:
                for side in ("l", "r"): add(f"step/{surf}/{m.group(1)}_{side}", os.path.join(d, f))
for f in sorted(os.listdir(foot)):
    m = re.match(r"prone_([a-z]+)_\d+\.wav$", f)
    if m: add(f"prone/{m.group(1)}", os.path.join(foot, f))

# gear with steps
mv = os.path.join(SRC, "mvmt")
for vest in ("vestlight", "vestheavy", "vestaq", "cloth"):
    for gait in ("creep", "walk", "run", "sprint", "prone"):
        d = os.path.join(mv, vest, gait)
        if not os.path.isdir(d): continue
        for f in sorted(os.listdir(d)):
            m = re.match(r"mvmtstep_\w+?_plr_" + gait + r"_(pre|post)_\d+\.wav$", f)
            if m: add(f"mvmt/{vest}/{gait}_{m.group(1)}", os.path.join(d, f))
for f in sorted(os.listdir(os.path.join(mv, "accents"))):
    if f.endswith(".wav"): add("accent", os.path.join(mv, "accents", f))
wm = os.path.join(SRC, "weapmvmt")
for size in ("large", "medium", "small", "launcher"):
    d = os.path.join(wm, size)
    for f in sorted(os.listdir(d)):
        if not f.endswith(".wav") or "_plr" in f: continue
        add("rattle/land" if "land" in f else f"rattle/{size}", os.path.join(d, f))

# body falls
bf = os.path.join(SRC, "bodyfalls")
for surf in os.listdir(bf):
    if surf == "player_death": continue
    d = os.path.join(bf, surf)
    for f in sorted(os.listdir(d)):
        m = re.match(r"iw8_bodyfall_(head|limb_lrg|limb_lg|limb_sm|torso)_", f)
        if m: add(f"fall/{surf}/{m.group(1).replace('limb_lg', 'limb_lrg')}", os.path.join(d, f))

# weapon drops
dr = os.path.join(SRC, "drop")
for f in sorted(os.listdir(dr)):
    m = re.match(r"weap_drop_(.+?)_(carpet|concrete|dirt|grass|metal|mud|sand|water|wood_hollow|wood_solid)_?\d*\.wav$", f)
    if m: add(f"drop/{m.group(1)}/{m.group(2)}", os.path.join(dr, f))

# stance changes, mantles
st = os.path.join(SRC, "stance")
for f in sorted(os.listdir(st)):
    m = re.match(r"mvmt_(\w+?)_plr_stance(_prone_up|_prone|_up)?_?\d*\.wav$", f)
    if m:
        kind = {"_prone_up": "prone_up", "_prone": "prone", "_up": "up", None: "down"}[m.group(2)]
        add(f"stance/{m.group(1)}/{kind}", os.path.join(st, f))
mt = os.path.join(SRC, "mantle")
for f in sorted(os.listdir(mt)):
    m = re.match(r"mantle_(\w+?)_(32|48|56)(over|up)(_extreme)?_?\d*\.wav$", f)
    if m and not m.group(4): add(f"mantle/{m.group(1)}/{m.group(2)}{m.group(3)}", os.path.join(mt, f))

if "--list" in sys.argv:
    for k in sorted(groups): print(f"{len(groups[k]):3} {k}")
    print(len(groups), "keys", sum(len(v) for v in groups.values()), "files")
    sys.exit()

if os.path.isdir(OUT): shutil.rmtree(OUT)
jobs = []
for k, files in sorted(groups.items()):
    d = os.path.join(OUT, *k.split("/"))
    os.makedirs(d, exist_ok=True)
    for i, src in enumerate(files, 1):
        jobs.append((src, os.path.join(d, f"{i}.ogg")))
def conv(j):
    subprocess.run([FF, "-v", "error", "-y", "-i", j[0], "-ac", "1", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "4", j[1]], check=True)
    return os.path.getsize(j[1])
from concurrent.futures import ThreadPoolExecutor
with ThreadPoolExecutor(8) as ex:
    total = sum(ex.map(conv, jobs))
with open(DATA, "w", encoding="utf-8", newline="\n") as fh:
    fh.write("-- Generated by foley_pack.py (MW19 foley, K:\\SOUNDSmw19): sound/tif/foley/<key>/<1..n>.ogg -> n\n")
    fh.write("TIF = TIF or {}\nTIF.FoleyData = {\n")
    for k in sorted(groups): fh.write(f'\t["{k}"] = {len(groups[k])},\n')
    fh.write("}\n")
print(len(groups), "keys", sum(len(v) for v in groups.values()), "files", round(total / 1048576, 1), "MB")
