function sol = ess_live_linprog(constraints,objective,ops)
% 兼容旧版 YALMIP 的 linprog 接口；沿用原模型，使用不含 X0 的调用语法。
compile_timer=tic;
[model,recovery,diagnostic]=export(constraints,objective,ops);
compile_seconds=toc(compile_timer);
if ~isempty(diagnostic)
    sol=diagnostic;
    return
end
% 新建原生选项，避免旧接口中的已取消选项影响当前 MATLAB。
native_options=optimoptions('linprog','Display','none');
solve_timer=tic;
[x,fval,exitflag,output,lambda]=linprog(model.c,model.A,model.b,...
    model.Aeq,model.beq,model.lb,model.ub,native_options);
solve_seconds=toc(solve_timer);
if exitflag>0
    problem=0;
    % 按 YALMIP 的恢复映射写回变量，后续仍通过 value 读取结果。
    primal=recovery.x_equ+recovery.H*x;
    assign(recover(recovery.used_variables),primal);
elseif exitflag==-2
    problem=1;
elseif exitflag==-3
    problem=2;
elseif exitflag==0
    problem=3;
else
    problem=5;
end
sol=struct('problem',problem,'info',yalmiperror(problem,'linprog'),...
    'yalmiptime',compile_seconds,'solvertime',solve_seconds,...
    'solveroutput',struct('x',x,'fval',fval,'exitflag',exitflag,...
        'output',output,'lambda',lambda),...
    'compatibility_path','YALMIP export + native linprog (without X0)');
end
