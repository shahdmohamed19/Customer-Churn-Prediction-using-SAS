/* import data */
%web_drop_table(WORK.IMPORT);

FILENAME REFFILE '../data/customer_churn_dataset-training-master.csv';

PROC IMPORT DATAFILE=REFFILE
	DBMS=CSV
	OUT=WORK.IMPORT;
	GETNAMES=YES;
RUN;

PROC CONTENTS DATA=WORK.IMPORT; RUN;


%web_open_table(WORK.IMPORT);
/* head */
title "First 10 Rows of the Dataset (Head)";
proc print data=WORK.IMPORT (obs=10);
run;
title;

/* Frequency analysis for categorical patterns and Target (Churn) */
title "Frequency Distribution of Categorical Variables";
proc freq data=WORK.IMPORT;
    tables Gender 'Subscription Type'n 'Contract Length'n Churn;
run;
title;

/* missing values in numeric columns */
title "Missing values in numeric columns";
proc means data=WORK.IMPORT n nmiss; 
run;
title;

/* Statistical Summary */
proc means data=WORK.IMPORT n mean std min max;
    var Age Tenure 'Usage Frequency'n 'Support Calls'n 'Payment Delay'n 'Total Spend'n 'Last Interaction'n;
run;

/* Cheking for duplicated */
title "Total Number of Duplicate Customer IDs";
proc sql;
    select count(*) as Duplicates
    from (
        select CustomerID
        from WORK.IMPORT
        group by CustomerID
        having count(*) > 1
    );
quit;
title;

/* visualization */
/* A. Distribution of the Target Variable (Churn) */
title "Analysis of Customer Churn Distribution";
proc sgplot data=WORK.IMPORT;
    vbar Churn / stat=percent datalabel;
run;

/* B. Distribution of Age */
title "Customer Age Distribution";
proc sgplot data=WORK.IMPORT;
    histogram Age / fillattrs=(color=CX3A5FCD);
    density Age;
run;

/* C. 1. Calculate Correlations */
proc corr data=WORK.IMPORT noprint outp=WORK.CORR_DATA;
    var Age Tenure 'Usage Frequency'n 'Support Calls'n 'Payment Delay'n 'Total Spend'n 'Last Interaction'n Churn;
run;

/* 2. Prepare the data */
data WORK.CORR_LONG;
    set WORK.CORR_DATA;
    where _TYPE_ = 'CORR';
    array vars(*) Age Tenure 'Usage Frequency'n 'Support Calls'n 'Payment Delay'n 'Total Spend'n 'Last Interaction'n Churn;
    Variable1 = _NAME_;
    do i = 1 to dim(vars);
        Variable2 = vname(vars(i));
        Corr_Value = vars(i);
        Corr_Label = put(Corr_Value, 6.2); 
        output;
    end;
    keep Variable1 Variable2 Corr_Value Corr_Label;
run;

/* 3. Create Heatmap */
title "Correlation Heatmap";
proc sgplot data=WORK.CORR_LONG noautolegend;
    heatmapparm x=Variable1 y=Variable2 colorresponse=Corr_Value / 
                colormodel=(Blue White Red) 
                outline name="heat";
    
    text x=Variable1 y=Variable2 text=Corr_Label / 
         textattrs=(size=8 weight=bold color=black) 
         strip;

    gradlegend "heat" / title="Correlation";
    xaxis display=(nolabel);
    yaxis display=(nolabel);
run;
title;

/* Outliers detection */

/* 1. Boxplot for Age */
title "Age Outliers by Churn";
proc sgplot data=WORK.IMPORT;
    vbox Age / category=Churn;
run;

/* 2. Boxplot for Tenure */
title "Tenure Outliers by Churn";
proc sgplot data=WORK.IMPORT;
    vbox Tenure / category=Churn;
run;

/* 3. Boxplot for Usage Frequency */
title "Usage Frequency Outliers by Churn";
proc sgplot data=WORK.IMPORT;
    vbox 'Usage Frequency'n / category=Churn;
run;

/* 4. Boxplot for Support Calls */
title "Support Calls Outliers by Churn";
proc sgplot data=WORK.IMPORT;
    vbox 'Support Calls'n / category=Churn;
