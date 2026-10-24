import numpy as np
f=np.float32
V=f(0.1031); V2=f(0.1030); V3=f(0.0973)

def fract(x): return x - np.floor(x)

def hash31(p):
    p = p.astype(f) * np.array([V,V2,V3], f)
    p = fract(p)
    pyzx = p[:, [1,2,0]]
    d = np.sum(p * (pyzx + f(33.33)), axis=1, keepdims=True)
    p = p + d
    return fract((p[:,0] + p[:,1]) * p[:,2])

def vnoise(x):
    i = np.floor(x); fr = x - i
    fr = fr*fr*(f(3.0) - f(2.0)*fr)
    def h(o): return hash31(i + np.array(o, f))
    def mix(a,b,t): return a + (b-a)*t
    x00 = mix(h((0,0,0)), h((1,0,0)), fr[:,0])
    x10 = mix(h((0,1,0)), h((1,1,0)), fr[:,0])
    x01 = mix(h((0,0,1)), h((1,0,1)), fr[:,0])
    x11 = mix(h((0,1,1)), h((1,1,1)), fr[:,0])
    y0 = mix(x00, x10, fr[:,1]); y1 = mix(x01, x11, fr[:,1])
    return mix(y0, y1, fr[:,2])

def fbm6(p):
    a=f(0.5); s=np.zeros(len(p), f); q=p.copy()
    for _ in range(6):
        s = s + a*vnoise(q); q = q*f(2.03); a = a*f(0.5)
    return s

def warp(d):
    w = np.stack([vnoise(d*f(3.1) + np.array([1.7,9.3,5.1],f)),
                  vnoise(d*f(3.1) + np.array([7.9,2.3,8.7],f)),
                  vnoise(d*f(3.1) + np.array([4.1,6.7,3.3],f))], axis=1)
    return d + f(0.20)*(w - f(0.5))

def mask_of(d, use_warp=True):
    q = warp(d) if use_warp else d
    n  = fbm6(q*f(4.0)  + np.array([11.317,4.719,21.933],f))
    n2 = fbm6(q*f(11.0) + np.array([3.107,27.413,8.601],f))
    n3 = fbm6(q*f(27.0) + np.array([19.703,6.311,44.107],f))
    return f(0.58)*n + f(0.28)*n2 + f(0.14)*n3, q

rng=np.random.default_rng(7)
N=400000
d=rng.normal(size=(N,3)).astype(f); d/=np.linalg.norm(d,axis=1,keepdims=True)
m,q = mask_of(d)
print('=== 整球随机采样（N=%d）==='%N)
print('vnoise 均值 = %.4f   fbm6 均值 = %.4f' % (vnoise(d*f(3.0)+f(1.0)).mean(), fbm6(d*f(4.0)).mean()))
print('掩码 m: mean %.4f  std %.4f  p05 %.4f  p50 %.4f  p95 %.4f'%(m.mean(), m.std(), *np.percentile(m,[5,50,95])))
# 校验点：实测 thr 0.515 时整帧 94.1% 陆地
for thr in [0.495,0.515,0.55,0.6,0.65,0.7,0.75]:
    print('   P(m > %.3f) = %.3f' % (thr, (m>thr).mean()))
# 目标 40% 陆地
for target in [0.30,0.40,0.50]:
    print('   => 陆地 %.0f%% 需要 thr = %.4f' % (target*100, np.percentile(m, 100*(1-target))))
print()
print('=== 只取正下方 49.1 度锥内（判据图的画面范围，按立体角均匀）===')
c=1-np.cos(np.radians(49.1))
z=rng.uniform(1-c,1,size=N).astype(f); r=np.sqrt(1-z*z); th=rng.uniform(0,2*np.pi,size=N)
dc=np.stack([r*np.cos(th), z, r*np.sin(th)],axis=1).astype(f)
mc,_=mask_of(dc)
print('锥内掩码: mean %.4f std %.4f'%(mc.mean(), mc.std()))
for thr in [0.515]:
    print('   P(m > %.3f) = %.3f   <-- 与实测整帧 94.1%% 对照'%(thr,(mc>thr).mean()))
