-- SQL-03C negative, rollback, identity and locked-period immutability tests.
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
CREATE PROCEDURE ac06.ExpectReject
    @TenantId varchar(32),@CommandId varchar(40),@Kind varchar(12),
    @PeriodId varchar(16),@ExpectedError int,
    @SkuId varchar(32)=NULL,@LocationId varchar(32)=NULL,
    @SourceId varchar(40)=NULL,@Qty int=NULL,
    @CostAmount decimal(28,0)=NULL,@InjectFault tinyint=0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Observed int=0,@Result varchar(32),
      @Commands bigint,@Issues bigint,@Versions bigint,
      @Returns bigint,@Corrections bigint,@Stocks bigint,@Effects bigint,
      @QtySum bigint,@ValueSum decimal(38,0),@CogsSum decimal(38,0);
    SELECT @Commands=COUNT_BIG(*) FROM ac06.Command WHERE TenantId=@TenantId;
    SELECT @Issues=COUNT_BIG(*) FROM ac06.IssueSource WHERE TenantId=@TenantId;
    SELECT @Versions=COUNT_BIG(*) FROM ac06.SourceCostVersion WHERE TenantId=@TenantId;
    SELECT @Returns=COUNT_BIG(*) FROM ac06.ReturnLine WHERE TenantId=@TenantId;
    SELECT @Corrections=COUNT_BIG(*) FROM ac06.ReturnCostAdjustment WHERE TenantId=@TenantId;
    SELECT @Stocks=COUNT_BIG(*),@QtySum=ISNULL(SUM(CONVERT(bigint,QtyDelta)),0),
      @ValueSum=ISNULL(SUM(CONVERT(decimal(38,0),ValueDelta)),0)
      FROM ac06.StockPosting WHERE TenantId=@TenantId;
    SELECT @Effects=COUNT_BIG(*),
      @CogsSum=ISNULL(SUM(CONVERT(decimal(38,0),DeltaCogs)),0)
      FROM ac06.CostEffect WHERE TenantId=@TenantId;
    BEGIN TRY
        EXEC ac06.PostCommand @TenantId=@TenantId,@CommandId=@CommandId,
             @Kind=@Kind,@PeriodId=@PeriodId,@SkuId=@SkuId,
             @LocationId=@LocationId,@SourceId=@SourceId,
             @Qty=@Qty,@CostAmount=@CostAmount,@InjectFault=@InjectFault,
             @Result=@Result OUTPUT;
    END TRY
    BEGIN CATCH
        SET @Observed=ERROR_NUMBER();
    END CATCH;
    IF @Observed<>@ExpectedError
       THROW 53930,'NEGATIVE_CASE_ERROR_CODE_MISMATCH',1;
    IF EXISTS(SELECT 1 FROM ac06.Command
      WHERE TenantId=@TenantId AND CommandId=@CommandId)
       THROW 53931,'REJECTED_COMMAND_DURABLE',1;
    IF @Commands<>(SELECT COUNT_BIG(*) FROM ac06.Command WHERE TenantId=@TenantId)
      OR @Issues<>(SELECT COUNT_BIG(*) FROM ac06.IssueSource WHERE TenantId=@TenantId)
      OR @Versions<>(SELECT COUNT_BIG(*) FROM ac06.SourceCostVersion WHERE TenantId=@TenantId)
      OR @Returns<>(SELECT COUNT_BIG(*) FROM ac06.ReturnLine WHERE TenantId=@TenantId)
      OR @Corrections<>(SELECT COUNT_BIG(*) FROM ac06.ReturnCostAdjustment WHERE TenantId=@TenantId)
      OR @Stocks<>(SELECT COUNT_BIG(*) FROM ac06.StockPosting WHERE TenantId=@TenantId)
      OR @Effects<>(SELECT COUNT_BIG(*) FROM ac06.CostEffect WHERE TenantId=@TenantId)
       THROW 53932,'REJECTED_COMMAND_LEFT_SOURCE_OR_EFFECT',1;
    IF @QtySum<>(SELECT ISNULL(SUM(CONVERT(bigint,QtyDelta)),0)
                    FROM ac06.StockPosting WHERE TenantId=@TenantId)
      OR @ValueSum<>(SELECT ISNULL(SUM(CONVERT(decimal(38,0),ValueDelta)),0)
                    FROM ac06.StockPosting WHERE TenantId=@TenantId)
      OR @CogsSum<>(SELECT ISNULL(SUM(CONVERT(decimal(38,0),DeltaCogs)),0)
                    FROM ac06.CostEffect WHERE TenantId=@TenantId)
       THROW 53933,'REJECTION_CHANGED_BALANCES',1;
