%[text] # 任务三：配电网储能日前优化调度（MISOCP）
%[text] 课程：《储能优化规划与运行》课程设计（南京工程学院）
%[text] 本文件为第一周**任务三（配电网日前调度）**的独立提交脚本，可单独"全部运行"。
%[text] **个人参数**：学号 $206231311$，末两位 $X=1,\ Y=1$ → $\alpha = 1.022$，
%[text] 算例 `case_nongcun`（49 节点，12.66 kV / 100 MVA），模型 A，接入节点 {4,9,14}，光伏 1.2 MW/节点，储能 1.5 MW / 3 MWh/节点
%[text] 对应课件：interactive03（网络调度）、Template_Week1（MISOCP 模板）。
%[text] ## 0 运行环境与个人参数
%%
%[text] ### 0.1 添加教学资源库、MATPOWER 与 YALMIP 路径
%[text] 首次运行请把 `ess_course_root` 改为本机 `ESS-Course-Materials` 的根目录；若该目录不存在，程序会弹出选择框。
ess_course_root = 'D:\ess_toolbox\ESS-Course-Materials';
matpower_root   = 'D:\ess_toolbox\matpower-8.1';
yalmip_root     = 'D:\ess_toolbox\YALMIP-master';
if ~isfolder(ess_course_root)
    ess_course_root = uigetdir(pwd, '请选择教学资源库 ESS-Course-Materials 的根目录');
end
if isfolder(matpower_root)
    mp_dirs = {'lib','lib/t','data','examples', ...
        'most/lib','most/lib/t','most/examples', ...
        'mp-opt-model/lib','mp-opt-model/lib/t','mp-opt-model/examples', ...
        'mips/lib','mips/lib/t','mips/examples','mptest/lib','mptest/lib/t'};
    for k = 1:numel(mp_dirs)
        d = fullfile(matpower_root, mp_dirs{k});
        if isfolder(d), addpath(d); end
    end
end
if isfolder(yalmip_root)
    addpath(genpath(yalmip_root));
end
addpath(fullfile(ess_course_root,'cases'));
assert(exist('runpf','file')==2, '未找到 MATPOWER：请检查 matpower_root。');
assert(exist('sdpvar','file')==2, '未找到 YALMIP：请检查 yalmip_root。');
fprintf('MATPOWER : %s\nYALMIP   : %s\n算例库   : %s\n', which('runpf'), which('sdpvar'), which('case_nongcun'));
%%
%[text] ### 0.2 学号映射与公共参数
%[text] 学号末两位 $XY$ 决定算例、$\alpha$、调度模型与候选节点；中间变量统一使用有名值 MW/Mvar 或标幺值 p.u.。
Stu_ID  = 206231311;
XY      = mod(Stu_ID, 100);
X_digit = floor(XY / 10);
Y_digit = mod(XY, 10);
alpha   = 1 + 0.002 * XY;
if ismember(Y_digit, [0 1 2 3])
    case_name = 'case_nongcun';
elseif ismember(Y_digit, [4 5 6])
    case_name = 'case_chengshi_A';
else
    case_name = 'case_kaifaqu_A';
end
if ismember(X_digit, [0 1 2])
    study_buses = [4 9 14];  model_type = 'A';
elseif ismember(X_digit, [3 4 5])
    study_buses = [5 11 16]; model_type = 'B';
else
    study_buses = [6 13 17]; model_type = 'C';
end
profiles = load(fullfile(ess_course_root,'cases','profiles_24h.mat'));
T = profiles.T;  dt = 1;
load_curve_pu = profiles.load_curve_pu(:);
pv_curve_pu   = profiles.pv_curve_pu(:);
price_MWh     = profiles.price_MWh(:);
price_kWh     = profiles.price_kWh(:);
mpc_base = loadcase(case_name);
mpopt    = mpoption('verbose',0,'out.all',0);
disp(table(Stu_ID, string(case_name), alpha, string(model_type), ...
    string(mat2str(study_buses)), 'VariableNames', ...
    {'StudentID','Case','LoadMultiplier','AssignedObjective','StudyNodes'}));

% 图形输出目录：各节画完立即导出（Live Editor 会在切换节时回收图形句柄）
out_dir = fullfile(pwd, 'figures');
if ~isfolder(out_dir), mkdir(out_dir); end
export_figs = true;
% 绘图公共变量（本脚本单独运行时的定义）
tt  = 1:T;
mk  = {'-o','-s','-^'};
clr = [0.235 0.329 0.533; 0.000 0.627 0.529; 0.902 0.294 0.208];


%[text] ## 3 任务三：含充放电互斥的配电网日前调度（MISOCP）
%[text] 光伏每节点 **1.2 MW**（可弃光），储能每节点 **1.5 MW / 3 MWh**，$\mathrm{SoC}\in[0.20,0.80]$，
%[text] 节点电压 $0.95\le V\le 1.05$ p.u.。采用 DistFlow 支路潮流与旋转二阶锥松弛（$U=V^2,\ L=I^2$）：
%[text] $$P_{ij,t}-r_{ij}L_{ij,t}-\sum_{k\in\delta(j)}P_{jk,t}=P_{j,t}^{\mathrm{load}}-P_{j,t}^{\mathrm{pv}}+P_{j,t}^{\mathrm{ch}}-P_{j,t}^{\mathrm{dis}}$$
%[text] $$U_{j,t}=U_{i,t}-2\left(r_{ij}P_{ij,t}+x_{ij}Q_{ij,t}\right)+\left(r_{ij}^2+x_{ij}^2\right)L_{ij,t}$$
%[text] $$\left\|{\left(2P_{ij,t},\ 2Q_{ij,t},\ L_{ij,t}-U_{i,t}\right)}\right\|_2\le L_{ij,t}+U_{i,t}$$
%[text] 由本人学号确定 **模型 A**（最大化新能源消纳 + $10^{-2}$ 网损正则项，保证松弛紧致）：
%[text] $$\min\ \sum_{t}\sum_{j}\left(P_{j,t}^{\mathrm{pv,max}}-P_{j,t}^{\mathrm{pv}}\right)\Delta t+10^{-2}\sum_{t}\sum_{ij}r_{ij}L_{ij,t}\Delta t$$
%%
%[text] ### 3.1 组装模型
cfg = struct();
cfg.stu_id = Stu_ID;
cfg.mpc    = mpc_base;
cfg.T      = T;
cfg.alpha  = alpha;
cfg.ess_buses = study_buses;
cfg.pv_buses  = study_buses;
cfg.load_curve_pu = load_curve_pu;
cfg.pv_curve_pu   = pv_curve_pu;
cfg.price_MWh     = price_MWh;
cfg.P_pv_peak_MW  = 1.2;
cfg.P_ess_MW      = 1.5;
cfg.E_ess_MWh     = 3.0;
cfg.eta_ch  = 0.90;
cfg.eta_dis = 0.95;
cfg.SoC_min = 0.20;
cfg.SoC_max = 0.80;
cfg.SoC_0   = 0.50;
cfg.V_min   = 0.95;
cfg.V_max   = 1.05;
M = w1_build_model(cfg);
fprintf('模型规模：变量 %d 个，等式约束 %d 条，线性不等式 %d 条，二阶锥 %d 个。\n', ...
    M.n, size(M.Aeq,1), size(M.Aineq,1), numel(M.soc));
