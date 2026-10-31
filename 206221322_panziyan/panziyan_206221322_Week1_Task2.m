%% 任务二：单节点储能分时电价套利
% 潘子岩，206221322。功率为MW，能量容量为MWh，电价为元/MWh。
% 本任务采用统一设备参数，学号用于署名和文件命名。
Stu_ID = 206221322;
Student_Name = '潘子岩';
candidate_dirs = {fileparts(mfilename('fullpath')), pwd};
try
    candidate_dirs{end+1} = fileparts(matlab.desktop.editor.getActiveFilename);
catch
end
script_dir = '';
for k = 1:numel(candidate_dirs)
    if isfile(fullfile(candidate_dirs{k}, 'helpers', 'ess_live_setup.m'))
        script_dir = candidate_dirs{k};
        break
    end
end
assert(~isempty(script_dir), '作业目录中缺少helpers。');
addpath(fullfile(script_dir, 'helpers'), '-begin');
lesson = ess_live_setup();
profiles = load(fullfile(lesson.cases, 'profiles_24h.mat'));
T = profiles.T;
price_MWh = profiles.price_MWh(:);
price_kWh = profiles.price_kWh(:);
export_figures = true;
yalmip('clear');

%% 设备参数、能量平衡与互斥模型
P_rated = 2; % MW
E_rated = 2; % MWh
eta_ch = 0.90;
eta_dis = 0.95;
SoC_0 = 0.50;
SoC_min = 0.10;
SoC_max = 1.00;
dt = 1; % h
% SoC(t)=SoC(t-1)+(eta_ch*Pch(t)-Pdis(t)/eta_dis)*dt/E_rated。
% 初末SoC均为0.5。MILP以二进制变量保证同一时段不同时充放电；
% LP保留其余约束，去掉充放电互斥，用于比较松弛前后的最优收益。
LP = local_storage(price_MWh, P_rated, E_rated, eta_ch, eta_dis, ...
    SoC_0, SoC_min, SoC_max, dt, false);
MILP = local_storage(price_MWh, P_rated, E_rated, eta_ch, eta_dis, ...
    SoC_0, SoC_min, SoC_max, dt, true);
Comparison = table(["LP"; "MILP"], [LP.Revenue_Yuan; MILP.Revenue_Yuan], ...
    [LP.MaxSimultaneousPower_MW; MILP.MaxSimultaneousPower_MW], ...
    [LP.TerminalSoCError; MILP.TerminalSoCError], ...
    'VariableNames', {'Model', 'DailyRevenue_Yuan', ...
    'MaxSimultaneousPower_MW', 'TerminalSoCError'});
assert(abs(diff(Comparison.DailyRevenue_Yuan)) < 1e-5, 'LP/MILP收益不一致。');

%% 电价、充放电功率与荷电状态
view_hour = 19;
fig_arbitrage = ess_live_view('arbitrage', price_kWh, MILP.P_ch_MW, ...
    MILP.P_dis_MW, MILP.SoC, view_hour, dt, E_rated);
sgtitle(sprintf('%s %d | 储能分时电价套利', Student_Name, Stu_ID));

%% 额定功率和容量对日收益的影响
% 分别改变额定功率、额定容量；其余条件均保持不变。
P_values = [0.5; 1; 2; 4];
E_values = [1; 2; 4; 8];
P_revenue = zeros(size(P_values));
E_revenue = zeros(size(E_values));
for k = 1:numel(P_values)
    trial = local_storage(price_MWh, P_values(k), E_rated, eta_ch, eta_dis, ...
        SoC_0, SoC_min, SoC_max, dt, true);
    P_revenue(k) = trial.Revenue_Yuan;
end
for k = 1:numel(E_values)
    trial = local_storage(price_MWh, P_rated, E_values(k), eta_ch, eta_dis, ...
        SoC_0, SoC_min, SoC_max, dt, true);
    E_revenue(k) = trial.Revenue_Yuan;
end
PowerSensitivity = table(P_values, repmat(E_rated, size(P_values)), P_revenue, ...
    'VariableNames', {'Power_MW', 'Energy_MWh', 'DailyRevenue_Yuan'});
EnergySensitivity = table(repmat(P_rated, size(E_values)), E_values, E_revenue, ...
    'VariableNames', {'Power_MW', 'Energy_MWh', 'DailyRevenue_Yuan'});
assert(all(diff(P_revenue) >= -1e-5) && all(diff(E_revenue) >= -1e-5), ...
    '参数试验收益单调性未通过。');
fig_sensitivity = figure('Color', 'w', 'Position', [100 100 1040 440]);
if isprop(fig_sensitivity, 'Theme'), theme(fig_sensitivity, 'light'); end
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
plot(P_values, P_revenue, '-o', 'LineWidth', 1.8, 'Color', [0.10 0.45 0.70]);
xlabel('额定功率 / MW'); ylabel('日套利收益 / 元');
title(sprintf('额定容量固定为%g MWh', E_rated));
xticks(P_values); grid on; box on;
nexttile;
plot(E_values, E_revenue, '-s', 'LineWidth', 1.8, 'Color', [0.83 0.40 0.14]);
xlabel('额定能量容量 / MWh'); ylabel('日套利收益 / 元');
title(sprintf('额定功率固定为%g MW', P_rated));
xticks(E_values); grid on; box on;
sgtitle(sprintf('%s %d | 储能功率与容量参数试验', Student_Name, Stu_ID));
set(findall(fig_sensitivity, '-property', 'FontName'), 'FontName', 'PingFang SC');
set(findall(fig_sensitivity, 'Type', 'axes'), 'FontSize', 11);

