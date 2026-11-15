-- SQL-03C AC-06 transactional source-cost commands, derived balances and assertions.
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
CREATE PROCEDURE ac06.AssertLedger
    @TenantId varchar(32), @SourceId varchar(40)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Qty int,@Original decimal(28,0),@Current decimal(28,0),
            @Returned int,@Refunded decimal(28,0),@Cogs decimal(28,0);
    SELECT @Qty=IssueQty,@Original=OriginalCost
      FROM ac06.IssueSource WHERE TenantId=@TenantId AND SourceId=@SourceId;
    IF @Qty IS NULL THROW 53900,'SOURCE_MISSING_FOR_ASSERT',1;
    SELECT @Current=TotalCost FROM ac06.CurrentSourceCost
      WHERE TenantId=@TenantId AND SourceId=@SourceId;
    IF @Current IS NULL THROW 53901,'SOURCE_VERSION_MISSING',1;
    IF EXISTS(SELECT 1 FROM ac06.StockBalances
      WHERE TenantId=@TenantId AND
        (Qty<0 OR StockValue<0 OR (Qty=0 AND StockValue<>0)))
        THROW 53902,'LOCATION_NEGATIVE_OR_RESIDUAL_VALUE',1;
    IF EXISTS(SELECT 1 FROM ac06.SourceCostVersion v
      WHERE v.TenantId=@TenantId AND v.SourceId=@SourceId
        AND ((v.VersionNo=1 AND
             (v.TotalCost<>@Original OR v.DeltaCost<>0 OR v.ChangeCommandId<>@SourceId))
          OR (v.VersionNo>1 AND
            (NOT EXISTS(SELECT 1 FROM ac06.SourceCostVersion p
               WHERE p.TenantId=v.TenantId AND p.SourceId=v.SourceId
                 AND p.VersionNo=v.VersionNo-1 AND
                 v.DeltaCost=v.TotalCost-p.TotalCost)))))
        THROW 53903,'COST_VERSION_CHAIN_INVALID',1;
    IF (SELECT COUNT(*) FROM ac06.SourceCostVersion
        WHERE TenantId=@TenantId AND SourceId=@SourceId)<>
       (SELECT MAX(VersionNo) FROM ac06.SourceCostVersion
        WHERE TenantId=@TenantId AND SourceId=@SourceId)
        THROW 53904,'COST_VERSION_GAP',1;
    IF NOT EXISTS(SELECT 1 FROM ac06.StockPosting p
         JOIN ac06.IssueSource s ON s.TenantId=p.TenantId
           AND s.SourceId=p.CommandId
         WHERE s.TenantId=@TenantId AND s.SourceId=@SourceId
           AND p.Kind='ISSUE' AND p.LineNo=1 AND p.SkuId=s.SkuId
           AND p.LocationId=s.FromLocationId AND p.QtyDelta=-s.IssueQty
           AND p.ValueDelta=-s.OriginalCost)
       OR NOT EXISTS(SELECT 1 FROM ac06.CostEffect e
         WHERE e.TenantId=@TenantId AND e.CommandId=@SourceId
           AND e.SourceId=@SourceId AND e.LineNo=1 AND e.Kind='ISSUE'
           AND e.DeltaCogs=@Original)
        THROW 53905,'ISSUE_SOURCE_OR_COST_EFFECT_MISMATCH',1;
    -- No return can alter quantities or the value of the original issue.
    SELECT @Returned=ISNULL(SUM(ReceivedQty),0)
      FROM ac06.ReturnLine WHERE TenantId=@TenantId AND SourceId=@SourceId;
    IF @Returned>@Qty THROW 53906,'SOURCE_OVER_RETURNED',1;

    -- Revalue each earlier return to the current source-cost version. A
    -- cumulative difference per return fixes both residual rounding and
    -- corrections after earlier return records were locked.
    IF EXISTS(
      SELECT 1 FROM ac06.ReturnLine r
      OUTER APPLY (
        SELECT ISNULL(SUM(prev.ReceivedQty),0) AS PrevQty
        FROM ac06.ReturnLine prev
        WHERE prev.TenantId=r.TenantId AND prev.SourceId=r.SourceId
          AND prev.ReturnOrdinal<r.ReturnOrdinal
      ) priorQty
      OUTER APPLY (
        SELECT ISNULL(SUM(a.DeltaRefund),0) AS Correction
        FROM ac06.ReturnCostAdjustment a
        WHERE a.TenantId=r.TenantId AND a.ReturnId=r.ReturnId
      ) adj
      WHERE r.TenantId=@TenantId AND r.SourceId=@SourceId AND
        r.RefundBase+adj.Correction <>
          CONVERT(decimal(28,0),ROUND(
            CONVERT(decimal(28,6),@Current) *
              (priorQty.PrevQty + r.ReceivedQty) / @Qty,0)
          - ROUND(CONVERT(decimal(28,6),@Current) *
              priorQty.PrevQty / @Qty,0))
    ) THROW 53907,'CUMULATIVE_REFUND_OR_REVALUE_DRIFT',1;
    IF EXISTS(SELECT 1 FROM ac06.ReturnLine r
       WHERE r.TenantId=@TenantId AND r.SourceId=@SourceId AND
         (NOT EXISTS(SELECT 1 FROM ac06.StockPosting p
           WHERE p.TenantId=r.TenantId AND p.CommandId=r.ReturnId
             AND p.LineNo=1 AND p.Kind='RETURN'
             AND p.SkuId=r.SkuId AND p.LocationId=r.ToLocationId
             AND p.QtyDelta=r.ReceivedQty AND p.ValueDelta=r.RefundBase)
          OR NOT EXISTS(SELECT 1 FROM ac06.CostEffect e
           WHERE e.TenantId=r.TenantId AND e.CommandId=r.ReturnId
             AND e.SourceId=r.SourceId AND e.LineNo=1 AND e.Kind='REFUND'
             AND e.DeltaCogs=-r.RefundBase)))
        THROW 53908,'RETURN_STOCK_OR_COGS_EFFECT_MISMATCH',1;
    IF EXISTS(SELECT 1 FROM ac06.ReturnCostAdjustment a
       JOIN ac06.ReturnLine r ON r.TenantId=a.TenantId AND r.ReturnId=a.ReturnId
       WHERE a.TenantId=@TenantId AND a.SourceId=@SourceId AND
         (NOT EXISTS(SELECT 1 FROM ac06.StockPosting p
           WHERE p.TenantId=a.TenantId AND p.CommandId=a.AdjustmentId
             AND p.LineNo=r.ReturnOrdinal+1 AND p.Kind='RETURN_REVAL'
             AND p.SkuId=r.SkuId AND p.LocationId=r.ToLocationId
             AND p.QtyDelta=0 AND p.ValueDelta=a.DeltaRefund)
          OR NOT EXISTS(SELECT 1 FROM ac06.CostEffect e
           WHERE e.TenantId=a.TenantId AND e.CommandId=a.AdjustmentId
             AND e.SourceId=a.SourceId AND e.LineNo=r.ReturnOrdinal+1
             AND e.Kind='REFUND_REVAL' AND e.DeltaCogs=-a.DeltaRefund)))
        THROW 53909,'FORWARD_REFUND_ADJUSTMENT_MISMATCH',1;
    IF EXISTS(SELECT 1 FROM ac06.SourceCostVersion v
       WHERE v.TenantId=@TenantId AND v.SourceId=@SourceId
         AND v.VersionNo>1 AND
         NOT EXISTS(SELECT 1 FROM ac06.CostEffect e
           WHERE e.TenantId=v.TenantId AND e.CommandId=v.ChangeCommandId
             AND e.SourceId=v.SourceId AND e.LineNo=1
             AND e.Kind='ISSUE_REVAL' AND e.DeltaCogs=v.DeltaCost))
        THROW 53910,'FORWARD_ISSUE_ADJUSTMENT_MISSING',1;
    SELECT @Refunded=
       ISNULL((SELECT SUM(r.RefundBase) FROM ac06.ReturnLine r
               WHERE r.TenantId=@TenantId AND r.SourceId=@SourceId),0)
      +ISNULL((SELECT SUM(a.DeltaRefund) FROM ac06.ReturnCostAdjustment a
               WHERE a.TenantId=@TenantId AND a.SourceId=@SourceId),0);
    IF @Refunded<0 OR @Refunded>@Current
       THROW 53911,'REFUND_TOTAL_EXCEEDS_CURRENT_SOURCE',1;
    SELECT @Cogs=ISNULL(SUM(DeltaCogs),0)
      FROM ac06.CostEffect WHERE TenantId=@TenantId AND SourceId=@SourceId;
    IF @Cogs<>@Current-@Refunded OR @Cogs<0
       THROW 53912,'SOURCE_REVALUE_COGS_RECONCILIATION_FAILED',1;