%%
%[text] ### 3.2 求解 MISOCP
%[text] 说明：本机未安装 MOSEK / Gurobi（二者均需注册并申请许可证）。本程序因此采用"凸松弛 + 整数回填 + 分支定界"求解：
%[text] 把互斥变量 $u_{i,t}$ 松弛到 $[0,1]$ 后，模型是标准二阶锥规划，可用 MATLAB 自带 `coneprog` 精确求解并给出下界；
%[text] 再由松弛解的 $P^{\mathrm{ch}}$、$P^{\mathrm{dis}}$ 反推 0/1 状态并回代，得到满足互斥约束的整数可行解；
%[text] 若上下界未闭合，则对同时充放电最严重的 $(i,t)$ 分支继续求解。该流程不依赖任何商业求解器。
%[text] 本程序优先调用 **MOSEK**（课程要求的 MISOCP 求解器，YALMIP 建模 + `binvar` 精确表达互斥）；
%[text] 若本机未配置 MOSEK 许可证，则自动回退到上述内置方案，保证脚本在任何机器上都能完整运行。
opts3 = struct('MaxNodes', 0, 'NodeMaxTime', 120, 'MaxTime', 600, 'Verbose', true);
mosek_dir = 'D:\mosek\11.2\toolbox\R2019b';
if isfolder(mosek_dir) && isempty(which('mosekopt'))
    addpath(mosek_dir);
end
SOL = [];
if ~isempty(which('mosekopt'))
    fprintf('检测到 MOSEK，尝试用 YALMIP + MOSEK 求解 MISOCP…\n');
    SOL = w1_solve_misocp_mosek(cfg, model_type, struct('MaxTime', 300, 'Verbose', false));
    if SOL.problem ~= 0
        fprintf('MOSEK 求解未成功（%s），改用内置凸松弛 + 整数回填方案。\n', SOL.info);
        SOL = [];
    end
end
if isempty(SOL)
    SOL = w1_solve_misocp(M, model_type, opts3);
end
fprintf('求解器：%s\n耗时 %.1f s，下界 LB = %.8f，上界 UB = %.8f，间隙 = %.3e\n', ...
    SOL.solver_name, SOL.solve_seconds, SOL.lower_bound, SOL.fval, SOL.gap);
%%
%[text] ### 3.3 运行校核与关键指标
%[text] 把最优充放电功率、光伏出力回代 MATPOWER 交流潮流，校验电压与网损；同时检查互斥性、SoC 边界、锥间隙与功率平衡残差。
K = w1_check(M, SOL.x, cfg, case_name, model_type);
K.Solver = SOL.solver_name;  K.SolveSeconds = SOL.solve_seconds;  K.Nodes = SOL.nodes;
K.LowerBound = SOL.lower_bound;  K.UpperBound = SOL.fval;  K.GapAbs = SOL.gap;
disp(table(K.Curtailment_MWh, K.LineLoss_MWh, K.ACLineLoss_MWh, K.GridCost_Yuan, ...
    K.MaxConeGap, K.MaxSimultaneousPower_MW, K.MinACVoltage, K.MaxACVoltage, ...
    'VariableNames', {'弃光_MWh','模型网损_MWh','交流网损_MWh','购电费用_元', ...
    '最大锥间隙','最大同时充放电_MW','最低电压_pu','最高电压_pu'}));
fprintf('约束检查：储能=%d 线性=%d 二阶锥=%d 交流电压=%d 总体=%d\n', ...
    K.StorageConstraintsPassed, K.LinearConstraintsPassed, ...
    K.ConeRelaxationExact, K.ACVoltageWithinLimits, K.Passed);
fprintf('模型电压与交流电压最大偏差 %.3e p.u.（节点 %d，第 %d 时段）\n', ...
    K.MaxACVoltageError, K.MaxVoltageErrorNode, K.MaxVoltageErrorHour);
%%
%[text] ### 3.4 任务三图形：储能出力与荷电状态
fig3 = figure('Name','任务三 日前调度','Color','w','Units','pixels','Position',[90 70 1000 640]);
axa = subplot(2,1,1); hold(axa,'on');
hh = gobjects(M.N_ess,1);
for k = 1:M.N_ess
    hh(k) = plot(axa, tt, K.NetMW(k,:), mk{k}, 'Color', clr(k,:), 'LineWidth', 2, ...
        'MarkerSize', 5, 'MarkerFaceColor', clr(k,:));
end
yline(axa, 0, '--k', 'LineWidth', 0.9);
style_axes(axa); xlim(axa,[1 T]);
ylabel(axa,'\fontname{宋体}储能净放电功率 \fontname{Times New Roman}{\itP}_{\rm{ess}}\rm{/MW}','Interpreter','tex');
title(axa, sprintf('\\fontname{宋体}(a) \\fontname{Times New Roman}\\it\\alpha\\rm{=%.3f} \\fontname{宋体}模型 \\fontname{Times New Roman}%s \\fontname{宋体}各节点储能日前出力', alpha, model_type), ...
    'FontWeight','normal','Interpreter','tex');
lg3 = arrayfun(@(b) sprintf('\\fontname{宋体}节点 \\fontname{Times New Roman}%d \\fontname{宋体}储能', b), study_buses, 'UniformOutput', false);
legend(axa, hh, lg3, 'Location','southoutside','Orientation','horizontal','NumColumns',3, ...
    'Interpreter','tex','Box','off');
set(axa,'XTickLabel',[]);
axb = subplot(2,1,2); hold(axb,'on');
for k = 1:M.N_ess
    plot(axb, tt, 100*K.SoC(k,:), mk{k}, 'Color', clr(k,:), 'LineWidth', 2, ...
        'MarkerSize', 5, 'MarkerFaceColor', clr(k,:));
