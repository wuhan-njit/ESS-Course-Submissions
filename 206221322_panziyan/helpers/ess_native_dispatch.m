function [D,solver_name,seconds,obj_value] = ess_native_dispatch(mpc,P,letter)

clock=tic; yalmip('clear');

nb=P.N_bus; nl=P.N_br; nt=P.T; ne=P.N_ess; sb=P.Sbase;
r=P.r_br/sb; x=P.x_br/sb;
V.U=sdpvar(nb,nt,'full'); V.L=sdpvar(nl,nt,'full');
V.P=sdpvar(nl,nt,'full'); V.Q=sdpvar(nl,nt,'full');
V.pg=sdpvar(1,nt,'full'); V.qg=sdpvar(1,nt,'full');
V.ch=sdpvar(ne,nt,'full'); V.dis=sdpvar(ne,nt,'full');
V.soc=sdpvar(ne,nt,'full'); V.pv=sdpvar(P.N_pv,nt,'full');
V.u=sdpvar(ne,nt,'full'); V.z=sdpvar(1);
af=sparse(P.fbus,1:nl,1,nb,nl); at=sparse(P.tbus,1:nl,1,nb,nl);
ae=sparse(P.ess_buses,1:ne,1,nb,ne); ap=sparse(P.pv_buses,1:P.N_pv,1,nb,P.N_pv);
a0=sparse(1,1,1,nb,1);
C=[0<=V.u<=1, 0<=V.ch<=sb*P.P_ess_rated_pu*V.u,...
   0<=V.dis<=sb*P.P_ess_rated_pu*(1-V.u),...
   P.SoC_min<=V.soc<=P.SoC_max,V.soc(:,end)==P.SoC_0,...
   0<=V.pv<=sb*P.P_pv_max_pu, V.L>=0,...
   P.V_min^2<=V.U<=P.V_max^2,V.U(1,:)==1];
prior=[repmat(P.SoC_0,ne,1),V.soc(:,1:end-1)];
C=[C,V.soc==prior+(P.eta_ch*V.ch-V.dis/P.eta_dis)*P.dt/(sb*P.E_ess_rated_pu)];
C=[C,at*(V.P-diag(r)*V.L)-af*V.P+a0*V.pg+ap*V.pv+ae*(V.dis-V.ch)==sb*P.Pd_pu];
C=[C,at*(V.Q-diag(x)*V.L)-af*V.Q+a0*V.qg==sb*P.Qd_pu];
C=[C,V.U(P.tbus,:)==V.U(P.fbus,:)-2*(diag(r)*V.P+diag(x)*V.Q)+diag(r.^2+x.^2)*V.L];
for t=1:nt
 for b=1:nl
  C=[C,cone([2*V.P(b,t);2*V.Q(b,t);V.L(b,t)-V.U(P.fbus(b),t)],V.L(b,t)+V.U(P.fbus(b),t))]; %#ok<AGROW>
 end
end
loss=sum(diag(r)*V.L,'all')*P.dt; curt=sum(sb*P.P_pv_max_pu-V.pv,'all')*P.dt;
cost=sum(P.price_MWh(:).*V.pg(:))*P.dt;
factor=1;
switch letter
 case 'A', expression=curt+0.01*loss;
 case 'B', expression=loss+1e-4/sb*sum(V.ch+V.dis,'all');
 otherwise, expression=cost/1000;factor=1000;
end
C=[C,V.z==expression];
ops=sdpsettings('solver','coneprog','verbose',0,'removeequalities',0,'cachesolvers',1);
[~,recovery,diagnostic,interface]=export(C,V.z,ops);
m=yalmip2coneprog(interface);
assert(isempty(diagnostic)||diagnostic.problem==0,'二阶锥模型转换失败。');
uid=find(ismember(recovery.used_variables,getvariables(V.u)));
assert(numel(uid)==ne*nt,'整数变量映射不完整。');
m.ops=optimoptions('coneprog','Display','off','ConstraintTolerance',1e-9,'OptimalityTolerance',1e-9,'MaxIterations',150);
[root,lb,flag,out]=coneprog(m.f,m.socConstraints,m.A,m.b,m.Aeq,m.beq,m.lb,m.ub,m.ops);
if flag<=0
 m.ops.ConstraintTolerance=1e-8;m.ops.OptimalityTolerance=1e-8;
 [root,lb,flag,out]=coneprog(m.f,m.socConstraints,m.A,m.b,m.Aeq,m.beq,m.lb,m.ub,m.ops);
end
if flag<=0
 m.ops.ConstraintTolerance=1e-7;m.ops.OptimalityTolerance=1e-7;
 [root,lb,flag,out]=coneprog(m.f,m.socConstraints,m.A,m.b,m.Aeq,m.beq,m.lb,m.ub,m.ops);
end

assert(flag>0,'连续松弛求解失败：%s',out.message);
assign(recover(recovery.used_variables),root);

upper=Inf; best=[]; rounds=0; cone_solves=1;
mode=double(value(V.ch)>=value(V.dis));
[fixed,ub,ok]=fixed_solve(mode);
if ok,upper=ub;best=fixed;end

