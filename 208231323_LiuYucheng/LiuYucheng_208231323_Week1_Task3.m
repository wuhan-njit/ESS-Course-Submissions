%% ========================================================================
%  第一周 任务三：含充放电互斥约束的配电网日前 MISOCP 调度（多目标对比）
%  姓名：刘宇成      学号：208231323      班级：储能231
%  算例：case_nongcun（49 节点农村配电网），alpha = 1.046
%  设备：节点 {4, 9, 14} 各 1.5 MW / 3.0 MWh 储能，SoC in [0.20, 0.80]；
%        同节点各 1.2 MW 光伏（可弃光）
%  本人分配目标：模型 A（最大化新能源消纳，含网损惩罚 rho = 1e-2）
%  对比目标：A / B（最小化网损）/ C（最小化购电成本）
%  交付：Fig_Week1_Task3_208231323.png / .pdf / .fig、result_summary.mat
%% ========================================================================
clear; clc; close all;
yalmip('clear');

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

%% 2. 学号映射与设备参数
Stu_ID   = 208231323;
XY       = mod(Stu_ID, 100);
X_digit  = floor(XY / 10);
Y_digit  = mod(XY, 10);
alpha    = 1 + 0.002 * XY;
case_name = 'case_nongcun';          % Y_digit = 3

if ismember(X_digit, [0 1 2])
    model_type = 'A';  ess_buses = [4 9 14];
elseif ismember(X_digit, [3 4 5])
    model_type = 'B';  ess_buses = [5 11 16];
else
    model_type = 'C';  ess_buses = [6 13 17];
end
pv_buses = ess_buses;

P_ess_rated_MW  = 1.5;
E_ess_rated_MWh = 3.0;
P_pv_peak_MW    = 1.2;
eta_ch  = 0.90;
eta_dis = 0.95;
SoC_min = 0.20;
SoC_max = 0.80;
SoC_0   = 0.50;

fprintf('学号 %d | 算例 %s | 本人目标 %s | alpha = %.3f | 储能/光伏节点 %s\n', ...
    Stu_ID, case_name, model_type, alpha, mat2str(ess_buses));

%% 3. 本人目标（模型 A）求解
t0 = tic;
R_A = local_dispatch(model_type, alpha, case_name, ess_buses, pv_buses, ...
    P_ess_rated_MW, E_ess_rated_MWh, P_pv_peak_MW, eta_ch, eta_dis, ...
    SoC_min, SoC_max, SoC_0, mat_dir);
fprintf('\n模型 %s 求解完成，用时 %.1f s，求解器 %s\n', model_type, toc(t0), R_A.solver);

%% 4. 多目标对比：A / B / C
models = {'A', 'B', 'C'};
R_all  = cell(1, 3);
R_all{1} = R_A;
for k = 2:3
    fprintf('\n---- 正在求解模型 %s ----\n', models{k});
    R_all{k} = local_dispatch(models{k}, alpha, case_name, ess_buses, pv_buses, ...
        P_ess_rated_MW, E_ess_rated_MWh, P_pv_peak_MW, eta_ch, eta_dis, ...
        SoC_min, SoC_max, SoC_0, mat_dir);
end