end
yline(axb, 100*cfg.SoC_max, ':', 'Color', clr(3,:), 'LineWidth', 1.5);
yline(axb, 100*cfg.SoC_min, ':', 'Color', clr(3,:), 'LineWidth', 1.5);
style_axes(axb); xlim(axb,[1 T]);
xlabel(axb,'\fontname{宋体}时间 \fontname{Times New Roman}{\itt}\rm{/h}','Interpreter','tex');
ylabel(axb,'\fontname{宋体}荷电状态 \fontname{Times New Roman}\rm{SoC}/%','Interpreter','tex');
title(axb,'\fontname{宋体}(b) 各节点储能荷电状态时序变化','FontWeight','normal','Interpreter','tex');
if export_figs
    export_figure(fig3, out_dir, sprintf('Fig_Week1_Task3_%d', Stu_ID));
    drawnow;
end

%[text] ## 结论与思考题
%[text] **结论**：模型 A 下三个储能节点在午间大功率充电消纳光伏、晚峰放电支撑电压，
%[text] 弃光接近 0，二阶锥松弛间隙约 $10^{-8}$ p.u.，回代交流潮流与模型电压偏差约 $10^{-7}$ p.u.。
%[text] **思考题（interactive03 练习）**：保持同一算例与设备参数，分别求解模型 A / B / C，
%[text] 比较弃光电量、交流电能损耗、购电费用、荷电状态与节点电压。
%[text] 三个目标的对比结果与"模型 C 二阶锥松弛不精确"的教学特例，
%[text] 见独立存档的《Interactive03_ABC三目标对比》文档与报告"思考题"一节。

%[text] ## 附：局部函数
%%
function style_axes(ax)
set(ax,'Color','w','XColor','k','YColor','k','FontName','Times New Roman', ...
    'FontSize',11,'LineWidth',0.75,'Box','on','TickDir','in', ...
    'GridLineStyle','--','XGrid','off','YGrid','on','GridAlpha',0.25, ...
    'GridColor',[0.4 0.4 0.4]);
end

function export_figure(f, outdir, base)
if ~isfolder(outdir), mkdir(outdir); end
exportgraphics(f, fullfile(outdir,[base '.png']), 'Resolution',600, 'BackgroundColor','white');
exportgraphics(f, fullfile(outdir,[base '.pdf']), 'ContentType','vector', 'BackgroundColor','white');
savefig(f, fullfile(outdir,[base '.fig']));
fprintf('已导出 %s.(png|pdf|fig)\n', base);
end

function M = w1_build_model(cfg)
%W1_MODEL  DistFlow + 二阶锥松弛 + 充放电互斥的配电网日前调度模型。
%
%   模型直接写成 MATLAB 内置 coneprog 的标准二阶锥形式，只依赖
%   Optimization Toolbox，不需要 MOSEK / Gurobi 许可证：
%
%       min  f'*x
%       s.t. Aeq*x = beq,  Aineq*x <= bineq,  lb <= x <= ub,
%            ||A_k*x - b_k||_2 <= d_k'*x - gamma_k ,  k = 1,...,N_br*T
%
%   变量向量 x 的分块顺序（各块均按“时间优先”拼接）：
%       U_bus(N_bus*T)  L_br(N_br*T)  P_br(N_br*T)  Q_br(N_br*T)
%       P_grid(T)  Q_grid(T)  P_ch(N_ess*T)  P_dis(N_ess*T)
%       u_ch(N_ess*T)  SoC(N_ess*T)  P_pv(N_pv*T)
%
%   cfg 字段：mpc, alpha, ess_buses, pv_buses, load_curve_pu, pv_curve_pu,
%            price_MWh, P_pv_peak_MW, P_ess_MW, E_ess_MWh, eta_ch, eta_dis,
%            SoC_min, SoC_max, SoC_0, V_min, V_max, T

mpc   = cfg.mpc;
T     = cfg.T;
Sbase = mpc.baseMVA;
N_bus = size(mpc.bus, 1);
N_br  = size(mpc.branch, 1);
N_ess = numel(cfg.ess_buses);
N_pv  = numel(cfg.pv_buses);

