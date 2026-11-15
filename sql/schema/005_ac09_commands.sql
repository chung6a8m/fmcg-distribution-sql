-- SQL-03A AC-09: atomic B sale, verified receipt/credit and durable replay.
-- The pool row is the serialization point for BOTH BQuota and credit grant.
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
-- A fixture-only authority step: reserve a specific opening-credit source
-- for one intended command. Both the reservation and the subsequent sale
-- serialize through the same tenant/pool row under SERIALIZABLE.
CREATE PROCEDURE ac09.ReserveCredit
    @PoolId varchar(40),
    @SourceId varchar(40),
    @CommandId varchar(40),
    @Amount decimal(28,6),
    @Result varchar(32) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    IF @PoolId IS NULL OR @SourceId IS NULL OR @CommandId IS NULL
       OR LEN(@PoolId)=0 OR LEN(@SourceId)=0 OR LEN(@CommandId)=0
       OR @Amount IS NULL OR @Amount<=0
        THROW 53215, 'INVALID_CREDIT_RESERVATION', 1;
    DECLARE @TenantId varchar(32)='T09',
            @PoolCustomer varchar(40),@SourceCustomer varchar(40),
            @SourceAmount decimal(28,6),@AlreadyReserved decimal(28,6),
            @ExistingSource varchar(40),@ExistingAmount decimal(28,6);
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @PoolCustomer=CustomerId FROM ac09.Pool WITH(UPDLOCK,HOLDLOCK)
        WHERE TenantId=@TenantId AND PoolId=@PoolId;
        IF @PoolCustomer IS NULL THROW 53202, 'B_POOL_NOT_FOUND', 1;
        SELECT @SourceCustomer=CustomerId,@SourceAmount=Amount
        FROM ac09.CreditSource WITH(UPDLOCK,HOLDLOCK)
        WHERE TenantId=@TenantId AND PoolId=@PoolId AND SourceId=@SourceId;
        IF @SourceCustomer IS NULL OR @SourceCustomer<>@PoolCustomer
            THROW 53215, 'CREDIT_SOURCE_NOT_OWNED_BY_CUSTOMER', 1;
        SELECT @ExistingSource=SourceId,@ExistingAmount=Amount
        FROM ac09.CreditReservation WITH(UPDLOCK,HOLDLOCK)
        WHERE TenantId=@TenantId AND PoolId=@PoolId AND CommandId=@CommandId;
        IF @ExistingSource IS NOT NULL
        BEGIN
            IF @ExistingSource<>@SourceId OR @ExistingAmount<>@Amount
                THROW 53216, 'CREDIT_RESERVATION_COMMAND_CONFLICT', 1;
            SET @Result='ALREADY_RESERVED';
            COMMIT;
            RETURN;
        END;
        SELECT @AlreadyReserved=ISNULL(SUM(Amount),0)
        FROM ac09.CreditReservation
        WHERE TenantId=@TenantId AND PoolId=@PoolId AND SourceId=@SourceId;
        IF @AlreadyReserved+@Amount>@SourceAmount
            THROW 53217, 'CREDIT_SOURCE_RESERVATION_EXCEEDED', 1;
        INSERT ac09.CreditReservation(TenantId,PoolId,CommandId,SourceId,CustomerId,Amount)
        VALUES(@TenantId,@PoolId,@CommandId,@SourceId,@PoolCustomer,@Amount);
        SET @Result='RESERVED';
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE PROCEDURE ac09.ExecuteSale
    @PoolId varchar(40),
    @CommandId varchar(40),
    @Qty decimal(19,6),
    @UnitPrice decimal(28,6),
    @CashApplied decimal(28,6),
    @ReservedCreditApplied decimal(28,6),
    @ActualCashReceived decimal(28,6),
    @PendingBankEvidence decimal(28,6) = 0,
    @InjectFault bit = 0,
    @HoldLock bit = 0,
    @Result varchar(32) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    DECLARE @TenantId varchar(32)='T09',@ProducerId varchar(40)='SQL03A',
            @CustomerId varchar(40),@UnitCost decimal(28,6),
            @P decimal(28,6),@Exposure decimal(28,6),@Overpay decimal(28,6),
            @Hash char(64),@OldHash char(64),
            @Quota decimal(19,6),@Stock decimal(19,6),
            @Grant decimal(28,6),@Credit decimal(28,6),
            @ReservedAmount decimal(28,6),@ReservedCustomer varchar(40);
    IF @PoolId IS NULL OR @CommandId IS NULL OR LEN(@CommandId)=0
       OR @Qty IS NULL OR @UnitPrice IS NULL OR @CashApplied IS NULL
       OR @ReservedCreditApplied IS NULL OR @ActualCashReceived IS NULL OR @PendingBankEvidence IS NULL
       OR @Qty<=0 OR @UnitPrice<=0 OR @CashApplied<0 OR @ReservedCreditApplied<0
       OR @ActualCashReceived<0 OR @PendingBankEvidence<0
        THROW 53200, 'INVALID_B_SALE_INPUT', 1;
    SET @P=CONVERT(decimal(28,6),@Qty*@UnitPrice);
    IF @P<=0 OR @CashApplied+@ReservedCreditApplied>@P OR @ActualCashReceived<@CashApplied
        THROW 53200, 'INVALID_RECEIPT_OR_PAYABLE', 1;
    SET @Exposure=@P-@CashApplied-@ReservedCreditApplied;
    SET @Overpay=@ActualCashReceived-@CashApplied;
    -- This narrow fixture allows new CustomerCredit only after the sale is
    -- fully covered; general multi-sale unapplied receipt is deferred to SQL-03B.
    IF @Overpay>0 AND @Exposure<>0
        THROW 53200, 'PARTIAL_PAYMENT_WITH_UNAPPLIED_CASH_NOT_IN_AC09', 1;
    -- Hash ALL semantic inputs; identical caller identity with changed amount,
    -- channel evidence, cost or reserved credit cannot masquerade as a replay.
    SET @Hash=CONVERT(char(64),HASHBYTES('SHA2_256',CONCAT(
        'AC09:v1:',@PoolId,':',@Qty,':',@UnitPrice,':',@CashApplied,':',
        @ReservedCreditApplied,':',@ActualCashReceived,':',@PendingBankEvidence)),2);
    BEGIN TRY
        BEGIN TRANSACTION;
        -- Lock a stable, existing right-pool row BEFORE checking derived
        -- balances or writing a source. This serializes distinct CommandIds.
        SELECT @CustomerId=CustomerId,@UnitCost=UnitCostSnapshot
        FROM ac09.Pool WITH (UPDLOCK,HOLDLOCK)
        WHERE TenantId=@TenantId AND PoolId=@PoolId;
        IF @CustomerId IS NULL THROW 53202, 'B_POOL_NOT_FOUND', 1;
        SELECT @OldHash=PayloadHash FROM ac09.Command WITH (UPDLOCK,HOLDLOCK)
        WHERE TenantId=@TenantId AND PoolId=@PoolId
              AND ProducerId=@ProducerId AND CommandId=@CommandId;
        IF @OldHash IS NOT NULL
        BEGIN
            IF @OldHash<>@Hash THROW 53201, 'COMMAND_ID_PAYLOAD_CONFLICT', 1;
            SET @Result='REPLAY_ACCEPTED';
            COMMIT;
            RETURN;
        END;
        SELECT @Quota=QuotaRemaining,@Stock=StockRemaining,
               @Grant=GrantRemaining,@Credit=CreditRemaining
        FROM ac09.PoolBalances WHERE TenantId=@TenantId AND PoolId=@PoolId;
        IF @Quota<@Qty THROW 53210, 'B_QUOTA_INSUFFICIENT', 1;
        IF @Grant<@Exposure THROW 53211, 'B_CREDIT_GRANT_INSUFFICIENT', 1;
        IF @Stock<@Qty THROW 53212, 'TRIP_STOCK_INSUFFICIENT', 1;
        IF @Credit<@ReservedCreditApplied THROW 53213, 'RESERVED_CUSTOMER_CREDIT_INSUFFICIENT', 1;
        SELECT @ReservedAmount=Amount,@ReservedCustomer=CustomerId
        FROM ac09.CreditReservation WITH(UPDLOCK,HOLDLOCK)
        WHERE TenantId=@TenantId AND PoolId=@PoolId AND CommandId=@CommandId;
        IF (@ReservedCreditApplied>0 AND
            (@ReservedAmount IS NULL OR @ReservedAmount<>@ReservedCreditApplied
             OR @ReservedCustomer<>@CustomerId))
           OR (@ReservedCreditApplied=0 AND @ReservedAmount IS NOT NULL)
            THROW 53215, 'CREDIT_NOT_RESERVED_FOR_THIS_COMMAND', 1;
        -- Long enough for the independent observer to sample a real KEY wait.
        IF @HoldLock=1 WAITFOR DELAY '00:00:04';
        INSERT ac09.Command(TenantId,PoolId,ProducerId,CommandId,PayloadHash)
        VALUES(@TenantId,@PoolId,@ProducerId,@CommandId,@Hash);
        INSERT ac09.Sale(TenantId,PoolId,CommandId,CustomerId,Qty,UnitPriceSnapshot,
            Payable,CashApplied,ReservedCreditApplied,ActualCashReceived,
            PendingBankEvidence,Exposure,NewCustomerCredit)
        VALUES(@TenantId,@PoolId,@CommandId,@CustomerId,@Qty,@UnitPrice,
            @P,@CashApplied,@ReservedCreditApplied,@ActualCashReceived,
            @PendingBankEvidence,@Exposure,@Overpay);
        INSERT ac09.StockIssue VALUES(@TenantId,@PoolId,@CommandId,@Qty,CONVERT(decimal(28,6),@Qty*@UnitCost));
        INSERT ac09.QuotaUse VALUES(@TenantId,@PoolId,@CommandId,@Qty);
        INSERT ac09.CogsEffect VALUES(@TenantId,@PoolId,@CommandId,CONVERT(decimal(28,6),@Qty*@UnitCost));
        -- Fault AFTER physically issued stock/COGS but BEFORE AR/receipt/grant.
        -- Both effects and the command identity must be rolled back.
        IF @InjectFault=1 THROW 53214, 'INJECTED_B_ATOMICITY_FAULT', 1;
        INSERT ac09.ArOpenItem VALUES(@TenantId,@PoolId,@CommandId,@CustomerId,@P);
        IF @Exposure>0
            INSERT ac09.GrantUse VALUES(@TenantId,@PoolId,@CommandId,@Exposure);
        IF @ActualCashReceived>0
        BEGIN
            INSERT ac09.Receipt VALUES(@TenantId,@PoolId,@CommandId,'CASH',@CustomerId,@ActualCashReceived,'CONFIRMED');
            INSERT ac09.CustodyEffect VALUES(@TenantId,@PoolId,@CommandId,@ActualCashReceived);
        END;
        IF @PendingBankEvidence>0
            INSERT ac09.Receipt VALUES(@TenantId,@PoolId,@CommandId,'BANK',@CustomerId,@PendingBankEvidence,'PENDING');
        IF @CashApplied>0
            INSERT ac09.ReceiptAllocation(TenantId,PoolId,CommandId,ReceiptKind,CustomerId,Amount)
            VALUES(@TenantId,@PoolId,@CommandId,'CASH',@CustomerId,@CashApplied);
        IF @ReservedCreditApplied>0
        BEGIN
            INSERT ac09.CreditApplication VALUES(@TenantId,@PoolId,@CommandId,@CustomerId,@ReservedCreditApplied);
            INSERT ac09.CreditEffect VALUES(@TenantId,@PoolId,@CommandId,'APPLY',@CustomerId,-@ReservedCreditApplied);
        END;
        IF @Overpay>0
            INSERT ac09.CreditEffect VALUES(@TenantId,@PoolId,@CommandId,'NEW',@CustomerId,@Overpay);
        EXEC ac09.AssertPool @PoolId;
        SET @Result='ACCEPTED';
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
-- Separate SQL sessions call this from two independent sqlcmd processes.
-- The committed barrier rows prove both SPIDs started before either ended.
CREATE PROCEDURE ac09.RunRaceAttempt
    @RaceId varchar(40),
    @AttemptId char(1)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    DECLARE @PoolId varchar(40),@Qty decimal(19,6),@Price decimal(28,6),
            @Cash decimal(28,6),@Result varchar(32),@ErrorNumber int,
            @Start datetime2(3)=SYSUTCDATETIME();
    SELECT @PoolId=PoolId,@Qty=Qty,@Price=UnitPrice,@Cash=CashApplied
    FROM ac09.RaceGate WHERE RaceId=@RaceId AND TenantId='T09';
    IF @PoolId IS NULL OR @AttemptId NOT IN ('A','B') OR @AttemptId IS NULL
        THROW 53300, 'INVALID_RACE', 1;
    INSERT ac09.RaceAttempt(RaceId,AttemptId,SessionId)
    VALUES(@RaceId,@AttemptId,@@SPID);
    WHILE (SELECT COUNT(*) FROM ac09.RaceAttempt WHERE RaceId=@RaceId)<2
    BEGIN
        IF DATEDIFF(second,@Start,SYSUTCDATETIME())>40
            THROW 53301, 'TWO_SESSION_RACE_BARRIER_TIMEOUT', 1;
        WAITFOR DELAY '00:00:00.100';
    END;
    BEGIN TRY
        DECLARE @RaceCommandId varchar(40)=CONCAT(@RaceId,'_',@AttemptId);
        EXEC ac09.ExecuteSale
            @PoolId=@PoolId,
            @CommandId=@RaceCommandId,
            @Qty=@Qty,@UnitPrice=@Price,@CashApplied=@Cash,
            @ReservedCreditApplied=0,@ActualCashReceived=@Cash,
            @PendingBankEvidence=0,@HoldLock=1,@Result=@Result OUTPUT;
        IF @Result<>'ACCEPTED' THROW 53302, 'RACE_UNEXPECTED_REPLAY', 1;
        UPDATE ac09.RaceAttempt SET Outcome='ACCEPTED',FinishedUtc=SYSUTCDATETIME()
         WHERE RaceId=@RaceId AND AttemptId=@AttemptId;
    END TRY
    BEGIN CATCH
        SET @ErrorNumber=ERROR_NUMBER();
        IF @@TRANCOUNT>0 ROLLBACK;
        IF @ErrorNumber NOT IN (53210,53211) THROW;
        UPDATE ac09.RaceAttempt
            SET Outcome='REJECTED',ErrorNumber=@ErrorNumber,FinishedUtc=SYSUTCDATETIME()
        WHERE RaceId=@RaceId AND AttemptId=@AttemptId;
    END CATCH;
    SELECT CONCAT('RACE_RESULT|',@RaceId,'|',@AttemptId,'|',Outcome,'|',
                  ISNULL(CONVERT(varchar(10),ErrorNumber),'0'))
    FROM ac09.RaceAttempt WHERE RaceId=@RaceId AND AttemptId=@AttemptId;
