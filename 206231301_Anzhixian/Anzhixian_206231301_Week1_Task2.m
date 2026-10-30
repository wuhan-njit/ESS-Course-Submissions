%% 江苏省工商业分时电价下独立储能日前套利优化模型
% 课程名称：《储能优化配置与调度技术》课程设计（随堂演示脚本 02）
%% 0. 教学目标与独立储能套利数学模型
% *教学目标*：
%% 
% * 掌握 YALMIP 建模工具箱中连续变量（|sdpvar|）、二进制变量（|binvar|）、约束集合（|Constraints|）与求解器配置（|sdpsettings|）的标准语法；
% * 建立以无量纲荷电状态 $\mathrm{SoC}_t$ 为直接决策变量的独立储能日前分时电价（TOU）套利混合整数线性规划（MILP）模型；
% * 对比验证正电价下“含充放电互斥二进制变量 $u_t^{\mathrm{ch}}$”与“松弛二进制变量（纯 LP）”解的等价性，并绘制符合《中国电机工程学报》规范的双轴运行曲线。
%% 
% *数学模型*：
% 
% *1) 目标函数（最大化全天电价套利净收益）*：
% 
% $$\max \sum_{t=1}^{T} \lambda_t \left( P_t^{\mathrm{dis}} - P_t^{\mathrm{ch}} 
% \right) \Delta t \Leftrightarrow \min \sum_{t=1}^{T} \lambda_t \left( P_t^{\mathrm{ch}} 
% - P_t^{\mathrm{dis}} \right) \Delta t$$
% 
% *2) 荷电状态（SoC）跨时段耦合差分方程*（注意分母除以额定容量 $E_{\mathrm{rated}}$ 以保证量纲一致）：
% 
% $$\mathrm{SoC}_t = \mathrm{SoC}_{t-1} + \frac{\eta_{\mathrm{ch}} P_t^{\mathrm{ch}} 
% \Delta t}{E_{\mathrm{rated}}} - \frac{P_t^{\mathrm{dis}} \Delta t}{\eta_{\mathrm{dis}} 
% E_{\mathrm{rated}}}, \quad \forall t \in \{1, 2, \dots, T\}$$
% 
% *3) 荷电状态上下限、首尾周期平衡与充放电互斥约束*：
% 
% $$\mathrm{SoC}_{\min} \le \mathrm{SoC}_t \le \mathrm{SoC}_{\max}, \quad \mathrm{SoC}_T 
% = \mathrm{SoC}_0$$
% 
% $$0 \le P_t^{\mathrm{ch}} \le u_t^{\mathrm{ch}} P_{\mathrm{rated}}, \quad 
% 0 \le P_t^{\mathrm{dis}} \le \left(1 - u_t^{\mathrm{ch}}\right) P_{\mathrm{rated}}, 
% \quad u_t^{\mathrm{ch}} \in \{0, 1\}$$

clear; clc; close all;
yalmip('clear');
%% 1. 加载江苏省分时电价数据与储能系统参数
%% 1.1 自动检测并加载分时电价数据包

if ~exist('profiles_24h.mat', 'file')
    rel_case_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'cases');
    if exist(rel_case_dir, 'dir')
        addpath(rel_case_dir);
    elseif exist(fullfile(pwd, 'ESS-Course-Materials', 'cases'), 'dir')
        addpath(fullfile(pwd, 'ESS-Course-Materials', 'cases'));
    else
        case_dir = uigetdir(pwd, '请选择教学资源库中的 cases 文件夹路径');
        addpath(case_dir);
    end
end
load('profiles_24h.mat');
%% 1.2 储能电站技术参数设置
% 给定独立储能电站额定功率 $P_{\mathrm{rated}} = 2.0\;\mathrm{MW}$，额定容量 $E_{\mathrm{rated}} 
% = 2.0\;\mathrm{MWh}$，充电效率 $\eta_{\mathrm{ch}} = 0.90$，放电效率 $\eta_{\mathrm{dis}} 
% = 0.95$。

P_rated = 2.0;    % 额定功率 P_rated (MW)
E_rated = 2.0;    % 额定能量容量 E_rated (MWh)
eta_ch  = 0.90;   % 充电效率 \eta_ch
eta_dis = 0.95;   % 放电效率 \eta_dis
SoC_0   = 0.50;   % 初始与末态荷电状态 SoC_0
SoC_min = 0.10;   % 最小荷电状态 SoC_min
SoC_max = 1.00;   % 最大荷电状态 SoC_max
dt      = 1.0;    % 调度时间步长 \Delta t (h)
%% 2. 声明 YALMIP 决策变量
% 直接以无量纲荷电状态 $\mathrm{SoC}_t \in [0, 1]$ 作为状态决策变量：