run;

/* 5. Boxplot for Payment Delay */
title "Payment Delay Outliers by Churn";
proc sgplot data=WORK.IMPORT;
    vbox 'Payment Delay'n / category=Churn;
run;

/* 6. Boxplot for Total Spend */
title "Total Spend Outliers by Churn";
proc sgplot data=WORK.IMPORT;
    vbox 'Total Spend'n / category=Churn;
run;

/* 7. Boxplot for Last Interaction */
title "Last Interaction Outliers by Churn";
proc sgplot data=WORK.IMPORT;
    vbox 'Last Interaction'n / category=Churn;
run;


/* Preprocessing */


/*Train-Test Split*/
PROC SURVEYSELECT DATA=WORK.IMPORT
    OUT=WORK.TRAIN_SELECTED
    METHOD=SRS
    SAMPRATE=0.80
    SEED=42
    OUTALL;
RUN;

DATA WORK.TRAIN WORK.TEST;
    SET WORK.TRAIN_SELECTED;
    IF Selected = 1 THEN OUTPUT WORK.TRAIN;
    ELSE OUTPUT WORK.TEST;
    DROP Selected SelectionProb SamplingWeight;
RUN;

/* Check split sizes */
title "Train Set Size";
PROC SQL;
    SELECT COUNT(*) AS Train_Rows FROM WORK.TRAIN;
QUIT;

title "Test Set Size";
PROC SQL;
    SELECT COUNT(*) AS Test_Rows FROM WORK.TEST;
QUIT;
title;


/*Cleaning the data*/

/*Calculate Medians*/
PROC MEANS DATA=WORK.TRAIN MEDIAN NOPRINT;
    VAR Age 'Total Spend'n;
    OUTPUT OUT=WORK.MEDIANS MEDIAN= Age_Med TotalSpend_Med;
RUN;

DATA _NULL_;
    SET WORK.MEDIANS;
    CALL SYMPUTX('Age_Med', ROUND(Age_Med, 1));
    CALL SYMPUTX('TotalSpend_Med', ROUND(TotalSpend_Med, 1));
RUN;

/* Impute Missing Values  */
DATA WORK.TRAIN;
    SET WORK.TRAIN;
    IF Age = . THEN Age = &Age_Med.;
    IF 'Total Spend'n = . THEN 'Total Spend'n = &TotalSpend_Med.;
    IF Gender = "" THEN Gender = "Unknown";
RUN;

/* Apply same values to TEST */
DATA WORK.TEST;
    SET WORK.TEST;
    IF Age = . THEN Age = &Age_Med.;
    IF 'Total Spend'n = . THEN 'Total Spend'n = &TotalSpend_Med.;
    IF Gender = "" THEN Gender = "Unknown";
RUN;

/* Verify No Missing Values Remain */
proc means data=WORK.TRAIN n nmiss; run;
proc means data=WORK.TEST n nmiss; run;

/*Reassign CustomerID  */
DATA WORK.TRAIN;
    RETAIN CustomerID;  
    SET WORK.TRAIN (DROP=CustomerID);
    CustomerID = _N_;   
RUN;
DATA WORK.TEST;
    RETAIN CustomerID;  
    SET WORK.TEST (DROP=CustomerID);
    CustomerID = _N_;
RUN;

/* --- Label Encoding for Categorical Variables --- */
DATA WORK.TRAIN;
    SET WORK.TRAIN;
    
    Gender_Female  = (Gender = "Female");
    Gender_Male    = (Gender = "Male");
    Gender_Unknown = (Gender = "Unknown");

    IF 'Subscription Type'n = "Basic"    THEN SubType_Enc = 0;
    IF 'Subscription Type'n = "Standard" THEN SubType_Enc = 1;
    IF 'Subscription Type'n = "Premium"  THEN SubType_Enc = 2;


    IF 'Contract Length'n = "Monthly"   THEN Contract_Enc = 0;
    IF 'Contract Length'n = "Quarterly" THEN Contract_Enc = 1;
    IF 'Contract Length'n = "Annual"    THEN Contract_Enc = 2;
    DROP Gender 'Subscription Type'n 'Contract Length'n;
