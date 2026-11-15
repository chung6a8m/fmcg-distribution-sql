-- SQL-02 / AC-03 commands. These are fixture-specific executable specifications,
-- not public application APIs. Each accepted command and its effects commit atomically.
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
CREATE PROCEDURE ac03.RecordCommand
    @CommandId varchar(50),
    @PayloadHash char(64),
    @Outcome varchar(16),
    @Reason varchar(64) = NULL,
    @Replay bit OUTPUT,
    @StoredOutcome varchar(16) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OldHash char(64);
    SELECT @OldHash=PayloadHash, @StoredOutcome=Outcome
    FROM ac03.BusinessEvent WITH (UPDLOCK,HOLDLOCK)
    WHERE TenantId='T01' AND ProducerId='SQL02' AND CommandId=@CommandId;
    SET @Replay=IIF(@OldHash IS NULL,0,1);
    IF @Replay=1
    BEGIN
        IF @OldHash <> @PayloadHash
            THROW 51100, 'COMMAND_ID_PAYLOAD_CONFLICT', 1;
        RETURN;
    END;
    INSERT ac03.BusinessEvent(TenantId,EventId,ProducerId,CommandId,PayloadHash,Outcome,Reason)
    VALUES('T01',@CommandId,'SQL02',@CommandId,@PayloadHash,@Outcome,@Reason);
    SET @StoredOutcome=@Outcome;
