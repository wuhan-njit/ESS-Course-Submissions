function [sol,solver_name,seconds]=ess_live_clarabel_misocp(C,f,u,pch,pdis,objective_scale)
% 保留原 MISOCP；连续松弛的对偶下界与固定整数可行解验证最优性。
if nargin<6,objective_scale=1e4;end
assert(isscalar(objective_scale) && objective_scale>0);
tic;scale=objective_scale;
lower=continuous(C,f/scale);
lb=lower.dual*scale;
modes=double(value(pch)>=value(pdis));
upper=continuous([C,u==modes],f/scale);
ub=value(f);best=upper;best_modes=modes;
queue={struct('index',[],'mode',[],'bound',lb,'solution',lower)};
closed_bounds=[];nodes=1;tol=1e-8*max(1,abs(ub));
while ~isempty(queue)
 bounds=cellfun(@(node)node.bound,queue);
 [global_lb,pos]=min(bounds);
 if ub-global_lb<=tol,break;end
 node=queue{pos};queue(pos)=[];
 if node.bound>=ub-tol,closed_bounds(end+1)=node.bound;continue;end
 assign(recover(node.solution.variables),node.solution.values);
 simultaneous=min(value(pch),value(pdis));
 [activity,branch]=max(simultaneous(:));
 assert(activity>1e-9,'无法继续整数分支，请检查数值精度。');
 for mode=0:1
  index=[node.index branch];fixed=[node.mode mode];
  child=continuous([C,u(index)==fixed],f/scale);
  nodes=nodes+1;assert(nodes<=500,'分支节点数超限。');
  if strcmp(strtrim(child.status),'PrimalInfeasible'),continue;end
  bound=child.dual*scale;
  if bound>=ub-tol,closed_bounds(end+1)=bound;continue;end
  candidate=double(value(pch)>=value(pdis));candidate(index)=fixed;
  integer=continuous([C,u==candidate],f/scale);
  if ~strcmp(strtrim(integer.status),'PrimalInfeasible') && value(f)<ub
   ub=value(f);best=integer;best_modes=candidate;
  end
  queue{end+1}=struct('index',index,'mode',fixed,'bound',bound,'solution',child);
 end
 fprintf('Conic branch-and-bound: nodes %d, feasible %.12g, lower %.12g\n',nodes,ub,global_lb);
end
bounds=cellfun(@(node)node.bound,queue);
lb=min([ub bounds closed_bounds]);
assign(recover(best.variables),best.values);upper=best;modes=best_modes;gap=ub-lb;
assert(gap>=-1e-5 && gap<=1e-6*max(1,abs(ub)),...
 '整数解与松弛下界差距未达要求：%.12g',gap);
assert(max(abs(value(u)-modes),[],'all')<=1e-6,'整数约束未满足。');
cert=struct('Method','Conic dual lower bound and binary-feasible upper bound',...
 'RelaxedPrimalObjective',lower.primal*scale,'RootRelaxedDualBound',lower.dual*scale,...
 'BranchNodes',nodes,'RelaxedDualBound',lb,...
 'IntegerObjective',ub,'AbsoluteObjectiveGap',gap,...
 'RelativeObjectiveGap',gap/max(1,abs(ub)),'CertifiedWithinTolerance',true,...
 'IntegerModes',modes,'RelaxedPrimalResidual',lower.primal_residual,...
 'RelaxedDualResidual',lower.dual_residual,'FixedPrimalResidual',upper.primal_residual,...
 'FixedDualResidual',upper.dual_residual,'ClarabelVersion',lower.clarabel_version);
sol=struct('problem',0,'info','Solved with conic bound certificate','certificate',cert);
solver_name='Clarabel (bound certificate)';seconds=toc;
fprintf('MISOCP: dual lower %.12f | feasible upper %.12f | objective gap %.3g\n',lb,ub,gap);
end
function r=continuous(C,f)
ops=sdpsettings('solver','coneprog','relax',1,'removeequalities',0,'verbose',0);
[~,recovery,diagnostic,internal]=export(C,f,ops);
assert(isempty(diagnostic)||diagnostic.problem==0,'模型导出失败。');
assert(~any(internal.Q(:)),'只支持本任务的线性目标。');
F=internal.F_struc;c=internal.c;lb=internal.lb;ub=internal.ub;
kf=internal.K.f;kl=internal.K.l;kq=internal.K.q;
folder=tempname;mkdir(folder);clean=onCleanup(@()rmdir(folder,'s'));
infile=fullfile(folder,'model.mat');outfile=fullfile(folder,'solution.mat');
save(infile,'F','c','lb','ub','kf','kl','kq','-v7');
python=getenv('ESS_PYTHON');
if isempty(python)
    if ispc,python='python';else,python='python3';end
end
script=fullfile(fileparts(mfilename('fullpath')),'ess_clarabel_conic.py');
cmd=strjoin({quote(python),quote(script),quote(infile),quote(outfile)},' ');
[status,message]=system(cmd);assert(status==0,'Clarabel 调用失败：%s',message);
r=load(outfile);
if strcmp(strtrim(r.status),'PrimalInfeasible'),return;end
assert(strcmp(strtrim(r.status),'Solved'),'未获得最优解。');
x=recovery.x_equ+recovery.H*r.x(:);
r.variables=recovery.used_variables;r.values=x;
assign(recover(recovery.used_variables),x);
base=getbase(f);objective_constant=full(base(1));
r.primal=r.primal+objective_constant;r.dual=r.dual+objective_constant;
% 核验恢复后的目标值与求解器目标值相符。
assert(abs(value(f)-r.primal)<=1e-7*max(1,abs(r.primal)),'目标值恢复失败。');
end
function q=quote(s)
if ispc
    q=['"' strrep(char(s),'"','""') '"'];return
end
q=['''' strrep(char(s),'''','''"''"''') ''''];
end