RUN;
/* Apply same Label Encoding to TEST */
DATA WORK.TEST;
    SET WORK.TEST;
    
    Gender_Female  = (Gender = "Female");
    Gender_Male    = (Gender = "Male");
    Gender_Unknown = (Gender = "Unknown");

    IF 'Subscription Type'n = "Basic"    THEN SubType_Enc = 0;
    IF 'Subscription Type'n = "Standard" THEN SubType_Enc = 1;
    IF 'Subscription Type'n = "Premium"  THEN SubType_Enc = 2;

    IF 'Contract Length'n = "Monthly"   THEN Contract_Enc = 0;
    IF 'Contract Length'n = "Quarterly" THEN Contract_Enc = 1;
    IF 'Contract Length'n = "Annual"    THEN Contract_Enc = 2;

    DROP Gender 'Subscription Type'n 'Contract Length'n;
RUN;
/* Get Train Min/Max */

/* feature engineering*/
DATA WORK.TRAIN; 
    SET WORK.TRAIN;

	/* 1. Support Call Rate */
	/* To Calculate how many times a customer complains per month */

    IF Tenure > 0 THEN SupportCallRate = 'Support Calls'n / Tenure;
    ELSE SupportCallRate = 0;

    /* 2. Monthly Spending Rate */
    /*  TO Calculate how much money the customer spends per month */
    IF Tenure > 0 THEN SpendingPerTenure = 'Total Spend'n / Tenure;
    ELSE SpendingPerTenure = 0;

    /* 3. Payment Risk Index */
    /*To Combine payment delays and support calls to find high-risk customers */
    PaymentRisk = 'Payment Delay'n + 'Support Calls'n;

    /* 4. Age Group Feature */
    /* Group ages into 3 categories to help the model see patterns */
    LENGTH AgeGroup $10;
    IF Age < 30 THEN AgeGroup = 'Young';
    ELSE IF Age >= 30 AND Age < 50 THEN AgeGroup = 'Adult';
    ELSE AgeGroup = 'Senior';
RUN;
DATA WORK.TEST;
    SET WORK.TEST;

    IF Tenure > 0 THEN SupportCallRate = 'Support Calls'n / Tenure;
    ELSE SupportCallRate = 0;

    IF Tenure > 0 THEN SpendingPerTenure = 'Total Spend'n / Tenure;
    ELSE SpendingPerTenure = 0;

    PaymentRisk = 'Payment Delay'n + 'Support Calls'n;

    LENGTH AgeGroup $10;
    IF Age < 30 THEN AgeGroup = 'Young';
    ELSE IF Age >= 30 AND Age < 50 THEN AgeGroup = 'Adult';
    ELSE AgeGroup = 'Senior';
RUN;

/*  To preview neww Features */

	title "Preview of the 4 New Engineered Features";
	PROC PRINT DATA=TRAIN (OBS=15);
    VAR CustomerID SupportCallRate SpendingPerTenure PaymentRisk AgeGroup;
RUN;

			/* Statistical Summary */

	title "Statistical Summary for New Features";
	PROC MEANS DATA=WORK.TRAIN N MEAN MIN MAX STD;
    VAR SupportCallRate SpendingPerTenure PaymentRisk;
RUN;

			/*	Visualizing Engineered Features Impact on Churn  */
									
																		
	/*  To Show which age group has the most customers leaving (Churn) */
	title "Churn Distribution by Age Group";
	proc sgplot data=TRAIN;
    vbar AgeGroup / group=Churn stat=percent missing;
    xaxis label="Age Categories";
    yaxis label="Percentage of Customers (%)";
run;
	title;

	/* To Check if customers who left had more complaints per month */
	title "Support Call Rate vs. Customer Churn";
	proc sgplot data=WORK.TRAIN;
    vbox SupportCallRate / category=Churn fillattrs=(color=CXE69F00);
    xaxis label="Customer Status (Churn)";
    yaxis label="Support Calls per Month (Rate)";
