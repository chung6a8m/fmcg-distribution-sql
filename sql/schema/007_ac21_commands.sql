-- SQL-03B AC-21/AC-20 transactional commands and ledger invariants.
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
CREATE PROCEDURE ac21.AssertScope
    @TenantId varchar(32), @ScopeId varchar(40)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS(SELECT 1 FROM ac21.Scope WHERE TenantId=@TenantId AND ScopeId=@ScopeId)
        THROW 53600, 'SCOPE_MISSING', 1;
    IF EXISTS(SELECT 1 FROM ac21.CustomerBalances
      WHERE TenantId=@TenantId AND ScopeId=@ScopeId
        AND (Ar<0 OR Credit<0 OR Custody<0 OR Fund<0 OR Allocated<0))
        THROW 53601, 'CUSTOMER_LEDGER_NEGATIVE', 1;
    IF EXISTS(SELECT 1 FROM ac21.ReceiptCredit
      WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND AvailableCredit<0)
        THROW 53602, 'RECEIPT_SOURCE_OVER_ALLOCATED', 1;
    IF EXISTS(
      SELECT 1 FROM ac21.ArOpenItem i
      WHERE i.TenantId=@TenantId AND i.ScopeId=@ScopeId
        AND i.OpeningAmount < ISNULL((SELECT SUM(a.Amount)
           FROM ac21.ArAllocation a WHERE a.TenantId=i.TenantId
            AND a.ScopeId=i.ScopeId AND a.ItemId=i.ItemId),0))
        THROW 53603, 'OPEN_ITEM_OVER_ALLOCATED', 1;
    -- Check both existence and amount of every source -> posting edge.
    IF EXISTS(
      SELECT 1 FROM ac21.Receipt r
      WHERE r.TenantId=@TenantId AND r.ScopeId=@ScopeId
        AND r.Channel='CASH' AND r.ReceiptState='CONFIRMED'
        AND NOT EXISTS(SELECT 1 FROM ac21.CustodyPosting p
          WHERE p.TenantId=r.TenantId AND p.ScopeId=r.ScopeId
            AND p.SourceId=r.ReceiptId AND p.SourceKind='RECEIPT'
            AND p.DeltaAmount=r.Amount))
        THROW 53604, 'CONFIRMED_CASH_MISSING_CUSTODY_EFFECT', 1;
    IF EXISTS(
      SELECT 1 FROM ac21.CustodyPosting p
      WHERE p.TenantId=@TenantId AND p.ScopeId=@ScopeId
        AND ((p.SourceKind='RECEIPT' AND NOT EXISTS(
           SELECT 1 FROM ac21.Receipt r WHERE r.TenantId=p.TenantId
            AND r.ScopeId=p.ScopeId AND r.ReceiptId=p.SourceId
            AND r.ReceiptState='CONFIRMED' AND r.Channel='CASH'
            AND r.Amount=p.DeltaAmount))
         OR (p.SourceKind='HANDOVER' AND NOT EXISTS(
           SELECT 1 FROM ac21.HandoverAccept a WHERE a.TenantId=p.TenantId
            AND a.ScopeId=p.ScopeId AND a.AcceptId=p.SourceId
            AND -a.AcceptedAmount=p.DeltaAmount))))
        THROW 53605, 'CUSTODY_EFFECT_WITHOUT_MATCHING_SOURCE', 1;
    IF EXISTS(
      SELECT 1 FROM ac21.HandoverAccept a
      WHERE a.TenantId=@TenantId AND a.ScopeId=@ScopeId
        AND (NOT EXISTS(SELECT 1 FROM ac21.CustodyPosting p
            WHERE p.TenantId=a.TenantId AND p.ScopeId=a.ScopeId
              AND p.SourceId=a.AcceptId AND p.SourceKind='HANDOVER'
              AND p.DeltaAmount=-a.AcceptedAmount)
          OR NOT EXISTS(SELECT 1 FROM ac21.FundPosting f
            WHERE f.TenantId=a.TenantId AND f.ScopeId=a.ScopeId
              AND f.AcceptId=a.AcceptId AND f.Amount=a.AcceptedAmount)))
        THROW 53606, 'CASHIER_ACCEPT_MISSING_ATOMIC_POSTINGS', 1;
    IF EXISTS(
      SELECT 1 FROM ac21.HandoverOffer o
      WHERE o.TenantId=@TenantId AND o.ScopeId=@ScopeId
        AND o.Amount < ISNULL((SELECT SUM(a.AcceptedAmount)
           FROM ac21.HandoverAccept a WHERE a.TenantId=o.TenantId
           AND a.ScopeId=o.ScopeId AND a.OfferId=o.OfferId),0))
        THROW 53607, 'HANDOVER_OVER_ACCEPTED', 1;
    IF EXISTS(SELECT 1 FROM ac21.AdvanceBalances
      WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND Outstanding<0)
        THROW 53608, 'ADVANCE_OUTSTANDING_NEGATIVE', 1;
    IF EXISTS(
      SELECT 1 FROM ac21.AdvanceOffer o
      WHERE o.TenantId=@TenantId AND o.ScopeId=@ScopeId
        AND o.Amount < ISNULL((SELECT SUM(a.AcceptedAmount)
           FROM ac21.AdvanceAccept a WHERE a.TenantId=o.TenantId
           AND a.ScopeId=o.ScopeId AND a.OfferId=o.OfferId),0))
        THROW 53609, 'ADVANCE_OFFER_OVER_ACCEPTED', 1;
