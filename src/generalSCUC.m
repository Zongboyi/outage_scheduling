%case5,case24_ieee_rts,case3012wp
%When nargin>2 , this function is used for the dynamic myopic UC (horizon=1),
%where we try to not deviate from the original onoff plan, and to have the
%least deviation from the original Pg due to redispatch costs
function [Pg,objective,onoff,y,demandVector,success,windSpilled,loadLost,warm_start,solution_time]=generalSCUC(str,params,state,dynamicUCParams)
tic
%% Data - horizon is 1 for dynamic mode
% params=getProblemParams_yalmip(mpcase);
horizon=params.horizon;
mpc=params.mpcase;
demandVector=zeros(horizon,1);
isolatedLastBus=0;
rate_a_limit = 1e-9;
%% data dimensions
nb   = size(mpc.bus, 1);    %% number of buses
nl   = size(mpc.branch, 1); %% number of branches
ng   = size(mpc.gen, 1);    %% number of dispatchable injections
%% Choose SCUC type
if(strcmp(str,'n1'))
    N_contingencies=nl;
else N_contingencies=0;
end
%% define optimization vars
onoff = binvar(ng,horizon,'full');
on = binvar(ng,horizon,'full');
off = binvar(ng,horizon,'full');
J=8;
z = binvar(ng,horizon,J);
Va     = sdpvar(nb,horizon,N_contingencies+1,'full');
Pg     = sdpvar(ng,horizon,'full');
sp      = sdpvar(nb,horizon,'full'); %wind spillage variable
ls      = sdpvar(nb,horizon,'full'); %load shedding variable

warm_start_mode = 0;
if(isfield(params,'warm_start') && ~isempty(params.warm_start))
    assign(onoff,params.warm_start.onoff);
    assign(Pg,params.warm_start.Pg);
    assign(sp,params.warm_start.sp);
    assign(ls,params.warm_start.ls);
    assign(on,params.warm_start.on);
    assign(off,params.warm_start.off);
    assign(z,params.warm_start.z);
    assign(Va,params.warm_start.Va);
    warm_start_mode = 1;
end


% Constraints = onoff==params.oo;
Constraints=[];
startTime=1;
dynamicUC=(exist('dynamicUCParams','var') && ~isempty(dynamicUCParams));
if(dynamicUC)
    if(~isempty(dynamicUCParams.externalStartTime))
        startTime = dynamicUCParams.externalStartTime;
    end
    if(isfield(dynamicUCParams,'originalOnoff') && ~isempty(dynamicUCParams.originalOnoff))
        originalOnoff=dynamicUCParams.originalOnoff;
    end
    if(dynamicUCParams.enforceOnoff && exist('originalOnoff','var'))
        Constraints = [Constraints , onoff(:,1) == originalOnoff];
    end
end


%% contrained model
%% define named indices into data matrices
[PQ, PV, REF, NONE, BUS_I, BUS_TYPE, PD, QD, GS, BS, BUS_AREA, VM, ...
    VA, BASE_KV, ZONE, VMAX, VMIN, LAM_P, LAM_Q, MU_VMAX, MU_VMIN] = idx_bus; %#ok<*ASGLU>
[GEN_BUS, PG, QG, QMAX, QMIN, VG, MBASE, GEN_STATUS, PMAX, PMIN, ...
    MU_PMAX, MU_PMIN, MU_QMAX, MU_QMIN, PC1, PC2, QC1MIN, QC1MAX, ...
    QC2MIN, QC2MAX, RAMP_AGC, RAMP_10, RAMP_30, RAMP_Q, APF] = idx_gen;
[F_BUS, T_BUS, BR_R, BR_X, BR_B, RATE_A, RATE_B, RATE_C, ...
    TAP, SHIFT, BR_STATUS, PF, QF, PT, QT, MU_SF, MU_ST, ...
    ANGMIN, ANGMAX, MU_ANGMIN, MU_ANGMAX] = idx_brch;
