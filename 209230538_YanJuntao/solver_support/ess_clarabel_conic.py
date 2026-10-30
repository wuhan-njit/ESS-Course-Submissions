"""Solve an exported YALMIP continuous conic problem; no model data are changed."""
import os,sys
if os.environ.get('ESS_PYTHONPATH'):sys.path.insert(0,os.environ['ESS_PYTHONPATH'])
import numpy as np
from scipy import sparse as sp
from scipy.io import loadmat,savemat
import clarabel
m=loadmat(sys.argv[1],squeeze_me=True)
vec=lambda x:np.asarray(x.toarray() if sp.issparse(x) else x,dtype=float).ravel()
c=vec(m['c']);F=sp.csc_matrix(m['F']);A=-F[:,1:];b=vec(F[:,0]);n=len(c)
kf=int(m['kf']);kl=int(m['kl']);kq=np.atleast_1d(m['kq']).astype(int).ravel()
cones=[]
if kf:cones.append(clarabel.ZeroConeT(kf))
if kl:cones.append(clarabel.NonnegativeConeT(kl))
for k in kq:
 if k:cones.append(clarabel.SecondOrderConeT(int(k)))
assert sum([kf,kl,*kq])==A.shape[0]
lb=vec(m['lb']);ub=vec(m['ub']);lo=np.flatnonzero(np.isfinite(lb));hi=np.flatnonzero(np.isfinite(ub));eye=sp.eye(n,format='csc')
if len(lo)+len(hi):
 A=sp.vstack([A,-eye[lo],eye[hi]],format='csc');b=np.r_[b,-lb[lo],ub[hi]]
 cones.append(clarabel.NonnegativeConeT(len(lo)+len(hi)))
s=clarabel.DefaultSettings();s.verbose=False;s.max_iter=300
s.tol_gap_abs=1e-11;s.tol_gap_rel=1e-11;s.tol_feas=1e-11
r=clarabel.DefaultSolver(sp.csc_matrix((n,n)),c,A,b,cones,s).solve()
savemat(sys.argv[2],{'x':np.asarray(r.x),'primal':r.obj_val,'dual':r.obj_val_dual,
 'status':str(r.status),'primal_residual':r.r_prim,'dual_residual':r.r_dual,'solve_seconds':r.solve_time,
 'clarabel_version':clarabel.__version__})
assert str(r.status) in ('Solved','PrimalInfeasible'),f'Clarabel status {r.status}'
