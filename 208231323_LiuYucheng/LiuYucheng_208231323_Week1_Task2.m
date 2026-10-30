%% ========================================================================
%  第一周 任务二：单节点储能分时电价套利与 LP / MILP 对比
%  姓名：刘宇成      学号：208231323      班级：储能231
%  算例：独立储能电站（不计网络潮流），2.0 MW / 2.0 MWh
%        eta_ch = 0.90，eta_dis = 0.95，SoC in [0.10, 1.00]，初末 SoC = 0.50
%  电价：江苏省工商业分时电价（profiles_24h.mat 内置）
%  交付：Fig_Week1_Task2_208231323.png / .pdf / .fig、result_summary.mat
%% ========================================================================
clear; clc; close all;

%% 1. 课程资源路径（换电脑时只需修改这一行）
mat_dir = "C:\Users\Administrator\Desktop\matlab\ESS-Course-Materials-main\ESS-Course-Materials-main";
if ~isfolder(mat_dir)
    mat_dir = uigetdir(pwd, '请选择本机 ESS-Course-Materials 仓库根目录');
end
addpath(fullfile(mat_dir, 'cases'));
out_dir = fileparts(mfilename('fullpath'));
if isempty(out_dir)
    out_dir = pwd;
end

%% 2. 场景参数
Stu_ID   = 208231323;
profiles = load(fullfile(mat_dir, 'cases', 'profiles_24h.mat'));
T        = profiles.T;
price_MWh = profiles.price_MWh(:);
price_kWh = profiles.price_kWh(:);
dt        = 1;

P_rated  = 2.0;      % MW
E_rated  = 2.0;      % MWh
eta_ch   = 0.90;
eta_dis  = 0.95;
SoC_0    = 0.50;
SoC_min  = 0.10;
SoC_max  = 1.00;

%% 3. 理论手算：充入 1 MWh 后可售出的电量
E_charge   = 1.0;                                   % 充入电量 MWh
E_stored   = E_charge * eta_ch;                     % 存储到电池中的电量
E_sellable = E_stored * eta_dis;                    % 之后可放出的电量
fprintf('\n================ 任务二：理论手算 ================\n');
fprintf('充入电量 %.3f MWh -> 存储 %.3f MWh -> 可售出 %.4f MWh\n', ...
    E_charge, E_stored, E_sellable);
fprintf('单次充放（谷充峰放）净收益 = %.4f*%.1f - %.1f*%.1f = %.2f 元\n', ...
    E_sellable, price_MWh(16), E_charge, price_MWh(1), ...
    E_sellable * price_MWh(16) - E_charge * price_MWh(1));
fprintf('往返效率 = %.4f\n', eta_ch * eta_dis);
fprintf('=================================================\n');

%% 4. 求解 LP（允许同时充放电）与 MILP（充放电互斥）
[rev_LP,  pc_LP,  pd_LP,  soc_LP,  ov_LP]  = local_solve(price_MWh, P_rated, E_rated, ...
    eta_ch, eta_dis, SoC_0, SoC_min, SoC_max, dt, false);
[rev_MILP, pc_M, pd_M, soc_M, ov_M]        = local_solve(price_MWh, P_rated, E_rated, ...
    eta_ch, eta_dis, SoC_0, SoC_min, SoC_max, dt, true);

Cmp = table(["LP"; "MILP"], [rev_LP; rev_MILP], [ov_LP; ov_M], ...
    [abs(soc_LP(end) - SoC_0); abs(soc_M(end) - SoC_0)], ...
    'VariableNames', {'Model', 'DailyRevenue_Yuan', 'MaxSimultaneousPower_MW', 'TerminalSoCError'});
disp('--- 保留 / 取消充放电互斥变量 u_t 的对比 ---');
disp(Cmp);

fprintf('LP 比 MILP 多出收益：%.4f 元（%.2f%%），原因是 LP 松弛允许同一时段同时充放电。\n', ...
    rev_LP - rev_MILP, 100 * (rev_LP - rev_MILP) / abs(rev_MILP));

%% 5. 参数灵敏度：分别改变额定功率与额定容量
P_list = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0];
E_list = [1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0];

rev_P = zeros(size(P_list));
for k = 1:numel(P_list)
    rev_P(k) = local_solve(price_MWh, P_list(k), E_rated, eta_ch, eta_dis, ...
        SoC_0, SoC_min, SoC_max, dt, true);
end