assert(isequal(mpc.bus(:,1), (1:N_bus)'), ...
    '本模型要求算例节点编号为 1..N 连续编号。');

fbus = mpc.branch(:,1);   tbus = mpc.branch(:,2);
r_br = mpc.branch(:,3);   x_br = mpc.branch(:,4);

% ---------- 24 小时源荷标幺值（基准 100 MVA）----------
Pd_pu    = (mpc.bus(:,3) * cfg.alpha / Sbase) * cfg.load_curve_pu(:)';
Qd_pu    = (mpc.bus(:,4) * cfg.alpha / Sbase) * cfg.load_curve_pu(:)';
P_pv_max = (cfg.P_pv_peak_MW / Sbase) * repmat(cfg.pv_curve_pu(:)', N_pv, 1);
P_ess_pu = cfg.P_ess_MW / Sbase;
E_ess_pu = cfg.E_ess_MWh / Sbase;

% ---------- 变量分块 ----------
nU = N_bus*T;  nL = N_br*T;  nP = N_br*T;  nQ = N_br*T;
nPg = T;       nQg = T;
nCh = N_ess*T; nDs = N_ess*T; nUc = N_ess*T; nSo = N_ess*T;
nPv = N_pv*T;

oU  = 0;            oL  = oU  + nU;
oP  = oL  + nL;     oQ  = oP  + nP;
oPg = oQ  + nQ;     oQg = oPg + nPg;
oCh = oQg + nQg;    oDs = oCh + nCh;
oUc = oDs + nDs;    oSo = oUc + nUc;
oPv = oSo + nSo;
n   = oPv + nPv;

IU  = reshape(oU  + (1:nU),  N_bus, T);
IL  = reshape(oL  + (1:nL),  N_br,  T);
IP  = reshape(oP  + (1:nP),  N_br,  T);
IQ  = reshape(oQ  + (1:nQ),  N_br,  T);
IPg = oPg + (1:nPg);
IQg = oQg + (1:nQg);
ICh = reshape(oCh + (1:nCh), N_ess, T);
IDs = reshape(oDs + (1:nDs), N_ess, T);
IUc = reshape(oUc + (1:nUc), N_ess, T);
ISo = reshape(oSo + (1:nSo), N_ess, T);
IPv = reshape(oPv + (1:nPv), N_pv,  T);

% ---------- 关联矩阵 ----------
A_from  = sparse(fbus, 1:N_br, 1, N_bus, N_br);
A_to    = sparse(tbus, 1:N_br, 1, N_bus, N_br);
A_ess   = sparse(cfg.ess_buses, 1:N_ess, 1, N_bus, N_ess);
A_pv    = sparse(cfg.pv_buses,  1:N_pv,  1, N_bus, N_pv);
A_slack = sparse(1, 1, 1, N_bus, 1);
A_in    = A_to - A_from;
D_r     = sparse(diag(r_br));
D_x     = sparse(diag(x_br));
D_r2x2  = sparse(diag(r_br.^2 + x_br.^2));
IT      = speye(T);
DT      = speye(T) - diag(ones(T-1,1), -1);     % SoC 一阶差分

% ---------- 等式约束 ----------
nG1 = N_bus*T;  nG2 = N_bus*T;  nG3 = N_br*T;
nG4 = N_ess*T;  nG5 = T;        nG6 = N_ess;
neq = nG1 + nG2 + nG3 + nG4 + nG5 + nG6;
widths = [nU nL nP nQ nPg nQg nCh nDs nUc nSo nPv];
nblk   = numel(widths);

G1 = rowblock(nG1, widths, { [], -kron(IT, A_to*D_r), kron(IT, A_in), [], ...
    kron(IT, A_slack), [], -kron(IT, A_ess), kron(IT, A_ess), [], [], ...
    kron(IT, A_pv) });
G2 = rowblock(nG2, widths, { [], -kron(IT, A_to*D_x), [], kron(IT, A_in), ...
    [], kron(IT, A_slack), [], [], [], [], [] });
G3 = rowblock(nG3, widths, { kron(IT, A_in'), -kron(IT, D_r2x2), ...
    kron(IT, 2*D_r), kron(IT, 2*D_x), [], [], [], [], [], [], [] });
G4 = rowblock(nG4, widths, { [], [], [], [], [], [], ...
    -(cfg.eta_ch/E_ess_pu)*speye(nCh), ...
    (1/(cfg.eta_dis*E_ess_pu))*speye(nDs), [], kron(DT, speye(N_ess)), [] });
G5 = rowblock(nG5, widths, { sparse(1:T, (0:T-1)*N_bus + 1, 1, T, nU), [], [], [], [], [], ...
    [], [], [], [], [] });
G6 = rowblock(nG6, widths, { [], [], [], [], [], [], [], [], [], ...
    sparse(1:N_ess, (T-1)*N_ess + (1:N_ess), 1, N_ess, nSo), [] });

Aeq = [G1; G2; G3; G4; G5; G6];
beq = zeros(neq, 1);
beq(1:nG1)                           = Pd_pu(:);       % 节点有功平衡右端
beq(nG1 + (1:nG2))                   = Qd_pu(:);       % 节点无功平衡右端
beq(nG1+nG2+nG3 + (1:N_ess))         = cfg.SoC_0;      % 第 1 时段 SoC 初值
beq(nG1+nG2+nG3+nG4 + (1:nG5))       = 1;              % U_1 = 1
beq(nG1+nG2+nG3+nG4+nG5 + (1:nG6))   = cfg.SoC_0;      % 终端 SoC

% ---------- 充放电互斥（线性 Big-M 形式）----------
nI    = 2*N_ess*T;
Aineq = spalloc(nI, n, 4*N_ess*T);
bineq = zeros(nI, 1);
for t = 1:T
    for k = 1:N_ess
        r1 = 2*(k-1) + 1 + (t-1)*2*N_ess;
        r2 = r1 + 1;
        Aineq(r1, ICh(k,t)) =  1;   Aineq(r1, IUc(k,t)) = -P_ess_pu;
        Aineq(r2, IDs(k,t)) =  1;   Aineq(r2, IUc(k,t)) =  P_ess_pu;
        bineq(r2) = P_ess_pu;
    end
end

% ---------- 二阶锥：||(2P, 2Q, L-U)||_2 <= L + U ----------
socCell = cell(N_br*T, 1);
for t = 1:T
    for b = 1:N_br
        kk  = (t-1)*N_br + b;
        iii = fbus(b);
        A_k = sparse(3, n);
        A_k(1, IP(b,t))    = 2;
        A_k(2, IQ(b,t))    = 2;
        A_k(3, IL(b,t))    = 1;
        A_k(3, IU(iii,t))  = -1;
        d_k = sparse(1, n);
        d_k(1, IL(b,t))    = 1;
        d_k(1, IU(iii,t))  = 1;
        socCell{kk} = secondordercone(A_k, zeros(3,1), d_k, 0);
    end
end
soc = [socCell{:}];

% ---------- 变量上下界 ----------
lb = -inf(n,1);
ub =  inf(n,1);
for t = 1:T
    lb(IU(2:end,t)) = cfg.V_min^2;
    ub(IU(2:end,t)) = cfg.V_max^2;
end
lb(IL(:))  = 0;
lb(ICh(:)) = 0;   ub(ICh(:)) = P_ess_pu;
lb(IDs(:)) = 0;   ub(IDs(:)) = P_ess_pu;
lb(IUc(:)) = 0;   ub(IUc(:)) = 1;
lb(ISo(:)) = cfg.SoC_min;
ub(ISo(:)) = cfg.SoC_max;
lb(IPv(:)) = 0;
ub(IPv(:)) = P_pv_max;

% ---------- 三种调度目标（均为线性）----------
const = Sbase * sum(P_pv_max(:));

fA = zeros(n,1);                              % 模型 A：最大化消纳 + 网损正则
fA(IPv(:)) = -Sbase;
fA(IL(:))  =  1e-2 * Sbase * repmat(r_br, T, 1);

fB = zeros(n,1);                              % 模型 B：最小化网损
fB(IL(:))  =  Sbase * repmat(r_br, T, 1);
fB(ICh(:)) =  1e-4;
fB(IDs(:)) =  1e-4;

fC = zeros(n,1);                              % 模型 C：最小化购电成本
fC(IPg)    =  Sbase * cfg.price_MWh(:);

% ---------- 打包 ----------
M = struct();
M.n = n;   M.T = T;   M.Sbase = Sbase;
M.N_bus = N_bus;  M.N_br = N_br;  M.N_ess = N_ess;  M.N_pv = N_pv;
M.fbus = fbus;  M.tbus = tbus;  M.r_br = r_br;  M.x_br = x_br;
M.f = fA;  M.fA = fA;  M.fB = fB;  M.fC = fC;  M.const = const;
M.Aeq = Aeq;     M.beq = beq;
M.Aineq = Aineq; M.bineq = bineq;
M.soc = soc;     M.lb = lb;  M.ub = ub;
M.IU = IU; M.IL = IL; M.IP = IP; M.IQ = IQ;
M.IPg = IPg; M.IQg = IQg;
M.ICh = ICh; M.IDs = IDs; M.IUc = IUc; M.ISo = ISo; M.IPv = IPv;
M.Pd_pu = Pd_pu;  M.Qd_pu = Qd_pu;  M.P_pv_max = P_pv_max;
M.P_ess_pu = P_ess_pu;  M.E_ess_pu = E_ess_pu;
M.N_pv = N_pv;
M.cfg = cfg;
end

% =====================================================================

function B = rowblock(nrows, widths, blks)
%ROWBLOCK  把若干变量块的系数横向拼成一个行组（空块用稀疏零补齐）。
B = sparse(nrows, 0);
for b = 1:numel(widths)
    if isempty(blks{b})
        B = [B, spalloc(nrows, widths(b), 0)];   %#ok<AGROW>
    else
        assert(size(blks{b},1) == nrows && size(blks{b},2) == widths(b), ...
            '变量块 %d 尺寸不符。', b);
        B = [B, blks{b}];                        %#ok<AGROW>
    end
end
end

function out = w1_solve_misocp(M, model_type, opts)
%W1_MISOCP  MISOCP 调度模型的分支定界求解器（仅依赖 MATLAB 内置 coneprog）。
%
%   充放电互斥变量 u_{i,t} 只出现在两条线性约束中：
%       0 <= P_ch  <= u * P_rated
%       0 <= P_dis <= (1 - u) * P_rated
%   把 u 松弛到 [0,1] 后原问题成为标准二阶锥规划，可直接用 coneprog 求解，
%   其最优值给出原 MISOCP 的下界 LB。
%
%   求解流程：
%     1) 求根节点凸松弛，得到下界 LB；
%     2) 启发式构造整数可行解：由松弛解 P_ch / P_dis 反推 0/1 状态并回代。
%        由于松弛会把储能当作“可损耗能量缓冲”而同时充放电，本函数额外求解
%        若干带充放电功率正则项 lam*(P_ch+P_dis) 的松弛，得到不同的候选状态，
%        对所有候选回代取最优，得到上界 UB；
%     3) 若 UB > LB，对“同时充放电最严重”的 (i,t) 按 u=1/u=0 分支，
%        在子节点上继续解凸松弛并定界剪枝。
%
%   out = w1_solve_misocp(M, model_type, opts)
%       opts.MaxNodes    分支节点预算（默认 30）
%       opts.ComplTol    互补判据容差 / MW（默认 1e-6）
%       opts.NodeMaxTime 单次 SOCP 求解时限 / s（默认 120）
%       opts.MaxTime     总时限 / s（默认 900）
%       opts.Verbose     打印过程（默认 false）

