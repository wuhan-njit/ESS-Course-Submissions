%% 潘子岩 206221322：配电网储能日前优化调度
candidate_dirs={fileparts(mfilename('fullpath')),pwd};
try,candidate_dirs{end+1}=fileparts(matlab.desktop.editor.getActiveFilename);catch,end
script_dir='';
for kk=1:numel(candidate_dirs)
 if isfile(fullfile(candidate_dirs{kk},'helpers','ess_live_setup.m')),script_dir=candidate_dirs{kk};break;end
end
assert(~isempty(script_dir),'请从本作业目录运行。');
addpath(fullfile(script_dir,'helpers'));
lesson = ess_live_setup();
export_figures = true;

Stu_ID = 206221322;
XY=mod(Stu_ID,100);
X_digit=floor(XY/10); Y_digit=mod(XY,10);
alpha=1+0.002*XY;
if ismember(Y_digit,[0 1 2 3])
    case_name='case_nongcun';
elseif ismember(Y_digit,[4 5 6])
    case_name='case_chengshi_A';
else
    case_name='case_kaifaqu_A';
end
if ismember(X_digit,[0 1 2])
    study_buses=[4 9 14]; model_type='A';
elseif ismember(X_digit,[3 4 5])
    study_buses=[5 11 16]; model_type='B';
else
    study_buses=[6 13 17]; model_type='C';
end
assigned_objective=model_type;
profiles=load(fullfile(lesson.cases,'profiles_24h.mat'));
T=profiles.T; dt=1;
load_curve_pu=profiles.load_curve_pu; pv_curve_pu=profiles.pv_curve_pu;
price_MWh=profiles.price_MWh; price_kWh=profiles.price_kWh;
disp(table(Stu_ID,string(case_name),alpha,string(model_type),string(mat2str(study_buses)),...
    'VariableNames',{'StudentID','Case','LoadMultiplier','AssignedObjective','StudyNodes'}));
mpc=loadcase(case_name);
ess_buses=study_buses;pv_buses=ess_buses;
yalmip('clear');

override_objective = false;
objective_number = 1;
objective_names='ABC';
if override_objective
 model_type=objective_names(objective_number);
else
 default_objective=1+(X_digit>=3)+(X_digit>=6);
 model_type=objective_names(default_objective);
end
disp(table(string(model_type),'VariableNames',{'SelectedObjective'}));

