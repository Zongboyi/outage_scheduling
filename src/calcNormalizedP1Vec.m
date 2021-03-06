function normalizedP1Vec=calcNormalizedP1Vec(p,epsilon,includeNull)
%generate a probability simplex vector, for drawing events where exactly one Xk=1
%of X1,...,Xn bernoulli variables. The way is to look at it as a binomial
%trial: P(X1=0,...,Xk=1,...Xn=0) = (n choose 1)*\Pi_{I/{k}}(1-pi)*pk = (n choose 1)*\Pi_{I}(1-pi)/(1-pk)*pk
%when using 'includeNull', the (n choose 1) coeff should be removed, but we
%neglected it here
%for computational efficiency, use log of that expression and at the end
%raise it to the power of exp
%this gives probability simplex vector by normalizing p1Vec, and afterwards
%using this simplex vector as multinomial distribution
pVec=p(:);
planProbVec=max(pVec,epsilon);
nullPlanProbVec=max((1-pVec),epsilon);
logNullPlanProb=sum(log(nullPlanProbVec));
p1LogVec=logNullPlanProb-log(nullPlanProbVec)+log(planProbVec);
if(includeNull)
    p1LogVec=[p1LogVec;logNullPlanProb]; %last entry is the null action (no assets mainained in this month)
end
p1Vec=exp(p1LogVec);
normalizedP1Vec=p1Vec/sum(p1Vec);
