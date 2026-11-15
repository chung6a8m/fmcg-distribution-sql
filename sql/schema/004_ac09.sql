-- SQL-03A / AC-09: isolated B credit executable slice (SQL Server 2017+).
-- Prototype fixture only; all writes require the guarded SQL-02 scratch harness.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE N'fmcg_sql02[_]%'
    OR OBJECT_ID(N'dbo.__Ac03ScratchMarker', N'U') IS NULL
    THROW 53100, 'AC09_REQUIRES_GUARDED_SQL02_SCRATCH', 1;
IF SCHEMA_ID(N'ac09') IS NOT NULL THROW 53101, 'AC09_ALREADY_INSTALLED', 1;
GO
CREATE SCHEMA ac09;
GO
-- One tenant+trip+SKU+customer scope per independent test. Opening is a
-- synthetic authority grant, NOT a production balance or financial policy.
CREATE TABLE ac09.Pool (
    TenantId varchar(32) NOT NULL,
    PoolId varchar(40) NOT NULL,
    TripId varchar(40) NOT NULL,
    SkuId varchar(40) NOT NULL,
    CustomerId varchar(40) NOT NULL,
    OpeningStockQty decimal(19,6) NOT NULL CHECK (OpeningStockQty >= 0),
    OpeningQuotaQty decimal(19,6) NOT NULL CHECK (OpeningQuotaQty >= 0),
    OpeningGrant decimal(28,6) NOT NULL CHECK (OpeningGrant >= 0),
    OpeningCustomerCredit decimal(28,6) NOT NULL CHECK (OpeningCustomerCredit >= 0),
    UnitCostSnapshot decimal(28,6) NOT NULL CHECK (UnitCostSnapshot >= 0),
    CONSTRAINT PK_Ac09Pool PRIMARY KEY (TenantId,PoolId),
    CONSTRAINT CK_Ac09Opening CHECK (OpeningQuotaQty <= OpeningStockQty)
);
CREATE TABLE ac09.Command (
    TenantId varchar(32) NOT NULL,
    PoolId varchar(40) NOT NULL,
    ProducerId varchar(40) NOT NULL,
    CommandId varchar(40) NOT NULL,
    PayloadHash char(64) NOT NULL,
    Outcome varchar(10) NOT NULL DEFAULT 'ACCEPTED' CHECK (Outcome='ACCEPTED'),
    RecordedUtc datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Ac09Command PRIMARY KEY (TenantId,PoolId,ProducerId,CommandId),
    CONSTRAINT UQ_Ac09Source UNIQUE (TenantId,PoolId,CommandId),
    CONSTRAINT FK_Ac09CommandPool FOREIGN KEY (TenantId,PoolId)
        REFERENCES ac09.Pool(TenantId,PoolId)
);
CREATE TABLE ac09.Sale (
    TenantId varchar(32) NOT NULL,
    PoolId varchar(40) NOT NULL,
    CommandId varchar(40) NOT NULL,
    CustomerId varchar(40) NOT NULL,
    Qty decimal(19,6) NOT NULL CHECK (Qty > 0),
    UnitPriceSnapshot decimal(28,6) NOT NULL CHECK (UnitPriceSnapshot > 0),
    Payable decimal(28,6) NOT NULL CHECK (Payable > 0),
    CashApplied decimal(28,6) NOT NULL CHECK (CashApplied >= 0),
    ReservedCreditApplied decimal(28,6) NOT NULL CHECK (ReservedCreditApplied >= 0),
    ActualCashReceived decimal(28,6) NOT NULL CHECK (ActualCashReceived >= 0),
    PendingBankEvidence decimal(28,6) NOT NULL CHECK (PendingBankEvidence >= 0),
    Exposure decimal(28,6) NOT NULL CHECK (Exposure >= 0),
    NewCustomerCredit decimal(28,6) NOT NULL CHECK (NewCustomerCredit >= 0),
    CONSTRAINT PK_Ac09Sale PRIMARY KEY (TenantId,PoolId,CommandId),
    CONSTRAINT FK_Ac09SaleCommand FOREIGN KEY (TenantId,PoolId,CommandId)
        REFERENCES ac09.Command(TenantId,PoolId,CommandId),
    CONSTRAINT CK_Ac09SaleMath CHECK (
        CashApplied+ReservedCreditApplied+Exposure=Payable
        AND ActualCashReceived=CashApplied+NewCustomerCredit)
);
CREATE TABLE ac09.StockIssue (
    TenantId varchar(32) NOT NULL, PoolId varchar(40) NOT NULL, CommandId varchar(40) NOT NULL,
    Qty decimal(19,6) NOT NULL CHECK (Qty > 0),
    CostValue decimal(28,6) NOT NULL CHECK (CostValue >= 0),
    CONSTRAINT PK_Ac09StockIssue PRIMARY KEY (TenantId,PoolId,CommandId),
    CONSTRAINT FK_Ac09StockIssueSale FOREIGN KEY (TenantId,PoolId,CommandId)
        REFERENCES ac09.Sale(TenantId,PoolId,CommandId)
);
CREATE TABLE ac09.QuotaUse (
    TenantId varchar(32) NOT NULL, PoolId varchar(40) NOT NULL, CommandId varchar(40) NOT NULL,
    Qty decimal(19,6) NOT NULL CHECK (Qty > 0),
    CONSTRAINT PK_Ac09QuotaUse PRIMARY KEY (TenantId,PoolId,CommandId),
    CONSTRAINT FK_Ac09QuotaUseSale FOREIGN KEY (TenantId,PoolId,CommandId)
        REFERENCES ac09.Sale(TenantId,PoolId,CommandId)
);
CREATE TABLE ac09.CogsEffect (
    TenantId varchar(32) NOT NULL, PoolId varchar(40) NOT NULL, CommandId varchar(40) NOT NULL,
    CostValue decimal(28,6) NOT NULL CHECK (CostValue >= 0),
    CONSTRAINT PK_Ac09Cogs PRIMARY KEY (TenantId,PoolId,CommandId),
    CONSTRAINT FK_Ac09CogsSale FOREIGN KEY (TenantId,PoolId,CommandId)
        REFERENCES ac09.Sale(TenantId,PoolId,CommandId)
);
CREATE TABLE ac09.ArOpenItem (
    TenantId varchar(32) NOT NULL, PoolId varchar(40) NOT NULL, CommandId varchar(40) NOT NULL,
    CustomerId varchar(40) NOT NULL,
    GrossDue decimal(28,6) NOT NULL CHECK (GrossDue > 0),
    CONSTRAINT PK_Ac09Ar PRIMARY KEY (TenantId,PoolId,CommandId),
    CONSTRAINT FK_Ac09ArSale FOREIGN KEY (TenantId,PoolId,CommandId)
        REFERENCES ac09.Sale(TenantId,PoolId,CommandId)
);
CREATE TABLE ac09.GrantUse (
    TenantId varchar(32) NOT NULL, PoolId varchar(40) NOT NULL, CommandId varchar(40) NOT NULL,
    Amount decimal(28,6) NOT NULL CHECK (Amount > 0),
    CONSTRAINT PK_Ac09GrantUse PRIMARY KEY (TenantId,PoolId,CommandId),
    CONSTRAINT FK_Ac09GrantUseSale FOREIGN KEY (TenantId,PoolId,CommandId)
        REFERENCES ac09.Sale(TenantId,PoolId,CommandId)
);
CREATE TABLE ac09.Receipt (
    TenantId varchar(32) NOT NULL, PoolId varchar(40) NOT NULL, CommandId varchar(40) NOT NULL,
    ReceiptKind varchar(12) NOT NULL CHECK (ReceiptKind IN ('CASH','BANK')),
    CustomerId varchar(40) NOT NULL,
    Amount decimal(28,6) NOT NULL CHECK (Amount > 0),
    State varchar(12) NOT NULL CHECK (State IN ('CONFIRMED','PENDING')),
    CONSTRAINT PK_Ac09Receipt PRIMARY KEY (TenantId,PoolId,CommandId,ReceiptKind),
    CONSTRAINT FK_Ac09ReceiptSale FOREIGN KEY (TenantId,PoolId,CommandId)
        REFERENCES ac09.Sale(TenantId,PoolId,CommandId),
    CONSTRAINT CK_Ac09ReceiptState CHECK (
        (ReceiptKind='CASH' AND State='CONFIRMED') OR
        (ReceiptKind='BANK' AND State='PENDING'))
);
CREATE TABLE ac09.ReceiptAllocation (
    TenantId varchar(32) NOT NULL, PoolId varchar(40) NOT NULL, CommandId varchar(40) NOT NULL,
    ReceiptKind varchar(12) NOT NULL DEFAULT 'CASH' CHECK (ReceiptKind='CASH'),
    CustomerId varchar(40) NOT NULL,
    Amount decimal(28,6) NOT NULL CHECK (Amount > 0),
    CONSTRAINT PK_Ac09Allocation PRIMARY KEY (TenantId,PoolId,CommandId),
    CONSTRAINT FK_Ac09AllocationReceipt FOREIGN KEY (TenantId,PoolId,CommandId,ReceiptKind)
        REFERENCES ac09.Receipt(TenantId,PoolId,CommandId,ReceiptKind),
    CONSTRAINT FK_Ac09AllocationAr FOREIGN KEY (TenantId,PoolId,CommandId)
        REFERENCES ac09.ArOpenItem(TenantId,PoolId,CommandId)
);
-- Fixture-local credit funding has a durable opening source. Reservations
-- are assigned to one command BEFORE the sale and cannot be borrowed by
-- another command merely because the customer has an unspent balance.
-- NEW credit from overpayment is recorded in CreditEffect; reserving such
-- newly minted credit is deliberately deferred to SQL-03B.
CREATE TABLE ac09.CreditSource (
    TenantId varchar(32) NOT NULL,
    PoolId varchar(40) NOT NULL,
    SourceId varchar(40) NOT NULL,
    CustomerId varchar(40) NOT NULL,
    SourceKind varchar(12) NOT NULL CHECK (SourceKind='OPENING'),
    Amount decimal(28,6) NOT NULL CHECK (Amount > 0),
    CONSTRAINT PK_Ac09CreditSource PRIMARY KEY (TenantId,PoolId,SourceId),
    CONSTRAINT UQ_Ac09CreditSourceCustomer UNIQUE (TenantId,PoolId,SourceId,CustomerId),
    CONSTRAINT FK_Ac09CreditSourcePool FOREIGN KEY (TenantId,PoolId)
        REFERENCES ac09.Pool(TenantId,PoolId)
);
CREATE TABLE ac09.CreditReservation (
    TenantId varchar(32) NOT NULL,
    PoolId varchar(40) NOT NULL,
    CommandId varchar(40) NOT NULL,
    SourceId varchar(40) NOT NULL,
    CustomerId varchar(40) NOT NULL,
    Amount decimal(28,6) NOT NULL CHECK (Amount > 0),
    CONSTRAINT PK_Ac09CreditReservation PRIMARY KEY (TenantId,PoolId,CommandId),
    CONSTRAINT UQ_Ac09CreditReservationCustomer UNIQUE (TenantId,PoolId,CommandId,CustomerId),
    CONSTRAINT FK_Ac09CreditReservationSource FOREIGN KEY (TenantId,PoolId,SourceId,CustomerId)
        REFERENCES ac09.CreditSource(TenantId,PoolId,SourceId,CustomerId)
);
CREATE TABLE ac09.CreditApplication (
    TenantId varchar(32) NOT NULL, PoolId varchar(40) NOT NULL, CommandId varchar(40) NOT NULL,
    CustomerId varchar(40) NOT NULL,
    Amount decimal(28,6) NOT NULL CHECK (Amount > 0),
    CONSTRAINT PK_Ac09CreditApplication PRIMARY KEY (TenantId,PoolId,CommandId),
    CONSTRAINT FK_Ac09CreditApplicationAr FOREIGN KEY (TenantId,PoolId,CommandId)
        REFERENCES ac09.ArOpenItem(TenantId,PoolId,CommandId),
    CONSTRAINT FK_Ac09CreditApplicationReservation FOREIGN KEY (TenantId,PoolId,CommandId,CustomerId)
        REFERENCES ac09.CreditReservation(TenantId,PoolId,CommandId,CustomerId)
);
CREATE TABLE ac09.CreditEffect (
    TenantId varchar(32) NOT NULL, PoolId varchar(40) NOT NULL, CommandId varchar(40) NOT NULL,
    EffectKind varchar(8) NOT NULL CHECK (EffectKind IN ('APPLY','NEW')),
    CustomerId varchar(40) NOT NULL,
    DeltaAmount decimal(28,6) NOT NULL CHECK (DeltaAmount <> 0),
    CONSTRAINT PK_Ac09CreditEffect PRIMARY KEY (TenantId,PoolId,CommandId,EffectKind),
    CONSTRAINT FK_Ac09CreditEffectSale FOREIGN KEY (TenantId,PoolId,CommandId)
        REFERENCES ac09.Sale(TenantId,PoolId,CommandId),
    CONSTRAINT CK_Ac09CreditSign CHECK (
        (EffectKind='APPLY' AND DeltaAmount<0) OR
        (EffectKind='NEW' AND DeltaAmount>0))
);
CREATE TABLE ac09.CustodyEffect (
    TenantId varchar(32) NOT NULL, PoolId varchar(40) NOT NULL, CommandId varchar(40) NOT NULL,
    Amount decimal(28,6) NOT NULL CHECK (Amount > 0),
    CONSTRAINT PK_Ac09Custody PRIMARY KEY (TenantId,PoolId,CommandId),
    CONSTRAINT FK_Ac09CustodySale FOREIGN KEY (TenantId,PoolId,CommandId)
        REFERENCES ac09.Sale(TenantId,PoolId,CommandId)
);
CREATE TABLE ac09.RaceGate (
    RaceId varchar(40) NOT NULL PRIMARY KEY,
    TenantId varchar(32) NOT NULL,
    PoolId varchar(40) NOT NULL,
    Qty decimal(19,6) NOT NULL,
    UnitPrice decimal(28,6) NOT NULL,
    CashApplied decimal(28,6) NOT NULL,
    CONSTRAINT FK_Ac09RacePool FOREIGN KEY (TenantId,PoolId)
        REFERENCES ac09.Pool(TenantId,PoolId)
);
CREATE TABLE ac09.RaceAttempt (
    RaceId varchar(40) NOT NULL,
    AttemptId char(1) NOT NULL CHECK (AttemptId IN ('A','B')),
    SessionId smallint NOT NULL,
    StartedUtc datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    FinishedUtc datetime2(3) NULL,
    Outcome varchar(12) NULL CHECK (Outcome IN ('ACCEPTED','REJECTED')),
    ErrorNumber int NULL,
    CONSTRAINT PK_Ac09RaceAttempt PRIMARY KEY (RaceId,AttemptId),
    CONSTRAINT FK_Ac09RaceAttemptGate FOREIGN KEY (RaceId) REFERENCES ac09.RaceGate(RaceId)
);
-- A third, independent SQL connection records a real KEY lock wait on Pool.
-- StartedUtc overlap alone is insufficient: it can also pass serial execution.
CREATE TABLE ac09.RaceLockObservation (
    RaceId varchar(40) NOT NULL PRIMARY KEY,
    HolderSessionId smallint NOT NULL,
    WaiterSessionId smallint NOT NULL,
    WaitType nvarchar(64) NOT NULL,
    HolderMode varchar(12) NOT NULL,
    WaiterMode varchar(12) NOT NULL,
    ResourceDescription nvarchar(256) NOT NULL,
    ObservedUtc datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_Ac09RaceLockGate FOREIGN KEY (RaceId)
        REFERENCES ac09.RaceGate(RaceId)
);
GO
CREATE VIEW ac09.PoolBalances AS
SELECT p.TenantId,p.PoolId,
    CAST(p.OpeningStockQty-ISNULL((SELECT SUM(Qty) FROM ac09.StockIssue x
        WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId),0) AS decimal(19,6)) AS StockRemaining,
    CAST(p.OpeningQuotaQty-ISNULL((SELECT SUM(Qty) FROM ac09.QuotaUse x
        WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId),0) AS decimal(19,6)) AS QuotaRemaining,
    CAST(p.OpeningGrant-ISNULL((SELECT SUM(Amount) FROM ac09.GrantUse x
        WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId),0) AS decimal(28,6)) AS GrantRemaining,
    CAST(ISNULL((SELECT SUM(GrossDue) FROM ac09.ArOpenItem x
        WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId),0)
      -ISNULL((SELECT SUM(Amount) FROM ac09.ReceiptAllocation x
        WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId),0)
      -ISNULL((SELECT SUM(Amount) FROM ac09.CreditApplication x
        WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId),0) AS decimal(28,6)) AS ArRemaining,
    CAST(ISNULL((SELECT SUM(Amount) FROM ac09.CustodyEffect x
        WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId),0) AS decimal(28,6)) AS CustodyCash,
    CAST(p.OpeningCustomerCredit+ISNULL((SELECT SUM(DeltaAmount) FROM ac09.CreditEffect x
        WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId),0) AS decimal(28,6)) AS CreditRemaining,
    CAST(ISNULL((SELECT SUM(DeltaAmount) FROM ac09.CreditEffect x
        WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId AND x.EffectKind='NEW'),0)
        AS decimal(28,6)) AS NewCustomerCredit,
    CAST(ISNULL((SELECT SUM(CostValue) FROM ac09.CogsEffect x
        WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId),0) AS decimal(28,6)) AS Cogs,
    CAST(ISNULL((SELECT SUM(Amount) FROM ac09.ReceiptAllocation x
        WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId),0) AS decimal(28,6)) AS AppliedCash,
    CAST(ISNULL((SELECT SUM(Amount) FROM ac09.CreditApplication x
        WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId),0) AS decimal(28,6)) AS AppliedCredit,
    CAST(ISNULL((SELECT SUM(Amount) FROM ac09.Receipt x
        WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId AND x.State='CONFIRMED'),0)
        AS decimal(28,6)) AS ConfirmedCash,
    CAST(ISNULL((SELECT SUM(Amount) FROM ac09.Receipt x
        WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId AND x.State='PENDING'),0)
        AS decimal(28,6)) AS PendingBank,
    (SELECT COUNT(*) FROM ac09.Command x WHERE x.TenantId=p.TenantId AND x.PoolId=p.PoolId)
        AS CommandCount
