function Comparison=YanJuntao_209230538_Week1_ABCComparison()
% 同场景 A/B/C 数值比较。运行任务三后调用，保留 C 为主结果。
out_dir=fileparts(mfilename('fullpath'));
addpath(fullfile(out_dir,'solver_support'));
results=cell(1,3); data=cell(1,3); checks=cell(1,3);
for n=1:2
 [Dispatch_Data,Dispatch_Check,V_dispatch_ac,Dispatch_Result,gap_matrix,sol]=ess_week1_dispatch_case(n);
 save(fullfile(out_dir,sprintf('Task3_%s_raw.mat','A'+n-1)),...
  'Dispatch_Data','Dispatch_Check','V_dispatch_ac','Dispatch_Result','gap_matrix','sol');
 data{n}=Dispatch_Data;checks{n}=Dispatch_Check;results{n}=Dispatch_Result;
end
c=load(fullfile(out_dir,'Task3_C_raw.mat'));
data{3}=c.Dispatch_Data;checks{3}=c.Dispatch_Check;results{3}=c.Dispatch_Result;
parameters={'mpc','Stu_ID','case_name','Sbase','dt','ess_buses','pv_buses',...
 'PratedMW','EratedMWh','SoC0','SoCmin','SoCmax','eta_ch','eta_dis',...
 'price_MWh','PloadMW','QloadMvar','PpvMaxMW'};
for n=1:3
 assert(checks{n}.Passed,'目标 %s 的运行核验未通过。','A'+n-1);
 assert(data{n}.OptimalityCertificate.CertifiedWithinTolerance);
 for k=1:numel(parameters)
  field=parameters{k};assert(isequaln(data{n}.(field),data{3}.(field)),...
   '目标间参数不一致：%s',field);
 end
end
Comparison=vertcat(results{:});
Comparison.ACLoss_MWh=cellfun(@(s)s.ACLineLoss_MWh,checks)';
Comparison.MaxACVoltageError=cellfun(@(s)s.MaxACVoltageError,checks)';
Comparison.ObjectiveUpperBound=cellfun(@(s)s.OptimalityCertificate.IntegerObjective,data)';
Comparison.ObjectiveLowerBound=cellfun(@(s)s.OptimalityCertificate.RelaxedDualBound,data)';
Comparison.ObjectiveGap=Comparison.ObjectiveUpperBound-Comparison.ObjectiveLowerBound;
writetable(Comparison,fullfile(out_dir,'Task3_ABC_Comparison.csv'));
s=load(fullfile(out_dir,'result_summary.mat'));
result_summary=s.result_summary;result_summary.Task3Comparison=Comparison;
result_summary.Task3ComparisonChecks=checks;
save(fullfile(out_dir,'result_summary.mat'),'result_summary');
disp(Comparison);
f=figure('Color','w','Position',[80 80 1100 800]);
tiledlayout(2,2,'TileSpacing','compact');
nexttile;bar(categorical({'A','B','C'}),max(0,Comparison.Curtailment_MWh));
ylabel('弃光电量 / MWh');title('光伏消纳');grid on;
nexttile;bar(categorical({'A','B','C'}),Comparison.Loss_MWh);
ylabel('全天网损 / MWh');title('线路电能损耗');grid on;
nexttile;bar(categorical({'A','B','C'}),Comparison.GridCost_Yuan);
ylabel('关口购电费用 / 元');title('购电费用');grid on;
nexttile;hold on;
for n=1:3,plot(0:24,[data{n}.SoC0 mean(data{n}.SoC,1)],'LineWidth',1.5);end
grid on;xlim([0 24]);xlabel('时间 / h');ylabel('三套储能平均 SoC');legend('A','B','C','Location','best');
ax=findall(f,'Type','axes');set(ax,'Color','white','XColor',[.15 .2 .25],'YColor',[.15 .2 .25]);
set(findall(f,'Type','text'),'Color',[.15 .2 .25]);
set(findall(f,'Type','legend'),'Color','white','TextColor',[.15 .2 .25]);
ess_live_export(f,out_dir,'Fig_Task3_ABC_Comparison');
end