Cmp = table( ...
    string(models'), ...
    cellfun(@(r) r.Obj_Value,        R_all)', ...
    cellfun(@(r) r.Curtail_MWh,      R_all)', ...
    cellfun(@(r) r.Loss_MWh,         R_all)', ...
    cellfun(@(r) r.Cost_Yuan,        R_all)', ...
    cellfun(@(r) r.SOCP_Gap,         R_all)', ...
    cellfun(@(r) r.MaxVErr_pu,       R_all)', ...
    'VariableNames', {'Model', 'Obj_Value', 'Curtail_MWh', 'Loss_MWh', ...
                      'Cost_Yuan', 'SOCP_Gap', 'MaxVErr_pu'});
disp('--- 多目标 A / B / C 对比 ---');
disp(Cmp);

%% 5. 二阶锥松弛间隙手算校验（U=1.00, L=0.02, P=0.10, Q=0.05）
U_h = 1.00; L_h = 0.02; P_h = 0.10; Q_h = 0.05;
lhs  = sqrt((2*P_h)^2 + (2*Q_h)^2 + (L_h - U_h)^2);
rhs  = L_h + U_h;
g_hand = rhs - lhs;
fprintf('\n================ 二阶锥松弛间隙手算 ================\n');
fprintf('sqrt((2P)^2+(2Q)^2+(L-U)^2) = %.6f,  L+U = %.6f\n', lhs, rhs);
fprintf('松弛间隙 g = (L+U) - sqrt(...) = %.6f\n', g_hand);
fprintf('约束取等（g = 0）表示松弛紧致；g > 0 表示存在松弛间隙。\n');
fprintf('===================================================\n');

%% 6. 绘图：储能充放电、SoC 与节点电压曲线（本人目标 A）
set(groot, 'defaultAxesFontName', 'Times New Roman');
set(groot, 'defaultTextFontName', 'Times New Roman');
T = numel(R_A.price);

fig = figure('Name', '第一周任务三：日前 MISOCP 调度结果', 'Color', 'w', 'Position', [70, 50, 860, 880]);
if isprop(fig, 'Theme'), theme(fig, 'light'); end

colors = [0.00, 0.45, 0.74; 0.85, 0.33, 0.10; 0.47, 0.67, 0.19];
styles = {'-o', '-s', '-^'};

% (a) 储能净充放电功率
subplot(3, 1, 1);
hold on;
for k = 1:numel(ess_buses)
    plot(1:T, R_A.P_net_MW(:, k), styles{k}, 'Color', colors(k, :), ...
        'LineWidth', 1.6, 'MarkerSize', 5, 'MarkerFaceColor', colors(k, :));
end
yline(0, '--k', 'LineWidth', 0.9);
xlim([1, T]); xticks(0:4:24);
set(gca, 'Box', 'on', 'TickDir', 'in', 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'XGrid', 'on', 'YGrid', 'on');
xlabel('时间 {\itt} / h', 'FontSize', 10.5);
ylabel('净放电功率 {\itP}_{ess} / MW', 'FontSize', 10.5);
legend(arrayfun(@(b) sprintf('节点 %d', b), ess_buses, 'UniformOutput', false), ...
    'Location', 'north', 'Orientation', 'horizontal', 'FontSize', 9);
title(sprintf('(a) 三个接入节点储能日前净充放电功率（模型 %s，放电为正）', model_type), ...
    'FontSize', 11, 'FontWeight', 'normal');

% (b) 荷电状态
subplot(3, 1, 2);
hold on;
for k = 1:numel(ess_buses)
    plot(1:T, R_A.SoC(:, k) * 100, styles{k}, 'Color', colors(k, :), ...
        'LineWidth', 1.6, 'MarkerSize', 5, 'MarkerFaceColor', colors(k, :));
end
yline(SoC_min * 100, ':k', 'LineWidth', 1.1);
yline(SoC_max * 100, ':r', 'LineWidth', 1.1);
xlim([1, T]); ylim([10, 95]); xticks(0:4:24);
set(gca, 'Box', 'on', 'TickDir', 'in', 'Color', 'w', 'XColor', 'k', 'YColor', 'k');
xlabel('时间 {\itt} / h', 'FontSize', 10.5);
ylabel('荷电状态 SoC / %', 'FontSize', 10.5);
legend(arrayfun(@(b) sprintf('节点 %d', b), ess_buses, 'UniformOutput', false), ...
    'Location', 'north', 'Orientation', 'horizontal', 'FontSize', 9);
title(sprintf('(b) 储能荷电状态（SoC \\in [%.0f%%, %.0f%%]）', SoC_min*100, SoC_max*100), ...
    'FontSize', 11, 'FontWeight', 'normal');

% (c) 节点电压曲线
subplot(3, 1, 3);
hold on;
plot(1:T, R_A.V_ac', '-', 'Color', [0.72, 0.74, 0.78], 'LineWidth', 0.6);
[~, ii] = min(R_A.V_ac(:));
[nb, nh] = ind2sub(size(R_A.V_ac), ii);
plot(1:T, R_A.V_ac(nb, :), '-', 'Color', [0.85, 0.20, 0.15], 'LineWidth', 1.8);
yline(0.95, '--k', 'LineWidth', 1.0);
yline(1.05, '--k', 'LineWidth', 1.0);
plot(nh, min(R_A.V_ac(:)), 'p', 'MarkerSize', 9, 'MarkerFaceColor', [0.85, 0.20, 0.15], 'MarkerEdgeColor', 'k');
xlim([1, T]); ylim([0.93, 1.06]); xticks(0:4:24);
set(gca, 'Box', 'on', 'TickDir', 'in', 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'XGrid', 'on', 'YGrid', 'on');
xlabel('时间 {\itt} / h', 'FontSize', 10.5);
ylabel('节点电压 {\itV} / p.u.', 'FontSize', 10.5);
legend({'全部节点', sprintf('节点 %d（最低 %.4f）', nb, min(R_A.V_ac(:)))}, ...
    'Location', 'southeast', 'FontSize', 9);
title('(c) 调度后 MATPOWER 交流潮流回代的全网节点电压', 'FontSize', 11, 'FontWeight', 'normal');

%% 7. 导出
exportgraphics(fig, fullfile(out_dir, sprintf('Fig_Week1_Task3_%d.png', Stu_ID)), ...
    'Resolution', 600, 'BackgroundColor', 'white');
exportgraphics(fig, fullfile(out_dir, sprintf('Fig_Week1_Task3_%d.pdf', Stu_ID)), ...
    'ContentType', 'vector', 'BackgroundColor', 'white');
savefig(fig, fullfile(out_dir, sprintf('Fig_Week1_Task3_%d.fig', Stu_ID)));

%% 8. 写入 result_summary.mat
res_file = fullfile(out_dir, 'result_summary.mat');
if isfile(res_file)
    S = load(res_file);  Result = S.Result;
else
    Result = struct();
end
Result.StuID = Stu_ID;
Result.Task3 = struct( ...
    'model_type', model_type, 'ess_buses', ess_buses, ...
    'P_ess_MW', P_ess_rated_MW, 'E_ess_MWh', E_ess_rated_MWh, ...
    'P_pv_MW', P_pv_peak_MW, ...
    'ConeGap_HandCalc', g_hand, ...
    'Model_A', R_all{1}, 'Model_B', R_all{2}, 'Model_C', R_all{3}, ...
    'Comparison', Cmp );
save(res_file, 'Result');
fprintf('结果已保存：%s\n', res_file);

%% ======================= 局部函数 =======================
function R = local_dispatch(model_type, alpha, case_name, ess_buses, pv_buses, ...
        P_ess_MW, E_ess_MWh, P_pv_MW, eta_ch, eta_dis, SoC_min, SoC_max, SoC_0, mat_dir)
% 固定容量配电网日前 MISOCP 调度：DistFlow 二阶锥松弛 + 充放电互斥
profiles = load(fullfile(mat_dir, 'cases', 'profiles_24h.mat'));
T = profiles.T;
price_MWh = profiles.price_MWh(:);
load_curve = profiles.load_curve_pu(:);
pv_curve   = profiles.pv_curve_pu(:);

mpc = loadcase(case_name);
Sbase = mpc.baseMVA;
N_bus = size(mpc.bus, 1);
N_br  = size(mpc.branch, 1);
N_ess = numel(ess_buses);
N_pv  = numel(pv_buses);

fbus = mpc.branch(:, 1);
tbus = mpc.branch(:, 2);
r_br = mpc.branch(:, 3);
x_br = mpc.branch(:, 4);

Pd_pu = (mpc.bus(:, 3) * alpha / Sbase) * load_curve';
Qd_pu = (mpc.bus(:, 4) * alpha / Sbase) * load_curve';
P_pv_max_pu = (P_pv_MW / Sbase) * repmat(pv_curve', N_pv, 1);

P_ess_rated_pu = P_ess_MW / Sbase;
E_ess_rated_pu = E_ess_MWh / Sbase;

%% 决策变量
U_bus  = sdpvar(N_bus, T, 'full');
L_br   = sdpvar(N_br,  T, 'full');
P_br   = sdpvar(N_br,  T, 'full');
Q_br   = sdpvar(N_br,  T, 'full');
P_grid = sdpvar(1,     T, 'full');
Q_grid = sdpvar(1,     T, 'full');
P_ch   = sdpvar(N_ess, T, 'full');
P_dis  = sdpvar(N_ess, T, 'full');
u_ch   = binvar(N_ess, T, 'full');
SoC    = sdpvar(N_ess, T, 'full');
P_pv   = sdpvar(N_pv,  T, 'full');

%% 约束
Constraints = [];
Constraints = [Constraints, 0 <= P_ch  <= P_ess_rated_pu * u_ch];
Constraints = [Constraints, 0 <= P_dis <= P_ess_rated_pu * (1 - u_ch)];
Constraints = [Constraints, SoC_min <= SoC <= SoC_max];
Constraints = [Constraints, SoC(:, T) == SoC_0];
Constraints = [Constraints, 0 <= P_pv <= P_pv_max_pu];

for t = 1:T
    if t == 1
        soc_prev = repmat(SoC_0, N_ess, 1);
    else
        soc_prev = SoC(:, t - 1);
    end
    Constraints = [Constraints, SoC(:, t) == soc_prev + ...
        (eta_ch * P_ch(:, t) - P_dis(:, t) / eta_dis) / E_ess_rated_pu]; %#ok<AGROW>
end

A_from  = sparse(fbus, 1:N_br, 1, N_bus, N_br);
A_to    = sparse(tbus, 1:N_br, 1, N_bus, N_br);
A_ess   = sparse(ess_buses, 1:N_ess, 1, N_bus, N_ess);
A_pv    = sparse(pv_buses,  1:N_pv,  1, N_bus, N_pv);
A_slack = sparse(1, 1, 1, N_bus, 1);

P_loss_br = diag(r_br) * L_br;
Q_loss_br = diag(x_br) * L_br;

Constraints = [Constraints, A_to * (P_br - P_loss_br) - A_from * P_br + ...
    A_slack * P_grid + A_pv * P_pv + A_ess * (P_dis - P_ch) == Pd_pu];
Constraints = [Constraints, A_to * (Q_br - Q_loss_br) - A_from * Q_br + ...
    A_slack * Q_grid == Qd_pu];

Constraints = [Constraints, U_bus(1, :) == 1.0];
Constraints = [Constraints, (0.95^2) <= U_bus(2:end, :) <= (1.05^2)];
Constraints = [Constraints, L_br >= 0];

for b = 1:N_br
    i = fbus(b);  j = tbus(b);
    Constraints = [Constraints, U_bus(j, :) == U_bus(i, :) - ...
        2 * (r_br(b) * P_br(b, :) + x_br(b) * Q_br(b, :)) + ...
        (r_br(b)^2 + x_br(b)^2) * L_br(b, :)]; %#ok<AGROW>
    for t = 1:T
        Constraints = [Constraints, cone([2 * P_br(b, t); 2 * Q_br(b, t); ...
            L_br(b, t) - U_bus(i, t)], L_br(b, t) + U_bus(i, t))]; %#ok<AGROW>
    end
end

%% 目标函数
Total_Loss_MWh    = Sbase * sum(sum(P_loss_br));
Total_Curtail_MWh = Sbase * sum(sum(P_pv_max_pu - P_pv));
Total_Cost_Yuan   = sum((Sbase * P_grid') .* price_MWh);

if strcmp(model_type, 'A')
    Objective = Total_Curtail_MWh + 1e-2 * Total_Loss_MWh;
elseif strcmp(model_type, 'B')
    Objective = Total_Loss_MWh + 1e-4 * sum(sum(P_ch + P_dis));
else
    Objective = Total_Cost_Yuan;
end

%% 求解（MISOCP：MOSEK / Gurobi）
solver_candidates = {};
if exist('mosekopt', 'file') ~= 0, solver_candidates{end+1} = 'mosek';  end %#ok<AGROW>
if exist('gurobi',   'file') ~= 0, solver_candidates{end+1} = 'gurobi'; end %#ok<AGROW>
assert(~isempty(solver_candidates), '含互斥二进制变量与二阶锥约束，需配置 MOSEK 或 Gurobi。');

solver_ok = false;
for k = 1:numel(solver_candidates)
    solver_name = solver_candidates{k};
    ops = sdpsettings('solver', solver_name, 'verbose', 0, 'savesolveroutput', 0);
    if strcmp(solver_name, 'mosek')
        ops.mosek.MSK_DPAR_MIO_MAX_TIME = 600;
        ops.mosek.MSK_DPAR_MIO_TOL_REL_GAP = 1e-6;
    else
        ops.gurobi.TimeLimit = 300;
        ops.gurobi.MIPGap    = 1e-6;
    end
    sol = optimize(Constraints, Objective, ops);
    if sol.problem == 0
        solver_ok = true;
        break;
    end
    fprintf('求解器 %s 失败：%s\n', solver_name, sol.info);
end
assert(solver_ok, 'MISOCP 求解失败。');

%% 结果提取
U_v   = value(U_bus);
L_v   = value(L_br);
P_v   = value(P_br);
Q_v   = value(Q_br);
Pch_v = value(P_ch);
Pdis_v = value(P_dis);
SoC_v = value(SoC);
Ppv_v = value(P_pv);

SOCP_Gap = max(max(abs(L_v .* U_v(fbus, :) - (P_v.^2 + Q_v.^2))));
V_socp   = sqrt(U_v);

% MATPOWER 交流潮流回代校验
mpopt = mpoption('verbose', 0, 'out.all', 0);
V_ac = zeros(N_bus, T);
Ploss_ac = 0;
P_net_ess_MW = Sbase * (Pdis_v - Pch_v);
P_pv_MW_val  = Sbase * Ppv_v;
for t = 1:T
    mpc_t = mpc;
    mpc_t.bus(:, 3) = Pd_pu(:, t) * Sbase;
    mpc_t.bus(:, 4) = Qd_pu(:, t) * Sbase;
    mpc_t.bus(pv_buses,  3) = mpc_t.bus(pv_buses,  3) - P_pv_MW_val(:, t);
    mpc_t.bus(ess_buses, 3) = mpc_t.bus(ess_buses, 3) - P_net_ess_MW(:, t);
    res_t = runpf(mpc_t, mpopt);
    assert(res_t.success == 1, '第 %d 时段交流潮流未收敛。', t);
    V_ac(:, t) = res_t.bus(:, 8);
    Ploss_ac   = Ploss_ac + sum(real(get_losses(res_t)));
end
MaxVErr = max(max(abs(V_socp - V_ac)));

R = struct( ...
    'model',        model_type, ...
    'solver',       solver_name, ...
    'Obj_Value',    value(Objective), ...
    'Curtail_MWh',  value(Total_Curtail_MWh), ...
    'Loss_MWh',     value(Total_Loss_MWh), ...
    'Cost_Yuan',    value(Total_Cost_Yuan), ...
    'Loss_AC_MWh',  Ploss_ac, ...
    'SOCP_Gap',     SOCP_Gap, ...
    'MaxVErr_pu',   MaxVErr, ...
    'P_net_MW',     P_net_ess_MW', ...
    'SoC',          SoC_v', ...
    'V_ac',         V_ac, ...
    'price',        price_MWh );

fprintf('模型 %s：弃光 %.4f MWh | 网损 %.4f MWh | 购电成本 %.2f 元 | 锥间隙 %.2e | AC 电压偏差 %.2e p.u.\n', ...
    model_type, R.Curtail_MWh, R.Loss_MWh, R.Cost_Yuan, R.SOCP_Gap, R.MaxVErr_pu);
end