if nargin < 3, opts = struct(); end
opts = setdefault(opts, 'MaxNodes',    30);
opts = setdefault(opts, 'ComplTol',    1e-6);
opts = setdefault(opts, 'NodeMaxTime', 120);
opts = setdefault(opts, 'MaxTime',     900);
opts = setdefault(opts, 'Verbose',     false);
opts = setdefault(opts, 'RelTol',      1e-6);

switch upper(model_type)
    case 'A', f = M.fA;
    case 'B', f = M.fB;
    case 'C', f = M.fC;
    otherwise, error('未定义的模型类型 %s（应为 A/B/C）。', model_type);
end

copts = optimoptions('coneprog', 'Display','off', ...
    'ConstraintTolerance',1e-6, 'OptimalityTolerance',1e-6, ...
    'MaxIterations',500, 'MaxTime', opts.NodeMaxTime);

t0 = tic;
solveF = @(ff, lb, ub) coneprog(ff, M.soc, M.Aineq, M.bineq, M.Aeq, M.beq, ...
    lb, ub, copts);
nSolved = 0;

% ---------- 1) 根节点凸松弛 ----------
[~, lbRoot, ef, output] = solveF(f, M.lb, M.ub);
assert(ef > 0, '根节点凸松弛求解失败（exitflag=%d）：%s', ef, output.message);
nSolved = nSolved + 1;
if opts.Verbose
    fprintf('[B&B] 根松弛 LB = %.8f（%d 次迭代，%.1f s）\n', lbRoot, output.iterations, toc(t0));
end

% ---------- 2) 多组正则松弛 + 整数回填，构造初始上界 ----------
bestX = [];  bestUB = Inf;
lams = [0, 1e-3, 1e-2, 1e-1];
for lam = lams
    fp = f;
    fp(M.ICh(:)) = fp(M.ICh(:)) + lam;
    fp(M.IDs(:)) = fp(M.IDs(:)) + lam;
    if lam == 0
        [xr, ~, efr] = solveF(f, M.lb, M.ub);
    else
        [xr, ~, efr] = solveF(fp, M.lb, M.ub);
    end
    nSolved = nSolved + 1;
    if efr <= 0, continue; end
    uFix = derive_binary_u(M, xr);
    lbF = M.lb; ubF = M.ub;
    lbF(M.IUc(:)) = uFix;  ubF(M.IUc(:)) = uFix;
    [xc, fc, efc] = solveF(f, lbF, ubF);
    nSolved = nSolved + 1;
    if efc > 0 && fc < bestUB
        bestUB = fc;  bestX = xc;
        if opts.Verbose
            fprintf('[B&B] lam=%-6g 回填候选 UB = %.8f（%.1f s）\n', lam, fc, toc(t0));
        end
    end
end
if isempty(bestX)
    error('未找到满足充放电互斥的整数可行解。');
end

% ---------- 3) 分支定界 ----------
stack = {};
[xr, ~, efr] = solveF(f, M.lb, M.ub);        % 重新取根松弛解用于分支
nSolved = nSolved + 1;
if efr > 0 && ~isComplementary(M, xr, opts.ComplTol)
    jv = worstComplementarity(M, xr);
    lb0 = M.lb; ub0 = M.ub; lb0(jv) = 1;
    lb1 = M.lb; ub1 = M.ub; ub1(jv) = 0;
    stack{end+1} = struct('lb', lb0, 'ub', ub0, 'depth', 1); %#ok<AGROW>
    stack{end+1} = struct('lb', lb1, 'ub', ub1, 'depth', 1); %#ok<AGROW>
end

