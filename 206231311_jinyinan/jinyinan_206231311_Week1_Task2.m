%[text] # 任务二：单节点储能分时电价套利
%[text] 课程：《储能优化规划与运行》课程设计（南京工程学院）
%[text] 本文件为第一周**任务二（单节点套利）**的独立提交脚本，可单独"全部运行"。
%[text] **个人参数**：学号 $206231311$，末两位 $X=1,\ Y=1$ → $\alpha = 1.022$，
%[text] 算例 `case_nongcun`（49 节点，12.66 kV / 100 MVA），单节点 2 MW / 2 MWh 储能，独立于配电网算例
%[text] 对应课件：interactive02（储能套利）、demo02（YALMIP 基础）。
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


%[text] ## 2 任务二：单节点储能分时电价日前套利
%[text] 单节点独立储能电站，不计网络约束，额定 **2 MW / 2 MWh**，$\eta_{\mathrm{ch}}=0.90$、$\eta_{\mathrm{dis}}=0.95$，
%[text] $\mathrm{SoC}\in[0.10,1.00]$，初末 $\mathrm{SoC}_0=0.50$。以江苏省工商业分时电价结算：
%[text] $$R=\sum_{t=1}^{T} c_t\left(P_t^{\mathrm{dis}}-P_t^{\mathrm{ch}}\right)\Delta t$$
%[text] 荷电状态递推与充放电互斥约束：
%[text] $$\mathrm{SoC}_t=\mathrm{SoC}_{t-1}+\frac{\eta_{\mathrm{ch}}P_t^{\mathrm{ch}}\Delta t}{E_{\mathrm{rated}}}-\frac{P_t^{\mathrm{dis}}\Delta t}{\eta_{\mathrm{dis}}E_{\mathrm{rated}}},\quad 0\le P_t^{\mathrm{ch}}\le u_tP_{\mathrm{rated}},\ 0\le P_t^{\mathrm{dis}}\le(1-u_t)P_{\mathrm{rated}}$$
%%
P_rated2 = 2.0;  E_rated2 = 2.0;
eta_ch2 = 0.90;  eta_dis2 = 0.95;
SoC0_2 = 0.50;   SoC_min2 = 0.10;  SoC_max2 = 1.00;
[Rev_milp, Pch2, Pds2, SoC2, ok2] = ess_arbitrage(profiles, P_rated2, E_rated2, ...
    eta_ch2, eta_dis2, SoC0_2, SoC_min2, SoC_max2, dt, true);
[Rev_lp, Pch2_lp, Pds2_lp, SoC2_lp] = ess_arbitrage(profiles, P_rated2, E_rated2, ...
    eta_ch2, eta_dis2, SoC0_2, SoC_min2, SoC_max2, dt, false);
fprintf('MILP（互斥）日收益 = %.2f 元；LP（无互斥）日收益 = %.2f 元；差值 = %.2f 元\n', ...
    Rev_milp, Rev_lp, Rev_lp - Rev_milp);
fprintf('同时充放电最大功率：MILP %.3e MW，LP %.3e MW\n', ...
    max(min(Pch2,Pds2)), max(min(Pch2_lp,Pds2_lp)));
plan2 = table((1:T)', price_kWh, Pch2, Pds2, Pds2-Pch2, SoC2, ...
    'VariableNames', {'t','电价_元每kWh','充电_MW','放电_MW','净放电_MW','SoC'});
disp(plan2);
%%
%[text] ### 2.1 任务二图形：电价、充放电功率与荷电状态
fig2 = figure('Name','任务二 储能套利','Color','w','Units','pixels','Position',[90 70 1000 660]);
brn = [0.494 0.380 0.282];
axp = subplot(3,1,1); hold(axp,'on');
stairs(axp, [0 tt], [price_kWh(1); price_kWh], '-', 'Color', brn, 'LineWidth', 2);
style_axes(axp); xlim(axp,[1 T]);
ylabel(axp,'\fontname{宋体}电价 \fontname{Times New Roman}{\itc}\rm{/(元\cdot kWh^{-1})}','Interpreter','tex');
title(axp,'\fontname{宋体}(a) 江苏省工商业分时电价与储能日前套利结果','FontWeight','normal','Interpreter','tex');
set(axp,'XTickLabel',[]);
axq = subplot(3,1,2); hold(axq,'on');
bar(axq, tt, -Pch2, 0.6, 'FaceColor', clr(1,:), 'EdgeColor','none');
bar(axq, tt,  Pds2, 0.6, 'FaceColor', clr(2,:), 'EdgeColor','none');
plot(axq, tt, Pds2-Pch2, '-o', 'Color', clr(3,:), 'LineWidth', 1.5, 'MarkerSize', 4);
yline(axq, 0, ':k', 'LineWidth', 0.8);
style_axes(axq); xlim(axq,[1 T]);
ylabel(axq,'\fontname{宋体}功率 \fontname{Times New Roman}{\itP}\rm{/MW}','Interpreter','tex');
title(axq,'\fontname{宋体}(b) 充电功率（负）、放电功率（正）与净功率','FontWeight','normal','Interpreter','tex');
legend(axq, {'\fontname{宋体}充电','\fontname{宋体}放电','\fontname{宋体}净放电'}, ...
    'Location','southwest','NumColumns',3,'Interpreter','tex','Box','off');