END;
GO
-- The observer is a third sqlcmd connection; it does not serialize either
-- contender. Capture a live LCK_M_* wait on precisely ac09.Pool's KEY row,
-- with the competing SPID holding the same HoBT+key resource.
-- SQL Server 2017+ requires VIEW SERVER STATE for cross-session DMVs.
CREATE PROCEDURE ac09.ObserveRaceContention @RaceId varchar(40)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Start datetime2(3)=SYSUTCDATETIME(),
            @Holder smallint,@Waiter smallint,@WaitType nvarchar(64),
            @HolderMode varchar(12),@WaiterMode varchar(12),
            @Resource nvarchar(256);
    IF NOT EXISTS(SELECT 1 FROM ac09.RaceGate WHERE RaceId=@RaceId AND TenantId='T09')
        THROW 53310, 'RACE_GATE_MISSING', 1;
    WHILE DATEDIFF(second,@Start,SYSUTCDATETIME())<45
    BEGIN
        SELECT TOP(1)
            @Holder=h.SessionId,@Waiter=w.SessionId,@WaitType=req.wait_type,
            @HolderMode=held.request_mode,@WaiterMode=waiting.request_mode,
            @Resource=waiting.resource_description
        FROM ac09.RaceAttempt w
        JOIN ac09.RaceAttempt h ON h.RaceId=w.RaceId AND h.AttemptId<>w.AttemptId
        JOIN sys.dm_exec_requests req ON req.session_id=w.SessionId
            AND req.blocking_session_id=h.SessionId AND req.wait_type LIKE N'LCK_M_%'
        JOIN sys.dm_tran_locks waiting ON waiting.request_session_id=w.SessionId
            AND waiting.request_status='WAIT' AND waiting.resource_type='KEY'
        JOIN sys.partitions part ON part.hobt_id=waiting.resource_associated_entity_id
            AND part.object_id=OBJECT_ID(N'ac09.Pool',N'U')
        JOIN sys.dm_tran_locks held ON held.request_session_id=h.SessionId
            AND held.request_status='GRANT' AND held.resource_type='KEY'
            AND held.resource_associated_entity_id=waiting.resource_associated_entity_id
            AND held.resource_description=waiting.resource_description
        WHERE w.RaceId=@RaceId;
        IF @Waiter IS NOT NULL
        BEGIN
            INSERT ac09.RaceLockObservation
                (RaceId,HolderSessionId,WaiterSessionId,WaitType,HolderMode,WaiterMode,ResourceDescription)
            VALUES(@RaceId,@Holder,@Waiter,@WaitType,@HolderMode,@WaiterMode,@Resource);
            SELECT 'LOCK_CONTENTION_OBSERVED';
            RETURN;
        END;
        WAITFOR DELAY '00:00:00.100';
    END;
    THROW 53315, 'RACE_POOL_LOCK_CONTENTION_NOT_OBSERVED', 1;
