-- SQL-03C AC-06 synthetic inputs: source cost is CALCULATED from a
-- location-specific moving average, not inserted as a golden expected value.
-- No accounting period is ever rewritten after LOCKED.
SET NOCOUNT ON;
SET XACT_ABORT ON;
INSERT ac06.Period(TenantId,PeriodId,PeriodState,ClosedBy)
VALUES('T_COST','P1','OPEN',NULL),('T_COST','P2','OPEN',NULL);
INSERT ac06.StockLocation(TenantId,SkuId,LocationId,LocationKind)
VALUES('T_COST','SKU_1','MAIN','AVAILABLE'),
      ('T_COST','SKU_1','AUX','AVAILABLE'),
      ('T_COST','SKU_1','QA','QUARANTINE');
DECLARE @Result varchar(32);
-- Two distinct confirmed inbound costs lead to moving average 3333.5:
-- MAIN 4 units / 13334. AUX holds a different average for the SAME SKU.
EXEC ac06.PostCommand 'T_COST','RECEIVE_MAIN_1','RECEIVE','P1',
     @SkuId='SKU_1',@LocationId='MAIN',@Qty=2,@CostAmount=6000,@Result=@Result OUTPUT;
EXEC ac06.PostCommand 'T_COST','RECEIVE_MAIN_2','RECEIVE','P1',
     @SkuId='SKU_1',@LocationId='MAIN',@Qty=2,@CostAmount=7334,@Result=@Result OUTPUT;
EXEC ac06.PostCommand 'T_COST','RECEIVE_AUX','RECEIVE','P1',
     @SkuId='SKU_1',@LocationId='AUX',@Qty=1,@CostAmount=10000,@Result=@Result OUTPUT;
-- Issue 2 @ moving average 3333.5 => actual issue source cost 6667.
EXEC ac06.PostCommand 'T_COST','ISSUE_MAIN','ISSUE','P1',
     @SkuId='SKU_1',@LocationId='MAIN',@Qty=2,@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53920,'ISSUE_NOT_ACCEPTED',1;
IF NOT EXISTS(SELECT 1 FROM ac06.IssueSource
 WHERE TenantId='T_COST' AND SourceId='ISSUE_MAIN'
   AND UnitAverageSnapshot=CONVERT(decimal(28,6),3333.5))
 THROW 53921,'LOCATION_SPECIFIC_MOVING_AVERAGE_WRONG',1;
IF NOT EXISTS(SELECT 1 FROM ac06.StockBalances
 WHERE TenantId='T_COST' AND SkuId='SKU_1' AND LocationId='AUX'
   AND Qty=1 AND StockValue=10000)
 THROW 53922,'ISSUE_CHANGED_UNRELATED_LOCATION',1;
-- Only a received/accepted return enters QUARANTINE; no QA release.
EXEC ac06.PostCommand 'T_COST','RETURN_1','RETURN','P1',
     @SkuId='SKU_1',@LocationId='QA',@SourceId='ISSUE_MAIN',
     @Qty=1,@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53923,'FIRST_RETURN_NOT_ACCEPTED',1;
EXEC ac06.CaptureCheckpoint 1,'FIRST_RETURN','T_COST','ISSUE_MAIN','SKU_1','MAIN','QA';
-- Immutable P1 issue, first return and their COGS effects.
UPDATE ac06.Period SET PeriodState='LOCKED',ClosedBy='CLOSE_P1'
 WHERE TenantId='T_COST' AND PeriodId='P1' AND PeriodState='OPEN';
IF @@ROWCOUNT<>1 THROW 53924,'PERIOD_CLOSE_FAILED',1;
-- P2 has a distinct source-identified revision; it posts +101 source COGS
-- and +50 on the already returned item without rewriting RETURN_1.
EXEC ac06.PostCommand 'T_COST','REVALUE_1','REVALUE','P2',
     @SourceId='ISSUE_MAIN',@CostAmount=6768,@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53925,'FORWARD_REVISION_NOT_ACCEPTED',1;
EXEC ac06.CaptureCheckpoint 2,'AFTER_ADJUST','T_COST','ISSUE_MAIN','SKU_1','MAIN','QA';
-- Final return is computed from current source version and cumulative qty;
-- it does NOT use current QA or MAIN moving average as the refund cost.
EXEC ac06.PostCommand 'T_COST','RETURN_2','RETURN','P2',
     @SkuId='SKU_1',@LocationId='QA',@SourceId='ISSUE_MAIN',
     @Qty=1,@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53926,'SECOND_RETURN_NOT_ACCEPTED',1;
EXEC ac06.CaptureCheckpoint 3,'FINAL_RETURN','T_COST','ISSUE_MAIN','SKU_1','MAIN','QA';
IF EXISTS(SELECT 1 FROM ac06.ReturnLine r
  JOIN ac06.StockLocation l ON l.TenantId=r.TenantId
     AND l.SkuId=r.SkuId AND l.LocationId=r.ToLocationId
  WHERE r.TenantId='T_COST' AND r.SourceId='ISSUE_MAIN'
    AND l.LocationKind<>'QUARANTINE')
 THROW 53927,'RETURN_LEFT_QUARANTINE',1;
EXEC ac06.AssertLedger 'T_COST','ISSUE_MAIN';