gap_tol=max(1e-7,1e-6*max(abs(upper),1e-3));
if isempty(best)||upper-lb>gap_tol
 [cuts,rhs]=cone_cuts(root,true);
 masterA=[m.A;cuts]; masterb=[m.b;rhs];
 intops=optimoptions('intlinprog','Display','off','RelativeGapTolerance',0,...
     'AbsoluteGapTolerance',1e-8,'ConstraintTolerance',1e-8,'MaxTime',90);
 for iteration=1:100
  rounds=iteration;
  [trial,~,ef,io]=intlinprog(m.f,uid,masterA,masterb,m.Aeq,m.beq,m.lb,m.ub,intops);
  assert(~isempty(trial)&&ef>0,'整数外逼近失败：%s',io.message);
  if isfield(io,'lowerbound'), lb=max(lb,io.lowerbound);else,lb=max(lb,m.f'*trial-io.absolutegap);end
  [newcuts,newrhs,violation]=cone_cuts(trial,false);
  
  assign(recover(recovery.used_variables),trial);
  trialmode=round(value(V.u));
  [candidate,ub,ok]=fixed_solve(trialmode);
  if ok&&ub<upper,upper=ub;best=candidate;end
  if upper-lb<=max(1e-7,1e-6*max(abs(upper),1e-3)),break;end
  masterA=[masterA;newcuts];masterb=[masterb;newrhs]; %#ok<AGROW>
  if ok
   [tangent,tanrhs]=cone_cuts(candidate,true);
   masterA=[masterA;tangent];masterb=[masterb;tanrhs]; %#ok<AGROW>
  end
 end
end
assert(~isempty(best),'未获得满足充放电互斥的可行解。');
assert(upper-lb<=max(1e-7,1e-6*max(abs(upper),1e-3)),...
    '整数优化尚未收敛：下界%.12g，上界%.12g。',lb*factor,upper*factor);
assign(recover(recovery.used_variables),best);
D=struct('P_ch',value(V.ch)/sb,'P_dis',value(V.dis)/sb,'SoC',value(V.soc),...
 'P_pv',value(V.pv)/sb,'u_ch',round(value(V.u)),'P_grid',value(V.pg)/sb,...
 'Q_grid',value(V.qg)/sb,'U_bus',value(V.U),'L_br',value(V.L)/sb^2,...
 'P_br',value(V.P)/sb,'Q_br',value(V.Q)/sb,'LowerBound',lb*factor,...
 'UpperBound',upper*factor,'RelativeGap',max(0,upper-lb)/max(abs(upper),1e-12),...
 'OuterIterations',rounds,'ConeSolves',cone_solves);
solver_name='MATLAB coneprog + intlinprog';seconds=toc(clock);obj_value=upper*factor;



 function [z,fval,ok]=fixed_solve(mode_matrix)
  n=numel(m.f); fullstate=zeros(n,1);
  modesdp=getvariables(V.u(:));
  fixedidx=zeros(numel(modesdp),1);
  for k=1:numel(modesdp)
   pos=find(recovery.used_variables==modesdp(k));
   fixedidx(k)=pos;fullstate(pos)=mode_matrix(k);
  end
  free=setdiff((1:n)',fixedidx);
  shiftedA=m.A(:,free);shiftedb=m.b-m.A*fullstate;
  shiftedE=m.Aeq(:,free);shiftedbe=m.beq-m.Aeq*fullstate;
  cones=m.socConstraints;
  for k=1:numel(cones)
   sc=m.socConstraints(k);
   cones(k)=secondordercone(sc.A(:,free),sc.b(:)-sc.A*fullstate,...
       sc.d(free),sc.gamma-sc.d(:)'*fullstate);
  end
  opt=m.ops;opt.MaxIterations=500;
  [reduced,fval,ef,detail]=coneprog(m.f(free),cones,shiftedA,shiftedb,shiftedE,shiftedbe,...
      m.lb(free),m.ub(free),opt);
  cone_solves=cone_solves+1;
  if ef<=0
   opt.ConstraintTolerance=1e-8;opt.OptimalityTolerance=1e-8;
   [reduced,fval,ef,detail]=coneprog(m.f(free),cones,shiftedA,shiftedb,shiftedE,shiftedbe,...
       m.lb(free),m.ub(free),opt);cone_solves=cone_solves+1;
  end
  
  ok=ef>0;
  if ok
   z=fullstate;z(free)=reduced;fval=fval+m.f'*fullstate;
  else
   z=[];fval=Inf;
  end
 end

 function [A,b,max_violation]=cone_cuts(z,all_cones)
  rows=cell(numel(m.socConstraints),1); vals=zeros(numel(rows),1); count=0;max_violation=0;
  for j=1:numel(m.socConstraints)
   s=m.socConstraints(j); v=s.A*z-s.b(:);nv=norm(v); violation=nv-(s.d(:)'*z-s.gamma);
   max_violation=max(max_violation,violation);
   if all_cones||violation>1e-8
    if nv<1e-12,continue;end
    n=v/nv;count=count+1;rows{count}=n'*s.A-s.d(:)';vals(count)=n'*s.b(:)-s.gamma;
   end
  end
  if count,A=vertcat(rows{1:count});b=vals(1:count);else,A=sparse(0,numel(z));b=zeros(0,1);end
 end
end