END;
GO
CREATE PROCEDURE ac09.AssertRace
    @RaceId varchar(40),
    @ExpectedError int,
    @ExpectedStockRemaining decimal(19,6),
    @ExpectedQuotaRemaining decimal(19,6),
    @ExpectedGrantRemaining decimal(28,6)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @PoolId varchar(40);
    SELECT @PoolId=PoolId FROM ac09.RaceGate WHERE RaceId=@RaceId AND TenantId='T09';
    IF @PoolId IS NULL THROW 53310, 'RACE_GATE_MISSING', 1;
    IF (SELECT COUNT(*) FROM ac09.RaceAttempt WHERE RaceId=@RaceId)<>2
       OR (SELECT COUNT(DISTINCT SessionId) FROM ac09.RaceAttempt WHERE RaceId=@RaceId)<>2
       OR EXISTS(SELECT 1 FROM ac09.RaceAttempt WHERE RaceId=@RaceId
                 AND (Outcome IS NULL OR FinishedUtc IS NULL))
        THROW 53311, 'RACE_NOT_TWO_COMPLETED_SESSIONS', 1;
    IF (SELECT MAX(StartedUtc) FROM ac09.RaceAttempt WHERE RaceId=@RaceId)
       >=(SELECT MIN(FinishedUtc) FROM ac09.RaceAttempt WHERE RaceId=@RaceId)
        THROW 53312, 'RACE_NO_REAL_OVERLAP', 1;
    IF NOT EXISTS(
        SELECT 1 FROM ac09.RaceLockObservation obs
        JOIN ac09.RaceAttempt h ON h.RaceId=obs.RaceId AND h.SessionId=obs.HolderSessionId
        JOIN ac09.RaceAttempt w ON w.RaceId=obs.RaceId AND w.SessionId=obs.WaiterSessionId
            AND w.AttemptId<>h.AttemptId
        WHERE obs.RaceId=@RaceId AND obs.WaitType LIKE N'LCK_M_%'
          AND LEN(obs.ResourceDescription)>0
          AND obs.ObservedUtc>=h.StartedUtc AND obs.ObservedUtc>=w.StartedUtc
          AND obs.ObservedUtc<h.FinishedUtc AND obs.ObservedUtc<w.FinishedUtc)
        THROW 53316, 'RACE_NO_WITNESSED_POOL_LOCK_WAIT', 1;
    IF (SELECT COUNT(*) FROM ac09.RaceAttempt WHERE RaceId=@RaceId AND Outcome='ACCEPTED')<>1
       OR (SELECT COUNT(*) FROM ac09.RaceAttempt WHERE RaceId=@RaceId
            AND Outcome='REJECTED' AND ErrorNumber=@ExpectedError)<>1
       OR (SELECT COUNT(*) FROM ac09.Command WHERE TenantId='T09' AND PoolId=@PoolId)<>1
        THROW 53313, 'RACE_BOTH_COMMITTED_OR_UNEXPECTED_REJECTION', 1;
    EXEC ac09.AssertPool @PoolId;
    IF NOT EXISTS(SELECT 1 FROM ac09.PoolBalances
        WHERE TenantId='T09' AND PoolId=@PoolId AND CommandCount=1
          AND StockRemaining=@ExpectedStockRemaining
          AND QuotaRemaining=@ExpectedQuotaRemaining
          AND GrantRemaining=@ExpectedGrantRemaining)
        THROW 53314, 'RACE_PERSISTED_BALANCES_MISMATCH', 1;
END;
GO