END;
GO
DECLARE @Result varchar(32),@N bigint,@Orig decimal(28,0);
-- Replay the original commands AFTER P1 is locked: no second mutation.
SELECT @N=COUNT_BIG(*) FROM ac06.ReturnLine WHERE TenantId='T_COST';
EXEC ac06.PostCommand 'T_COST','RETURN_1','RETURN','P1',
    @SkuId='SKU_1',@LocationId='QA',@SourceId='ISSUE_MAIN',@Qty=1,
    @Result=@Result OUTPUT;
IF @Result<>'REPLAY_ACCEPTED' OR
 @N<>(SELECT COUNT_BIG(*) FROM ac06.ReturnLine WHERE TenantId='T_COST')
 THROW 53934,'LOCKED_RETURN_REPLAY_DUPLICATED',1;
EXEC ac06.PostCommand 'T_COST','REVALUE_1','REVALUE','P2',
    @SourceId='ISSUE_MAIN',@CostAmount=6768,@Result=@Result OUTPUT;
IF @Result<>'REPLAY_ACCEPTED' THROW 53935,'REVALUE_REPLAY_DUPLICATED',1;
EXEC ac06.PostCommand 'T_COST','RETURN_2','RETURN','P2',
    @SkuId='SKU_1',@LocationId='QA',@SourceId='ISSUE_MAIN',@Qty=1,
    @Result=@Result OUTPUT;
IF @Result<>'REPLAY_ACCEPTED' THROW 53936,'FINAL_RETURN_REPLAY_DUPLICATED',1;
EXEC ac06.PostCommand 'T_COST','ISSUE_MAIN','ISSUE','P1',
    @SkuId='SKU_1',@LocationId='MAIN',@Qty=2,@Result=@Result OUTPUT;
IF @Result<>'REPLAY_ACCEPTED' THROW 53937,'LOCKED_ISSUE_REPLAY_DUPLICATED',1;

-- A same-ID/different-payload conflict cannot slip through a locked period.
BEGIN TRY
    EXEC ac06.PostCommand 'T_COST','RETURN_1','RETURN','P1',
       @SkuId='SKU_1',@LocationId='QA',@SourceId='ISSUE_MAIN',@Qty=2,
       @Result=@Result OUTPUT;
    THROW 53938,'PAYLOAD_CONFLICT_NOT_BLOCKED',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>53801 THROW;
END CATCH;
BEGIN TRY
    EXEC ac06.PostCommand 'T_COST','REVALUE_1','REVALUE','P2',
       @SourceId='ISSUE_MAIN',@CostAmount=6769,@Result=@Result OUTPUT;
    THROW 53939,'REVALUE_PAYLOAD_CONFLICT_NOT_BLOCKED',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>53801 THROW;
END CATCH;
EXEC ac06.ExpectReject 'T_COST','LATE_P1_REVALUE','REVALUE','P1',53802,
    @SourceId='ISSUE_MAIN',@CostAmount=6770;
EXEC ac06.ExpectReject 'T_COST','LATE_P1_RETURN','RETURN','P1',53802,
    @SkuId='SKU_1',@LocationId='QA',@SourceId='ISSUE_MAIN',@Qty=1;
EXEC ac06.ExpectReject 'T_COST','OVER_RETURN','RETURN','P2',53806,
    @SkuId='SKU_1',@LocationId='QA',@SourceId='ISSUE_MAIN',@Qty=1;
EXEC ac06.ExpectReject 'T_COST','WRONG_RETURN_LOCATION','RETURN','P2',53805,
    @SkuId='SKU_1',@LocationId='MAIN',@SourceId='ISSUE_MAIN',@Qty=1;
EXEC ac06.ExpectReject 'T_COST','WRONG_RETURN_SKU','RETURN','P2',53803,
    @SkuId='SKU_2',@LocationId='QA',@SourceId='ISSUE_MAIN',@Qty=1;
