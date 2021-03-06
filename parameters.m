%% Parameters configuration file for the test-cases, algorithm, distributions and simulation
%% UC_NN simulation parameters
params.N_jobs_NN=150; %240
params.compare_solution_times = 1;
%Problem - correlation is very high for all values. My guess: it was classified using too large of a training set. Solution: try to reduce training size
params.training_set_effective_size=1; %0.05 - mainly for the reliability std test 
%% number of samples for building db in each job
params.N_samples_bdb = 1; %400
%% num samples for testing in each job
params.N_samples_test = ceil(params.N_samples_bdb/8);%1
%% choose whether to run in n-1 mode
params.n1_str = 'not-n1'; %'n1,not-n1'
%% Outage_scheduling simulation parameters
params.N_CE=15; %15
%in case5, 4 months, 75 plans , 2x10 - finished in 40 mins
%in case9, 4 months, 75 plans , 2x25 - finished in 4 hours
%in case9, 8 months, 75 plans , 3x25 - in 7 hours t.o, 280 out of 600
%reached
% in case24, 4 months, 75 plans, params.numOfDaysPerMonth=2;
% params.dynamicSamplesPerDay=15; - in 7 hours timeout, 100 of 300 plans
% finished
params.numOfDaysPerMonth=3; %3. currently 1 since there is no difference between them in any case
if(strcmp(config.program_name,'optimize'))
    %reduced to three since currently we draw very little contingencies, and reduced the rand_walk_w_std,rand_walk_d_std values
    params.dynamicSamplesPerDay=2; %3
else %compare mode
    params.dynamicSamplesPerDay=3; %5
end
params.N_plans=125; %75,150
params.numOfMonths=12; %when changing this, make sure generate_shared_DA_scenarios(params,i_month) is fixed to not rely on 8 months (hardcoded).
params.myopicUCForecast=0;
params.dropUpDownConstraints=0; %1
params.SU_cost = 1;
params.use_NN_UC = true; %true,false
%if false - success rate will be simply the rate of success
%if true - success rate will be computed as the portion of N-1 list that is
%recoverable, averaged over the 24-hours (increases complexity by a factor
%of params.nl, per each day of simulation)
params.n1_success_rate = true;
if(strcmp('case96',params.caseName))
    params.reliability_percentageTolerance = 80;
end
if(strcmp('case24',params.caseName))
    params.reliability_percentageTolerance = 50;
end
%% seperate the edited cases (which include dynamic parameters for UC,
%% s.a min up/down times, initial state, etc.) and the non-edited, classic matpower cases
if(sum(strcmp(caseName,{'case5','case9','case14','case24','case24_ieee_rts','case96'}))>0)
    params.caseName=caseName;
    caseParams=getSpecificCaseParams(caseName,'matpower_cases/ieee_RTS96_UW');
    generatorTypeVector=caseParams.generatorTypeVector;
    generatorBusVector=caseParams.generatorBusVector;
    
    caseParams.initialGeneratorState = flex_initial_generator_state(caseParams.initialGeneratorState);
    params.initialGeneratorState=caseParams.initialGeneratorState;
    loads=caseParams.loads;
    params.windScaleRatio=caseParams.windScaleRatio; %%wind generation mean will be devided by this factor
    
    
    generatorData=getGeneratorData();
    [mpcase,redispatch_price]=setCaseParams(caseName,generatorData,generatorTypeVector,generatorBusVector,loads,caseParams);
    params.redispatch_price = redispatch_price;
    
    if(strcmp('case96',params.caseName))
        params.numerical_branch = modify_to_numerical_branch(mpcase.branch);
    end
    
    unitsInfo=[];
    for g=generatorTypeVector
        unitsInfo=[unitsInfo;generatorData{g}.PMIN,generatorData{g}.PMAX,generatorData{g}.MD,generatorData{g}.MU];
    end
    params.PMIN=1;
    params.PMAX=2;
    params.MD=3; %column enum, not value!
    params.MU=4;
    params.unitsInfo=unitsInfo;
    
    params.generatorTypeVector=generatorTypeVector;
    params.generatorBusVector=generatorBusVector;
    params.generatorData=generatorData;
else
    funcHandle=str2func(caseName);
    mpcase=funcHandle();
end
params.mpcase=mpcase;

% small corrections needed for RTS96 network
% if(strcmp('case96',params.caseName))
%     case24_copy = case24_ieee_rts;
%     case24_pmin = case24_copy.gen(:,PMIN);
%     params.mpcase.gen(:,PMIN) = repmat(case24_pmin,[3,1]);
% end

params.verbose=0;
params.horizon=24;
%% data dimensions
params.nb   = size(mpcase.bus, 1);    %% number of buses
params.nl   = size(mpcase.branch, 1); %% number of branches
params.ng   = size(mpcase.gen, 1);    %% number of dispatchable injections
%% set up requested outages
ro = zeros(params.nl,1);

if(strcmp(caseName,'case96'))
    % if(strcmp(caseName,'case96'))
    %% some changes to make things interesting
    params.mpcase.branch([1;42;80],BR_STATUS)=0;
    params.mpcase.branch([1;42;80],RATE_A)=0;
    %These turned out to be over-restrictive
    