FROM ac09.Pool p;
GO
CREATE PROCEDURE ac09.AssertPool @PoolId varchar(40)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS(SELECT 1 FROM ac09.Pool WHERE TenantId='T09' AND PoolId=@PoolId)
        THROW 53110, 'POOL_MISSING', 1;
    IF EXISTS(SELECT 1 FROM ac09.PoolBalances
              WHERE TenantId='T09' AND PoolId=@PoolId
                AND (StockRemaining<0 OR QuotaRemaining<0 OR GrantRemaining<0
                     OR ArRemaining<0 OR CreditRemaining<0))
        THROW 53111, 'POOL_BALANCE_NEGATIVE', 1;
    -- Synthetic opening CustomerCredit must have matching same-customer
    -- sources. Reserving from a source must never overbook its amount.
    IF EXISTS(
        SELECT 1 FROM ac09.Pool p
        WHERE p.TenantId='T09' AND p.PoolId=@PoolId
          AND (p.OpeningCustomerCredit<>ISNULL((
                 SELECT SUM(cs.Amount) FROM ac09.CreditSource cs
                 WHERE cs.TenantId=p.TenantId AND cs.PoolId=p.PoolId),0)
               OR EXISTS(SELECT 1 FROM ac09.CreditSource cs
                  WHERE cs.TenantId=p.TenantId AND cs.PoolId=p.PoolId
                    AND cs.CustomerId<>p.CustomerId)))
        THROW 53115, 'CREDIT_OPENING_SOURCE_MISMATCH', 1;
    IF EXISTS(
        SELECT 1 FROM ac09.CreditSource cs
        WHERE cs.TenantId='T09' AND cs.PoolId=@PoolId
          AND cs.Amount<ISNULL((
              SELECT SUM(r.Amount) FROM ac09.CreditReservation r
              WHERE r.TenantId=cs.TenantId AND r.PoolId=cs.PoolId
                AND r.SourceId=cs.SourceId),0))
        THROW 53116, 'CREDIT_SOURCE_OVER_RESERVED', 1;
    -- Every sale has exact per-source stock, quota, COGS, AR, receipt,
    -- allocation, grant and CustomerCredit/custody effect provenance.
    IF EXISTS(
        SELECT 1 FROM ac09.Sale s
        JOIN ac09.Pool p ON p.TenantId=s.TenantId AND p.PoolId=s.PoolId
        LEFT JOIN ac09.StockIssue i ON i.TenantId=s.TenantId AND i.PoolId=s.PoolId AND i.CommandId=s.CommandId
        LEFT JOIN ac09.QuotaUse q ON q.TenantId=s.TenantId AND q.PoolId=s.PoolId AND q.CommandId=s.CommandId
        LEFT JOIN ac09.CogsEffect c ON c.TenantId=s.TenantId AND c.PoolId=s.PoolId AND c.CommandId=s.CommandId
        LEFT JOIN ac09.ArOpenItem ar ON ar.TenantId=s.TenantId AND ar.PoolId=s.PoolId AND ar.CommandId=s.CommandId
        LEFT JOIN ac09.GrantUse g ON g.TenantId=s.TenantId AND g.PoolId=s.PoolId AND g.CommandId=s.CommandId
        LEFT JOIN ac09.ReceiptAllocation a ON a.TenantId=s.TenantId AND a.PoolId=s.PoolId AND a.CommandId=s.CommandId
        LEFT JOIN ac09.CreditApplication ca ON ca.TenantId=s.TenantId AND ca.PoolId=s.PoolId AND ca.CommandId=s.CommandId
        LEFT JOIN ac09.CreditReservation cr ON cr.TenantId=s.TenantId AND cr.PoolId=s.PoolId AND cr.CommandId=s.CommandId
        LEFT JOIN ac09.CustodyEffect cu ON cu.TenantId=s.TenantId AND cu.PoolId=s.PoolId AND cu.CommandId=s.CommandId
        WHERE s.TenantId='T09' AND s.PoolId=@PoolId AND
          (s.CustomerId<>p.CustomerId OR i.Qty IS NULL OR i.Qty<>s.Qty
           OR i.CostValue<>CONVERT(decimal(28,6),s.Qty*p.UnitCostSnapshot)
           OR q.Qty IS NULL OR q.Qty<>s.Qty OR c.CostValue IS NULL OR c.CostValue<>i.CostValue
           OR ar.GrossDue IS NULL OR ar.GrossDue<>s.Payable OR ar.CustomerId<>s.CustomerId
           OR (s.Exposure>0 AND (g.Amount IS NULL OR g.Amount<>s.Exposure))
           OR (s.Exposure=0 AND g.Amount IS NOT NULL)
           OR (s.CashApplied>0 AND (a.Amount IS NULL OR a.Amount<>s.CashApplied OR a.CustomerId<>s.CustomerId))
           OR (s.CashApplied=0 AND a.Amount IS NOT NULL)
           OR (s.ReservedCreditApplied>0 AND (ca.Amount IS NULL OR ca.Amount<>s.ReservedCreditApplied OR ca.CustomerId<>s.CustomerId))
           OR (s.ReservedCreditApplied=0 AND ca.Amount IS NOT NULL)
           OR (s.ReservedCreditApplied>0 AND
                (cr.Amount IS NULL OR cr.Amount<>s.ReservedCreditApplied OR cr.CustomerId<>s.CustomerId))
           OR (s.ReservedCreditApplied=0 AND cr.CommandId IS NOT NULL)
           OR (s.ActualCashReceived>0 AND (cu.Amount IS NULL OR cu.Amount<>s.ActualCashReceived))
           OR (s.ActualCashReceived=0 AND cu.Amount IS NOT NULL)
           OR ISNULL((SELECT SUM(r.Amount) FROM ac09.Receipt r
               WHERE r.TenantId=s.TenantId AND r.PoolId=s.PoolId AND r.CommandId=s.CommandId
                 AND r.State='CONFIRMED' AND r.CustomerId=s.CustomerId),0)<>s.ActualCashReceived
           OR ISNULL((SELECT SUM(r.Amount) FROM ac09.Receipt r
               WHERE r.TenantId=s.TenantId AND r.PoolId=s.PoolId AND r.CommandId=s.CommandId
                 AND r.State='PENDING' AND r.CustomerId=s.CustomerId),0)<>s.PendingBankEvidence
           OR ISNULL((SELECT SUM(e.DeltaAmount) FROM ac09.CreditEffect e
               WHERE e.TenantId=s.TenantId AND e.PoolId=s.PoolId AND e.CommandId=s.CommandId
                 AND e.EffectKind='APPLY' AND e.CustomerId=s.CustomerId),0)<>-s.ReservedCreditApplied
           OR ISNULL((SELECT SUM(e.DeltaAmount) FROM ac09.CreditEffect e
               WHERE e.TenantId=s.TenantId AND e.PoolId=s.PoolId AND e.CommandId=s.CommandId
                 AND e.EffectKind='NEW' AND e.CustomerId=s.CustomerId),0)<>s.NewCustomerCredit)
    ) THROW 53112, 'SOURCE_EFFECT_PROVENANCE_MISMATCH', 1;
    IF EXISTS (SELECT 1 FROM ac09.Command e
               LEFT JOIN ac09.Sale s ON s.TenantId=e.TenantId AND s.PoolId=e.PoolId AND s.CommandId=e.CommandId
               WHERE e.TenantId='T09' AND e.PoolId=@PoolId AND s.CommandId IS NULL)
        THROW 53113, 'COMMAND_WITHOUT_SALE', 1;
    IF EXISTS (SELECT 1 FROM ac09.ReceiptAllocation a JOIN ac09.Receipt r
                 ON r.TenantId=a.TenantId AND r.PoolId=a.PoolId AND r.CommandId=a.CommandId
                    AND r.ReceiptKind=a.ReceiptKind
               WHERE a.TenantId='T09' AND a.PoolId=@PoolId
                 AND (r.State<>'CONFIRMED' OR r.CustomerId<>a.CustomerId OR a.Amount>r.Amount))
        THROW 53114, 'UNVERIFIED_OR_CROSS_CUSTOMER_RECEIPT', 1;
END;
GO
