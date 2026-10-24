# -*- coding: utf-8 -*-
"""跨进程联机验证驱动：起两个 Godot 进程（主机 + 客机），跑真 ENet/UDP 回环。

用法：
    python _lan_pair_driver.py            # 跑全部三个场景
    python _lan_pair_driver.py happy      # 只跑一个

只依赖 stdout 里的 `LANRESULT {...}` 那一行（跨进程比对不依赖文件/权限）。
"""
import json
import re
import subprocess
import sys
import time

GODOT = "C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe"
PROJECT = "C:/Users/MSIPC/Documents/gundam"
SCENE = "res://tests/_probe_lan_pair.tscn"

SCENARIOS = [
    ("happy", 27020, "双方准备 → 开局；双方都必须看到对面那一票"),
    ("badpass", 27021, "密码不对 ⇒ 主机踢人 + 客机回到 NONE"),
    ("formswap", 27022, "主机改对战形式 ⇒ 客机必须跟着改（房间设置归主机）"),
]

RESULT_RE = re.compile(r"^LANRESULT (.*)$", re.M)


def run_one(role, scenario, port, budget):
    args = [
        GODOT, "--headless", "--path", PROJECT, SCENE, "--",
        "--role=%s" % role, "--scenario=%s" % scenario, "--port=%d" % port,
        "--budget=%.0f" % budget, "--out=C:/tmp/lan_pair_%s_%s.json" % (scenario, role),
    ]
    p = subprocess.run(args, capture_output=True, text=True, timeout=budget + 60,
                       errors="replace")
    out = (p.stdout or "") + "\n" + (p.stderr or "")
    ms = RESULT_RE.findall(out)
    res = json.loads(ms[-1]) if ms else None
    return res, out


def launch(role, scenario, port, budget, want_host):
    """起一个进程。host 先起；guest 隔 1.5 s。返回 (Popen, 采集函数)。"""
    args = [
        GODOT, "--headless", "--path", PROJECT, SCENE, "--",
        "--role=%s" % role, "--scenario=%s" % scenario, "--port=%d" % port,
        "--budget=%.0f" % budget, "--out=C:/tmp/lan_pair_%s_%s.json" % (scenario, role),
    ]
    p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, errors="replace")
    return p


def collect(p, timeout):
    try:
        out, _ = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        p.kill()
        out, _ = p.communicate()
        out = (out or "") + "\n<<TIMEOUT>>"
    ms = RESULT_RE.findall(out or "")
    res = json.loads(ms[-1]) if ms else None
    return res, (out or "")


def check(scenario, h, g):
    """返回 (通过?, 逐条判据列表)。"""
    rows = []
    if h is None or g is None:
        rows.append((False, "有两个进程没吐出 LANRESULT（h=%s g=%s）" % (h is not None, g is not None)))
        return False, rows

    if scenario == "happy":
        rows.append((not h["fail"] and not g["fail"],
                     "两进程都没卡在等待上（h.fail=%r g.fail=%r）" % (h["fail"], g["fail"])))
        rows.append((h["start_committed"] and g["start_committed"],
                     "双方都提交了开局（h=%s g=%s）" % (h["start_committed"], g["start_committed"])))
        rows.append((h["remote_suit"] == g["own_suit"] and g["remote_suit"] == h["own_suit"],
                     "机体的票互相对上（主机看到客机=%d 客机看到主机=%d）"
                     % (h["remote_suit"], g["remote_suit"])))
        rows.append((h["remote_side"] == g["own_side"] and g["remote_side"] == h["own_side"],
                     "阵营的票互相对上"))
        rows.append((h["remote_form"] == g["own_form"] and g["remote_form"] == h["own_form"],
                     "形式的票互相对上（form=%d）" % h["own_form"]))
        rows.append((h["local_ready"] and h["remote_ready"] and g["local_ready"] and g["remote_ready"],
                     "双方本机与对端都记成「已准备」"))

    elif scenario == "badpass":
        rows.append(("密码不正确" in (h["status"] or ""),
                     "主机侧说出了「密码不正确」（status=%r）" % h["status"]))
        rows.append((g["role_end"] == 0,
                     "被拒的客机回到 NONE（role_end=%d，0=NONE）" % g["role_end"]))
        rows.append((not g["start_committed"],
                     "密码不对时**没有**开局（g.start_committed=%s）" % g["start_committed"]))

    elif scenario == "formswap":
        rows.append((g["own_form"] == h["own_form"],
                     "客机跟上了主机改的形式（host=%d guest=%d）"
                     % (h["own_form"], g["own_form"])))
        # 主机 request_form 那一步必须把**双方**的准备清掉
        cleared = any("local_ready=False remote_ready=False" in s for s in h["steps"])
        rows.append((cleared, "主机改设置那一刻，**双方**准备都被清掉（步骤里读到 local_ready=False remote_ready=False）"))
        rows.append((h["start_committed"] and g["start_committed"],
                     "改完设置、双方重新准备后照样能开局"))
        rows.append((h["remote_suit"] == g["own_suit"] and g["remote_suit"] == h["own_suit"],
                     "改完之后机体的票仍然对得上"))

    return all(ok for ok, _ in rows), rows


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    allok = True
    for scenario, port, desc in SCENARIOS:
        if only and scenario != only:
            continue
        print("=" * 78)
        print("场景 %s · 端口 %d · %s" % (scenario, port, desc))
        print("=" * 78)
        hp = launch("host", scenario, port, 30, True)
        time.sleep(1.5)
        gp = launch("guest", scenario, port, 30, False)
        h, hout = collect(hp, 70)
        g, gout = collect(gp, 70)
        for tag, txt in (("HOST", hout), ("GUEST", gout)):
            for ln in (txt or "").splitlines():
                if ln.startswith("[LAN:") or ln.startswith("LANRESULT") or "ERROR" in ln:
                    print("  %-5s %s" % (tag, ln[:190]))
        ok, rows = check(scenario, h, g)
        print("  ---- 判据 ----")
        for good, label in rows:
            print("  [%s] %s" % ("OK  " if good else "FAIL", label))
        print("  => 场景 %s：%s" % (scenario, "通过" if ok else "**不通过**"))
        allok = allok and ok
        print("")
    print("总判定：%s" % ("全部通过" if allok else "**有场景不通过**"))
    return 0 if allok else 1


if __name__ == "__main__":
    sys.exit(main())