EXEC ac06.ExpectReject 'T_COST','REVALUE_NO_CHANGE','REVALUE','P2',53808,
    @SourceId='ISSUE_MAIN',@CostAmount=6768;
EXEC ac06.ExpectReject 'T_COST','ISSUE_OVER_STOCK','ISSUE','P2',53804,
    @SkuId='SKU_1',@LocationId='MAIN',@Qty=3;
EXEC ac06.ExpectReject 'T_COST','RECEIVE_DIRECT_QA','RECEIVE','P2',53809,
    @SkuId='SKU_1',@LocationId='QA',@Qty=1,@CostAmount=50;
-- Tenant crossing: source identity/period under one tenant cannot be reused
-- by another tenant even when the SKU and location IDs happen to match.
INSERT ac06.Period VALUES('OTHER_TENANT','P2','OPEN',NULL);
INSERT ac06.StockLocation VALUES('OTHER_TENANT','SKU_1','QA','QUARANTINE');
EXEC ac06.ExpectReject 'OTHER_TENANT','FOREIGN_SOURCE_RETURN','RETURN','P2',53807,
    @SkuId='SKU_1',@LocationId='QA',@SourceId='ISSUE_MAIN',@Qty=1;
EXEC ac06.ExpectReject 'OTHER_TENANT','FOREIGN_SOURCE_REVALUE','REVALUE','P2',53807,
    @SourceId='ISSUE_MAIN',@CostAmount=8000;

-- Test DIRECT writes to locked source data, not just command rejection.
-- Triggers keep historic issue, return, cost-version and all postings
-- append-only; a period cannot be reopened to smuggle in backdated effects.
SELECT @Orig=OriginalCost FROM ac06.IssueSource
 WHERE TenantId='T_COST' AND SourceId='ISSUE_MAIN';
BEGIN TRY
    UPDATE ac06.IssueSource SET OriginalCost=OriginalCost+1
      WHERE TenantId='T_COST' AND SourceId='ISSUE_MAIN';
    THROW 53940,'DIRECT_ISSUE_MUTATION_ALLOWED',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>53870 THROW;
END CATCH;
BEGIN TRY
    UPDATE ac06.ReturnLine SET RefundBase=RefundBase+1
      WHERE TenantId='T_COST' AND ReturnId='RETURN_1';
    THROW 53941,'DIRECT_LOCKED_RETURN_MUTATION_ALLOWED',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>53870 THROW;
END CATCH;
BEGIN TRY
    UPDATE ac06.SourceCostVersion SET TotalCost=TotalCost+1
      WHERE TenantId='T_COST' AND SourceId='ISSUE_MAIN' AND VersionNo=1;
    THROW 53942,'DIRECT_LOCKED_COST_VERSION_MUTATION_ALLOWED',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>53870 THROW;
END CATCH;
BEGIN TRY
    UPDATE ac06.StockPosting SET ValueDelta=ValueDelta+1
      WHERE TenantId='T_COST' AND CommandId='ISSUE_MAIN';
    THROW 53943,'DIRECT_LOCKED_STOCK_MUTATION_ALLOWED',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>53870 THROW;
END CATCH;
BEGIN TRY
    UPDATE ac06.CostEffect SET DeltaCogs=DeltaCogs+1
      WHERE TenantId='T_COST' AND CommandId='ISSUE_MAIN';
    THROW 53944,'DIRECT_LOCKED_COGS_MUTATION_ALLOWED',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>53870 THROW;
END CATCH;
BEGIN TRY
    UPDATE ac06.Period SET PeriodState='OPEN',ClosedBy=NULL
      WHERE TenantId='T_COST' AND PeriodId='P1';
    THROW 53945,'PERIOD_REOPEN_ALLOWED',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>53871 THROW;
END CATCH;
BEGIN TRY
    DELETE ac06.ReturnCostAdjustment
      WHERE TenantId='T_COST' AND AdjustmentId='REVALUE_1';
    THROW 53946,'FORWARD_ADJUSTMENT_DELETE_ALLOWED',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>53870 THROW;
END CATCH;
IF @Orig<>(SELECT OriginalCost FROM ac06.IssueSource
    WHERE TenantId='T_COST' AND SourceId='ISSUE_MAIN')
 OR NOT EXISTS(SELECT 1 FROM ac06.Period
    WHERE TenantId='T_COST' AND PeriodId='P1' AND PeriodState='LOCKED')
 THROW 53947,'LOCKED_HISTORY_WAS_CHANGED',1;