rev_E = zeros(size(E_list));
for k = 1:numel(E_list)
    rev_E(k) = local_solve(price_MWh, P_rated, E_list(k), eta_ch, eta_dis, ...
        SoC_0, SoC_min, SoC_max, dt, true);
end

fprintf('\n--- 额定功率灵敏度（E_rated = %.1f MWh）---\n', E_rated);
disp(table(P_list', rev_P', 'VariableNames', {'P_rated_MW', 'DailyRevenue_Yuan'}));
fprintf('--- 额定容量灵敏度（P_rated = %.1f MW）---\n', P_rated);
disp(table(E_list', rev_E', 'VariableNames', {'E_rated_MWh', 'DailyRevenue_Yuan'}));

%% 6. 绘图：电价—充放电功率—荷电状态时序图
set(groot, 'defaultAxesFontName', 'Times New Roman');
set(groot, 'defaultTextFontName', 'Times New Roman');

fig = figure('Name', '第一周任务二：储能分时套利', 'Color', 'w', 'Position', [80, 60, 880, 900]);
if isprop(fig, 'Theme'), theme(fig, 'light'); end

% (a) 分时电价
subplot(4, 2, [1, 2]);
stairs(1:T, price_kWh, '-', 'Color', [0.85, 0.35, 0.15], 'LineWidth', 1.8);
xlim([0.5, T + 0.5]); ylim([0.2, 1.30]);
set(gca, 'Box', 'on', 'TickDir', 'in', 'XTick', 0:4:24, 'XGrid', 'on');
xlabel('时间 {\itt} / h', 'FontSize', 10.5);
ylabel('电价 / (元·kWh^{-1})', 'FontSize', 10.5);
title(sprintf('(a) 江苏省工商业分时电价（谷 %.3f / 平 %.3f / 峰 %.3f 元·kWh^{-1}）', ...
    min(price_kWh), median(price_kWh), max(price_kWh)), 'FontSize', 10.8, 'FontWeight', 'normal');

% (b) 储能净充放电功率
subplot(4, 2, [3, 4]);
plot(1:T, pd_M - pc_M, '-o', 'Color', [0.15, 0.45, 0.70], 'LineWidth', 1.6, ...
    'MarkerSize', 5, 'MarkerFaceColor', [0.15, 0.45, 0.70]);
yline(0, '--k', 'LineWidth', 0.9);
xlim([0.5, T + 0.5]); ylim([-2.6, 2.6]);
set(gca, 'Box', 'on', 'TickDir', 'in', 'XTick', 0:4:24, 'XGrid', 'on', 'YGrid', 'on');
xlabel('时间 {\itt} / h', 'FontSize', 10.5);
ylabel('净放电功率 {\itP}_{ess} / MW', 'FontSize', 10.5);
title('(b) 储能净放电功率（放电为正、充电为负）', 'FontSize', 10.8, 'FontWeight', 'normal');