END;
GO
-- All commands are tenant-wide idempotent (including across location/source).
-- Lock order: open period -> command unique key/range -> stock location
-- for RECEIVE/ISSUE, or issue source for RETURN/REVALUE. The source lock
-- serializes simultaneous returns against cost revaluations.
CREATE PROCEDURE ac06.PostCommand
    @TenantId varchar(32),
    @CommandId varchar(40),
    @Kind varchar(12),
    @PeriodId varchar(16),
    @SkuId varchar(32)=NULL,
    @LocationId varchar(32)=NULL,
    @SourceId varchar(40)=NULL,
    @Qty int=NULL,
    @CostAmount decimal(28,0)=NULL,
    @InjectFault tinyint=0,
    @Result varchar(32) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    IF @TenantId IS NULL OR LEN(@TenantId)=0
       OR @CommandId IS NULL OR LEN(@CommandId)=0
       OR @PeriodId IS NULL OR LEN(@PeriodId)=0
       OR @Kind IS NULL OR @Kind NOT IN ('RECEIVE','ISSUE','RETURN','REVALUE')
       THROW 53800,'INVALID_COST_COMMAND',1;
    IF (@Kind='RECEIVE' AND
         (@SkuId IS NULL OR @LocationId IS NULL OR @Qty IS NULL OR @Qty<=0
         OR @CostAmount IS NULL OR @CostAmount<=0 OR @SourceId IS NOT NULL))
       OR (@Kind='ISSUE' AND
         (@SkuId IS NULL OR @LocationId IS NULL OR @Qty IS NULL OR @Qty<=0
         OR @CostAmount IS NOT NULL OR @SourceId IS NOT NULL))
       OR (@Kind='RETURN' AND
         (@SkuId IS NULL OR @LocationId IS NULL OR @SourceId IS NULL
         OR @Qty IS NULL OR @Qty<=0 OR @CostAmount IS NOT NULL))
       OR (@Kind='REVALUE' AND
         (@SourceId IS NULL OR @Qty IS NOT NULL OR @CostAmount IS NULL
         OR @CostAmount<=0 OR @SkuId IS NOT NULL OR @LocationId IS NOT NULL))
       THROW 53800,'COST_COMMAND_PAYLOAD_SHAPE_INVALID',1;
    DECLARE @Hash char(64),@OldHash char(64),@OldKind varchar(12),
            @State varchar(8),@LocKind varchar(12),@BalanceQty int,
            @BalanceValue decimal(28,0),@IssueCost decimal(28,0),
            @SrcQty int,@SrcSku varchar(32),@CurrentCost decimal(28,0),
            @CostVersion int,@ReturnedQty int,@Refund decimal(28,0),
            @NewCumulative decimal(28,0),@OldCumulative decimal(28,0),
            @OldCost decimal(28,0),@CostDelta decimal(28,0),@Ordinal int,
            @ReturnId varchar(40),@ReturnQty int,@ReturnLocation varchar(32),
            @ReturnBase decimal(28,0),@AlreadyBooked decimal(28,0),
            @Desired decimal(28,0),@Correction decimal(28,0),
            @BeforeQty int,@LineNo int;
    SET @Hash=CONVERT(char(64),HASHBYTES('SHA2_256',CONCAT(
       'AC06:v1|',LEN(@Kind),':',@Kind,
       '|',LEN(@PeriodId),':',@PeriodId,
       '|',CASE WHEN @SkuId IS NULL THEN 'N' ELSE CONCAT('V',LEN(@SkuId),':',@SkuId) END,
       '|',CASE WHEN @LocationId IS NULL THEN 'N' ELSE CONCAT('V',LEN(@LocationId),':',@LocationId) END,
       '|',CASE WHEN @SourceId IS NULL THEN 'N' ELSE CONCAT('V',LEN(@SourceId),':',@SourceId) END,
       '|',CASE WHEN @Qty IS NULL THEN 'N' ELSE CONVERT(varchar(20),@Qty) END,
       '|',CASE WHEN @CostAmount IS NULL THEN 'N' ELSE CONVERT(varchar(60),@CostAmount) END
    )),2);
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @State=PeriodState FROM ac06.Period WITH(UPDLOCK,HOLDLOCK)
          WHERE TenantId=@TenantId AND PeriodId=@PeriodId;
        -- A retry of a previously committed command is allowed after period lock,
        -- but a fresh command MUST target an OPEN period.
        SELECT @OldHash=PayloadHash,@OldKind=Kind
          FROM ac06.Command WITH(UPDLOCK,HOLDLOCK)
          WHERE TenantId=@TenantId AND CommandId=@CommandId;
        IF @OldHash IS NOT NULL
        BEGIN
            IF @OldHash<>@Hash OR @OldKind<>@Kind
                THROW 53801,'COMMAND_ID_PAYLOAD_CONFLICT',1;
            SET @Result='REPLAY_ACCEPTED';
            COMMIT;
            RETURN;
        END;
        IF @State IS NULL OR @State<>'OPEN'
            THROW 53802,'PERIOD_MISSING_OR_LOCKED',1;

        IF @Kind IN ('RECEIVE','ISSUE')
        BEGIN
            SELECT @LocKind=LocationKind FROM ac06.StockLocation WITH(UPDLOCK,HOLDLOCK)
             WHERE TenantId=@TenantId AND SkuId=@SkuId AND LocationId=@LocationId;
            IF @LocKind<>'AVAILABLE' OR @LocKind IS NULL
               THROW 53809,'ISSUE_RECEIVE_LOCATION_NOT_AVAILABLE',1;
            SELECT @BalanceQty=Qty,@BalanceValue=StockValue
             FROM ac06.StockBalances
             WHERE TenantId=@TenantId AND SkuId=@SkuId AND LocationId=@LocationId;
            IF @Kind='ISSUE' AND
               (@BalanceQty IS NULL OR @BalanceQty<@Qty OR @BalanceValue<=0)
               THROW 53804,'AVAILABLE_STOCK_INSUFFICIENT',1;
            IF @Kind='ISSUE'
            BEGIN
                -- Exhausting a location transfers its full residual value.
                SET @IssueCost=CASE WHEN @Qty=@BalanceQty THEN @BalanceValue
                     ELSE CONVERT(decimal(28,0),ROUND(
                       CONVERT(decimal(28,6),@BalanceValue)*@Qty/@BalanceQty,0))
                     END;
                IF @IssueCost<=0 OR @IssueCost>@BalanceValue
                    THROW 53810,'INVALID_ISSUE_COST',1;
            END;
        END
        ELSE
        BEGIN
            SELECT @SrcSku=SkuId,@SrcQty=IssueQty FROM ac06.IssueSource
               WITH(UPDLOCK,HOLDLOCK)
              WHERE TenantId=@TenantId AND SourceId=@SourceId;
            IF @SrcQty IS NULL THROW 53807,'SOURCE_NOT_FOUND_FOR_TENANT',1;
            SELECT @CurrentCost=TotalCost,@CostVersion=VersionNo
              FROM ac06.CurrentSourceCost
              WHERE TenantId=@TenantId AND SourceId=@SourceId;
            IF @Kind='RETURN'
            BEGIN
                IF @SkuId<>@SrcSku THROW 53803,'RETURN_SKU_SOURCE_MISMATCH',1;
                SELECT @LocKind=LocationKind FROM ac06.StockLocation WITH(UPDLOCK,HOLDLOCK)
                  WHERE TenantId=@TenantId AND SkuId=@SkuId AND LocationId=@LocationId;
                IF @LocKind<>'QUARANTINE' OR @LocKind IS NULL
                    THROW 53805,'RETURN_MUST_ENTER_QUARANTINE',1;
                SELECT @ReturnedQty=ISNULL(SUM(ReceivedQty),0)
                 FROM ac06.ReturnLine WHERE TenantId=@TenantId AND SourceId=@SourceId;
                IF @Qty>@SrcQty-@ReturnedQty THROW 53806,'SOURCE_OVER_RETURN',1;
                SET @BeforeQty=@ReturnedQty;
                SET @NewCumulative=CONVERT(decimal(28,0),ROUND(
                    CONVERT(decimal(28,6),@CurrentCost)*(@BeforeQty+@Qty)/@SrcQty,0));
                SET @OldCumulative=CONVERT(decimal(28,0),ROUND(
                    CONVERT(decimal(28,6),@CurrentCost)*@BeforeQty/@SrcQty,0));
                SET @Refund=@NewCumulative-@OldCumulative;
                SET @Ordinal=ISNULL((SELECT MAX(ReturnOrdinal)
                  FROM ac06.ReturnLine WHERE TenantId=@TenantId AND SourceId=@SourceId),0)+1;
            END
            ELSE IF @CostAmount=@CurrentCost
                THROW 53808,'SOURCE_COST_REVALUE_UNCHANGED',1;
        END;

        INSERT ac06.Command(TenantId,CommandId,Kind,PeriodId,PayloadHash)
        VALUES(@TenantId,@CommandId,@Kind,@PeriodId,@Hash);
        IF @Kind='RECEIVE'
        BEGIN
            INSERT ac06.StockPosting
              (TenantId,CommandId,LineNo,SkuId,LocationId,Kind,QtyDelta,ValueDelta)
            VALUES(@TenantId,@CommandId,1,@SkuId,@LocationId,'RECEIVE',@Qty,@CostAmount);
        END
        ELSE IF @Kind='ISSUE'
        BEGIN
            INSERT ac06.IssueSource(TenantId,SourceId,SkuId,FromLocationId,
                 SourcePeriodId,IssueQty,OriginalCost,UnitAverageSnapshot)
            VALUES(@TenantId,@CommandId,@SkuId,@LocationId,@PeriodId,
                @Qty,@IssueCost,CONVERT(decimal(28,6),
                CONVERT(decimal(28,6),@BalanceValue)/@BalanceQty));
            INSERT ac06.SourceCostVersion
              (TenantId,SourceId,VersionNo,TotalCost,DeltaCost,
               EffectivePeriodId,ChangeCommandId)
            VALUES(@TenantId,@CommandId,1,@IssueCost,0,@PeriodId,@CommandId);
            IF @InjectFault=1 THROW 53890,'INJECTED_ISSUE_SOURCE_FAULT',1;
            INSERT ac06.StockPosting
              (TenantId,CommandId,LineNo,SkuId,LocationId,Kind,QtyDelta,ValueDelta)
            VALUES(@TenantId,@CommandId,1,@SkuId,@LocationId,'ISSUE',-@Qty,-@IssueCost);
            IF @InjectFault=2 THROW 53890,'INJECTED_ISSUE_POSTING_FAULT',1;
            INSERT ac06.CostEffect(TenantId,CommandId,LineNo,SourceId,Kind,DeltaCogs)
            VALUES(@TenantId,@CommandId,1,@CommandId,'ISSUE',@IssueCost);
        END
        ELSE IF @Kind='RETURN'
        BEGIN
            INSERT ac06.ReturnLine
              (TenantId,ReturnId,SourceId,SkuId,ReturnOrdinal,ToLocationId,
               ReceivedQty,RefundBase,CostVersionNo,PeriodId)
            VALUES(@TenantId,@CommandId,@SourceId,@SkuId,@Ordinal,@LocationId,
                   @Qty,@Refund,@CostVersion,@PeriodId);
            IF @InjectFault=1 THROW 53890,'INJECTED_RETURN_SOURCE_FAULT',1;
            INSERT ac06.StockPosting
              (TenantId,CommandId,LineNo,SkuId,LocationId,Kind,QtyDelta,ValueDelta)
            VALUES(@TenantId,@CommandId,1,@SkuId,@LocationId,'RETURN',@Qty,@Refund);
            IF @InjectFault=2 THROW 53890,'INJECTED_RETURN_POSTING_FAULT',1;
            INSERT ac06.CostEffect(TenantId,CommandId,LineNo,SourceId,Kind,DeltaCogs)
            VALUES(@TenantId,@CommandId,1,@SourceId,'REFUND',-@Refund);
        END
        ELSE
        BEGIN
            -- The issue and any prior returns stay immutable. Revision is an
            -- appended source version + forward-period COGS effect.
            SET @OldCost=@CurrentCost;
            SET @CostDelta=@CostAmount-@OldCost;
            INSERT ac06.SourceCostVersion
              (TenantId,SourceId,VersionNo,TotalCost,DeltaCost,
               EffectivePeriodId,ChangeCommandId)
            VALUES(@TenantId,@SourceId,@CostVersion+1,@CostAmount,@CostDelta,
                   @PeriodId,@CommandId);
            IF @InjectFault=1 THROW 53890,'INJECTED_REVALUE_VERSION_FAULT',1;
            INSERT ac06.CostEffect(TenantId,CommandId,LineNo,SourceId,Kind,DeltaCogs)
            VALUES(@TenantId,@CommandId,1,@SourceId,'ISSUE_REVAL',@CostDelta);
            -- Recalculate already returned lines with the revised source cost;
            -- post only the difference for each line in the open period.
            DECLARE cur_returns CURSOR LOCAL FAST_FORWARD FOR
              SELECT ReturnId,ReceivedQty,RefundBase,ToLocationId
              FROM ac06.ReturnLine
              WHERE TenantId=@TenantId AND SourceId=@SourceId
              ORDER BY ReturnOrdinal;
            SET @BeforeQty=0;
            SET @LineNo=1;
            OPEN cur_returns;
            FETCH NEXT FROM cur_returns
              INTO @ReturnId,@ReturnQty,@ReturnBase,@ReturnLocation;
            WHILE @@FETCH_STATUS=0
            BEGIN
                SET @NewCumulative=CONVERT(decimal(28,0),ROUND(
                   CONVERT(decimal(28,6),@CostAmount)*
                   (@BeforeQty+@ReturnQty)/@SrcQty,0));
                SET @OldCumulative=CONVERT(decimal(28,0),ROUND(
                   CONVERT(decimal(28,6),@CostAmount)*@BeforeQty/@SrcQty,0));
                SET @Desired=@NewCumulative-@OldCumulative;
                SELECT @AlreadyBooked=@ReturnBase+ISNULL(SUM(DeltaRefund),0)
                 FROM ac06.ReturnCostAdjustment
                 WHERE TenantId=@TenantId AND ReturnId=@ReturnId;
                SET @Correction=@Desired-@AlreadyBooked;
                SET @LineNo=@LineNo+1;
                IF @Correction<>0
                BEGIN
                    INSERT ac06.ReturnCostAdjustment
                      (TenantId,AdjustmentId,ReturnId,SourceId,VersionNo,DeltaRefund,PeriodId)
                    VALUES(@TenantId,@CommandId,@ReturnId,@SourceId,
                           @CostVersion+1,@Correction,@PeriodId);
                    INSERT ac06.StockPosting
                      (TenantId,CommandId,LineNo,SkuId,LocationId,Kind,QtyDelta,ValueDelta)
                    VALUES(@TenantId,@CommandId,@LineNo,@SrcSku,@ReturnLocation,
                           'RETURN_REVAL',0,@Correction);
                    IF @InjectFault=2 THROW 53890,'INJECTED_REVALUE_POSTING_FAULT',1;
                    INSERT ac06.CostEffect
                      (TenantId,CommandId,LineNo,SourceId,Kind,DeltaCogs)
                    VALUES(@TenantId,@CommandId,@LineNo,@SourceId,
                           'REFUND_REVAL',-@Correction);
                END;
                SET @BeforeQty=@BeforeQty+@ReturnQty;
                FETCH NEXT FROM cur_returns
                    INTO @ReturnId,@ReturnQty,@ReturnBase,@ReturnLocation;
            END;
            CLOSE cur_returns;
            DEALLOCATE cur_returns;
        END;
        -- These checks are run inside the same transaction as the source and
        -- all postings, so a failed invariant rolls back every effect.
        IF EXISTS(SELECT 1 FROM ac06.StockBalances
          WHERE TenantId=@TenantId AND
             (Qty<0 OR StockValue<0 OR (Qty=0 AND StockValue<>0)))
             THROW 53902,'LOCATION_NEGATIVE_OR_RESIDUAL_VALUE',1;
        IF @Kind IN ('ISSUE','RETURN','REVALUE')
        BEGIN
            DECLARE @AssertSourceId varchar(40);
            SET @AssertSourceId=CASE WHEN @Kind='ISSUE' THEN @CommandId ELSE @SourceId END;
            EXEC ac06.AssertLedger @TenantId,@AssertSourceId;
        END;
        SET @Result='ACCEPTED';
        COMMIT;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local','cur_returns')>=0
        BEGIN
            CLOSE cur_returns;
            DEALLOCATE cur_returns;
        END
        ELSE IF CURSOR_STATUS('local','cur_returns')=-1
            DEALLOCATE cur_returns;
        IF @@TRANCOUNT>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
