num_of_plots = 10;
values = zeros(num_of_plots,i_CE-1);
values_med = zeros(num_of_plots,i_CE-1);
for j=1:i_CE-1
    stats=cell(8,1);
    for i = 1:length(cell2mat(bestPlanVecTemp(4,:,j)))
        if(~isempty(bestPlanVecTemp{4,i,j}))
            c=c+1;
            stats{1}=[stats{1}, bestPlanVecTemp{4,i,j}];
            stats{2}=[stats{2},bestPlanVecTemp{7,i,j}];
            stats{3}=[stats{3},bestPlanVecTemp{8,i,j}]; %success rate values
            stats{4} = [stats{4},K*success_rate_barrier(bestPlanVecTemp{8,i,j},barrier_struct,params.alpha,1)];
            stats{5}=[stats{5},bestPlanVecTemp{6,i,j}]; %lost load
            if(~isempty(bestPlanVecTemp{9,i,j}))              %one-time fix. remove after used onces (happened since I(j_plan) was not originally used for bestPlanVecTemp{9,i,j})   
                stats{6}=[stats{6},bestPlanVecTemp{9,i,j}]; %relative std
            end
            stats{7}=[stats{7},bestPlanVecTemp{10,i,j}]; %LS barrier
            stats{8}=[stats{8},bestPlanVecTemp{11,i,j}]; % objective cost
        end
    end
    mean_stat_6 = mean(stats{6}); rep_mean_6 = repmat(mean_stat_6,size(stats{1})); %one-time fix. remove after used onces
    vec_of_interest = [stats{1};stats{1}-stats{5}*params.VOLL;stats{2};stats{3};stats{5};rep_mean_6;stats{1}+stats{2};stats{1}+stats{4};stats{7};stats{8}];
    values(:,j) = mean(vec_of_interest,2); %replace mean_stat_6 with stats{6}
    values_med(:,j) = median(vec_of_interest,2); %replace mean_stat_6 with stats{6}

end

figure(9);
titles={'planValues','planValues with deducted load shedding','success rate barrier values','success rate values','lost load','relative std','overall objective values','overall objective values - normalized barrier values','LS barrier','Total orig objective'};
%this is averaged over months (average planValues per month)
for i_plot=1:num_of_plots
    subplot(2,5,i_plot);
    plot(values(i_plot,:));
    title(titles{i_plot});
end
set(gcf,'name','Means','numbertitle','off')

figure(10);
%this is averaged over months (average planValues per month)
for i_plot=1:num_of_plots
    subplot(2,5,i_plot);
    plot(values_med(i_plot,:));
    title(titles{i_plot});
end

set(gcf,'name','Medians','numbertitle','off')

figure(11);
xyHandles = zeros(1,i_CE-1);
%this is averaged over months (average planValues per month)
x_min = 1;
for i_plot=1:i_CE-1
    xyHandles(i_plot) = subplot(4,4,i_plot);
    [n1,x1] = hist(cell2mat(bestPlanVecTemp(8,:,i_plot)),150);
    x_min = min(x_min,min(x1));
    bar(x1,n1/sum(n1));
    title(num2str(i_plot));
end

linkaxes(xyHandles,'xy');
ylim([0,0.11]);
xlim([0,1]);


% for j=1:6
%     size(stats{j})
% end

%% reconstruct o3 - for the experiment done when it wasn't available
% o3_values = zeros(1,i_CE-1);
%
% for j=1:i_CE-1
%     o3=[];
%     for i = 1:length(S_sorted)
%         if(~isempty(bestPlanVecTemp{7,i,j}))
%             o2_curr_val = bestPlanVecTemp{7,i,j};
%             syms t
%             eqn = (1/j)*(0.5*(j*(t-params.alpha)*barrier_struct.x0/(1-params.alpha))^2 + (j*(t-params.alpha)*barrier_struct.x0/(1-params.alpha))) == o2_curr_val;
%             res = solve(eqn,t);
%             res_val = double(res);
%             o3_curr_val = res_val(res_val>0);
%             o3 = [o3,o3_curr_val];
%             j
%             i
%         end
%     end
%     o3_values(j) = mean(o3);
% end
%
% values(3,:) = o3_values;
% and now run the subplot again to include o3