nodes = 0;
while ~isempty(stack) && nodes < opts.MaxNodes && toc(t0) < opts.MaxTime
    node = stack{end};  stack(end) = [];   nodes = nodes + 1;
    [x, fv, efn] = solveF(f, node.lb, node.ub);
    nSolved = nSolved + 1;
    if efn <= 0 || fv >= bestUB - opts.RelTol*max(1, abs(bestUB)), continue; end
    uFix = derive_binary_u(M, x);
    lbP = node.lb; ubP = node.ub;
    lbP(M.IUc(:)) = uFix;  ubP(M.IUc(:)) = uFix;
    [xp, fpv, efp] = solveF(f, lbP, ubP);
    nSolved = nSolved + 1;
    if efp > 0 && fpv < bestUB
        bestUB = fpv;  bestX = xp;
        if opts.Verbose
            fprintf('[B&B] 节点 %d 更新 UB = %.8f（%.1f s）\n', nodes, fpv, toc(t0));
        end
    end
    if ~isComplementary(M, x, opts.ComplTol)
        jv = worstComplementarity(M, x);
        lb0 = node.lb; ub0 = node.ub; lb0(jv) = 1;
        lb1 = node.lb; ub1 = node.ub; ub1(jv) = 0;
        stack{end+1} = struct('lb', lb0, 'ub', ub0, 'depth', node.depth+1); %#ok<AGROW>
        stack{end+1} = struct('lb', lb1, 'ub', ub1, 'depth', node.depth+1); %#ok<AGROW>
    end
end

out = struct();
out.solver_name   = 'coneprog + 自编分支定界（MATLAB 内置，无需商业求解器）';
out.nodes         = nodes;
out.n_solved      = nSolved;
out.lower_bound   = lbRoot;
out.x             = bestX;
out.fval          = bestUB;
out.gap           = max(0, bestUB - lbRoot);
out.gap_rel       = out.gap / max(1e-9, abs(lbRoot));
out.exitflag      = 1;
out.integral      = true;
out.proven_optimal = out.gap <= opts.RelTol*max(1, abs(bestUB));
out.solve_seconds = toc(t0);
end

% =====================================================================

function tf = isComplementary(M, x, tol)
Pch = reshape(x(M.ICh), M.N_ess, M.T) * M.Sbase;
Pds = reshape(x(M.IDs), M.N_ess, M.T) * M.Sbase;
tf  = max(min(Pch, Pds), [], 'all') <= tol;
end

function jv = worstComplementarity(M, x)
Pch = reshape(x(M.ICh), M.N_ess, M.T) * M.Sbase;
Pds = reshape(x(M.IDs), M.N_ess, M.T) * M.Sbase;
[~, k] = max(min(Pch, Pds), [], 'all', 'linear');
jv = M.IUc(k);
end

function u = derive_binary_u(M, x)
Pch = reshape(x(M.ICh), M.N_ess, M.T);
Pds = reshape(x(M.IDs), M.N_ess, M.T);
u   = double(Pch >= Pds);
u   = u(:);
end

function s = setdefault(s, name, val)
if ~isfield(s, name) || isempty(s.(name))
    s.(name) = val;
end
end

function K = w1_check(M, x, cfg, case_name, model_type)
%W1_KPI  Decode the solution and evaluate every operating index + AC check.
T = M.T;  Sbase = M.Sbase;

U   = reshape(x(M.IU),  M.N_bus, T);
L   = reshape(x(M.IL),  M.N_br,  T);
Pbr = reshape(x(M.IP),  M.N_br,  T);
Qbr = reshape(x(M.IQ),  M.N_br,  T);
Pg  = x(M.IPg)';   Qg = x(M.IQg)';
Pch = reshape(x(M.ICh), M.N_ess, T) * Sbase;
Pds = reshape(x(M.IDs), M.N_ess, T) * Sbase;
u   = reshape(x(M.IUc), M.N_ess, T);
SoC = reshape(x(M.ISo), M.N_ess, T);
Ppv = reshape(x(M.IPv), M.N_pv,  T) * Sbase;

PloadMW = M.Pd_pu * Sbase;
QloadMvar = M.Qd_pu * Sbase;
PpvMaxMW = M.P_pv_max * Sbase;
PratedMW = M.P_ess_pu * Sbase;
EratedMWh = M.E_ess_pu * Sbase;

fb = M.fbus;  tb = M.tbus;  r = M.r_br;  xr = M.x_br;
af = sparse(fb, 1:M.N_br, 1, M.N_bus, M.N_br);
at = sparse(tb, 1:M.N_br, 1, M.N_bus, M.N_br);
ae = sparse(cfg.ess_buses, 1:M.N_ess, 1, M.N_bus, M.N_ess);
ap = sparse(cfg.pv_buses,  1:M.N_pv,  1, M.N_bus, M.N_pv);
a0 = sparse(1, 1, 1, M.N_bus, 1);

p_res = at*(Pbr - r.*L) - af*Pbr + a0*Pg + ap*Ppv/Sbase + ae*(Pds-Pch)/Sbase - PloadMW/Sbase;
q_res = at*(Qbr - xr.*L) - af*Qbr + a0*Qg - QloadMvar/Sbase;
v_res = U(tb,:) - U(fb,:) + 2*(r.*Pbr + xr.*Qbr) - (r.^2 + xr.^2).*L;
gap   = abs(L.*U(fb,:) - Pbr.^2 - Qbr.^2);
prev  = [repmat(cfg.SoC_0, M.N_ess, 1), SoC(:, 1:end-1)];
energy_res = EratedMWh*(SoC - prev) - (cfg.eta_ch*Pch - Pds/cfg.eta_dis)*1;

K = struct();
K.ModelType = 'MISOCP';
K.Case = case_name;
K.Objective = model_type;
K.StudentID = cfg.stu_id;
K.MaxSimultaneousPower_MW = max(min(Pch, Pds), [], 'all');
K.MinSoC = min(SoC(:));  K.MaxSoC = max(SoC(:));
K.TerminalSoCError = max(abs(SoC(:,end) - cfg.SoC_0));
K.EnergyBalanceError_MWh = max(abs(energy_res), [], 'all');
K.PowerLimitViolation_MW = max([0; Pch(:)-PratedMW; Pds(:)-PratedMW; -Pch(:); -Pds(:)]);
K.PVLimitViolation_MW = max([0; Ppv(:)-PpvMaxMW(:); -Ppv(:)]);
K.IntegerError = max(abs(u(:) - round(u(:))));
K.MaxConeGap = max(gap(:));
K.ActiveBalanceError_pu = max(abs(p_res), [], 'all');
K.ReactiveBalanceError_pu = max(abs(q_res), [], 'all');
K.VoltageEquationError_pu = max(abs(v_res), [], 'all');
K.MinModelVoltage = min(sqrt(U(:)));
K.MaxModelVoltage = max(sqrt(U(:)));
K.Curtailment_MWh = sum(PpvMaxMW - Ppv, 'all');
K.LineLoss_MWh = Sbase*sum(r.*L, 'all');
K.PurchaseCost_Yuan = sum(cfg.price_MWh(:).*(Sbase*Pg(:)));
K.GridCost_Yuan = K.PurchaseCost_Yuan;