Sbase = mpc.baseMVA;
N_bus = size(mpc.bus, 1);
N_br  = size(mpc.branch, 1);
N_ess = length(ess_buses);
N_pv  = length(pv_buses);
fbus = mpc.branch(:, 1); % 支路首端（上游节点）编号
tbus = mpc.branch(:, 2); % 支路末端（下游节点）编号
r_br = mpc.branch(:, 3);
x_br = mpc.branch(:, 4);
Pd_pu       = (mpc.bus(:, 3) * alpha / Sbase) * load_curve_pu';
Qd_pu       = (mpc.bus(:, 4) * alpha / Sbase) * load_curve_pu';
P_pv_max_pu = (1.2 / Sbase) * repmat(pv_curve_pu', N_pv, 1);
P_ess_rated_pu = 1.5 / Sbase;
E_ess_rated_pu = 3.0 / Sbase;
eta_ch  = 0.90;
eta_dis = 0.95;
SoC_min = 0.20;
SoC_max = 0.80;
SoC_0   = 0.50;

Params=struct('Sbase',Sbase,'N_bus',N_bus,'N_br',N_br,'N_ess',N_ess,'N_pv',N_pv,...
    'T',T,'dt',dt,'fbus',fbus,'tbus',tbus,'r_br',r_br,'x_br',x_br,...
    'ess_buses',ess_buses,'pv_buses',pv_buses,'P_ess_rated_pu',P_ess_rated_pu,...
    'E_ess_rated_pu',E_ess_rated_pu,'P_pv_max_pu',P_pv_max_pu,...
    'Pd_pu',Pd_pu,'Qd_pu',Qd_pu,'eta_ch',eta_ch,'eta_dis',eta_dis,...
    'SoC_0',SoC_0,'SoC_min',SoC_min,'SoC_max',SoC_max,'V_min',0.95,'V_max',1.05,...
    'price_MWh',price_MWh);

%% 三类目标求解与校核
selected_objective=model_type;
objective_letters='ABC';
objective_descriptions={'最大化光伏消纳','最小化全天网损','最小化购电费用'};
out_dir=fullfile(lesson.results,'Task3');
if ~isfolder(out_dir),mkdir(out_dir);end
Day3=struct('StudentID',Stu_ID,'Case',case_name,'Alpha',alpha,...
    'AssignedObjective',assigned_objective,'SelectedObjective',selected_objective,...
    'ESSNodes',ess_buses,'PVNodes',pv_buses,'Objectives',struct());
Comparison=table();
for objective_index=1:numel(objective_letters)
    model_type=objective_letters(objective_index);
    [Native,solver_name,solve_seconds,objective_value]=ess_native_dispatch(mpc,Params,model_type);
    Dispatch_Data=struct('mpc',mpc,'Stu_ID',Stu_ID,'case_name',case_name,...
        'model_type',model_type,'solver',solver_name,'solve_seconds',solve_seconds,...
        'Sbase',Sbase,'dt',dt,'ess_buses',ess_buses,'pv_buses',pv_buses,...
        'PratedMW',P_ess_rated_pu*Sbase,'EratedMWh',E_ess_rated_pu*Sbase,...
        'SoC0',SoC_0,'SoCmin',SoC_min,'SoCmax',SoC_max,...
        'eta_ch',eta_ch,'eta_dis',eta_dis,'price_MWh',price_MWh,...
        'PloadMW',Pd_pu*Sbase,'QloadMvar',Qd_pu*Sbase,...
        'PpvMW',Sbase*Native.P_pv,'PpvMaxMW',P_pv_max_pu*Sbase,...
        'PchMW',Sbase*Native.P_ch,'PdisMW',Sbase*Native.P_dis,...
        'SoC',Native.SoC,'u',Native.u_ch,'U',Native.U_bus,...
        'L',Native.L_br,'P',Native.P_br,'Q',Native.Q_br,...
        'Pgrid',Native.P_grid,'Qgrid',Native.Q_grid);
    [Dispatch_Check,V_dispatch_ac]=ess_live_check_dispatch(Dispatch_Data);
    Dispatch_Check.ObjectiveValue=objective_value;
    assert(Dispatch_Check.StorageConstraintsPassed && Dispatch_Check.LinearConstraintsPassed,...
        '目标%s储能或线性潮流约束校核未通过。',model_type);
    if ~Dispatch_Check.TeachingCounterexample
        assert(Dispatch_Check.Passed,'目标%s二阶锥或交流电压校核未通过。',model_type);
    end
    OptimalityCertificate=struct('LowerBound',Native.LowerBound,...
        'UpperBound',Native.UpperBound,'RelativeGap',Native.RelativeGap);
    gap_matrix=abs(Native.L_br.*Native.U_bus(fbus,:)-Native.P_br.^2-Native.Q_br.^2);
    row=table(Stu_ID,string(case_name),string(model_type),string(objective_descriptions{objective_index}),...
        string(solver_name),Dispatch_Check.Curtailment_MWh,Dispatch_Check.LineLoss_MWh,...
        Dispatch_Check.ACLineLoss_MWh,Dispatch_Check.GridCost_Yuan,...
        Dispatch_Check.MaxConeGap,Dispatch_Check.MaxSimultaneousPower_MW,...
        Dispatch_Check.MinACVoltage,Dispatch_Check.MaxACVoltage,...
        Dispatch_Check.Passed,Dispatch_Check.TeachingCounterexample,Native.RelativeGap,...
        'VariableNames',{'StudentID','Case','Objective','Description','Solver',...
        'Curtailment_MWh','Loss_MWh','ACLoss_MWh','GridCost_Yuan','MaxConeGap',...
        'SimultaneousPower_MW','MinACVoltage','MaxACVoltage','Passed',...
        'TeachingCounterexample','RelativeOptimalityGap'});
    Comparison=[Comparison;row];
    Day3.Objectives.(model_type)=struct('Dispatch',Dispatch_Data,'Check',Dispatch_Check,...
        'VoltageAC',V_dispatch_ac,'Gap',gap_matrix,'Certificate',OptimalityCertificate,'Result',row);
    objective_dir=fullfile(out_dir,model_type);
    if ~isfolder(objective_dir),mkdir(objective_dir);end
    Dispatch_Result=row;
    save(fullfile(objective_dir,'dispatch_result.mat'),'Dispatch_Data','Dispatch_Check',...
        'V_dispatch_ac','gap_matrix','Dispatch_Result','OptimalityCertificate');
    Hourly=table((1:T)',price_MWh(:),Dispatch_Data.Pgrid(:)*Sbase,...
        sum(Dispatch_Data.PpvMW,1)',sum(Dispatch_Data.PchMW,1)',sum(Dispatch_Data.PdisMW,1)',...
        Dispatch_Data.SoC(1,:)',Dispatch_Data.SoC(2,:)',Dispatch_Data.SoC(3,:)',...
        'VariableNames',{'Period','Price_YuanPerMWh','GridPurchase_MW','PV_MW',...
        'Charge_MW','Discharge_MW','SoC_Node4','SoC_Node9','SoC_Node14'});
    writetable(Hourly,fullfile(objective_dir,'Hourly.csv'));
    disp(row);
end

%% 学号指定目标结果图
Day3.Comparison=Comparison;
Day3.Completed=true;
Selected=Day3.Objectives.(selected_objective);
Dispatch_Data=Selected.Dispatch;Dispatch_Check=Selected.Check;
V_dispatch_ac=Selected.VoltageAC;gap_matrix=Selected.Gap;
Dispatch_Result=Selected.Result;OptimalityCertificate=Selected.Certificate;
model_type=selected_objective;
Day3.Dispatch=Dispatch_Data;Day3.Check=Dispatch_Check;
Day3.Result=Dispatch_Result;Day3.OptimalityCertificate=OptimalityCertificate;
view_storage=1;
fig_dispatch_storage=ess_live_view('dispatch_storage',price_kWh,...
    Dispatch_Data.PchMW(view_storage,:)',Dispatch_Data.PdisMW(view_storage,:)',...
    Dispatch_Data.SoC(view_storage,:)',19,1,Dispatch_Data.EratedMWh);
sgtitle(sprintf('目标 %s：节点 %d 储能运行',model_type,ess_buses(view_storage)),'FontName','PingFang SC');
view_hour=19;
fig_gap=ess_live_view('gap',gap_matrix,view_hour);
fig_dispatch_voltage=ess_live_view('voltage',mpc,V_dispatch_ac,view_hour,13);
compare_node=Dispatch_Check.MaxVoltageErrorNode;
fig_dispatch_compare=ess_live_view('relaxation_voltage',sqrt(Dispatch_Data.U),V_dispatch_ac,compare_node);
fig_matrix=ess_live_view('matrix',mpc,1);
fig_objectives=figure('Color','w','Position',[100 100 1050 820]);
if isprop(fig_objectives,'Theme'),theme(fig_objectives,'light');end
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
nexttile;bar(categorical(cellstr(objective_letters')),max(0,Comparison.Curtailment_MWh));ylabel('弃光电量 / MWh');
nexttile;bar(categorical(cellstr(objective_letters')), [Comparison.Loss_MWh Comparison.ACLoss_MWh]);ylabel('全天网损 / MWh');legend('二阶锥模型','交流潮流','Location','northoutside');
nexttile;bar(categorical(cellstr(objective_letters')),Comparison.GridCost_Yuan);ylabel('购电费用 / 元');
nexttile;hold on;
for k=1:numel(objective_letters)
    val=Day3.Objectives.(objective_letters(k));
    plot(1:T,max(val.VoltageAC,[],1),'LineWidth',1.6);
end
yline(1.05,'--','电压上限');xlabel('时间 / h');ylabel('全网最高交流电压 / p.u.');legend('A','B','C','Location','northoutside','Orientation','horizontal');
sgtitle('三类调度目标比较：C 为松弛不精确教学反例','FontName','PingFang SC');
fig_standard=ess_task3_figure(Day3);
if export_figures
    ess_live_export(fig_standard,script_dir,'Fig_Week1_Task3_206221322');
    ess_live_export(fig_dispatch_storage,script_dir,'Fig_Week1_Task3_Storage_206221322');
    ess_live_export(fig_gap,script_dir,'Fig_Week1_Task3_ConeGap_206221322');
    ess_live_export(fig_dispatch_voltage,script_dir,'Fig_Week1_Task3_Voltage_206221322');
    ess_live_export(fig_dispatch_compare,script_dir,'Fig_Week1_Task3_VoltageComparison_206221322');
    ess_live_export(fig_matrix,script_dir,'Fig_Week1_Task3_Network_206221322');
    ess_live_export(fig_objectives,script_dir,'Fig_Week1_Task3_Comparison_206221322');
end

%% 标准化结果
save(fullfile(out_dir,'dispatch_result.mat'),'Dispatch_Data','Dispatch_Check',...
    'V_dispatch_ac','Dispatch_Result','OptimalityCertificate','Day3','Comparison');
writetable(Comparison,fullfile(script_dir,'Task3_206221322.csv'));
writetable(Comparison,fullfile(out_dir,'Task3_206221322.csv'));
summary_file=fullfile(script_dir,'result_summary.mat');
if isfile(summary_file),save(summary_file,'Day3','-append');else,save(summary_file,'Day3');end
Validation=struct('Completed',true,'AssignedObjective',assigned_objective,...
    'SelectedObjective',selected_objective,'Check',Dispatch_Check,'Certificate',OptimalityCertificate);
for k=1:numel(objective_letters)
    letter=objective_letters(k);
    Validation.Objectives.(letter)=struct('Check',Day3.Objectives.(letter).Check,...
        'Certificate',Day3.Objectives.(letter).Certificate);
end
fid=fopen(fullfile(script_dir,'Task3_Validation.json'),'w');
fwrite(fid,jsonencode(Validation),'char');fclose(fid);
Lesson_Stats=Dispatch_Check;
disp(Comparison);