run;
PROC MEANS DATA=WORK.TRAIN NOPRINT;
    VAR Age Tenure 'Usage Frequency'n 
        'Support Calls'n 'Payment Delay'n 
        'Total Spend'n 'Last Interaction'n
         SupportCallRate SpendingPerTenure PaymentRisk;
    OUTPUT OUT=WORK.SCALE_STATS
        MEAN=Age_Mean Tenure_Mean Usage_Mean Support_Mean Delay_Mean Spend_Mean Last_Mean
                 SCR_Mean SPT_Mean PR_Mean
        STD=Age_Std Tenure_Std Usage_Std Support_Std Delay_Std Spend_Std Last_Std SCR_Std  SPT_Std  PR_Std;
RUN;
/* Encode AgeGroup */
DATA WORK.TRAIN;
    SET WORK.TRAIN;

    IF AgeGroup="Young"  THEN AgeGroup_Enc=0;
    ELSE IF AgeGroup="Adult"  THEN AgeGroup_Enc=1;
    ELSE IF AgeGroup="Senior" THEN AgeGroup_Enc=2;

    DROP AgeGroup;
RUN;

DATA WORK.TEST;
    SET WORK.TEST;

    IF AgeGroup="Young"  THEN AgeGroup_Enc=0;
    ELSE IF AgeGroup="Adult"  THEN AgeGroup_Enc=1;
    ELSE IF AgeGroup="Senior" THEN AgeGroup_Enc=2;

    DROP AgeGroup;
RUN;

/* Standardize TRAIN dataset */
/* Apply Standardization to TRAIN */
DATA WORK.TRAIN;
   IF _N_=1 THEN SET WORK.SCALE_STATS
    (KEEP=Age_Mean Age_Std Tenure_Mean Tenure_Std Usage_Mean Usage_Std 
          Support_Mean Support_Std Delay_Mean Delay_Std Spend_Mean Spend_Std 
          Last_Mean Last_Std
          SCR_Mean SCR_Std SPT_Mean SPT_Std PR_Mean PR_Std);
    SET WORK.TRAIN;

    Age    = (Age - Age_Mean) / Age_Std;
    Tenure = (Tenure - Tenure_Mean) / Tenure_Std;
    'Usage Frequency'n = ('Usage Frequency'n - Usage_Mean) / Usage_Std;
    'Support Calls'n   = ('Support Calls'n - Support_Mean) / Support_Std;
    'Payment Delay'n   = ('Payment Delay'n - Delay_Mean) / Delay_Std;
    'Total Spend'n     = ('Total Spend'n - Spend_Mean) / Spend_Std;
    'Last Interaction'n= ('Last Interaction'n - Last_Mean) / Last_Std;
    SupportCallRate = (SupportCallRate - SCR_Mean) / SCR_Std;
    SpendingPerTenure = (SpendingPerTenure - SPT_Mean) / SPT_Std;
    PaymentRisk = (PaymentRisk - PR_Mean) / PR_Std;

    DROP Age_Mean Age_Std Tenure_Mean Tenure_Std Usage_Mean Usage_Std 
     Support_Mean Support_Std Delay_Mean Delay_Std Spend_Mean Spend_Std 
     Last_Mean Last_Std
     SCR_Mean SCR_Std SPT_Mean SPT_Std PR_Mean PR_Std;
RUN;

/* Apply Standardization to TEST */
DATA WORK.TEST;
    IF _N_=1 THEN SET WORK.SCALE_STATS
    (KEEP=Age_Mean Age_Std Tenure_Mean Tenure_Std Usage_Mean Usage_Std 
          Support_Mean Support_Std Delay_Mean Delay_Std Spend_Mean Spend_Std 
          Last_Mean Last_Std
          SCR_Mean SCR_Std SPT_Mean SPT_Std PR_Mean PR_Std);
    SET WORK.TEST;

    Age    = (Age - Age_Mean) / Age_Std;
    Tenure = (Tenure - Tenure_Mean) / Tenure_Std;
    'Usage Frequency'n = ('Usage Frequency'n - Usage_Mean) / Usage_Std;
    'Support Calls'n   = ('Support Calls'n - Support_Mean) / Support_Std;
    'Payment Delay'n   = ('Payment Delay'n - Delay_Mean) / Delay_Std;
    'Total Spend'n     = ('Total Spend'n - Spend_Mean) / Spend_Std;
    'Last Interaction'n= ('Last Interaction'n - Last_Mean) / Last_Std;
    SupportCallRate = (SupportCallRate - SCR_Mean) / SCR_Std;
    SpendingPerTenure = (SpendingPerTenure - SPT_Mean) / SPT_Std;
    PaymentRisk = (PaymentRisk - PR_Mean) / PR_Std;

        DROP Age_Mean Age_Std Tenure_Mean Tenure_Std Usage_Mean Usage_Std 
     Support_Mean Support_Std Delay_Mean Delay_Std Spend_Mean Spend_Std 
     Last_Mean Last_Std
     SCR_Mean SCR_Std SPT_Mean SPT_Std PR_Mean PR_Std;