END;
GO
CREATE PROCEDURE ac03.ExecuteTransfer
    @Action varchar(6),              -- LOAD or UNLOAD
    @CommandId varchar(50),
    @PayloadHash char(64),
    @AQty decimal(19,6),
    @BQty decimal(19,6),
    @InjectFault bit = 0,
    @Result varchar(32) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    DECLARE @Replay bit, @StoredOutcome varchar(16), @From varchar(64), @To varchar(64),
            @FromQty decimal(19,6), @FromValue decimal(28,6),
            @AAvailable decimal(19,6), @BAvailable decimal(19,6),
            @UnitCost decimal(28,10), @RequestedValue decimal(28,6);
    IF @Action NOT IN ('LOAD','UNLOAD') OR @AQty<=0 OR @BQty<=0
        THROW 51101, 'INVALID_TRANSFER_INPUT', 1;
    SET @From=IIF(@Action='LOAD','MAIN','TRIP');
    SET @To=IIF(@Action='LOAD','TRIP','MAIN');
    SET @PayloadHash=CONVERT(char(64),HASHBYTES('SHA2_256',
        CONCAT(@PayloadHash,':TRANSFER:',@Action,':',@AQty,':',@BQty)),2);
    BEGIN TRY
        BEGIN TRANSACTION;
        -- Stable master/right locks make same-scope commands serialize. SQL-03A
        -- will separately verify true two-session races; this does not claim that gate.
        SELECT @UnitCost=UnitCost FROM ac03.Sku WITH (UPDLOCK,HOLDLOCK)
        WHERE TenantId='T01' AND SkuId='SKU01';
        SELECT 1 FROM ac03.Trip WITH (UPDLOCK,HOLDLOCK)
        WHERE TenantId='T01' AND TripId='TR01';
        SELECT 1 FROM ac03.AReservation WITH (UPDLOCK,HOLDLOCK)
        WHERE TenantId='T01' AND RightId='RA01';
        SELECT 1 FROM ac03.BQuota WITH (UPDLOCK,HOLDLOCK)
        WHERE TenantId='T01' AND RightId='QB01';

        EXEC ac03.RecordCommand @CommandId,@PayloadHash,'ACCEPTED',NULL,@Replay OUTPUT,@StoredOutcome OUTPUT;
        IF @Replay=1
        BEGIN
            SET @Result='REPLAY_' + @StoredOutcome;
            COMMIT;
            RETURN;
        END;

        SELECT @AAvailable=ISNULL(SUM(DeltaQty),0) FROM ac03.RightPosting
        WHERE TenantId='T01' AND RightKind='A' AND RightId='RA01' AND LocationId=@From;
        SELECT @BAvailable=ISNULL(SUM(DeltaQty),0) FROM ac03.RightPosting
        WHERE TenantId='T01' AND RightKind='B' AND RightId='QB01' AND LocationId=@From;
        SELECT @FromQty=ISNULL(SUM(DeltaQty),0), @FromValue=ISNULL(SUM(DeltaValue),0)
        FROM ac03.StockPosting WHERE TenantId='T01' AND LocationId=@From AND SkuId='SKU01';
        SET @RequestedValue=CONVERT(decimal(28,6),(@AQty+@BQty)*@UnitCost);
        IF @UnitCost IS NULL OR @AAvailable<@AQty OR @BAvailable<@BQty
           OR @FromQty<(@AQty+@BQty) OR @FromValue<@RequestedValue
            THROW 51102, 'TRANSFER_RIGHT_OR_STOCK_INSUFFICIENT', 1;
        IF @Action='LOAD'
           AND EXISTS (SELECT 1 FROM ac03.ManifestLine
                       WHERE TenantId='T01' AND TripId='TR01' AND SkuId='SKU01')
            THROW 51103, 'AC03_MANIFEST_ALREADY_LOADED', 1;
        IF @Action='UNLOAD'
        BEGIN
            IF (SELECT COUNT(*) FROM ac03.ManifestLine WHERE TenantId='T01'
                AND SourceLineId IN ('LOAD1-A','LOAD1-B'))<>2
                THROW 51104, 'MANIFEST_LINEAGE_MISSING', 1;
            -- Cannot unload more units than were loaded on each original source.
            IF EXISTS (
                SELECT 1 FROM (VALUES ('LOAD1-A',@AQty),('LOAD1-B',@BQty)) q(ManifestId,Qty)
                JOIN ac03.ManifestLine m ON m.TenantId='T01' AND m.SourceLineId=q.ManifestId
                OUTER APPLY (SELECT ISNULL(SUM(u.Qty),0) UsedQty FROM ac03.UnloadLine u
                             WHERE u.TenantId='T01' AND u.ManifestLineId=m.SourceLineId) used
                WHERE q.Qty+used.UsedQty>m.Qty)
                THROW 51105, 'UNLOAD_EXCEEDS_MANIFEST', 1;
        END;

        DECLARE @Lines table
        (LineOrdinal int NOT NULL, Pool char(1) NOT NULL, RightId varchar(64) NOT NULL,
         SourceLineId varchar(64) NOT NULL, Qty decimal(19,6) NOT NULL, CostValue decimal(28,6) NOT NULL);
        INSERT @Lines VALUES
            (1,'A','RA01',@CommandId+'-A',@AQty,CONVERT(decimal(28,6),@AQty*@UnitCost)),
            (2,'B','QB01',@CommandId+'-B',@BQty,CONVERT(decimal(28,6),@BQty*@UnitCost));
        INSERT ac03.SourceLine(TenantId,SourceLineId,EventId,LineOrdinal,SourceRole)
        SELECT 'T01',SourceLineId,@CommandId,LineOrdinal,@Action FROM @Lines;
        IF @Action='LOAD'
            INSERT ac03.ManifestLine(TenantId,SourceLineId,TripId,SkuId,Pool,RightId,
                                      AReservationId,BQuotaId,Qty,CostValue)
            SELECT 'T01',SourceLineId,'TR01','SKU01',Pool,RightId,
                   IIF(Pool='A',RightId,NULL),IIF(Pool='B',RightId,NULL),Qty,CostValue FROM @Lines;
        ELSE
            INSERT ac03.UnloadLine(TenantId,SourceLineId,ManifestLineId,TripId,SkuId,Pool,
                                   RightId,Qty,CostValue)
            SELECT 'T01',SourceLineId,CASE WHEN Pool='A' THEN 'LOAD1-A' ELSE 'LOAD1-B' END,
                   'TR01','SKU01',Pool,RightId,Qty,CostValue FROM @Lines;
        INSERT ac03.StockMovement(TenantId,SourceLineId,MovementRole,SkuId,Qty,CostValue)
        SELECT 'T01',SourceLineId,'TRANSFER','SKU01',Qty,CostValue FROM @Lines;
        INSERT ac03.StockPosting(TenantId,SourceLineId,MovementRole,LegOrdinal,LocationId,SkuId,DeltaQty,DeltaValue)
        SELECT 'T01',SourceLineId,'TRANSFER',1,@From,'SKU01',-Qty,-CostValue FROM @Lines
        UNION ALL
        SELECT 'T01',SourceLineId,'TRANSFER',2,@To,'SKU01',Qty,CostValue FROM @Lines;
        IF @InjectFault=1 THROW 51106, 'INJECTED_TRANSFER_FAULT', 1;
        INSERT ac03.RightPosting(TenantId,SourceLineId,EffectOrdinal,RightKind,RightId,LocationId,DeltaQty)
        SELECT 'T01',SourceLineId,1,Pool,RightId,@From,-Qty FROM @Lines
        UNION ALL
        SELECT 'T01',SourceLineId,2,Pool,RightId,@To,Qty
        FROM @Lines WHERE @Action='LOAD' OR Pool='A';
        EXEC ac03.AssertInvariants;
        SET @Result='ACCEPTED';
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE PROCEDURE ac03.ExecuteSaleB
    @CommandId varchar(50),
    @PayloadHash char(64),
    @Qty decimal(19,6),
    @VerifiedCash decimal(28,6),
    @CustomerId varchar(64) = 'C_B',
    @InjectFault bit = 0,
    @Result varchar(32) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    DECLARE @Replay bit, @OldOutcome varchar(16), @Available decimal(19,6), @TripQty decimal(19,6),
            @TripValue decimal(28,6), @UnitCost decimal(28,10), @P decimal(28,6),
            @Cost decimal(28,6), @Exposure decimal(28,6), @GrantRemaining decimal(28,6),
            @Source varchar(64);
    IF @Qty<=0 OR @VerifiedCash<0
        THROW 51110, 'INVALID_B_INPUT', 1;
    SET @P=CONVERT(decimal(28,6),@Qty*CONVERT(decimal(28,10),15));
    IF @VerifiedCash>@P
        THROW 51111, 'CASH_EXCEEDS_PAYABLE_FOR_AC03', 1;
    SET @Exposure=@P-@VerifiedCash;
    SET @Source=@CommandId+'-01';
    SET @PayloadHash=CONVERT(char(64),HASHBYTES('SHA2_256',
        CONCAT(@PayloadHash,':B:',@Qty,':',@VerifiedCash,':',@CustomerId)),2);
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @UnitCost=UnitCost FROM ac03.Sku WITH (UPDLOCK,HOLDLOCK)
            WHERE TenantId='T01' AND SkuId='SKU01';
        SELECT 1 FROM ac03.BQuota WITH (UPDLOCK,HOLDLOCK)
            WHERE TenantId='T01' AND RightId='QB01';
        SELECT 1 FROM ac03.BCreditGrant WITH (UPDLOCK,HOLDLOCK)
            WHERE TenantId='T01' AND GrantId='GB01';
        -- Resolve replay/conflict before checking changing quota/grant state.
        EXEC ac03.RecordCommand @CommandId,@PayloadHash,'ACCEPTED',NULL,@Replay OUTPUT,@OldOutcome OUTPUT;
        IF @Replay=1
        BEGIN
            SET @Result=CASE WHEN @OldOutcome='REJECTED' THEN 'REPLAY_REJECTED_QUOTA'
                              ELSE 'REPLAY_ACCEPTED' END;
            COMMIT;
            RETURN;
        END;
        SELECT @Available=ISNULL(SUM(DeltaQty),0) FROM ac03.RightPosting
            WHERE TenantId='T01' AND RightKind='B' AND RightId='QB01' AND LocationId='TRIP';
        -- B31 has otherwise sufficient synthetic cash; reject with no business effects.
        IF @Available<@Qty
        BEGIN
            UPDATE ac03.BusinessEvent SET Outcome='REJECTED',Reason='B_QUOTA_INSUFFICIENT'
            WHERE TenantId='T01' AND EventId=@CommandId;
            SET @Result='REJECTED_QUOTA';
            COMMIT;
            RETURN;
        END;
        IF NOT EXISTS(SELECT 1 FROM ac03.Customer WHERE TenantId='T01' AND CustomerId=@CustomerId)
            THROW 51112, 'B_CUSTOMER_NOT_FOUND', 1;
        SELECT @TripQty=ISNULL(SUM(DeltaQty),0),@TripValue=ISNULL(SUM(DeltaValue),0)
        FROM ac03.StockPosting WHERE TenantId='T01' AND LocationId='TRIP' AND SkuId='SKU01';
        SET @Cost=CONVERT(decimal(28,6),@Qty*@UnitCost);
        SELECT @GrantRemaining=ISNULL(SUM(DeltaAmount),0)
        FROM ac03.GrantEffect WHERE TenantId='T01' AND GrantId='GB01';
        IF @TripQty<@Qty OR @TripValue<@Cost OR @GrantRemaining<@Exposure
            THROW 51113, 'B_STOCK_OR_CREDIT_INSUFFICIENT', 1;
        INSERT ac03.SourceLine VALUES('T01',@Source,@CommandId,1,'B_SALE_DELIVERY_RECEIPT');
        INSERT ac03.BSaleLine VALUES('T01',@CommandId+'-BS',@CustomerId,'QB01',@Qty,15,N'Synthetic ShipTo B');
        INSERT ac03.DeliveryLine(TenantId,SourceLineId,Module,CustomerId,SkuId,AOrderLineId,
                BSaleLineId,Qty,UnitPriceSnapshot,CostBasisSnapshot,BusinessDate,ShipToSnapshot)
        VALUES('T01',@Source,'B',@CustomerId,'SKU01',NULL,@CommandId+'-BS',@Qty,15,
               @UnitCost,CONVERT(date,'2026-11-15'),N'Synthetic ShipTo B');
        INSERT ac03.StockMovement VALUES('T01',@Source,'ISSUE','SKU01',@Qty,@Cost);
        INSERT ac03.StockPosting VALUES('T01',@Source,'ISSUE',1,'TRIP','SKU01',-@Qty,-@Cost);
        INSERT ac03.RightPosting VALUES('T01',@Source,1,'B','QB01','TRIP',-@Qty);
        INSERT ac03.CogsEffect VALUES('T01',@Source,@Cost);
        IF @InjectFault=1 THROW 51114, 'INJECTED_B_AFTER_STOCK_COST', 1;
        INSERT ac03.ArOpenItem VALUES('T01',@CommandId+'-AR',@Source,@CustomerId,'B',
                                      @P,CONVERT(date,'2026-11-15'));
        IF @VerifiedCash>0
        BEGIN
            INSERT ac03.Receipt VALUES('T01',@CommandId+'-RC',@Source,@CustomerId,
                                       @VerifiedCash,'CASH','CONFIRMED');
            INSERT ac03.ReceiptAllocation VALUES('T01',@CommandId+'-AL',@Source,
                                                  @CustomerId,@CommandId+'-RC',@CommandId+'-AR',@VerifiedCash);
            INSERT ac03.CustodyEffect VALUES('T01',@Source,@VerifiedCash);
        END;
        IF @Exposure>0
            INSERT ac03.GrantEffect VALUES('T01',@Source,'GB01',-@Exposure);
        EXEC ac03.AssertInvariants;
        SET @Result='ACCEPTED';
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE PROCEDURE ac03.ExecuteDeliveryA
    @CommandId varchar(50),
    @PayloadHash char(64),
    @Qty decimal(19,6),
    @CustomerId varchar(64)='C_A',
    @Result varchar(32) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    DECLARE @Replay bit,@OldOutcome varchar(16),@Available decimal(19,6),@Cost decimal(28,6),
            @UnitCost decimal(28,10),@Price decimal(28,10),@Terms int,
            @OrderQty decimal(19,6),@AlreadyDelivered decimal(19,6),@ShipTo nvarchar(200),
            @Source varchar(64);
    IF @Qty<=0 THROW 51120, 'INVALID_A_QTY', 1;
    SET @Source=@CommandId+'-01';
    SET @PayloadHash=CONVERT(char(64),HASHBYTES('SHA2_256',
        CONCAT(@PayloadHash,':A:',@Qty,':',@CustomerId)),2);
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @UnitCost=UnitCost FROM ac03.Sku WITH (UPDLOCK,HOLDLOCK)
            WHERE TenantId='T01' AND SkuId='SKU01';
        SELECT 1 FROM ac03.AReservation WITH (UPDLOCK,HOLDLOCK)
            WHERE TenantId='T01' AND RightId='RA01';
        EXEC ac03.RecordCommand @CommandId,@PayloadHash,'ACCEPTED',NULL,@Replay OUTPUT,@OldOutcome OUTPUT;
        IF @Replay=1
        BEGIN
            SET @Result='REPLAY_'+@OldOutcome;
            COMMIT;
            RETURN;
        END;
        SELECT @OrderQty=ConfirmedQty,@Price=UnitPriceSnapshot,
               @Terms=TermsDaysSnapshot,@ShipTo=ShipToSnapshot
        FROM ac03.AOrderLine WITH (UPDLOCK,HOLDLOCK)
        WHERE TenantId='T01' AND OrderLineId='OA01' AND CustomerId=@CustomerId;
        IF @OrderQty IS NULL THROW 51121, 'A_DELIVERY_WRONG_CUSTOMER', 1;
        SELECT @Available=ISNULL(SUM(DeltaQty),0) FROM ac03.RightPosting
            WHERE TenantId='T01' AND RightKind='A' AND RightId='RA01' AND LocationId='TRIP';
        SELECT @AlreadyDelivered=ISNULL(SUM(Qty),0) FROM ac03.DeliveryLine
            WHERE TenantId='T01' AND Module='A' AND AOrderLineId='OA01';
        IF @Available<@Qty OR @AlreadyDelivered+@Qty>@OrderQty
            THROW 51122, 'A_HOLD_OR_CONFIRMED_EXCEEDED', 1;
        SET @Cost=CONVERT(decimal(28,6),@Qty*@UnitCost);
        IF (SELECT ISNULL(SUM(DeltaQty),0) FROM ac03.StockPosting
            WHERE TenantId='T01' AND LocationId='TRIP')<@Qty
            THROW 51123, 'A_TRIP_STOCK_INSUFFICIENT', 1;
        INSERT ac03.SourceLine VALUES('T01',@Source,@CommandId,1,'A_DELIVERY');
        INSERT ac03.DeliveryLine(TenantId,SourceLineId,Module,CustomerId,SkuId,AOrderLineId,
                BSaleLineId,Qty,UnitPriceSnapshot,CostBasisSnapshot,BusinessDate,ShipToSnapshot)
        VALUES('T01',@Source,'A',@CustomerId,'SKU01','OA01',NULL,@Qty,@Price,
               @UnitCost,CONVERT(date,'2026-11-15'),@ShipTo);
        INSERT ac03.StockMovement VALUES('T01',@Source,'ISSUE','SKU01',@Qty,@Cost);
        INSERT ac03.StockPosting VALUES('T01',@Source,'ISSUE',1,'TRIP','SKU01',-@Qty,-@Cost);
        INSERT ac03.RightPosting VALUES('T01',@Source,1,'A','RA01','TRIP',-@Qty);
        INSERT ac03.CogsEffect VALUES('T01',@Source,@Cost);
        INSERT ac03.ArOpenItem VALUES('T01',@CommandId+'-AR',@Source,@CustomerId,'A',
               CONVERT(decimal(28,6),@Qty*@Price),DATEADD(day,@Terms,CONVERT(date,'2026-11-15')));
        EXEC ac03.AssertInvariants;
        SET @Result='ACCEPTED';
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE PROCEDURE ac03.OfferHandover
    @CommandId varchar(50),
    @PayloadHash char(64),
    @Amount decimal(28,6),
    @Result varchar(32) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Replay bit,@OldOutcome varchar(16);
    IF @Amount<=0 THROW 51130, 'INVALID_HANDOVER_OFFER', 1;
    SET @PayloadHash=CONVERT(char(64),HASHBYTES('SHA2_256',CONCAT(@PayloadHash,':OFFER:',@Amount)),2);
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC ac03.RecordCommand @CommandId,@PayloadHash,'ACCEPTED',NULL,@Replay OUTPUT,@OldOutcome OUTPUT;
        IF @Replay=1
        BEGIN
            SET @Result='REPLAY_'+@OldOutcome;
            COMMIT; RETURN;
        END;
        INSERT ac03.SourceLine VALUES('T01',@CommandId+'-01',@CommandId,1,'HANDOVER_OFFER');
        INSERT ac03.Handover VALUES('T01',@CommandId,@CommandId+'-01',@Amount,'DELIVERY_EMPLOYEE');
        SET @Result='ACCEPTED';
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE PROCEDURE ac03.AcceptHandover
    @CommandId varchar(50),
    @PayloadHash char(64),
    @HandoverId varchar(64),
    @Amount decimal(28,6),
    @CashierId varchar(64),
    @Result varchar(32) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    DECLARE @Replay bit,@OldOutcome varchar(16),@Custody decimal(28,6),
            @Offered decimal(28,6),@Accepted decimal(28,6),@OfferedBy varchar(64);
    IF @Amount<=0 THROW 51131, 'INVALID_HANDOVER_ACCEPT', 1;
    SET @PayloadHash=CONVERT(char(64),HASHBYTES('SHA2_256',
        CONCAT(@PayloadHash,':ACCEPT:',@HandoverId,':',@Amount,':',@CashierId)),2);
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC ac03.RecordCommand @CommandId,@PayloadHash,'ACCEPTED',NULL,@Replay OUTPUT,@OldOutcome OUTPUT;
        IF @Replay=1
        BEGIN
            SET @Result='REPLAY_'+@OldOutcome;
            COMMIT; RETURN;
        END;
        SELECT @Offered=OfferedAmount,@OfferedBy=OfferedBy FROM ac03.Handover WITH (UPDLOCK,HOLDLOCK)
            WHERE TenantId='T01' AND HandoverId=@HandoverId;
        SELECT @Accepted=ISNULL(SUM(AcceptedAmount),0) FROM ac03.CashierAcceptance
            WHERE TenantId='T01' AND HandoverId=@HandoverId;
        SELECT @Custody=ISNULL(SUM(DeltaAmount),0) FROM ac03.CustodyEffect
            WHERE TenantId='T01';
        IF @Offered IS NULL OR @Offered<(@Accepted+@Amount) OR @Custody<@Amount
            THROW 51132, 'HANDOVER_EXCEEDS_OFFER_OR_CUSTODY', 1;
        IF @CashierId=@OfferedBy OR @CashierId<>'CASHIER'
            THROW 51133, 'CASHIER_ROLE_SEPARATION_REQUIRED', 1;
        INSERT ac03.SourceLine VALUES('T01',@CommandId+'-01',@CommandId,1,'CASHIER_ACCEPT');
        INSERT ac03.CashierAcceptance VALUES('T01',@CommandId,@CommandId+'-01',
                                             @HandoverId,@Amount,@CashierId);
        INSERT ac03.CustodyEffect VALUES('T01',@CommandId+'-01',-@Amount);
        INSERT ac03.FundEffect VALUES('T01',@CommandId+'-01',@Amount);
        EXEC ac03.AssertInvariants;
        SET @Result='ACCEPTED';
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
