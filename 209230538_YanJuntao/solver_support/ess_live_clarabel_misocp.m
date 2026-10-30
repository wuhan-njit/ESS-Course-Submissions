function [sol,solver_name,seconds]=ess_live_clarabel_misocp(C,f,u,pch,pdis)
% 保留原 MISOCP；连续松弛的对偶下界与固定整数可行解验证最优性。
tic;scale=1e4;
lower=continuous(C,f/scale);
lb=lower.dual*scale;
modes=double(value(pch)>=value(pdis));
upper=continuous([C,u==modes],f/scale);
ub=value(f);gap=ub-lb;
assert(gap>=-1e-5 && gap<=1e-6*max(1,abs(ub)),...
 '整数解与松弛下界差距未达要求：%.12g',gap);
assert(max(abs(value(u)-modes),[],'all')<=1e-6,'整数约束未满足。');
cert=struct('Method','Conic dual lower bound and binary-feasible upper bound',...
 'RelaxedPrimalObjective',lower.primal*scale,'RelaxedDualBound',lb,...
 'IntegerObjective',ub,'AbsoluteObjectiveGap',gap,...
 'RelativeObjectiveGap',gap/max(1,abs(ub)),'CertifiedWithinTolerance',true,...
 'IntegerModes',modes,'RelaxedPrimalResidual',lower.primal_residual,...
 'RelaxedDualResidual',lower.dual_residual,'FixedPrimalResidual',upper.primal_residual,...
 'FixedDualResidual',upper.dual_residual,'ClarabelVersion',lower.clarabel_version);
sol=struct('problem',0,'info','Solved with conic bound certificate','certificate',cert);
solver_name='Clarabel (bound certificate)';seconds=toc;
fprintf('MISOCP: dual lower %.12f | feasible upper %.12f | gap %.3g Yuan\n',lb,ub,gap);
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
r=load(outfile);assert(strcmp(strtrim(r.status),'Solved'),'未获得最优解。');
x=recovery.x_equ+recovery.H*r.x(:);
assign(recover(recovery.used_variables),x);
% 核验恢复后的目标值与求解器目标值相符。
assert(abs(value(f)-r.primal)<=1e-7*max(1,abs(r.primal)),'目标值恢复失败。');
end
function q=quote(s)
if ispc
    q=['"' strrep(char(s),'"','""') '"'];return
end
q=['''' strrep(char(s),'''','''"''"''') ''''];
end