CREATE PROCEDURE ac06.CaptureCheckpoint
    @Ordinal int,@Name varchar(24),@TenantId varchar(32),
    @SourceId varchar(40),@SkuId varchar(32),
    @MainLocation varchar(32),@QuarantineLocation varchar(32)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Version int,@Cost decimal(28,0),@Q int,
            @Refund decimal(28,0),@Cogs decimal(28,0),
            @MainQty int,@MainValue decimal(28,0),
            @QuarantineQty int,@QuarantineValue decimal(28,0);
    EXEC ac06.AssertLedger @TenantId,@SourceId;
    SELECT @Version=VersionNo,@Cost=TotalCost FROM ac06.CurrentSourceCost
     WHERE TenantId=@TenantId AND SourceId=@SourceId;
    SELECT @Q=ISNULL(SUM(ReceivedQty),0) FROM ac06.ReturnLine
     WHERE TenantId=@TenantId AND SourceId=@SourceId;
    SELECT @Refund=ISNULL((SELECT SUM(RefundBase) FROM ac06.ReturnLine
      WHERE TenantId=@TenantId AND SourceId=@SourceId),0)+
      ISNULL((SELECT SUM(DeltaRefund) FROM ac06.ReturnCostAdjustment
      WHERE TenantId=@TenantId AND SourceId=@SourceId),0);
    SELECT @Cogs=ISNULL(SUM(DeltaCogs),0) FROM ac06.CostEffect
     WHERE TenantId=@TenantId AND SourceId=@SourceId;
    SELECT @MainQty=Qty,@MainValue=StockValue FROM ac06.StockBalances
     WHERE TenantId=@TenantId AND SkuId=@SkuId AND LocationId=@MainLocation;
    SELECT @QuarantineQty=Qty,@QuarantineValue=StockValue FROM ac06.StockBalances
     WHERE TenantId=@TenantId AND SkuId=@SkuId AND LocationId=@QuarantineLocation;
    IF @MainQty IS NULL OR @QuarantineQty IS NULL
        THROW 53913,'CHECKPOINT_STOCK_LOCATION_MISSING',1;
    INSERT ac06.Checkpoint VALUES(@Ordinal,@Name,@Version,@Cost,@Q,@Refund,@Cogs,
                    @MainQty,@MainValue,@QuarantineQty,@QuarantineValue);
END;
GO