-- Value is derived from successful negative probes. If any test above fails
-- this script stops and this row cannot be produced.
INSERT ac06.TestProbe VALUES('LOCKED_MUTATION_DENIED',1,0);
EXEC ac06.AssertLedger 'T_COST','ISSUE_MAIN';

-- Separate scope for fault injection and reversal; AC-06 oracle is unchanged.
INSERT ac06.Period VALUES('T_NEG','P1','OPEN',NULL),('T_NEG','P2','OPEN',NULL);
INSERT ac06.StockLocation VALUES('T_NEG','S1','MAIN','AVAILABLE'),
                               ('T_NEG','S1','QA','QUARANTINE');
EXEC ac06.PostCommand 'T_NEG','OPEN_NEG','RECEIVE','P1',
    @SkuId='S1',@LocationId='MAIN',@Qty=2,@CostAmount=200,@Result=@Result OUTPUT;
EXEC ac06.ExpectReject 'T_NEG','FAULT_ISSUE_1','ISSUE','P1',53890,
    @SkuId='S1',@LocationId='MAIN',@Qty=2,@InjectFault=1;
EXEC ac06.ExpectReject 'T_NEG','FAULT_ISSUE_2','ISSUE','P1',53890,
    @SkuId='S1',@LocationId='MAIN',@Qty=2,@InjectFault=2;
EXEC ac06.PostCommand 'T_NEG','ISSUE_NEG','ISSUE','P1',
    @SkuId='S1',@LocationId='MAIN',@Qty=2,@Result=@Result OUTPUT;
EXEC ac06.ExpectReject 'T_NEG','FAULT_RETURN_1','RETURN','P1',53890,
    @SkuId='S1',@LocationId='QA',@SourceId='ISSUE_NEG',
    @Qty=1,@InjectFault=1;
EXEC ac06.ExpectReject 'T_NEG','FAULT_RETURN_2','RETURN','P1',53890,
    @SkuId='S1',@LocationId='QA',@SourceId='ISSUE_NEG',
    @Qty=1,@InjectFault=2;
EXEC ac06.PostCommand 'T_NEG','RETURN_NEG','RETURN','P1',
    @SkuId='S1',@LocationId='QA',@SourceId='ISSUE_NEG',
    @Qty=1,@Result=@Result OUTPUT;
UPDATE ac06.Period SET PeriodState='LOCKED',ClosedBy='NEG_CLOSE_P1'
    WHERE TenantId='T_NEG' AND PeriodId='P1';
EXEC ac06.ExpectReject 'T_NEG','FAULT_REVALUE_1','REVALUE','P2',53890,
    @SourceId='ISSUE_NEG',@CostAmount=220,@InjectFault=1;
EXEC ac06.ExpectReject 'T_NEG','FAULT_REVALUE_2','REVALUE','P2',53890,
    @SourceId='ISSUE_NEG',@CostAmount=220,@InjectFault=2;
-- A new version can also reverse a prior adjustment forward (never DELETE).
EXEC ac06.PostCommand 'T_NEG','REVALUE_NEG','REVALUE','P2',
    @SourceId='ISSUE_NEG',@CostAmount=220,@Result=@Result OUTPUT;
EXEC ac06.PostCommand 'T_NEG','REVERSE_NEG','REVALUE','P2',
    @SourceId='ISSUE_NEG',@CostAmount=200,@Result=@Result OUTPUT;
EXEC ac06.AssertLedger 'T_NEG','ISSUE_NEG';
IF NOT EXISTS(SELECT 1 FROM ac06.CurrentSourceCost
 WHERE TenantId='T_NEG' AND SourceId='ISSUE_NEG'
   AND TotalCost=200 AND VersionNo=3)
 OR (SELECT COUNT_BIG(*) FROM ac06.ReturnCostAdjustment
     WHERE TenantId='T_NEG' AND SourceId='ISSUE_NEG')<>2
 THROW 53948,'FORWARD_COST_REVERSAL_NOT_RECORDED',1;
EXEC ac06.AssertLedger 'T_COST','ISSUE_MAIN';