RUN;

title "First 10 Rows of TRAIN Dataset";
proc print data=WORK.TRAIN (obs=10);
run;
title;
title "First 10 Rows of TEST Dataset";
proc print data=WORK.TEST (obs=10);
run;
title;
/*logistic model was choosen cuz of target variable is categorical with 0 and 1*/
proc logistic data=WORK.TRAIN descending plots(only)=roc;
    model Churn =
        Age Tenure 
        'Usage Frequency'n 
        'Support Calls'n 
        'Payment Delay'n 
        'Total Spend'n
        'Last Interaction'n
        SupportCallRate
        SpendingPerTenure
        PaymentRisk
        SubType_Enc
        Contract_Enc
        AgeGroup_Enc;
/* apllied it to test data and train data */
    score data=WORK.TRAIN out=WORK.PRED_TRAIN outroc=roc_data;
    score data=WORK.TEST out=WORK.PRED_TEST outroc= roc_tdata;
run;

proc contents data=Work.pred_train;
run;
proc contents data=Work.pred_test;
run;
/* getting best cutoffs instead of 0.5 */
proc sql;
create table best_cutoff as
select 
    _PROB_ as Cutoff,
    _SENSIT_ as Sensitivity,
    (1 - _1MSPEC_) as Specificity,
    (_SENSIT_ + (1 - _1MSPEC_) - 1) as Youden_Index
from roc_tdata
order by Youden_Index desc;

quit;

proc print data=best_cutoff(obs=5);
run;
/* we didnot use best cutoff because its not good in our scenario however it 
leads to more precesion*/
data pred_train_cm;
    set WORK.PRED_TRAIN;

    if P_1 >= 0.5 then Pred_Churn = 1;
    else Pred_Churn = 0;
run;

data pred_test_cm;
    set WORK.PRED_TEST;

    if P_1 >= 0.5 then Pred_Churn = 1;
    else Pred_Churn = 0;
run;

proc freq data=pred_train_cm;
    tables Churn * Pred_Churn / norow nocol nopercent;
run;

proc freq data=pred_test_cm;
    tables Churn * Pred_Churn / norow nocol nopercent;
run;
/*calculating metrices forboth train and test to determine whether there is overfitting or no*/
proc sql;
create table train_metrics as
select 
    "Train" as Dataset,

    /* TP, TN, FP, FN */
    sum(case when Churn=1 and Pred_Churn=1 then 1 else 0 end) as TP,
    sum(case when Churn=0 and Pred_Churn=0 then 1 else 0 end) as TN,
    sum(case when Churn=0 and Pred_Churn=1 then 1 else 0 end) as FP,
    sum(case when Churn=1 and Pred_Churn=0 then 1 else 0 end) as FN,

    /* Metrics */
    calculated TP / (calculated TP + calculated FN) as Recall format=percent8.2,
    calculated TP / (calculated TP + calculated FP) as Precision format=percent8.2,
    (2 * calculated Precision * calculated Recall) / (calculated Precision + calculated Recall) as F1 format=percent8.2,
    (calculated TP + calculated TN) / 
    (calculated TP + calculated TN + calculated FP + calculated FN) as Accuracy format=percent8.2

from pred_train_cm;
quit;