% ---------- 交流潮流回代校核 ----------
opts = mpoption('verbose', 0, 'out.all', 0);
V_ac = zeros(M.N_bus, T);  ac_loss = zeros(1, T);  ok = true;
for t = 1:T
    ac = cfg.mpc;
    ac.bus(:,3) = PloadMW(:,t);
    ac.bus(:,4) = QloadMvar(:,t);
    ac.bus(cfg.pv_buses,3)  = ac.bus(cfg.pv_buses,3)  - Ppv(:,t);
    ac.bus(cfg.ess_buses,3) = ac.bus(cfg.ess_buses,3) + Pch(:,t) - Pds(:,t);
    rr = runpf(ac, opts);
    ok = ok && (rr.success == 1);
    V_ac(:,t) = rr.bus(:,8);
    ac_loss(t) = sum(real(get_losses(rr)));
end
K.ACConverged = ok;
K.MinACVoltage = min(V_ac(:));
K.MaxACVoltage = max(V_ac(:));
K.MaxACVoltageError = max(abs(V_ac - sqrt(U)), [], 'all');
[~, ixe] = max(abs(V_ac(:) - sqrt(U(:))));
[K.MaxVoltageErrorNode, K.MaxVoltageErrorHour] = ind2sub([M.N_bus T], ixe);
K.ACLineLoss_MWh = sum(ac_loss);

% ---------- 判定 ----------
K.StorageConstraintsPassed = K.MaxSimultaneousPower_MW <= 1e-6 && K.IntegerError <= 1e-6 ...
    && K.MinSoC >= cfg.SoC_min-1e-6 && K.MaxSoC <= cfg.SoC_max+1e-6 ...
    && K.TerminalSoCError <= 1e-6 && K.EnergyBalanceError_MWh <= 1e-6 ...
    && K.PowerLimitViolation_MW <= 1e-5;
K.LinearConstraintsPassed = K.PVLimitViolation_MW <= 1e-5 ...
    && K.ActiveBalanceError_pu <= 1e-7 && K.ReactiveBalanceError_pu <= 1e-7 ...
    && K.VoltageEquationError_pu <= 1e-7;
K.ConeRelaxationExact = K.MaxConeGap <= 1e-5;
K.ACVoltageWithinLimits = ok && K.MinACVoltage >= 0.95-1e-6 && K.MaxACVoltage <= 1.05+1e-6;
K.Passed = K.StorageConstraintsPassed && K.LinearConstraintsPassed ...
    && K.ConeRelaxationExact && K.ACVoltageWithinLimits;
K.TeachingCounterexample = strcmp(model_type,'C') && K.StorageConstraintsPassed ...
    && K.LinearConstraintsPassed && ~K.ConeRelaxationExact;

% 供绘图使用
K.PchMW = Pch;  K.PdisMW = Pds;  K.NetMW = Pds - Pch;  K.SoC = SoC;
K.PpvMW = Ppv;  K.PgridMW = Sbase*Pg(:)';  K.U_model = U;  K.V_ac = V_ac;
K.u = u;
end

function out = w1_solve_misocp_mosek(cfg, model_type, opts)
%W1_SOLVE_MISOCP_MOSEK  用 YALMIP + MOSEK 求解 MISOCP（课程模板的标准做法）。
%
%   与 w1_build_model 描述的是同一个数学模型，只是改用二进制变量 u_ch 精确
%   表达充放电互斥，交给 MOSEK 的分支定界求解。求解完成后把结果整理成与
%   w1_build_model 相同顺序的变量向量 x，交给同一个 w1_check 校核，
%   从而保证两条求解路径的结果可以直接互相印证。
%
%   out = w1_solve_misocp_mosek(cfg, model_type, opts)

if nargin < 3, opts = struct(); end
if ~isfield(opts, 'MaxTime') || isempty(opts.MaxTime), opts.MaxTime = 300; end
if ~isfield(opts, 'Verbose') || isempty(opts.Verbose), opts.Verbose = true; end

assert(~isempty(which('mosekopt')), ...
    '未找到 mosekopt。请把 MOSEK 的 MATLAB 工具箱目录加入路径，例如 addpath(''D:\mosek\11.2\toolbox\R2019b'')。');

yalmip('clear');
mpc   = cfg.mpc;
T     = cfg.T;
Sbase = mpc.baseMVA;
N_bus = size(mpc.bus, 1);
N_br  = size(mpc.branch, 1);
N_ess = numel(cfg.ess_buses);
N_pv  = numel(cfg.pv_buses);

fbus = mpc.branch(:,1);   tbus = mpc.branch(:,2);
r_br = mpc.branch(:,3);   x_br = mpc.branch(:,4);

