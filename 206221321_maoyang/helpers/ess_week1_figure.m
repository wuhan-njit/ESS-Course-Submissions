function f = ess_week1_figure(task, d, root)
f = figure('Color','w','NumberTitle','off','Position',[70 70 1120 780]);
if isprop(f,'Theme'), theme(f,'light'); end
if task == 1
    b=d.Day1.Baseline; h=d.Day1.Load110; t=1:24; node=b.MinBus;
    buses=1:size(b.Voltage_pu,1);
    voltage_range=[min([b.Voltage_pu(:);h.Voltage_pu(:)]),max([b.Voltage_pu(:);h.Voltage_pu(:)])];
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
    nexttile;
    surf(t,buses,b.Voltage_pu,'EdgeColor','none');view(-45,30);
    xlabel('时段 / h');ylabel('节点编号');zlabel('电压 / p.u.');
    title(sprintf('基准负荷：全网49节点，α=%.4f',b.Alpha));
    clim(voltage_range);zlim(voltage_range);colorbar;
    nexttile;
    surf(t,buses,h.Voltage_pu,'EdgeColor','none');view(-45,30);
    xlabel('时段 / h');ylabel('节点编号');zlabel('电压 / p.u.');
    title(sprintf('负荷增加10%%：全网49节点，α=%.4f',h.Alpha));
    clim(voltage_range);zlim(voltage_range);colorbar;
    nexttile;
    plot(t,b.Voltage_pu(node,:),'-o',t,h.Voltage_pu(node,:),'--s','LineWidth',1.8,'MarkerSize',4);
    ylabel('电压 / p.u.'); title(sprintf('节点 %d 的全天电压',node));
    legend({'基准负荷','负荷增加10%'},'Location','best','AutoUpdate','off');
    nexttile;
    plot(t,b.Loss_MW,'-o',t,h.Loss_MW,'--s','LineWidth',1.8,'MarkerSize',4);
    ylabel('有功网损 / MW'); xlabel('时段 / h'); title('全网有功网损');
    legend({'基准负荷','负荷增加10%'},'Location','best','AutoUpdate','off');
elseif task == 2
    z=d.Day2; m=z.MILP; t=1:24;
    tiledlayout(3,2,'TileSpacing','compact','Padding','compact');
    nexttile; stairs(t,z.Price_YuanPerMWh/1000,'LineWidth',1.8);ylabel('电价 / (元/kWh)');title('分时电价');
    nexttile;plot(0:24,[z.SoC0;m.SoC],'-o','LineWidth',1.8,'MarkerSize',3);ylabel('SoC');title('荷电状态');ylim([0 1.05]);
    nexttile([1 2]);stairs(t,m.P_ch_MW,'--','LineWidth',1.8);hold on;stairs(t,m.P_dis_MW,'-','LineWidth',1.8);
    ylabel('功率 / MW');xlabel('时段 / h');title('储能充放电功率');legend({'充电','放电'},'Location','northoutside','Orientation','horizontal','AutoUpdate','off');
    nexttile;plot(z.PowerSensitivity.Power_MW,z.PowerSensitivity.DailyRevenue_Yuan,'-o','LineWidth',1.8);xlabel('额定功率 / MW');ylabel('日收益 / 元');title('容量固定为2 MWh');
    nexttile;plot(z.EnergySensitivity.Energy_MWh,z.EnergySensitivity.DailyRevenue_Yuan,'-s','LineWidth',1.8);xlabel('额定容量 / MWh');ylabel('日收益 / 元');title('功率固定为2 MW');
else
    z=d.Day3; a=z.TimeSeries.A; c=z.TimeSeries.C; t=1:24;
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
    nexttile;stairs(t,sum(a.Pch_MW,1),'--','LineWidth',1.8);hold on;stairs(t,sum(a.Pdis_MW,1),'-','LineWidth',1.8);
    ylabel('合计功率 / MW');xlabel('时段 / h');title('目标A：三个储能节点合计');legend({'充电','放电'},'Location','best','AutoUpdate','off');
    nexttile;plot(0:24,[repmat(z.SoC0,3,1),a.SoC]','LineWidth',1.8);
    ylabel('SoC');xlabel('时段 / h');title('目标A：储能荷电状态');ylim([0 1]);legend({'节点4','节点9','节点14'},'Location','best','AutoUpdate','off');
    nexttile;plot(t,min(a.V_ac_pu,[],1),'-o',t,max(a.V_ac_pu,[],1),'--s','LineWidth',1.8,'MarkerSize',3);
    ylabel('电压 / p.u.');xlabel('时段 / h');title('目标A：逐时全网交流电压范围');legend({'最低电压','最高电压'},'Location','best','AutoUpdate','off');
    nexttile;node=z.Check.C.MaxVoltageErrorNode;
    plot(t,c.V_model_pu(node,:),'-o',t,c.V_ac_pu(node,:),'--s','LineWidth',1.8,'MarkerSize',3);
    ylabel('电压 / p.u.');xlabel('时段 / h');title(sprintf('目标C：节点%d的松弛电压偏差',node));legend({'二阶锥模型','交流潮流'},'Location','best','AutoUpdate','off');
end
axes_all=findall(f,'Type','axes');
for i=1:numel(axes_all)
    ax=axes_all(i);grid(ax,'on');ax.GridAlpha=0.12;
    if task==1 || (task==2 && i>=3) || task==3
        if max(ax.XLim)>=24
            series=findobj(ax,'-property','XData'); has_initial=false;
            for n=1:numel(series), has_initial=has_initial||any(series(n).XData==0,'all');end
            if has_initial,ax.XLim=[0 24];ax.XTick=0:3:24;
            else,ax.XLim=[1 24];ax.XTick=1:2:24;end
        end
    end
    if task==1 && abs(ax.View(2)-90)>1
        ax.XTick=[1 6 12 18 24];ax.YTick=[1 13 25 37 49];
    end
end
set(findall(f,'-property','FontName'),'FontName','PingFang SC');
set(findall(f,'Type','axes'),'FontSize',11,'LineWidth',0.8);
set(findall(f,'Type','legend'),'FontSize',10,'Box','off');
stem=sprintf('Fig_Week1_Task%d_206221321',task);
exportgraphics(f,fullfile(root,[stem '.png']),'Resolution',600,'BackgroundColor','white');
exportgraphics(f,fullfile(root,[stem '.pdf']),'ContentType','vector','BackgroundColor','white');
savefig(f,fullfile(root,[stem '.fig']));
end