%      bus_change_local = [1,2]; bus_change = [bus_change_local,bus_change_local+24,bus_change_local+24*2];
%      for b=bus_change
%          params.mpcase.bus(b+2,[PD,QD])=params.mpcase.bus(b,[PD,QD])+params.mpcase.bus(b+2,[PD,QD]);
%          params.mpcase.bus(b,[PD,QD])=0;
%      end
%          params.mpcase.bus(10,BS) = params.mpcase.bus(6,BS);
%          params.mpcase.bus(6,BS) = 0;
    %For case96 we choose one area and then choose its outages. Therefore we have 3 columns.
    ro = zeros(120,3);
    if(~strcmp(params.n1_str,'n1'))
        
        ro(2:5,1)=2;      ro(11,1)=1;      %ro(33)=2;    %ro(40)=2; %
        ro(43:46,2)=2;    ro(52,2)=1;      %ro(72)=2;    %ro(79)=2; %
        ro(81:84,3)=2;    ro(90,3)=1;      %ro(110)=2;   %ro(117)=2;%
        
        ro(12,1:3)=1;  ro(119,1:3)=1; ro(120,1:3)=1;
    end
    
end

% if(strcmp(caseName,'case24') && ~strcmp(params.n1_str,'n1'))
if(strcmp(caseName,'case24'))
    %% some changes to make things interesting
    params.mpcase.branch(1,BR_STATUS)=0;
    params.mpcase.bus(3,[PD,QD])=params.mpcase.bus(1,[PD,QD])+params.mpcase.bus(3,[PD,QD]);
    params.mpcase.bus(1,[PD,QD])=0;
    params.mpcase.bus(4,[PD,QD])=params.mpcase.bus(2,[PD,QD])+params.mpcase.bus(4,[PD,QD]);
    params.mpcase.bus(2,[PD,QD])=0;
    
    params.mpcase.bus(10,BS) = params.mpcase.bus(6,BS);
    params.mpcase.bus(6,BS) = 0;
    params.mpcase.branch(1,RATE_A)=1e-9;
    params.mpcase.branch([24;27],RATE_A)=250;
%     if(~strcmp(params.n1_str,'n1'))
        ro(2:5)=2;   ro(11)=1; ro(25)=2;    ro(26)=2; %r(31)=2; r(38)=2;      
        %     if(strcmp(config.program_name,'compare')) %add some
        %
        %     end
%     end
end
if(strcmp(caseName,'case5'))
    ro(1)=2; ro(3)=1; ro(6)=1;
end
params.requested_outages = ro;
params.shrinkage_factor = 0.75; %shrink the schedule probability matrix entries
%that were chosen from one month to the next by this amount
%% wind params
params.windBuses = caseParams.windBuses;
params.windHourlyForcast = caseParams.windHourlyForcast;
params.windCurtailmentPrice=100; %[$/MW]
%% optimization parameters
params.alpha = 0.05; %0.05 % success_rate chance-constraint parameter : P['bad event']<alpha
%% demand and wind STDs
params.demandStd = 0.02;
params.muStdRatio = 0.05;
params.rand_walk_w_std = 0.01; %0.03
params.rand_walk_d_std = 0.002; %0.01
%% DEBUG! TODO: remove
% params.demandStd = 1e-9;
% params.muStdRatio = 1e-9;
% params.rand_walk_w_std = 1e-9; %%TODO: remove
% params.rand_walk_d_std = 1e-9;
%% VOLL
params.VOLL = 1000;
%% fine payment escalation cost
params.finePayment = sum(mpcase.bus(:,3))*params.VOLL; %multiple of the full LS cost - this is per hour
params.fixDuration=24*params.numOfDaysPerMonth+1;
%% optimization settings
params.verbose = 0;
% params.optimizationSettings =  sdpsettings('solver','mosek','mosek.MSK_DPAR_MIO_MAX_TIME',200,'verbose',params.verbose); %gurobi,sdpa,mosek
% params.optimizationSettings =  sdpsettings('solver','mosek','verbose',params.verbose);
% params.optimizationSettings = sdpsettings('solver','gurobi','gurobi.MIPGap','1e-2','verbose',params.verbose); %gurobi,sdpa,mosek

% params.optimizationSettings = sdpsettings('solver','cplex','cplex.timelimit',5,'verbose',params.verbose); %gurobi,sdpa,mosek

% params.optimizationSettings = sdpsettings('solver','cplex','verbose',params.verbose); %good for hermes
params.optimizationSettings = sdpsettings('solver','cplex','verbose',params.verbose,'cplex.output.clonelog',-1);

% ops = sdpsettings('solver','cplex');
%% db random NN mode
params.db_rand_mode = true;
%% contingency prob per line
if(strcmp('case96',params.caseName))
    params.failure_probability = 0.08;
else
    params.failure_probability = 0.15;
end
%% NN weighted norm
params.line_status_norm_weight = 100;
params.KNN = 10;
%% monthly wind-demand factor params
if(strcmp(params.caseName,'case24'))
    %     categories = linspace(2.5,5.5,5);
    categories = linspace(3.5,4.5,5);
    %     extra_categories = linspace(4.75,5.5,4);
    extra_categories = linspace(4.25,4.5,4);
    categories = [categories(1:3),extra_categories];
    monthly_categories_vec = [7,7:-1:1,2,4,5,6];
    monthly_categories = categories(monthly_categories_vec);
end

if(strcmp(params.caseName,'case96'))
    %     categories = linspace(2.5,5.5,5);
    categories = linspace(3.5,4.5,5);
    
    extra_categories = linspace(4.25,4.5,6);
    categories = [categories(1:3),extra_categories];
    monthly_categories_vec = [9:-1:2,3,5,7,9];
    monthly_categories = categories(monthly_categories_vec);
end

params.monthly_categories = monthly_categories;
params.categories = categories;