END;
GO
-- All commands on the same tenant/scope serialize on one existing Scope row.
-- All semantic inputs (including kind/ref/channel/state) are hashed for retry.
-- InjectFault is a test-only rollback probe; it is not business payload.
CREATE PROCEDURE ac21.PostCommand
    @TenantId varchar(32),
    @ScopeId varchar(40),
    @CommandId varchar(40),
    @Kind varchar(20),
    @Amount decimal(28,6),
    @RefId varchar(40) = NULL,
    @TargetId varchar(40) = NULL,
    @Channel varchar(8) = NULL,
    @ReceiptState varchar(12) = NULL,
    @InjectFault bit = 0,
    @Result varchar(32) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    IF @TenantId IS NULL OR LEN(@TenantId)=0
       OR @ScopeId IS NULL OR LEN(@ScopeId)=0
       OR @CommandId IS NULL OR LEN(@CommandId)=0
       OR @Kind IS NULL OR @Kind NOT IN
       ('RECEIPT','ALLOCATE','HANDOVER_OFFER','HANDOVER_ACCEPT',
        'ADV_ISSUE','ADV_EXPENSE','ADV_OFFER','ADV_ACCEPT')
       OR @Amount IS NULL OR @Amount<=0
       THROW 53300, 'INVALID_COMMAND', 1;
    IF (@Kind='RECEIPT' AND (@Channel IS NULL OR @Channel NOT IN ('CASH','BANK')
        OR @ReceiptState IS NULL OR @ReceiptState NOT IN ('CONFIRMED','PENDING')
        OR @RefId IS NOT NULL OR @TargetId IS NOT NULL))
       OR (@Kind<>'RECEIPT' AND (@Channel IS NOT NULL OR @ReceiptState IS NOT NULL))
       OR (@Kind IN ('ALLOCATE','HANDOVER_ACCEPT','ADV_ACCEPT') AND
           (@RefId IS NULL OR LEN(@RefId)=0))
       OR (@Kind NOT IN ('ALLOCATE','HANDOVER_ACCEPT','ADV_ACCEPT') AND
           @RefId IS NOT NULL)
       OR (@Kind IN ('ALLOCATE','ADV_ISSUE','ADV_EXPENSE','ADV_OFFER','ADV_ACCEPT')
           AND (@TargetId IS NULL OR LEN(@TargetId)=0))
       OR (@Kind NOT IN ('ALLOCATE','ADV_ISSUE','ADV_EXPENSE','ADV_OFFER','ADV_ACCEPT')
           AND @TargetId IS NOT NULL)
       THROW 53300, 'INVALID_COMMAND_PAYLOAD_SHAPE', 1;

    DECLARE @Hash char(64), @OldHash char(64), @OldKind varchar(20),
            @CustomerId varchar(40), @ReceiptCustomer varchar(40),
            @RState varchar(12), @ArCustomer varchar(40),
            @Available decimal(28,6), @ArAvailable decimal(28,6),
            @OfferAmount decimal(28,6), @Used decimal(28,6),
            @OfferAdvanceId varchar(40), @Account varchar(40);
    -- Length-prefix identifiers (NULL and empty are distinct). No delimiter collision.
    SET @Hash=CONVERT(char(64),HASHBYTES('SHA2_256',CONCAT(
       'AC21:v1|',LEN(@Kind),':',@Kind,
       '|',CONVERT(varchar(50),@Amount),
       '|',CASE WHEN @RefId IS NULL THEN 'N' ELSE CONCAT('V',LEN(@RefId),':',@RefId) END,
       '|',CASE WHEN @TargetId IS NULL THEN 'N' ELSE CONCAT('V',LEN(@TargetId),':',@TargetId) END,
       '|',CASE WHEN @Channel IS NULL THEN 'N' ELSE CONCAT('V',LEN(@Channel),':',@Channel) END,
       '|',CASE WHEN @ReceiptState IS NULL THEN 'N' ELSE CONCAT('V',LEN(@ReceiptState),':',@ReceiptState) END)),2);
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @CustomerId=CustomerId
        FROM ac21.Scope WITH(UPDLOCK,HOLDLOCK)
        WHERE TenantId=@TenantId AND ScopeId=@ScopeId;
        IF @CustomerId IS NULL THROW 53302, 'SCOPE_NOT_FOUND', 1;

        SELECT @OldHash=PayloadHash,@OldKind=Kind
        FROM ac21.Command WITH(UPDLOCK,HOLDLOCK)
        WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND CommandId=@CommandId;
        IF @OldHash IS NOT NULL
        BEGIN
            IF @OldHash<>@Hash OR @OldKind<>@Kind
               THROW 53301, 'COMMAND_ID_PAYLOAD_CONFLICT', 1;
            SET @Result='REPLAY_ACCEPTED';
            COMMIT;
            RETURN;
        END;

        IF @Kind='RECEIPT'
        BEGIN
            INSERT ac21.Command(TenantId,ScopeId,CommandId,Kind,PayloadHash)
            VALUES(@TenantId,@ScopeId,@CommandId,@Kind,@Hash);
            INSERT ac21.Receipt
                (TenantId,ScopeId,ReceiptId,CustomerId,Channel,ReceiptState,Amount)
            VALUES(@TenantId,@ScopeId,@CommandId,@CustomerId,@Channel,@ReceiptState,@Amount);
            -- Fail after durable receipt row: both receipt and command must roll back.
            IF @InjectFault=1 THROW 53390, 'INJECTED_PARTIAL_RECEIPT', 1;
            IF @Channel='CASH' AND @ReceiptState='CONFIRMED'
                INSERT ac21.CustodyPosting
                  (TenantId,ScopeId,SourceId,SourceKind,DeltaAmount)
                VALUES(@TenantId,@ScopeId,@CommandId,'RECEIPT',@Amount);
        END
        ELSE IF @Kind='ALLOCATE'
        BEGIN
            SELECT @ReceiptCustomer=CustomerId,@RState=ReceiptState
              FROM ac21.Receipt WITH(UPDLOCK,HOLDLOCK)
              WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND ReceiptId=@RefId;
            IF @ReceiptCustomer IS NULL OR @RState<>'CONFIRMED'
                THROW 53320, 'RECEIPT_NOT_CONFIRMED', 1;
            SELECT @ArCustomer=CustomerId,
                   @ArAvailable=OpeningAmount-ISNULL(
                    (SELECT SUM(Amount) FROM ac21.ArAllocation
                     WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND ItemId=@TargetId),0)
              FROM ac21.ArOpenItem WITH(UPDLOCK,HOLDLOCK)
              WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND ItemId=@TargetId;
            IF @ArCustomer IS NULL OR @ArCustomer<>@CustomerId
               OR @ReceiptCustomer<>@CustomerId
               THROW 53322, 'ALLOCATION_CUSTOMER_OR_ITEM_MISMATCH', 1;
            SELECT @Available=AvailableCredit FROM ac21.ReceiptCredit
              WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND ReceiptId=@RefId;
            IF @Available<@Amount THROW 53321, 'RECEIPT_CREDIT_INSUFFICIENT', 1;
            IF @ArAvailable<@Amount THROW 53323, 'AR_OPEN_ITEM_INSUFFICIENT', 1;
            INSERT ac21.Command(TenantId,ScopeId,CommandId,Kind,PayloadHash)
            VALUES(@TenantId,@ScopeId,@CommandId,@Kind,@Hash);
            INSERT ac21.ArAllocation
              (TenantId,ScopeId,AllocationId,ReceiptId,ItemId,CustomerId,Amount)
            VALUES(@TenantId,@ScopeId,@CommandId,@RefId,@TargetId,@CustomerId,@Amount);
            IF @InjectFault=1 THROW 53390, 'INJECTED_ALLOCATION_FAULT', 1;
        END
        ELSE IF @Kind='HANDOVER_OFFER'
        BEGIN
            SELECT @Available=Custody FROM ac21.CustomerBalances
             WHERE TenantId=@TenantId AND ScopeId=@ScopeId;
            IF @Available<@Amount THROW 53330, 'CASH_CUSTODY_INSUFFICIENT_TO_OFFER', 1;
            INSERT ac21.Command(TenantId,ScopeId,CommandId,Kind,PayloadHash)
            VALUES(@TenantId,@ScopeId,@CommandId,@Kind,@Hash);
            INSERT ac21.HandoverOffer VALUES(@TenantId,@ScopeId,@CommandId,@Amount);
            IF @InjectFault=1 THROW 53390, 'INJECTED_OFFER_FAULT', 1;
            -- OFFER intentionally creates NO CustodyPosting or FundPosting.
        END
        ELSE IF @Kind='HANDOVER_ACCEPT'
        BEGIN
            SELECT @OfferAmount=Amount FROM ac21.HandoverOffer WITH(UPDLOCK,HOLDLOCK)
             WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND OfferId=@RefId;
            IF @OfferAmount IS NULL THROW 53331, 'HANDOVER_OFFER_NOT_FOUND', 1;
            SELECT @Used=ISNULL(SUM(AcceptedAmount),0) FROM ac21.HandoverAccept
             WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND OfferId=@RefId;
            IF @OfferAmount-@Used<@Amount THROW 53332, 'HANDOVER_OVER_ACCEPTANCE', 1;
            SELECT @Available=Custody FROM ac21.CustomerBalances
             WHERE TenantId=@TenantId AND ScopeId=@ScopeId;
            IF @Available<@Amount THROW 53333, 'CASH_CUSTODY_INSUFFICIENT', 1;
            INSERT ac21.Command(TenantId,ScopeId,CommandId,Kind,PayloadHash)
            VALUES(@TenantId,@ScopeId,@CommandId,@Kind,@Hash);
            INSERT ac21.HandoverAccept VALUES(@TenantId,@ScopeId,@CommandId,@RefId,@Amount);
            INSERT ac21.CustodyPosting
              (TenantId,ScopeId,SourceId,SourceKind,DeltaAmount)
            VALUES(@TenantId,@ScopeId,@CommandId,'HANDOVER',-@Amount);
            -- Fail BETWEEN custody and fund postings; no half-accepted handover.
            IF @InjectFault=1 THROW 53390, 'INJECTED_CASHIER_ATOMICITY_FAULT', 1;
            INSERT ac21.FundPosting VALUES(@TenantId,@ScopeId,@CommandId,@Amount);
        END
        ELSE
        BEGIN
            SELECT @Account=AdvanceId
              FROM ac21.AdvanceAccount WITH(UPDLOCK,HOLDLOCK)
              WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND AdvanceId=@TargetId;
            IF @Account IS NULL THROW 53340, 'ADVANCE_ACCOUNT_NOT_FOUND', 1;
            IF @Kind='ADV_ISSUE'
            BEGIN
                INSERT ac21.Command(TenantId,ScopeId,CommandId,Kind,PayloadHash)
                VALUES(@TenantId,@ScopeId,@CommandId,@Kind,@Hash);
                INSERT ac21.AdvanceIssue VALUES(@TenantId,@ScopeId,@CommandId,@TargetId,@Amount);
            END
            ELSE IF @Kind='ADV_EXPENSE'
            BEGIN
                SELECT @Available=Outstanding FROM ac21.AdvanceBalances
                 WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND AdvanceId=@TargetId;
                IF @Available<@Amount THROW 53341, 'ADVANCE_EXPENSE_EXCEEDS_OUTSTANDING', 1;
                INSERT ac21.Command(TenantId,ScopeId,CommandId,Kind,PayloadHash)
                VALUES(@TenantId,@ScopeId,@CommandId,@Kind,@Hash);
                INSERT ac21.AdvanceExpense VALUES(@TenantId,@ScopeId,@CommandId,@TargetId,@Amount);
            END
            ELSE IF @Kind='ADV_OFFER'
            BEGIN
                SELECT @Available=Outstanding FROM ac21.AdvanceBalances
                 WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND AdvanceId=@TargetId;
                IF @Available<@Amount THROW 53342, 'ADVANCE_OFFER_EXCEEDS_OUTSTANDING', 1;
                INSERT ac21.Command(TenantId,ScopeId,CommandId,Kind,PayloadHash)
                VALUES(@TenantId,@ScopeId,@CommandId,@Kind,@Hash);
                INSERT ac21.AdvanceOffer VALUES(@TenantId,@ScopeId,@CommandId,@TargetId,@Amount);
            END
            ELSE IF @Kind='ADV_ACCEPT'
            BEGIN
                SELECT @OfferAmount=Amount,@OfferAdvanceId=AdvanceId
                  FROM ac21.AdvanceOffer WITH(UPDLOCK,HOLDLOCK)
                  WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND OfferId=@RefId;
                IF @OfferAmount IS NULL OR @OfferAdvanceId<>@TargetId
                    THROW 53343, 'ADVANCE_OFFER_OR_ACCOUNT_MISMATCH', 1;
                SELECT @Used=ISNULL(SUM(AcceptedAmount),0) FROM ac21.AdvanceAccept
                 WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND OfferId=@RefId;
                IF @OfferAmount-@Used<@Amount
                    THROW 53343, 'ADVANCE_OFFER_OVER_ACCEPTANCE', 1;
                SELECT @Available=Outstanding FROM ac21.AdvanceBalances
                 WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND AdvanceId=@TargetId;
                IF @Available<@Amount THROW 53344, 'ADVANCE_OUTSTANDING_INSUFFICIENT', 1;
                INSERT ac21.Command(TenantId,ScopeId,CommandId,Kind,PayloadHash)
                VALUES(@TenantId,@ScopeId,@CommandId,@Kind,@Hash);
                INSERT ac21.AdvanceAccept
                VALUES(@TenantId,@ScopeId,@CommandId,@RefId,@TargetId,@Amount);
            END;
            IF @InjectFault=1 THROW 53390, 'INJECTED_ADVANCE_ATOMICITY_FAULT', 1;
        END;
        EXEC ac21.AssertScope @TenantId,@ScopeId;
        SET @Result='ACCEPTED';
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE PROCEDURE ac21.CaptureCustomer
    @StepOrdinal int, @Step varchar(32), @TenantId varchar(32), @ScopeId varchar(40)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC ac21.AssertScope @TenantId,@ScopeId;
    INSERT ac21.CustomerCheckpoint(StepOrdinal,Step,Ar,Credit,Custody,Fund,Allocated)
    SELECT @StepOrdinal,@Step,Ar,Credit,Custody,Fund,Allocated
      FROM ac21.CustomerBalances WHERE TenantId=@TenantId AND ScopeId=@ScopeId;
    IF @@ROWCOUNT<>1 THROW 53610, 'CUSTOMER_CHECKPOINT_MISSING', 1;
END;
GO
CREATE PROCEDURE ac21.CaptureAdvance
    @StepOrdinal int, @Step varchar(32), @TenantId varchar(32),
    @ScopeId varchar(40), @AdvanceId varchar(40)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC ac21.AssertScope @TenantId,@ScopeId;
    INSERT ac21.AdvanceCheckpoint
      (StepOrdinal,Step,Issued,ApprovedExpenses,CashierAcceptedReturns,Outstanding)
    SELECT @StepOrdinal,@Step,Issued,ApprovedExpenses,CashierAcceptedReturns,Outstanding
      FROM ac21.AdvanceBalances
      WHERE TenantId=@TenantId AND ScopeId=@ScopeId AND AdvanceId=@AdvanceId;
    IF @@ROWCOUNT<>1 THROW 53611, 'ADVANCE_CHECKPOINT_MISSING', 1;
END;
GO