set(axq,'XTickLabel',[]);
axs = subplot(3,1,3); hold(axs,'on');
plot(axs, tt, 100*SoC2, '-o', 'Color', clr(1,:), 'LineWidth', 2, 'MarkerSize', 5, ...
    'MarkerFaceColor', clr(1,:));
yline(axs, 100*SoC_max2, ':', 'Color', clr(3,:), 'LineWidth', 1.5);
yline(axs, 100*SoC_min2, ':', 'Color', clr(3,:), 'LineWidth', 1.5);
style_axes(axs); xlim(axs,[1 T]);
xlabel(axs,'\fontname{宋体}时间 \fontname{Times New Roman}{\itt}\rm{/h}','Interpreter','tex');
ylabel(axs,'\fontname{宋体}荷电状态 \fontname{Times New Roman}\rm{SoC}/%','Interpreter','tex');
title(axs,'\fontname{宋体}(c) 储能荷电状态时序曲线','FontWeight','normal','Interpreter','tex');
if export_figs
    export_figure(fig2, out_dir, sprintf('Fig_Week1_Task2_%d', Stu_ID));
    drawnow;
end

%[text] ## 结论与思考题
%[text] **结论**：2 MW / 2 MWh 储能在江苏省分时电价下按"谷充峰放"运行，日收益约 1553 元；
%[text] 由于往返效率 $\eta_{\mathrm{ch}}\eta_{\mathrm{dis}}=0.855<1$，最优解本身不出现同时充放电，
%[text] LP 与 MILP 结果一致，说明单节点场景下互斥约束不紧（但任务三中会变紧）。
%[text] **思考题（interactive02 练习）**：分别改变额定功率与额定能量容量，观察受约束的充放电时段，
%[text] 解释"功率上限"与"可用电量"对收益的不同影响。
%[text] 功率上限决定单时段最大吞吐能力，能量容量决定可搬运的总电量；前者约束峰谷两个时段的瞬时功率，
%[text] 后者约束跨时段的总能量。定量结果见报告"思考题"一节。

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

function [Rev, Pch, Pds, SoC, ok] = ess_arbitrage(profiles, Pm, Em, ech, edis, ...
    SoC0, Smin, Smax, dt, useBinary)
% 注意：MOSEK 的 MATLAB 工具箱目录带有同名的 linprog / intlinprog / quadprog
% 兼容接口，一旦该目录位于搜索路径前端，就会覆盖 MathWorks 原生实现。
% 本函数强制把原生 optim 目录提到最前，确保任务二使用 MATLAB 内置求解器。
old_path    = path;
restore_path = onCleanup(@() path(old_path)); %#ok<NASGU>
addpath(fullfile(matlabroot,'toolbox','optim','optim'), '-begin');
yalmip('clear');
T = profiles.T;
P_ch  = sdpvar(T,1,'full');
P_dis = sdpvar(T,1,'full');
S     = sdpvar(T,1,'full');
if useBinary
    u = binvar(T,1,'full');
else
    u = sdpvar(T,1,'full');
end
Cons = [0 <= P_ch <= Pm, 0 <= P_dis <= Pm, 0 <= u <= 1];
Cons = [Cons, P_ch <= u*Pm, P_dis <= (1-u)*Pm];
Cons = [Cons, Smin <= S <= Smax, S(T) == SoC0];
for t = 1:T
    if t == 1, sp = SoC0; else, sp = S(t-1); end
    Cons = [Cons, S(t) == sp + (ech*P_ch(t)*dt)/Em - (P_dis(t)*dt)/(edis*Em)];
end
Revenue = sum(profiles.price_MWh(:) .* (P_dis - P_ch) * dt);
if useBinary
    ops = sdpsettings('solver','intlinprog','verbose',0);
    ops.intlinprog.RelativeGapTolerance = 1e-9;
    ops.intlinprog.AbsoluteGapTolerance = 1e-9;
else
    ops = sdpsettings('solver','linprog','verbose',0);
end
sol = optimize(Cons, -Revenue, ops);
assert(sol.problem == 0, '任务二求解失败：%s', sol.info);
Rev = value(Revenue);  Pch = value(P_ch);  Pds = value(P_dis);  SoC = value(S);
ok  = true;
end