[PW_LINEAR, POLYNOMIAL, MODEL, STARTUP, SHUTDOWN, NCOST, COST] = idx_cost;
%% update contingencies - if field exists (currently, only used in the UC_NN program. 
%% In outage_scheduling program, it is being updated through the state struct
if(isfield(params,'line_status'))
%     mpc.branch(:,BR_STATUS)=params.line_status; %this doesn't seem to
%     affect anything in our DC UC function. The only thing it does is ruin
%     the calculation - RATE_A limit is irrelevant when BR_STATUS=0, while
%     BR_STATUS=0 generates the same result as with  BR_STATUS=1 and no
%      strong limit on RATE_A
    mpc.branch(logical(1-params.line_status),RATE_A)=rate_a_limit;
end
%% ignore reactive costs for DC
mpc.gencost = pqcost(mpc.gencost, ng);
%% convert single-block piecewise-linear costs into linear polynomial cost
pwl1 = find(mpc.gencost(:, MODEL) == PW_LINEAR & mpc.gencost(:, NCOST) == 2);
% p1 = [];
if ~isempty(pwl1)
    x0 = mpc.gencost(pwl1, COST);
    y0 = mpc.gencost(pwl1, COST+1);
    x1 = mpc.gencost(pwl1, COST+2);
    y1 = mpc.gencost(pwl1, COST+3);
    m = (y1 - y0) ./ (x1 - x0);
    b = y0 - m .* x0;
    mpc.gencost(pwl1, MODEL) = POLYNOMIAL;
    mpc.gencost(pwl1, NCOST) = 2;
    mpc.gencost(pwl1, COST:COST+1) = [m b];
end

%% create (read-only) copies of individual fields for convenience
[baseMVA, bus, gen, branch, gencost, Au, lbu, ubu, mpopt, ...
    N, fparm, H, Cw, z0, zl, zu, userfcn] = opf_args(mpc);
%% normalize original PG constraint
if(dynamicUC && isfield(dynamicUCParams,'originalPg') && ~isempty(dynamicUCParams.originalPg))
    deviationPenalty=1;
    normalizedOriginalPg=dynamicUCParams.originalPg / baseMVA;
else
    deviationPenalty=0;
end


%% warn if there is more than one reference bus
refs = find(bus(:, BUS_TYPE) == REF);
if length(refs) > 1 && mpopt.verbose > 0
    errstr = ['\nopf_setup: Warning: Multiple reference buses.\n', ...
        '           For a system with islands, a reference bus in each island\n', ...
        '           may help convergence, but in a fully connected system such\n', ...
        '           a situation is probably not reasonable.\n\n' ];
    fprintf(errstr);
end
%% set up initial variables and bounds
Pmin = gen(:, PMIN) / baseMVA;
Pmax = gen(:, PMAX) / baseMVA;
%% more problem dimensions
nv    = 0;            %% number of voltage magnitude vars
nq    = 0;            %% number of Qg vars
q1    = [];           %% index of 1st Qg column in Ay

%% basin constraints for piece-wise linear gen cost variables
ipwl = find(gencost(:, MODEL) == PW_LINEAR);  %% piece-wise linear costs
ny = size(ipwl, 1);   %% number of piece-wise linear cost vars
[Ay, by] = makeAy(baseMVA, ng, gencost, 1, q1, 1+ng+nq);
numSegments=length(by)/ng;

if(ny>0)
    y=sdpvar(ny,horizon,'full'); %in case of pwl costs, form epigraph variables y
    for k=1:horizon
        coeff=kron(onoff(:,k),ones(numSegments,1));
        Constraints=[Constraints,Ay*[Pg(:,k);y(:,k)]<=by.*coeff]; %y basin constraints
        %NOTE: the structure of Ay*[Pg;y]<=by gives constraints of the
        %form: Pg(segment1)*Pg(1)-y(1)<=noLoad value.
        %therefore to zero-out y's for decommited units - since for them Pg
        %is zero, all that remains is to zero-out the corresponding elemnts
        %in by, and we'll then get y>=0 for all generators that are off! :)
    end
else y=0;
    if(warm_start_mode)
        assign(y,params.warm_start.y);
    end
end

currBranch=mpc.branch;
%% add all security and dynamic power flow constraints
for k = 1:horizon
    %% this should run only once per time step, and not for each contingency
    %     w=zeros(nb,1); w((bus(:,PD)>1))=0; w=zeros(nb,1);
    bus = mpc.bus;
    currHour = mod(startTime-1+k-1,24)+1;
    w = params.windScenario(:,currHour);
    if(isfield(params,'demandScenario'))
        d = params.demandScenario(:,currHour);
        bus(:,PD) = d;
    else
        dailyDemandFactor=getDeterministicDemandFactor(currHour);
        monthlyDemandFactor = getMonthlyDemandFactor(state);
        bus=scale_load(dailyDemandFactor*monthlyDemandFactor,mpc.bus); %mpc bus stays fixed
    end
    windAdditionToDemand =  - w + sp(:,k);
    loadhShedding_reductionFromDemand =  ls(:,k);

    Constraints = [Constraints , 0 <= ls(:,k) <= d];
    Constraints = [Constraints , 0 <= sp(:,k) <= w];
    demandVector(k)=sum(bus(:,PD));
    %% update current topology and update if lines were fixed - changes both 
    %% in day-ahead and in real-time (RT), used for outage_scheduling program
    %% as oppose to params.line_status, which is used for the uc_nn program
    [lineStatus_OS] = getFixedLineStatus(currHour,dynamicUC,params,state);
%     currBranch(:,BR_STATUS)=lineStatus_OS;
    currBranch(logical(1-lineStatus_OS),RATE_A)=rate_a_limit;
    %% N-1 criterion - N(=nl) possible single line outage
    %debuggnin to try and get N-1 to work when several outages
%     skipSet = 1:28; %28 seems to create trouble
%     N_contingencies=30;
    skipSet = [];
    for i_branch = 1:N_contingencies+1
        newMpcase=mpc;
        newMpcase.bus=bus;
        newMpcase.branch=currBranch;
        if(i_branch>1)
            %for i_branc==1, no contingencies.
            %for i_branc==2, 1st contingency, etc..
            newMpcase.branch(i_branch-1,BR_STATUS)=0;
            newMpcase.branch(i_branch-1,RATE_A)=rate_a_limit;
%             newMpcase.branch(i_branch-1,:)=[];
            if(~checkConnectivity(newMpcase,params) || sum(skipSet==i_branch)>0)
                continue;
            end
        end
        if(sum(newMpcase.branch(:,BR_STATUS))==0)
            Pg=zeros(size((Pg)));
            objective=0;
            onoff=zeros(size(onoff));
            success=0;
            windSpilled=0;
            loadLost = 0;
            return
        end
%         if(strcmp('case96',params.caseName))
%             newMpcaseInternal = newMpcase;
%         else
            newMpcaseInternal=ext2int(newMpcase); %transform to internal format,
%            newMpcaseInternal=ext2int( newMpcase.bus, newMpcase.gen, newMpcase.branch, newMpcase.areas);
            %to remove components  that can be disconnected as a result of line outage
%         end
        [baseMVA, curr_bus, gen, branch, gencost, Au, lbu, ubu, mpopt, ...
            N, fparm, H, Cw, z0, zl, zu, userfcn] = opf_args(newMpcaseInternal);
        
        %% power mismatch constraints - updated as load changes - equation 6.16 in manual
        [Amis,bmis,Bf,Pfinj] = mismatchConstraints(baseMVA,curr_bus,branch,gen,ng,nb,windAdditionToDemand,loadhShedding_reductionFromDemand);
        %% branch flow constraints - equation 6.17,6.18 in manual
        [upf,upt,il] = powerFlowConstraints(baseMVA,branch,Pfinj);
        %% branch voltage angle difference limits - updated as load changes
        [Aang, lang, uang, iang]  = makeAang(baseMVA, branch, nb, mpopt);
        %% problem constraints
        %     Constraints = [Constraints, sum(onoff(:,k).*(Pmin*mpc.baseMVA)) <= getHourlyDemand(k,params)];
        %     Constraints = [Constraints, sum(onoff(:,k).*(Pmax*mpc.baseMVA)) >= getHourlyDemand(k,params)];
        Constraints = [Constraints, onoff(:,k).*Pmin <= Pg(:,k) <= onoff(:,k).*Pmax];
        Constraints = [Constraints,Va(refs,k,i_branch)== curr_bus(refs,VA)*(pi/180)]; %constrain ref angle to be
        %the specified (usually 0)
        if(size(Amis,2) ~= length([Va(:,k,i_branch);Pg(:,k)])) %if there's a size mismatch, it means
            %that the last bus is isolated and this is an infeasible
            %problem.
            Pg=zeros(size((Pg)));
            objective=0;
            onoff=zeros(size(onoff));
            success=0;
            windSpilled=0;
            loadLost = 0;
            return
        else
            Constraints = [Constraints,Amis*[Va(:,k,i_branch);Pg(:,k)] == bmis]; %overall power equality
        end
        if(size(lang,1)+size(lang,2)>0) %only add this constraint when relevant, otherwise causes
            %size mismatch issues in yalmip
            Constraints=[Constraints,lang<=Aang*Va(:,k,i_branch)<=uang]; %angle differences between
            %lines limits (as appears in ANGMAX,ANGMIN in the branch matrix). if 0 - unconstrained.
        end
        if(size(upt,1)+size(upt,2)>0) %only add this constraint when relevant, otherwise
            %causes size mismatch issues in yalmip
            Constraints=[Constraints,-upt<=Bf(il,:)*Va(:,k,i_branch)<=upf]; %line rating limits
        end
    end
end

%% Objective
pwlCost=sum(sum(y));
windCurtailmentCost=sum(sum(params.windCurtailmentPrice*sp));
loadShedding_cost=sum(sum(params.VOLL*ls));

Objective = windCurtailmentCost + loadShedding_cost;
if(~deviationPenalty)
    Objective = Objective + pwlCost;
else
    if(exist('originalOnoff','var'))
        Objective=Objective+pgDeviationCost(normalizedOriginalPg*baseMVA,originalOnoff,Pg*baseMVA,gencost,params);
    end
end


%% Adding minimum up- and down-time, and calculate start-up times
%% params.dropUpDownConstraints allows neglecting these constraints for faster run-time
if(~(isfield(params,'dropUpDownConstraints') && params.dropUpDownConstraints));
    minup   = params.unitsInfo(:,params.MU);
    mindown = params.unitsInfo(:,params.MD);
    initialGeneratorState=state.initialGeneratorState;
    for unit = 1:ng
        initialOnOffLength=abs(initialGeneratorState(unit));
        if(initialGeneratorState(unit)>0)
            initialOnOff=ones(1,initialOnOffLength);
            initialOnOff_ud=[0,initialOnOff]; %the initial 1/0 are for the min up/down constraints
            startedOff=0;
        else initialOnOff=zeros(1,initialOnOffLength);
            initialOnOff_ud=[1,initialOnOff];
            startedOff=1;
        end
        suBlocksCosts=params.generatorData{params.generatorTypeVector(unit)}.cost.startUpBlocksCosts;
        maxSuRange=length(suBlocksCosts);
        onoffExtended=[initialOnOff_ud,onoff(unit,:)];
        onExtended=[zeros(1,initialOnOffLength),on(unit,:)];
        offExtended=[zeros(1,initialOnOffLength),off(unit,:)];
        if(startedOff)
            offExtended(1)=1;
        end
        %% on/off/z UC constraints (3bin)
        for t=initialOnOffLength+1:length(onExtended)
            Constraints = [Constraints, onExtended(t)-offExtended(t)==onoffExtended(t+1)-onoffExtended(t)];
            %t+1 and t since in onoffExtended we have an extra initial bit
            if(~dynamicUC || (dynamicUC && isfield(dynamicUCParams,'enforceOnoff') && ~dynamicUCParams.enforceOnoff))
                if(isfield(params,'SU_cost') && params.SU_cost);
                    Constraints = [Constraints, onExtended(t)+offExtended(t)<=1]; %take this line off if no SU cost is wanted
                    Constraints = [Constraints, sum(squeeze(z(unit,t-initialOnOffLength,:)))==onExtended(t)]; %take this line off if no SU cost is wanted
                    Objective=Objective+squeeze(z(unit,t-initialOnOffLength,:))'*suBlocksCosts; %take this line off if no SU cost is wanted
                    
                    for j=1:min(J-1,t-1) %take this block off if no SU cost is wanted
                        Constraints = [Constraints, z(unit,t-initialOnOffLength,j)<=offExtended(t-j)]; %can'
                        %t have == since for every 'off', we will have a '1' here
                        %(where there might not have been any 'on') - so sum(z)
                        %might be 1 or even more, and from the sum(z) constraint,
                        %we may have sum(z)==0
                        %Also, when on=1, there might be more than one y=1 in the window of 8
                        %time steps backwards. we rely on the optimizer to choose the smallest j among them
                        %since it is the cheapest
                    end
                else
                    Objective=Objective+onExtended(t)*suBlocksCosts(J);
                    %             take this line ON if no SU cost is wanted
                end
            end
        end
        
        for k = 2:length(onoffExtended)
            % indicator will be 1 only when switched on
            indicator = onoffExtended(k)-onoffExtended(k-1);
            range = k:min(length(onoffExtended),k+minup(unit)-1);
            % Constraints will be redundant unless indicator = 1
            Constraints = [Constraints, onoffExtended(range) >= indicator];
            % indicator will be 1 only when switched off
            indicator = onoffExtended(k-1)-onoffExtended(k);
            range = k:min(length(onoffExtended),k+mindown(unit)-1);
            % Constraints will be redundant unless indicator = 1
            Constraints = [Constraints, onoffExtended(range) <= 1-indicator];
        end
    end
end
%% solve
gurobiParams.MIPGap=1e-2; %(default is 1e-4)
% ops = sdpsettings('solver','gurobi','gurobi.MIPGap','1e-2','verbose',params.verbose); %gurobi,sdpa,mosek
% ops = sdpsettings('solver','mosek','mosek.MSK_DPAR_MIO_MAX_TIME',20,'verbose',params.verbose); %gurobi,sdpa,mosek
% ops = sdpsettings('solver','mosek','verbose',params.verbose); %gurobi,sdpa,mosek

% ops = sdpsettings('solver','gurobi','verbose',params.verbose); %gurobi,sdpa,mosek
% ops = sdpsettings('solver','cplex','cplex.timelimit',5,'verbose',params.verbose); %gurobi,sdpa,mosek
% ops = sdpsettings('solver','cplex','verbose',params.verbose);

% result=optimize(Constraints,Objective,ops); %verify that value(objective) is
solution_time =zeros(1,3);
solution_time(3)=toc
tic
result=optimize(Constraints,Objective,params.optimizationSettings); %verify that value(objective) is
solution_time(1) = toc
if(params.compare_solution_times && warm_start_mode)
    params.optimizationSettings.usex0 = 1;
    tic
    result=optimize(Constraints,Objective,params.optimizationSettings); %verify that value(objective) is
    solution_time(2) = toc
end

% the value of the objective , proper use will just be to
%calculate the objective cost given the solution (for OPF:
%sum(totcost(gencost,value(Pg))).*onoff )
Pg=value(Pg)*baseMVA;
objective=value(Objective);
onoff=value(onoff);
success = (~isempty(strfind(result.info,'Successfully solved')));
windSpilled=value(sp);
loadLost = value(ls);
%The dynamic UC optimization obviously wishes to minimize LS. However, in
%the current version (since July 2017), the LS is removed from the mid-term
%optimization objective.
if(dynamicUC)
    objective = objective - value(loadShedding_cost);
end
%% save warm_start values
warm_start.ls = value(ls);
warm_start.sp = value(sp);
warm_start.onoff = value(onoff);
warm_start.Objective = value(Objective);
warm_start.Pg = value(Pg);
warm_start.on = value(on);
warm_start.off = value(off);
warm_start.z = value(z);
warm_start.Va = value(Va);
warm_start.y = value(y);
% warm_start.onExtended = value(onExtended);
% warm_start.offExtended = value(offExtended);
% warm_start.onoffExtended = value(onoffExtended);