P_ch  = sdpvar(T, 1, 'full'); % 充电功率 P_t^{ch} (MW)
P_dis = sdpvar(T, 1, 'full'); % 放电功率 P_t^{dis} (MW)
SoC   = sdpvar(T, 1, 'full'); % 荷电状态 SoC_t
u_ch  = binvar(T, 1, 'full'); % 充电状态二进制变量 u_t^{ch} \in {0,1}
%% 3. 构建储能运行约束条件集合

Constraints = [];

% 充放电功率上下限与互斥逻辑约束
Constraints = [Constraints, 0 <= P_ch  <= u_ch * P_rated];
Constraints = [Constraints, 0 <= P_dis <= (1 - u_ch) * P_rated];

% 荷电状态安全边界与日周期首尾平衡约束
Constraints = [Constraints, SoC_min <= SoC <= SoC_max];
Constraints = [Constraints, SoC(T) == SoC_0];

% 时序荷电状态递推差分方程
for t = 1:T
    if t == 1
        soc_prev = SoC_0;
    else
        soc_prev = SoC(t - 1);
    end
    Constraints = [Constraints, SoC(t) == soc_prev + ...
        (eta_ch * P_ch(t) * dt) / E_rated - (P_dis(t) * dt) / (eta_dis * E_rated)];
end
%% 4. 定义目标函数并调用 MATLAB 原生求解器求解
% YALMIP 默认求解最小化问题，因此最大化套利净收益 $R_{\mathrm{arb}}$ 等价于最小化 $-R_{\mathrm{arb}}$。任务二 
% MILP 模型默认调用 MATLAB Optimization Toolbox 原生 |intlinprog| 求解（调用前将内置 |optim| 目录置顶，避免被路径中 
% MOSEK 的同名兼容函数覆盖）。

Total_Revenue = sum(price_MWh .* (P_dis - P_ch) * dt);
Objective     = -Total_Revenue;

native_optim_dir = fullfile(matlabroot, 'toolbox', 'optim', 'optim');
if exist(native_optim_dir, 'dir')
    addpath(native_optim_dir, '-begin');
end
solver_name = 'mosek';
ops = sdpsettings('solver', solver_name, 'verbose', 1);
sol = optimize(Constraints, Objective, ops);

if sol.problem == 0
    fprintf('求解成功 (求解器: %s)，全天最大套利净收益: %.2f 元\n', solver_name, value(Total_Revenue));
else
    error('求解失败: %s', yalmiperror(sol.problem));
end
%% 5. 绘制符合《中国电机工程学报》规范的储能套利运行曲线
% 规范要求：中文采用宋体，西文与数字采用 Times New Roman，物理量变量符号采用斜体，下标说明与单位采用正体。

P_net_val = value(P_dis - P_ch);
SoC_val   = [SoC_0; value(SoC)] * 100; % 转换为百分比 (%)

fig1 = figure('Name', '独立储能日前分时电价套利曲线', 'Color', 'w', 'Position', [120, 100, 700, 500]);
if isprop(fig1, 'Theme'), theme(fig1, 'light'); end

% 子图 (a)：充放电功率与分时电价
subplot(2, 1, 1);
yyaxis left;
b_handle = bar(1:T, P_net_val, 0.62, 'FaceColor', [0.16, 0.44, 0.69], 'EdgeColor', 'none');
ylabel('\fontname{宋体}净放电功率 \fontname{Times New Roman}{\itP}_{\rm{net}}\rm{/MW}', 'FontSize', 11.5, 'Interpreter', 'tex');
ylim([-2.5, 3.2]);
ax1 = gca;
ax1.YAxis(1).Color = [0.10, 0.30, 0.55];

yyaxis right;
s_handle = stairs(1:T, price_kWh, '-r', 'LineWidth', 1.8);
ylabel('\fontname{宋体}分时电价 \fontname{Times New Roman}{\itc}_{\itt}\rm{/(\fontname{宋体}元\fontname{Times New Roman}\cdot(kW\cdot h)^{-1})}', ...
    'FontSize', 11.5, 'Interpreter', 'tex');
