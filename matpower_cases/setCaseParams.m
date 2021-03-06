function [modifiedMpcase,redispatch_price]=setCaseParams(caseName,generatorData,generatorTypeVector,generatorBusVector,loads,caseParams)
%this function is needed for updateing the test-case to fit Prof. Daniel Kirschen's group in UW. 
%costs and generation values are updated. Also, there are 32x3 generators
%both in the original and updated test cases, however in the original one
%there is an additional fake generator in each area for some reason, so
%overall it technically has 99 generators. We add this fake generator to
%sync the two test-cases (for matpower's internal functions not to go crazy).

%Update: cancelled all of the above and changed the actual case96.m to have
%96 generators.
redispatch_price = zeros(length(generatorTypeVector),1);
if(strcmp(caseName,'case24'))
    caseName='case24_ieee_rts';
end
funcHandle=str2func(caseName);
modifiedMpcase=funcHandle();
modifiedMpcase.gencost=[];
modifiedMpcase.gen=[];
for g=1:length(generatorTypeVector)
    modifiedMpcase.gencost=[modifiedMpcase.gencost;buildCostRow(generatorData{generatorTypeVector(g)})];
    modifiedMpcase.gen=[modifiedMpcase.gen;generatorBusVector(g) generatorData{generatorTypeVector(g)}.PMAX	0	30	-30	 1	100	1	generatorData{generatorTypeVector(g)}.PMAX	generatorData{generatorTypeVector(g)}.PMIN 	0	0   	0	0	0	0	0	0	0	0	0];
    redispatch_price(g) = mean(generatorData{generatorTypeVector(g)}.cost.segmentSlopes);
end
if(~strcmp(caseName,'case24_ieee_rts')) % for all except case24 - no longer deciding on loads on my own, just rescaling
    loadToGenRatio=0.8; %change 1.2 to 0.8
    loadRescaleFactor=getLoadRescaleFactor(loadToGenRatio,modifiedMpcase,caseParams);
    modifiedMpcase.bus=scale_load(loadRescaleFactor,modifiedMpcase.bus);
else
    modifiedMpcase.bus(:,3)=loads;
end
if(strcmp(caseName,'case96'))
%     fake_gen_row = zeros(1,20);
%     fake_gen_row(7) = 1;
%     modifiedMpcase.gen = [modifiedMpcase.gen(1:14,:);[14,fake_gen_row];modifiedMpcase.gen(15:46,:);[38,fake_gen_row];modifiedMpcase.gen(47:78,:);[62,fake_gen_row];modifiedMpcase.gen(79:96,:)];
%     modifiedMpcase.gencost = [modifiedMpcase.gencost(1:14,:);modifiedMpcase.gencost(14,:);modifiedMpcase.gencost(15:46,:);modifiedMpcase.gencost(46,:);modifiedMpcase.gencost(47:78,:);modifiedMpcase.gencost(78,:);modifiedMpcase.gencost(79:96,:)];
    c=case96; original_gen_buses = c.gen(:,1);
    modifiedMpcase.gen(:,1) = original_gen_buses;
    modifiedMpcase.gen(11,1) = 108;  modifiedMpcase.gen(42,1) = 206;  modifiedMpcase.gen(75,1) = 306;    
end