% (c) 荷电状态
subplot(4, 2, [5, 6]);
hold on;
plot(1:T, soc_LP' * 100, '--s', 'Color', [0.55, 0.55, 0.55], 'LineWidth', 1.3, 'MarkerSize', 4);
plot(1:T, soc_M' * 100, '-o', 'Color', [0.15, 0.45, 0.70], 'LineWidth', 1.8, 'MarkerSize', 5, ...
    'MarkerFaceColor', [0.15, 0.45, 0.70]);
yline(SoC_min * 100, ':k', 'LineWidth', 1.1);
yline(SoC_max * 100, ':k', 'LineWidth', 1.1);
xlim([1, T]); ylim([8, 102]);
set(gca, 'Box', 'on', 'TickDir', 'in', 'XTick', 0:4:24, 'XColor', 'k', 'YColor', 'k');
xlabel('时间 {\itt} / h', 'FontSize', 10.5);
ylabel('荷电状态 SoC / %', 'FontSize', 10.5);
legend({'LP（无互斥）', 'MILP（充放电互斥）'}, 'Location', 'southeast', 'FontSize', 9);
title('(c) 荷电状态时序（LP 与 MILP 对比）', 'FontSize', 10.8, 'FontWeight', 'normal');

% (d) 额定功率灵敏度
subplot(4, 2, 7);
plot(P_list, rev_P, '-o', 'Color', [0.15, 0.45, 0.70], 'LineWidth', 1.7, ...
    'MarkerFaceColor', [0.15, 0.45, 0.70], 'MarkerSize', 5);
set(gca, 'Box', 'on', 'TickDir', 'in', 'XColor', 'k', 'YColor', 'k');
xlabel('额定功率 {\itP}^{rated} / MW', 'FontSize', 10.5);
ylabel('日收益 / 元', 'FontSize', 10.5);
title(sprintf('(d) 功率灵敏度（{\\itE}^{rated} = %.1f MWh）', E_rated), ...
    'FontSize', 10.8, 'FontWeight', 'normal');
grid on;

% (e) 额定容量灵敏度
subplot(4, 2, 8);
plot(E_list, rev_E, '-s', 'Color', [0.85, 0.45, 0.20], 'LineWidth', 1.7, ...
    'MarkerFaceColor', [0.85, 0.45, 0.20], 'MarkerSize', 5);
set(gca, 'Box', 'on', 'TickDir', 'in', 'XColor', 'k', 'YColor', 'k');
xlabel('额定容量 {\itE}^{rated} / MWh', 'FontSize', 10.5);
ylabel('日收益 / 元', 'FontSize', 10.5);
title(sprintf('(e) 容量灵敏度（{\\itP}^{rated} = %.1f MW）', P_rated), ...
    'FontSize', 10.8, 'FontWeight', 'normal');
grid on;

%% 7. 导出
exportgraphics(fig, fullfile(out_dir, sprintf('Fig_Week1_Task2_%d.png', Stu_ID)), ...
    'Resolution', 600, 'BackgroundColor', 'white');
exportgraphics(fig, fullfile(out_dir, sprintf('Fig_Week1_Task2_%d.pdf', Stu_ID)), ...
    'ContentType', 'vector', 'BackgroundColor', 'white');
savefig(fig, fullfile(out_dir, sprintf('Fig_Week1_Task2_%d.fig', Stu_ID)));

%% 8. 写入 result_summary.mat
res_file = fullfile(out_dir, 'result_summary.mat');
if isfile(res_file)
    S = load(res_file);  Result = S.Result;
else
    Result = struct();
end
Result.StuID = Stu_ID;
Result.Task2 = struct( ...
    'P_rated_MW', P_rated, 'E_rated_MWh', E_rated, ...
    'eta_ch', eta_ch, 'eta_dis', eta_dis, ...
    'HandCalc_Sellable_MWh', E_sellable, ...
    'LP_Revenue_Yuan',   rev_LP, ...
    'MILP_Revenue_Yuan', rev_MILP, ...
    'MaxSimultaneousPower_LP_MW',   ov_LP, ...
    'MaxSimultaneousPower_MILP_MW', ov_M, ...
    'P_sweep_MW', P_list, 'P_sweep_Revenue_Yuan', rev_P, ...
    'E_sweep_MWh', E_list, 'E_sweep_Revenue_Yuan', rev_E );
save(res_file, 'Result');
fprintf('结果已保存：%s\n', res_file);

%% ======================= 局部函数 =======================
function [revenue, p_ch, p_dis, soc, overlap] = local_solve(price, P_r, E_r, ...
        eta_ch, eta_dis, soc0, soc_min, soc_max, dt, use_binary)
% 单节点储能日前套利：min 购电成本（等价于 max 净售电收益）
T = numel(price);
p_ch  = sdpvar(T, 1, 'full');
p_dis = sdpvar(T, 1, 'full');
soc   = sdpvar(T, 1, 'full');

c = [0 <= p_ch <= P_r, 0 <= p_dis <= P_r, ...
     soc_min <= soc <= soc_max, soc(T) == soc0];

if use_binary
    u = binvar(T, 1, 'full');
    c = [c, p_ch <= u * P_r, p_dis <= (1 - u) * P_r]; %#ok<AGROW>
end

soc_prev = [soc0; soc(1:end-1)];
c = [c, soc == soc_prev + (eta_ch * p_ch * dt - p_dis * dt / eta_dis) / E_r];

obj = sum(price .* (p_ch - p_dis)) * dt;   % 最小化净购电成本

ops = sdpsettings('solver', 'mosek', 'verbose', 0);
sol = optimize(c, obj, ops);
assert(sol.problem == 0, '套利模型求解失败：%s', yalmiperror(sol.problem));

revenue = -value(obj);
p_ch    = value(p_ch);
p_dis   = value(p_dis);
soc     = value(soc);
overlap = max(min(p_ch, p_dis));
end