%% 标准数据和两幅图导出
Hourly = table((1:T)', price_kWh, MILP.P_ch_MW, MILP.P_dis_MW, MILP.SoC, ...
    price_MWh.*(MILP.P_dis_MW-MILP.P_ch_MW)*dt, ...
    'VariableNames', {'Hour', 'Price_YuanPerKWh', 'Charge_MW', ...
    'Discharge_MW', 'SoC', 'Revenue_Yuan'});
Day2 = struct('StudentID', Stu_ID, 'StudentName', Student_Name, ...
    'Power_MW', P_rated, 'Energy_MWh', E_rated, 'EtaCharge', eta_ch, ...
    'EtaDischarge', eta_dis, 'SoC0', SoC_0, 'SoCMin', SoC_min, 'SoCMax', SoC_max, ...
    'TimeStep_h', dt, 'LP', LP, 'MILP', MILP, 'Comparison', Comparison, ...
    'Hourly', Hourly, 'PowerSensitivity', PowerSensitivity, ...
    'EnergySensitivity', EnergySensitivity);
writetable(Hourly, fullfile(script_dir, sprintf('Hourly_%d.csv', Stu_ID)));
writetable(Comparison, fullfile(script_dir, sprintf('LP_MILP_%d.csv', Stu_ID)));
writetable(PowerSensitivity, fullfile(script_dir, sprintf('PowerSensitivity_%d.csv', Stu_ID)));
writetable(EnergySensitivity, fullfile(script_dir, sprintf('EnergySensitivity_%d.csv', Stu_ID)));
summary_file = fullfile(script_dir, 'result_summary.mat');
if isfile(summary_file)
    save(summary_file, 'Day2', '-append');
else
    save(summary_file, 'Day2');
end
if export_figures
    ess_live_export(fig_arbitrage, script_dir, sprintf('Fig_Week1_Task2_Arbitrage_%d', Stu_ID));
    ess_live_export(fig_sensitivity, script_dir, sprintf('Fig_Week1_Task2_Sensitivity_%d', Stu_ID));
    for figure_format = {'png', 'pdf', 'fig'}
        copyfile(fullfile(script_dir, sprintf('Fig_Week1_Task2_Arbitrage_%d.%s', Stu_ID, figure_format{1})), ...
            fullfile(script_dir, sprintf('Fig_Week1_Task2_%d.%s', Stu_ID, figure_format{1})));
    end
end
Lesson_Stats = struct('Lesson', 2, 'Revenue_Yuan', MILP.Revenue_Yuan, ...
    'LP_MILP_Difference', abs(LP.Revenue_Yuan-MILP.Revenue_Yuan));
disp(Comparison);
disp(PowerSensitivity);
disp(EnergySensitivity);

function s = local_storage(price, Pmax, Emax, eta_ch, eta_dis, s0, smin, smax, dt, binary)
T = numel(price);
pc = sdpvar(T, 1); % 充电功率，MW
pd = sdpvar(T, 1); % 放电功率，MW
soc = sdpvar(T, 1);
C = [0 <= pc <= Pmax, 0 <= pd <= Pmax, smin <= soc <= smax, soc(T) == s0];
C = [C, soc == [s0; soc(1:end-1)] + (eta_ch*pc-pd/eta_dis)*dt/Emax];
if binary
    u = binvar(T, 1);
    C = [C, pc <= u*Pmax, pd <= (1-u)*Pmax];
    kind = 'MILP';
else
    kind = 'LP';
end
% 最小化购电净支出，等价于最大化放电收入减充电支出。
obj = sum(price(:).*(pc-pd))*dt;
[sol, solver, seconds] = ess_live_solve(C, obj, kind);
assert(sol.problem == 0, '储能优化求解失败。');
s = struct('Model', kind, 'Solver', solver, 'SolveSeconds', seconds, ...
    'P_ch_MW', value(pc), 'P_dis_MW', value(pd), 'SoC', value(soc), ...
    'Revenue_Yuan', -value(obj));
s.MaxSimultaneousPower_MW = max(min(s.P_ch_MW, s.P_dis_MW));
s.TerminalSoCError = abs(s.SoC(end)-s0);
s.MaxEnergyError_MWh = max(abs(Emax*(s.SoC-[s0; s.SoC(1:end-1)]) ...
    - (eta_ch*s.P_ch_MW-s.P_dis_MW/eta_dis)*dt));
s.PowerLimitViolation_MW = max([0; -s.P_ch_MW; -s.P_dis_MW; ...
    s.P_ch_MW-Pmax; s.P_dis_MW-Pmax]);
s.ChargeEnergy_MWh = sum(s.P_ch_MW)*dt;
s.DischargeEnergy_MWh = sum(s.P_dis_MW)*dt;
assert(s.TerminalSoCError < 1e-6 && s.MaxEnergyError_MWh < 1e-6 ...
    && s.PowerLimitViolation_MW < 1e-6, '储能约束不满足。');
assert(min(s.SoC) >= smin-1e-6 && max(s.SoC) <= smax+1e-6, 'SoC越界。');
assert(abs(s.DischargeEnergy_MWh-eta_ch*eta_dis*s.ChargeEnergy_MWh) < 1e-6, ...
    '充放电能量平衡不满足。');
if binary
    s.IntegerError = max(abs(value(u)-round(value(u))));
    assert(s.MaxSimultaneousPower_MW < 1e-6 && s.IntegerError < 1e-6, ...
        '充放电互斥约束不满足。');
end
end