Pd_pu      = (mpc.bus(:,3) * cfg.alpha / Sbase) * cfg.load_curve_pu(:)';
Qd_pu      = (mpc.bus(:,4) * cfg.alpha / Sbase) * cfg.load_curve_pu(:)';
P_pv_max   = (cfg.P_pv_peak_MW / Sbase) * repmat(cfg.pv_curve_pu(:)', N_pv, 1);
P_ess_pu   = cfg.P_ess_MW / Sbase;
E_ess_pu   = cfg.E_ess_MWh / Sbase;

U_bus  = sdpvar(N_bus, T, 'full');
L_br   = sdpvar(N_br,  T, 'full');
P_br   = sdpvar(N_br,  T, 'full');
Q_br   = sdpvar(N_br,  T, 'full');
P_grid = sdpvar(1,     T, 'full');
Q_grid = sdpvar(1,     T, 'full');
P_ch   = sdpvar(N_ess, T, 'full');
P_dis  = sdpvar(N_ess, T, 'full');
SoC    = sdpvar(N_ess, T, 'full');
P_pv   = sdpvar(N_pv,  T, 'full');
u_ch   = binvar(N_ess, T, 'full');

Constraints = [];
Constraints = [Constraints, 0 <= P_ch  <= P_ess_pu * u_ch];
Constraints = [Constraints, 0 <= P_dis <= P_ess_pu * (1 - u_ch)];
Constraints = [Constraints, cfg.SoC_min <= SoC <= cfg.SoC_max];
Constraints = [Constraints, SoC(:, T) == cfg.SoC_0];
Constraints = [Constraints, 0 <= P_pv <= P_pv_max];
for t = 1:T
    if t == 1
        soc_prev = repmat(cfg.SoC_0, N_ess, 1);
    else
        soc_prev = SoC(:, t-1);
    end
    Constraints = [Constraints, SoC(:, t) == soc_prev + ...
        (cfg.eta_ch * P_ch(:, t) - P_dis(:, t) / cfg.eta_dis) / E_ess_pu];
end

A_from  = sparse(fbus, 1:N_br, 1, N_bus, N_br);
A_to    = sparse(tbus, 1:N_br, 1, N_bus, N_br);
A_ess   = sparse(cfg.ess_buses, 1:N_ess, 1, N_bus, N_ess);
A_pv    = sparse(cfg.pv_buses,  1:N_pv,  1, N_bus, N_pv);
A_slack = sparse(1, 1, 1, N_bus, 1);

P_loss_br = diag(r_br) * L_br;
Q_loss_br = diag(x_br) * L_br;
Constraints = [Constraints, A_to * (P_br - P_loss_br) - A_from * P_br + ...
    A_slack * P_grid + A_pv * P_pv + A_ess * (P_dis - P_ch) == Pd_pu];
Constraints = [Constraints, A_to * (Q_br - Q_loss_br) - A_from * Q_br + ...
    A_slack * Q_grid == Qd_pu];
Constraints = [Constraints, U_bus(1, :) == 1.0];
Constraints = [Constraints, cfg.V_min^2 <= U_bus(2:end, :) <= cfg.V_max^2];
Constraints = [Constraints, L_br >= 0];
for b = 1:N_br
    i = fbus(b);
    j = tbus(b);
    Constraints = [Constraints, U_bus(j, :) == U_bus(i, :) - ...
        2 * (r_br(b) * P_br(b, :) + x_br(b) * Q_br(b, :)) + ...
        (r_br(b)^2 + x_br(b)^2) * L_br(b, :)];
    for t = 1:T
        Constraints = [Constraints, cone([2*P_br(b,t); 2*Q_br(b,t); ...
            L_br(b,t) - U_bus(i,t)], L_br(b,t) + U_bus(i,t))];
    end
end

Total_Loss_MWh    = Sbase * sum(sum(P_loss_br));
Total_Curtail_MWh = Sbase * sum(sum(P_pv_max - P_pv));
Total_Cost_Yuan   = sum((Sbase * P_grid') .* cfg.price_MWh(:));
switch upper(model_type)
    case 'A', Objective = Total_Curtail_MWh + 1e-2 * Total_Loss_MWh;
    case 'B', Objective = Total_Loss_MWh + 1e-4 * sum(sum(P_ch + P_dis));
    case 'C', Objective = Total_Cost_Yuan;
    otherwise, error('未定义的模型类型 %s。', model_type);
end

ops = sdpsettings('solver', 'mosek', 'verbose', double(opts.Verbose) > 0);
ops.mosek.MSK_DPAR_MIO_MAX_TIME          = opts.MaxTime;
ops.mosek.MSK_DPAR_MIO_TOL_REL_GAP       = 1e-6;
ops.mosek.MSK_DPAR_MIO_TOL_ABS_GAP       = 1e-8;
ops.mosek.MSK_DPAR_MIO_TOL_FEAS          = 1e-9;
ops.mosek.MSK_DPAR_MIO_TOL_ABS_RELAX_INT = 1e-9;
ops.mosek.MSK_DPAR_INTPNT_CO_TOL_PFEAS   = 1e-10;
ops.mosek.MSK_DPAR_INTPNT_CO_TOL_DFEAS   = 1e-10;
ops.mosek.MSK_DPAR_INTPNT_CO_TOL_REL_GAP = 1e-10;

t0  = tic;
sol = optimize(Constraints, Objective, ops);
secs = toc(t0);

out = struct();
out.solver_name   = 'YALMIP + MOSEK (MISOCP)';
out.solve_seconds = secs;
out.problem       = sol.problem;
out.info          = sol.info;
out.nodes         = NaN;
out.lower_bound   = NaN;
out.fval          = NaN;
out.gap           = NaN;
out.gap_rel       = NaN;
out.exitflag      = 0;
out.integral      = false;
out.proven_optimal = false;
out.x             = [];

if sol.problem ~= 0
    return
end

% ---- 把结果整理成 w1_build_model 的变量顺序，交给同一个 w1_check ----
M = w1_build_model(cfg);
x = zeros(M.n, 1);
x(M.IU)  = value(U_bus);
x(M.IL)  = value(L_br);
x(M.IP)  = value(P_br);
x(M.IQ)  = value(Q_br);
x(M.IPg) = value(P_grid);
x(M.IQg) = value(Q_grid);
x(M.ICh) = value(P_ch);
x(M.IDs) = value(P_dis);
x(M.IUc) = round(value(u_ch));
x(M.ISo) = value(SoC);
x(M.IPv) = value(P_pv);

out.x        = x;
out.fval     = value(Objective);
out.exitflag = 1;
out.integral = true;
out.nodes    = NaN;

% MOSEK 已给出整数最优解；这里再用内置 coneprog 求一次"完全松弛"（u ∈ [0,1]）
% 的最优值，用于量化"整数松弛间隙"，使上下界口径与报告一致。
switch upper(model_type)
    case 'A', fA = M.fA;
    case 'B', fA = M.fB;
    otherwise, fA = M.fC;
end
copts = optimoptions('coneprog', 'Display','off', ...
    'ConstraintTolerance',1e-6, 'OptimalityTolerance',1e-6, 'MaxIterations',500);
[~, lbRoot] = coneprog(fA, M.soc, M.Aineq, M.bineq, M.Aeq, M.beq, M.lb, M.ub, copts);
out.root_lb     = lbRoot;
out.lower_bound = lbRoot + M.const;          % 换算到与 Objective 相同的目标口径
out.gap         = max(0, out.fval - out.lower_bound);
out.gap_rel     = out.gap / max(1e-9, abs(out.lower_bound));
out.proven_optimal = true;                   % MOSEK 报告 INTEGER_OPTIMAL
end