proc sql;
create table test_metrics as
select 
    "Test" as Dataset,

    sum(case when Churn=1 and Pred_Churn=1 then 1 else 0 end) as TP,
    sum(case when Churn=0 and Pred_Churn=0 then 1 else 0 end) as TN,
    sum(case when Churn=0 and Pred_Churn=1 then 1 else 0 end) as FP,
    sum(case when Churn=1 and Pred_Churn=0 then 1 else 0 end) as FN,

    calculated TP / (calculated TP + calculated FN) as Recall format=percent8.2,
    calculated TP / (calculated TP + calculated FP) as Precision format=percent8.2,
    (2 * calculated Precision * calculated Recall) / (calculated Precision + calculated Recall) as F1 format=percent8.2,
    (calculated TP + calculated TN) / 
    (calculated TP + calculated TN + calculated FP + calculated FN) as Accuracy format=percent8.2

from pred_test_cm;
quit;
/* table for comparing */
data comparison;
    set train_metrics test_metrics;
run;

proc print data=comparison label;
run;
/* difference in metrices */
proc sql;
select 
    a.Accuracy - b.Accuracy as Diff_Accuracy,
    a.Recall - b.Recall as Diff_Recall,
    a.Precision - b.Precision as Diff_Precision,
    a.F1 - b.F1 as Diff_F1
from train_metrics a, test_metrics b;
quit;

/* Decision Tree Model */
proc hpsplit data=WORK.TRAIN seed=42 maxdepth=5 minleafsize=100;
    class Churn SubType_Enc Contract_Enc AgeGroup_Enc;

    model Churn =
        Age Tenure 
        'Usage Frequency'n 
        'Total Spend'n
        'Last Interaction'n
        SubType_Enc
        Contract_Enc
        AgeGroup_Enc;

    grow entropy;
    prune costcomplexity;

    code file="../code/tree_score.sas";
run;
/*run model*/

data TREE_TRAIN;
    set WORK.TRAIN;
    %include "../code/tree_score.sas";
run;

data TREE_TEST;
    set WORK.TEST;
    %include "../code/tree_score.sas";
run;
data TREE_TRAIN_CM;
    set TREE_TRAIN;
    if P_Churn1 >= 0.5 then Pred_Churn = 1;
    else Pred_Churn = 0;
run;

data TREE_TEST_CM;
    set TREE_TEST;
    if P_Churn1 >= 0.5 then Pred_Churn = 1;
    else Pred_Churn = 0;
run;

proc sql;
create table tree_train_metrics as
select 
    "Tree_Train" as Dataset,

    sum(case when Churn=1 and Pred_Churn=1 then 1 else 0 end) as TP,
    sum(case when Churn=0 and Pred_Churn=0 then 1 else 0 end) as TN,
    sum(case when Churn=0 and Pred_Churn=1 then 1 else 0 end) as FP,
    sum(case when Churn=1 and Pred_Churn=0 then 1 else 0 end) as FN,

    calculated TP / (calculated TP + calculated FN) as Recall format=percent8.2,
    calculated TP / (calculated TP + calculated FP) as Precision format=percent8.2,
    (2 * calculated Precision * calculated Recall) /
    (calculated Precision + calculated Recall) as F1 format=percent8.2,
    (calculated TP + calculated TN) /
    (calculated TP + calculated TN + calculated FP + calculated FN) as Accuracy format=percent8.2

from TREE_TRAIN_CM;
quit;


proc sql;
create table tree_test_metrics as
select 
    "Tree_Test" as Dataset,

    sum(case when Churn=1 and Pred_Churn=1 then 1 else 0 end) as TP,
    sum(case when Churn=0 and Pred_Churn=0 then 1 else 0 end) as TN,
    sum(case when Churn=0 and Pred_Churn=1 then 1 else 0 end) as FP,
    sum(case when Churn=1 and Pred_Churn=0 then 1 else 0 end) as FN,

    calculated TP / (calculated TP + calculated FN) as Recall format=percent8.2,
    calculated TP / (calculated TP + calculated FP) as Precision format=percent8.2,
    (2 * calculated Precision * calculated Recall) /
    (calculated Precision + calculated Recall) as F1 format=percent8.2,
    (calculated TP + calculated TN) /
    (calculated TP + calculated TN + calculated FP + calculated FN) as Accuracy format=percent8.2

from TREE_TEST_CM;
quit;

data tree_final_metrics;
    set tree_train_metrics tree_test_metrics;
run;

proc print data=tree_final_metrics label;
run;
