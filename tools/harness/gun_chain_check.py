import sys, os, numpy as np
R = r"K:\jimmyproject\Tactical Infantry Framework\Tactical Infantry Framework\tools"
sys.path.insert(0, os.path.join(R, "anims")); sys.path.insert(0, os.path.join(R, "guns"))
import cod_anim_prep as prep, cod_to_breen as c2b
ok = fail = 0
def check(c, w):
    global ok, fail
    if c: ok += 1
    else: fail += 1; print("FAIL:", w)
body = prep.read_smd("K:/head2/PlaceHolder_Body.smd"); prep.fill_frames(body)
mp = prep.load_mapping(prep.DEFAULT_MAPPING)
def built(path):
    a = prep.read_seanim(path)
    smd, _ = prep.seanim_to_smd(a, body, mp, True, prep.CM_TO_INCH, inplace=True)
    prep.fill_frames(smd)
    idx = {n: i for i, (n, _) in enumerate(smd.nodes)}
    out = []
    for _, bones in smd.frames:
        w = c2b.world_pose(smd.nodes, {i: prep.to_rt(v) for i, v in bones.items()})
        out.append(np.array(w[idx["j_gun"]][0]))
    return a, out, smd.nodes[smd.nodes.index(("j_gun", smd.nodes[idx["j_gun"]][1]))][1], smd.nodes
a19, g19, p19, n19 = built("K:/duglastakedown/sdr_com_exposed_stand_idle01.seanim")
a22, g22, p22, n22 = built("K:/mw22 anims 2/xanims/sdr_com_exposed_stand_idle01.seanim")
check(not prep.is_chain_gun(a19) and prep.is_chain_gun(a22), "MW19 AI clip: plain gun bone; MW22 copy: j_gun + j_gun_adjust chain")
check(n22[p22][0] == "ValveBiped.Bip01_R_Clavicle", "the chain hangs off the right clavicle")
err = max(float(np.degrees(np.arccos(np.clip((np.trace(g19[f].T @ g22[f]) - 1) / 2, -1, 1)))) for f in range(0, min(len(g19), len(g22)), 4))
check(err < 1.0, "decoded MW22 gun rotation = MW19's gun bone on the same clip (%.2f deg)" % err)
saved = prep.MP_GUN
prep.MP_GUN = prep.MP_GUN_FIT
a, gm, pm, nm = built("K:/mw22 anims 2/xanims/sdr_com_exposed_stand_idle01.seanim")
prep.MP_GUN = saved
check(nm[pm][0] == "ValveBiped.Bip01_R_Clavicle", "MPM's MP_GUN still takes precedence (its own fit)")
import gun_holds as g
check(g.src_file("sdr_stl_patrol_stand_scratching03_idle").startswith("K:/mw22 anims 2/xanims"), "gun_holds reads the same MW22 file as the builder (xanims first)")
spot = g.cod_wrist_in_jgun("sdr_com_exposed_stand_idle01")[0]
q = g.cod_wrist_in_jgun("sdr_stl_patrol_stand_radio01_idle")
check(q is not None and max(float(np.linalg.norm(x - spot)) for x in q) < 2.5, "a decoded MW22 radio call keeps the wrist on MW19's grip spot")
q = g.cod_wrist_in_jgun("sdr_stl_patrol_stand_stretching01_idle")
check(q is not None and max(float(np.linalg.norm(x - spot)) for x in q) > 5, "a decoded stretch lets go of the gun")
import tif_mw_build as tb, manifest as man
mm = {k: getattr(man, k) for k in dir(man) if not k.startswith("__")}
def hand_gun(anim):
    smd, _ = prep.seanim_to_smd(anim, body, mp, True, prep.CM_TO_INCH, inplace=True)
    prep.fill_frames(smd)
    ix = {n: i for i, (n, _) in enumerate(smd.nodes)}
    w = c2b.world_pose(smd.nodes, {i: prep.to_rt(v) for i, v in smd.frames[0][1].items()})
    H, G = w[ix["ValveBiped.Bip01_R_Hand"]], w[ix["j_gun"]]
    return np.array(H[0]).T @ np.array(G[0]), np.array(H[0]).T @ (np.array(G[1]) - np.array(H[1]))
src = lambda n: tb.src_path(mm, n)
base = prep.read_seanim(src("sdr_com_strafe_walk_start_8"))
idle = prep.read_seanim(src("sdr_com_exposed_stand_idle01"))
ready = set(prep.read_seanim(src("sdr_com_exposed_stand_ready"))["bones"])
comp = tb.overlay_pose(base, idle, ready, None)
comp["bones"].pop("j_gun_adjust", None)
r1, t1 = hand_gun(comp)
r0, t0 = hand_gun(idle)
ang = float(np.degrees(np.arccos(np.clip((np.trace(r0.T @ r1) - 1) / 2, -1, 1))))
check(not prep.is_chain_gun(comp), "arm-overlay clips (MW22 legs + MW19 arms) bake the overlay's gun, not the MW22 chain")
check(ang < 2 and float(np.linalg.norm(t1 - t0)) < 1.5, "and the gun sits in the hand like the aimed idle (%.2f deg, %.2f u)" % (ang, float(np.linalg.norm(t1 - t0))))
src_t = open(os.path.join(R, "anims", "tif_mw_build.py"), encoding="utf-8").read()
check('anim_override["bones"].pop("j_gun_adjust", None)' in src_t, "the builder drops the base's j_gun_adjust under an overlay gun")
print("passed %d, failed %d" % (ok, fail))
