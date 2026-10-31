function [sol,solver_name,solve_seconds] = ess_live_solve(constraints,objective,model_type)
% LP/MILP/SOCP 使用 MATLAB 内置求解器；MISOCP 使用支持该模型的求解器。
model_type=upper(char(model_type));
if ismember(model_type,{'LP','MILP','SOCP'})
    original_path=path;
    restore_path=onCleanup(@()path(original_path)); %#ok<NASGU>
    % 优先使用 MathWorks 实现，避免同名的 MOSEK 兼容接口覆盖原生函数。
    native_dir=fullfile(matlabroot,'toolbox','optim','optim');
    addpath(native_dir,'-begin');
    switch model_type
        case 'LP',solver_name='linprog';
        case 'MILP',solver_name='intlinprog';
        case 'SOCP',solver_name='coneprog';
    end
    solver_file=which(solver_name);
    assert(startsWith(solver_file,matlabroot,'IgnoreCase',true),...
        '请安装并启用 Optimization Toolbox 的 %s。',solver_name);
    ops=sdpsettings('solver',solver_name,'verbose',0,'savesolveroutput',1);
    if strcmp(model_type,'MILP')
        ops.intlinprog.RelativeGapTolerance=1e-6;
        ops.intlinprog.AbsoluteGapTolerance=1e-8;
    end
    tic;sol=optimize(constraints,objective,ops);solve_seconds=toc;
    % 旧版 YALMIP 可能仍向 linprog 传入已取消的 X0 参数。
    if strcmp(model_type,'LP') && sol.problem~=0 && ...
            contains(lower(sol.info),'linprog') && contains(upper(sol.info),'X0')
        tic;sol=ess_live_linprog(constraints,objective,ops);
        solve_seconds=solve_seconds+toc;
    end
    sol.native_solver_file=solver_file;
    assert(sol.problem==0,'%s 求解失败：%s',solver_name,sol.info);
    return
end
assert(strcmp(model_type,'MISOCP'),'未定义的模型类型：%s',model_type);
solver_candidates={};
if exist('mosekopt','file')~=0,solver_candidates{end+1}='mosek';end
if exist('gurobi','file')~=0,solver_candidates{end+1}='gurobi';end
assert(~isempty(solver_candidates),...
    '本任务含充放电二进制变量和二阶锥约束，需配置 MOSEK 或 Gurobi。');
messages=cell(0,1);tic;
for k=1:numel(solver_candidates)
    solver_name=solver_candidates{k};
    ops=sdpsettings('solver',solver_name,'verbose',0,'savesolveroutput',1);
    % 由本函数捕获原始异常，既保留错误原因，也继续尝试下一个求解器。
    ops.debug=1;
    if strcmp(solver_name,'mosek')
        ops.mosek.MSK_DPAR_MIO_MAX_TIME=600;
        ops.mosek.MSK_DPAR_MIO_TOL_REL_GAP=1e-6;
        ops.mosek.MSK_DPAR_MIO_TOL_ABS_GAP=1e-8;
        ops.mosek.MSK_DPAR_MIO_TOL_FEAS=1e-9;
        ops.mosek.MSK_DPAR_MIO_TOL_ABS_RELAX_INT=1e-9;
        ops.mosek.MSK_DPAR_INTPNT_CO_TOL_PFEAS=1e-10;
        ops.mosek.MSK_DPAR_INTPNT_CO_TOL_DFEAS=1e-10;
        ops.mosek.MSK_DPAR_INTPNT_CO_TOL_REL_GAP=1e-10;
    else
        % 旧版 YALMIP 默认值为 -1，新版 Gurobi 要求非负。
        ops.gurobi.TuneTimeLimit=0;
        ops.gurobi.TimeLimit=120;
        ops.gurobi.MIPGap=1e-6;
        ops.gurobi.FeasibilityTol=1e-9;
        ops.gurobi.IntFeasTol=1e-9;
        ops.gurobi.OptimalityTol=1e-8;
        ops.gurobi.BarQCPConvTol=1e-9;
    end
    try
        sol=optimize(constraints,objective,ops);
    catch solver_error
        messages{end+1}=sprintf('%s [%s]: %s',solver_name,...
            solver_error.identifier,solver_error.message); %#ok<AGROW>
        continue
    end
    if sol.problem==0,solve_seconds=toc;return;end
    detail=sol.info;
    if isfield(sol,'solveroutput') && ~isempty(sol.solveroutput)
        % MOSEK 的 rcode/rmsg/rcodestr 及终止状态保留在原始输出中。
        detail=sprintf('%s\n原始求解器输出：\n%s',detail,evalc('disp(sol.solveroutput)'));
        if strcmp(solver_name,'mosek') && isfield(sol.solveroutput,'res')
            raw=sol.solveroutput.res;
            detail=sprintf('%s\nMOSEK 返回信息：\n%s',detail,evalc('disp(raw)'));
            if isfield(raw,'sol') && isfield(raw.sol,'int')
                integer_solution=raw.sol.int;
                if isfield(integer_solution,'prosta')
                    detail=sprintf('%s\n整数问题状态：%s',detail,integer_solution.prosta);
                end
                if isfield(integer_solution,'solsta')
                    detail=sprintf('%s\n整数解状态：%s',detail,integer_solution.solsta);
                end
            end
            if isfield(raw,'rcode') && raw.rcode==100001
                detail=sprintf('%s\nMOSEK 已达到本次设置的 %g 秒时间上限。',...
                    detail,ops.mosek.MSK_DPAR_MIO_MAX_TIME);
            end
        end
    end
    messages{end+1}=[solver_name ': ' detail]; %#ok<AGROW>
end
error('MISOCP 求解失败：%s',strjoin(messages,'; '));
end
