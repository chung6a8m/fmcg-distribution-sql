-- Regression for P1: no double-rounding before whole-VND cost allocation.
-- Expected numbers here are derived independently by integer arithmetic.
SET NOCOUNT ON;
SET XACT_ABORT ON;
-- 20000000 * 975001 / 1000001 = 19500000.499999500000...
IF ac06.RoundProratedCost(20000000,975001,1000001)<>19500000
    THROW 53950,'NEAR_HALF_CUMULATIVE_ROUNDING_WRONG',1;
IF ac06.RoundProratedCost(20000000,25000,1000001)<>500000
 OR ac06.RoundProratedCost(20000000,1000001,1000001)<>20000000
 OR ac06.RoundProratedCost(20000000,0,1000001)<>0
    THROW 53951,'PRORATION_RESIDUAL_OR_BOUNDARY_WRONG',1;
IF ac06.RoundProratedCost(1,1,2)<>1
 OR ac06.RoundProratedCost(1,1,3)<>0
 OR ac06.RoundProratedCost(6667,1,2)<>3334
    THROW 53952,'PRORATION_TIE_POLICY_WRONG',1;
IF ac06.RoundProratedCost(1,3,2) IS NOT NULL
 OR ac06.RoundProratedCost(1,1,0) IS NOT NULL
 OR ac06.RoundProratedCost(-1,1,2) IS NOT NULL
    THROW 53953,'PRORATION_INVALID_INPUT_ACCEPTED',1;
IF ac06.RoundProratedCost(
      CONVERT(decimal(28,0),'9999999999999999999999999999'),
      2147483647,2147483647)
   <>CONVERT(decimal(28,0),'9999999999999999999999999999')
    THROW 53954,'PRORATION_MAX_AMOUNT_WRONG',1;

-- Separate tenant and sources: exercise real ISSUE, RETURN, REVALUE postings.
INSERT ac06.Period(TenantId,PeriodId,PeriodState,ClosedBy)
 VALUES('T_ROUND','P1','OPEN',NULL),('T_ROUND','P2','OPEN',NULL);
INSERT ac06.StockLocation(TenantId,SkuId,LocationId,LocationKind)
 VALUES('T_ROUND','SKU_I','MAIN','AVAILABLE'),
       ('T_ROUND','SKU_R','MAIN','AVAILABLE'),
       ('T_ROUND','SKU_R','QA','QUARANTINE');
DECLARE @Result varchar(32);
EXEC ac06.PostCommand 'T_ROUND','I_RECEIVE','RECEIVE','P1',
    @SkuId='SKU_I',@LocationId='MAIN',@Qty=1000001,@CostAmount=20000000,
    @Result=@Result OUTPUT;
EXEC ac06.PostCommand 'T_ROUND','I_ISSUE_NEAR_HALF','ISSUE','P1',
    @SkuId='SKU_I',@LocationId='MAIN',@Qty=975001,@Result=@Result OUTPUT;
IF NOT EXISTS(SELECT 1 FROM ac06.IssueSource
    WHERE TenantId='T_ROUND' AND SourceId='I_ISSUE_NEAR_HALF'
      AND IssueQty=975001 AND OriginalCost=19500000)
 OR NOT EXISTS(SELECT 1 FROM ac06.StockBalances
    WHERE TenantId='T_ROUND' AND SkuId='SKU_I' AND LocationId='MAIN'
      AND Qty=25000 AND StockValue=500000)
    THROW 53955,'ISSUE_NEAR_HALF_MISPOSTED',1;
EXEC ac06.PostCommand 'T_ROUND','I_ISSUE_RESIDUAL','ISSUE','P1',
    @SkuId='SKU_I',@LocationId='MAIN',@Qty=25000,@Result=@Result OUTPUT;
IF NOT EXISTS(SELECT 1 FROM ac06.IssueSource
    WHERE TenantId='T_ROUND' AND SourceId='I_ISSUE_RESIDUAL'
      AND OriginalCost=500000)
 OR NOT EXISTS(SELECT 1 FROM ac06.StockBalances
    WHERE TenantId='T_ROUND' AND SkuId='SKU_I' AND LocationId='MAIN'
      AND Qty=0 AND StockValue=0)
    THROW 53956,'ISSUE_RESIDUAL_MISPOSTED',1;

EXEC ac06.PostCommand 'T_ROUND','R_RECEIVE','RECEIVE','P1',
    @SkuId='SKU_R',@LocationId='MAIN',@Qty=1000001,@CostAmount=20000001,
    @Result=@Result OUTPUT;
EXEC ac06.PostCommand 'T_ROUND','R_ISSUE','ISSUE','P1',
    @SkuId='SKU_R',@LocationId='MAIN',@Qty=1000001,@Result=@Result OUTPUT;
EXEC ac06.PostCommand 'T_ROUND','R_RETURN_1','RETURN','P1',
    @SkuId='SKU_R',@LocationId='QA',@SourceId='R_ISSUE',@Qty=975001,
    @Result=@Result OUTPUT;
IF NOT EXISTS(SELECT 1 FROM ac06.ReturnLine
     WHERE TenantId='T_ROUND' AND ReturnId='R_RETURN_1'
       AND RefundBase=19500001)
    THROW 53957,'FIRST_RETURN_NEAR_HALF_MISPOSTED',1;
UPDATE ac06.Period SET PeriodState='LOCKED',ClosedBy='ROUND_CLOSE'
 WHERE TenantId='T_ROUND' AND PeriodId='P1';
IF @@ROWCOUNT<>1 THROW 53958,'ROUND_TEST_PERIOD_NOT_LOCKED',1;
EXEC ac06.PostCommand 'T_ROUND','R_REVALUE','REVALUE','P2',
    @SourceId='R_ISSUE',@CostAmount=20000000,@Result=@Result OUTPUT;
IF NOT EXISTS(SELECT 1 FROM ac06.ReturnCostAdjustment
    WHERE TenantId='T_ROUND' AND AdjustmentId='R_REVALUE'
      AND ReturnId='R_RETURN_1' AND DeltaRefund=-1)
 OR NOT EXISTS(SELECT 1 FROM ac06.StockBalances
    WHERE TenantId='T_ROUND' AND SkuId='SKU_R' AND LocationId='QA'
      AND Qty=975001 AND StockValue=19500000)
    THROW 53959,'REVALUE_NEAR_HALF_NOT_CORRECTED',1;
EXEC ac06.PostCommand 'T_ROUND','R_RETURN_2','RETURN','P2',
    @SkuId='SKU_R',@LocationId='QA',@SourceId='R_ISSUE',@Qty=25000,
    @Result=@Result OUTPUT;
IF NOT EXISTS(SELECT 1 FROM ac06.ReturnLine
    WHERE TenantId='T_ROUND' AND ReturnId='R_RETURN_2'
      AND RefundBase=500000)
 OR NOT EXISTS(SELECT 1 FROM ac06.StockBalances
    WHERE TenantId='T_ROUND' AND SkuId='SKU_R' AND LocationId='QA'
      AND Qty=1000001 AND StockValue=20000000)
 OR (SELECT ISNULL(SUM(DeltaCogs),0) FROM ac06.CostEffect
      WHERE TenantId='T_ROUND' AND SourceId='R_ISSUE')<>0
    THROW 53960,'FINAL_RETURN_NEAR_HALF_DRIFT',1;
EXEC ac06.AssertLedger 'T_ROUND','I_ISSUE_NEAR_HALF';
EXEC ac06.AssertLedger 'T_ROUND','I_ISSUE_RESIDUAL';
EXEC ac06.AssertLedger 'T_ROUND','R_ISSUE';