ylim([0.1, 1.55]);
ax1.YAxis(2).Color = [0.80, 0.10, 0.10];

set(gca, 'Color', 'w', 'XColor', 'k', 'FontName', 'Times New Roman', 'FontSize', 10.5, 'LineWidth', 1.0, ...
    'Box', 'on', 'TickDir', 'in', 'XTick', 0:4:24, 'GridLineStyle', '--', 'GridAlpha', 0.3, 'GridColor', [0.4, 0.4, 0.4]);
xlim([0.5, 24.5]);
xlabel('\fontname{宋体}时间 \fontname{Times New Roman}{\itt}\rm{/h}', 'FontSize', 11.5, 'Color', 'k', 'Interpreter', 'tex');
title(sprintf('\\fontname{宋体}(a) 储能充放电功率与分时电价曲线 (日最大净收益: \\fontname{Times New Roman}%.2f \\fontname{宋体}元)', ...
    value(Total_Revenue)), 'FontSize', 11.5, 'FontWeight', 'normal', 'Color', 'k', 'Interpreter', 'tex');
leg1 = legend([b_handle, s_handle], {'\fontname{宋体}净放电功率 \fontname{Times New Roman}{\itP}_{\rm{dis}}-{\itP}_{\rm{ch}}', ...
    '\fontname{宋体}分时电价 \fontname{Times New Roman}{\itc}_{\itt}'}, ...
    'Location', 'north', 'Orientation', 'horizontal', 'FontSize', 10, 'Interpreter', 'tex', 'Box', 'on');
set(leg1, 'Color', 'w', 'TextColor', 'k', 'EdgeColor', 'k');
grid on;

% 子图 (b)：储能荷电状态 SoC 时序轨迹
subplot(2, 1, 2);
plot(0:T, SoC_val, '-bo', 'LineWidth', 1.6, 'MarkerSize', 5, 'MarkerFaceColor', [0.16, 0.44, 0.69], 'Color', [0.16, 0.44, 0.69]);
hold on;
yline(SoC_min * 100, '--k', 'LineWidth', 1.1);
yline(SoC_max * 100, '--r', 'LineWidth', 1.1);
set(gca, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'FontName', 'Times New Roman', 'FontSize', 10.5, 'LineWidth', 1.0, ...
    'Box', 'on', 'TickDir', 'in', 'XTick', 0:4:24, 'GridLineStyle', '--', 'GridAlpha', 0.3, 'GridColor', [0.4, 0.4, 0.4]);
xlim([0, 24]);
ylim([0, 128]);
xlabel('\fontname{宋体}时间 \fontname{Times New Roman}{\itt}\rm{/h}', 'FontSize', 11.5, 'Color', 'k', 'Interpreter', 'tex');
ylabel('\fontname{宋体}荷电状态 \fontname{Times New Roman}\rm{SoC}/%', 'FontSize', 11.5, 'Color', 'k', 'Interpreter', 'tex');
title('\fontname{宋体}(b) 储能电站荷电状态 \fontname{Times New Roman}\rm{SoC} \fontname{宋体}时序变化轨迹', ...
    'FontSize', 11.5, 'FontWeight', 'normal', 'Color', 'k', 'Interpreter', 'tex');
leg2 = legend({'\fontname{宋体}荷电状态 \fontname{Times New Roman}\rm{SoC}_{\itt}', ...
    '\fontname{宋体}下限 \fontname{Times New Roman}\rm{SoC}_{\rm{min}}', ...
    '\fontname{宋体}上限 \fontname{Times New Roman}\rm{SoC}_{\rm{max}}'}, ...
    'Location', 'north', 'Orientation', 'horizontal', 'FontSize', 10, 'Interpreter', 'tex', 'Box', 'on');
set(leg2, 'Color', 'w', 'TextColor', 'k', 'EdgeColor', 'k');
grid on;

% 默认自动导出高质量白底 PNG (600 dpi)、矢量 PDF 与 MATLAB 源文件 FIG
exportgraphics(fig1, 'Fig_Task2_SingleNode_Arbitrage.png', 'Resolution', 600, 'BackgroundColor', 'white');
exportgraphics(fig1, 'Fig_Task2_SingleNode_Arbitrage.pdf', 'ContentType', 'vector', 'BackgroundColor', 'white');
savefig(fig1, 'Fig_Task2_SingleNode_Arbitrage.fig');