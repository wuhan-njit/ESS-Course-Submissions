function comparison = ess_live_compare_arbitrage(price,pmax,emax,eta_ch,eta_dis,smin,smax,dt)
% 在相同输入条件下比较 LP 和 MILP 的最优电费收益。
T=numel(price); profit=zeros(2,1); overlap=zeros(2,1); energy_error=zeros(2,1);
for idx=1:2
    pc=sdpvar(T,1,'full'); pd=sdpvar(T,1,'full'); s=sdpvar(T,1,'full');
    c=[0<=pc<=pmax,0<=pd<=pmax,smin<=s<=smax,s(T)==0.5];
    if idx==2
        u=binvar(T,1,'full'); c=[c,pc<=u*pmax,pd<=(1-u)*pmax];
    end
    previous=[0.5;s(1:end-1)];
    c=[c,s==previous+(eta_ch*pc-pd/eta_dis)*dt/emax];
    obj=sum(price(:).*(pc-pd))*dt;
    if idx==1,model_type='LP';else,model_type='MILP';end
    [sol,solver]=ess_live_solve(c,obj,model_type);
    assert(sol.problem==0,'LP/MILP 比较求解失败：%s',yalmiperror(sol.problem));
    profit(idx)=-value(obj); overlap(idx)=max(min(value(pc),value(pd)));
    energy_error(idx)=abs(value(s(T))-0.5);
end
comparison=table(["LP";"MILP"],profit,overlap,energy_error,...
    'VariableNames',{'Model','DailyRevenue_Yuan','MaxSimultaneousPower_MW','TerminalSoCError'});
end
