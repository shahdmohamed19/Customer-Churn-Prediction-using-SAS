****************************************************************;
******        HP TREE (PROC HPSPLIT) SCORING CODE        ******;
****************************************************************;
 
******              LABELS FOR NEW VARIABLES              ******;
LABEL _Node_ = 'Node number';
LABEL _Leaf_ = 'Leaf number';
LABEL _WARN_ = 'Warnings';
LABEL P_Churn0 = 'Predicted: Churn=0';
LABEL P_Churn1 = 'Predicted: Churn=1';
 
 _WARN_ = ' ';
 
******      TEMPORARY VARIABLES FOR FORMATTED VALUES      ******;
LENGTH _RT_6_12 $12;
_RT_6_12 = ' ';
DROP _RT_6_12;
_RT_6_12 = LEFT(TRIM(PUT(Contract_Enc, BEST12.)));
 
******             ASSIGN OBSERVATION TO NODE             ******;
IF NOT MISSING('Total Spend'n) AND (('Total Spend'n < -0.5628976740423819))
 THEN DO;
  _Node_ = 1;
  _Leaf_ = 0;
  P_Churn0 = 0;
  P_Churn1 = 1;
END;
ELSE DO;
  IF NOT MISSING(Contract_Enc) AND (_RT_6_12 IN ('0') )
   THEN DO;
    _Node_ = 4;
    _Leaf_ = 1;
    P_Churn0 = 0;
    P_Churn1 = 1;
  END;
  ELSE DO;
    IF NOT MISSING(Age) AND ((Age >= 0.8886629836193356))
     THEN DO;
      _Node_ = 6;
      _Leaf_ = 3;
      P_Churn0 = 0;
      P_Churn1 = 1;
    END;
    ELSE DO;
      _Node_ = 5;
      _Leaf_ = 2;
      P_Churn0 = 0.77324975;
      P_Churn1 = 0.22675025;
    END;
END;
END;
****************************************************************;
******     END OF HP TREE (PROC HPSPLIT) SCORING CODE    ******;
****************************************************************;
