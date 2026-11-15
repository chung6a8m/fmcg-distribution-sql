-- SQL-03B / AC-21 and AC-20. Isolated executable specification, not production DDL.
-- Requires the SQL-02 owned scratch database; Business Baseline is immutable.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE N'fmcg_sql02[_]%'
   OR OBJECT_ID(N'dbo.__Ac03ScratchMarker',N'U') IS NULL
    THROW 53500, 'AC21_REQUIRES_GUARDED_SCRATCH', 1;
IF SCHEMA_ID(N'ac21') IS NOT NULL THROW 53501, 'AC21_ALREADY_INSTALLED', 1;
GO
CREATE SCHEMA ac21;
GO
-- Stable serialization boundary. No balance column: every balance is derived.
CREATE TABLE ac21.Scope (
    TenantId varchar(32) NOT NULL,
    ScopeId varchar(40) NOT NULL,
    CustomerId varchar(40) NOT NULL,
    CollectorId varchar(40) NOT NULL,
    CONSTRAINT PK_Ac21Scope PRIMARY KEY (TenantId,ScopeId),
    CONSTRAINT UQ_Ac21ScopeCustomer UNIQUE (TenantId,ScopeId,CustomerId)
);
CREATE TABLE ac21.Command (
    TenantId varchar(32) NOT NULL, ScopeId varchar(40) NOT NULL,
    CommandId varchar(40) NOT NULL,
    Kind varchar(20) NOT NULL CHECK (Kind IN
      ('RECEIPT','ALLOCATE','HANDOVER_OFFER','HANDOVER_ACCEPT',
       'ADV_ISSUE','ADV_EXPENSE','ADV_OFFER','ADV_ACCEPT')),
    PayloadHash char(64) NOT NULL,
    AcceptedUtc datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Ac21Command PRIMARY KEY (TenantId,ScopeId,CommandId),
    -- A command/source identity must not be reused in another scope of the same tenant.
    CONSTRAINT UQ_Ac21CommandTenantIdentity UNIQUE (TenantId,CommandId),
    CONSTRAINT FK_Ac21CommandScope FOREIGN KEY (TenantId,ScopeId)
      REFERENCES ac21.Scope(TenantId,ScopeId)
);
-- Synthetic opening AR has an explicit item/source, never an unexplained balance.
CREATE TABLE ac21.ArOpenItem (
    TenantId varchar(32) NOT NULL, ScopeId varchar(40) NOT NULL,
    ItemId varchar(40) NOT NULL, CustomerId varchar(40) NOT NULL,
    OpeningAmount decimal(28,6) NOT NULL CHECK (OpeningAmount>0),
    CONSTRAINT PK_Ac21ArItem PRIMARY KEY (TenantId,ScopeId,ItemId),
    CONSTRAINT UQ_Ac21ArItemCustomer UNIQUE (TenantId,ScopeId,ItemId,CustomerId),
    CONSTRAINT FK_Ac21ArCustomer FOREIGN KEY (TenantId,ScopeId,CustomerId)
      REFERENCES ac21.Scope(TenantId,ScopeId,CustomerId)
);
CREATE TABLE ac21.Receipt (
    TenantId varchar(32) NOT NULL, ScopeId varchar(40) NOT NULL,
    ReceiptId varchar(40) NOT NULL, CustomerId varchar(40) NOT NULL,
    Channel varchar(8) NOT NULL CHECK (Channel IN ('CASH','BANK')),
    ReceiptState varchar(12) NOT NULL CHECK (ReceiptState IN ('CONFIRMED','PENDING')),
    Amount decimal(28,6) NOT NULL CHECK (Amount>0),
    CONSTRAINT PK_Ac21Receipt PRIMARY KEY (TenantId,ScopeId,ReceiptId),
    CONSTRAINT UQ_Ac21ReceiptConfirmedKey UNIQUE
      (TenantId,ScopeId,ReceiptId,CustomerId,ReceiptState),
    CONSTRAINT FK_Ac21ReceiptCommand FOREIGN KEY (TenantId,ScopeId,ReceiptId)
      REFERENCES ac21.Command(TenantId,ScopeId,CommandId),
    CONSTRAINT FK_Ac21ReceiptCustomer FOREIGN KEY (TenantId,ScopeId,CustomerId)
      REFERENCES ac21.Scope(TenantId,ScopeId,CustomerId)
);
-- Explicit source-to-item allocation. The fixed CONFIRMED discriminator in
-- the FK means a PENDING receipt can NEVER fund an allocation, even by SQL DML.
CREATE TABLE ac21.ArAllocation (
    TenantId varchar(32) NOT NULL, ScopeId varchar(40) NOT NULL,
    AllocationId varchar(40) NOT NULL,
    ReceiptId varchar(40) NOT NULL, ItemId varchar(40) NOT NULL,
    CustomerId varchar(40) NOT NULL,
    RequiredReceiptState varchar(12) NOT NULL
      DEFAULT 'CONFIRMED' CHECK (RequiredReceiptState='CONFIRMED'),
    Amount decimal(28,6) NOT NULL CHECK (Amount>0),
    CONSTRAINT PK_Ac21Allocation PRIMARY KEY (TenantId,ScopeId,AllocationId),
    CONSTRAINT FK_Ac21AllocCommand FOREIGN KEY (TenantId,ScopeId,AllocationId)
      REFERENCES ac21.Command(TenantId,ScopeId,CommandId),
    CONSTRAINT FK_Ac21AllocConfirmedReceipt FOREIGN KEY
      (TenantId,ScopeId,ReceiptId,CustomerId,RequiredReceiptState)
      REFERENCES ac21.Receipt(TenantId,ScopeId,ReceiptId,CustomerId,ReceiptState),
    CONSTRAINT FK_Ac21AllocItem FOREIGN KEY (TenantId,ScopeId,ItemId,CustomerId)
      REFERENCES ac21.ArOpenItem(TenantId,ScopeId,ItemId,CustomerId)
);
CREATE TABLE ac21.HandoverOffer (
    TenantId varchar(32) NOT NULL, ScopeId varchar(40) NOT NULL,
    OfferId varchar(40) NOT NULL,
    Amount decimal(28,6) NOT NULL CHECK (Amount>0),
    CONSTRAINT PK_Ac21HandoverOffer PRIMARY KEY (TenantId,ScopeId,OfferId),
    CONSTRAINT FK_Ac21OfferCommand FOREIGN KEY (TenantId,ScopeId,OfferId)
      REFERENCES ac21.Command(TenantId,ScopeId,CommandId)
);
CREATE TABLE ac21.HandoverAccept (
    TenantId varchar(32) NOT NULL, ScopeId varchar(40) NOT NULL,
    AcceptId varchar(40) NOT NULL, OfferId varchar(40) NOT NULL,
    AcceptedAmount decimal(28,6) NOT NULL CHECK (AcceptedAmount>0),
    CONSTRAINT PK_Ac21HandoverAccept PRIMARY KEY (TenantId,ScopeId,AcceptId),
    CONSTRAINT FK_Ac21AcceptCommand FOREIGN KEY (TenantId,ScopeId,AcceptId)
      REFERENCES ac21.Command(TenantId,ScopeId,CommandId),
    CONSTRAINT FK_Ac21AcceptOffer FOREIGN KEY (TenantId,ScopeId,OfferId)
      REFERENCES ac21.HandoverOffer(TenantId,ScopeId,OfferId)
);
-- Cash custody and cashier fund are separate posting ledgers. OFFER has none.
CREATE TABLE ac21.CustodyPosting (
    TenantId varchar(32) NOT NULL, ScopeId varchar(40) NOT NULL,
    SourceId varchar(40) NOT NULL,
    SourceKind varchar(10) NOT NULL CHECK (SourceKind IN ('RECEIPT','HANDOVER')),
    DeltaAmount decimal(28,6) NOT NULL CHECK (DeltaAmount<>0),
    CONSTRAINT PK_Ac21CustodyPosting PRIMARY KEY (TenantId,ScopeId,SourceId),
    CONSTRAINT FK_Ac21CustodyCommand FOREIGN KEY (TenantId,ScopeId,SourceId)
      REFERENCES ac21.Command(TenantId,ScopeId,CommandId),
    CONSTRAINT CK_Ac21CustodySign CHECK (
       (SourceKind='RECEIPT' AND DeltaAmount>0)
       OR (SourceKind='HANDOVER' AND DeltaAmount<0))
);
CREATE TABLE ac21.FundPosting (
    TenantId varchar(32) NOT NULL, ScopeId varchar(40) NOT NULL,
    AcceptId varchar(40) NOT NULL, Amount decimal(28,6) NOT NULL CHECK (Amount>0),
    CONSTRAINT PK_Ac21FundPosting PRIMARY KEY (TenantId,ScopeId,AcceptId),
    CONSTRAINT FK_Ac21FundAccept FOREIGN KEY (TenantId,ScopeId,AcceptId)
      REFERENCES ac21.HandoverAccept(TenantId,ScopeId,AcceptId)
);
-- Employee advance is NOT customer AR, receipt credit or cash custody.
CREATE TABLE ac21.AdvanceAccount (
    TenantId varchar(32) NOT NULL, ScopeId varchar(40) NOT NULL,
    AdvanceId varchar(40) NOT NULL, EmployeeId varchar(40) NOT NULL,
    CONSTRAINT PK_Ac21AdvanceAccount PRIMARY KEY (TenantId,ScopeId,AdvanceId),
    CONSTRAINT FK_Ac21AdvanceScope FOREIGN KEY (TenantId,ScopeId)
      REFERENCES ac21.Scope(TenantId,ScopeId)
);
CREATE TABLE ac21.AdvanceIssue (
    TenantId varchar(32) NOT NULL, ScopeId varchar(40) NOT NULL,
    IssueId varchar(40) NOT NULL, AdvanceId varchar(40) NOT NULL,
    Amount decimal(28,6) NOT NULL CHECK (Amount>0),
    CONSTRAINT PK_Ac21AdvanceIssue PRIMARY KEY (TenantId,ScopeId,IssueId),
    CONSTRAINT FK_Ac21IssueCommand FOREIGN KEY (TenantId,ScopeId,IssueId)
      REFERENCES ac21.Command(TenantId,ScopeId,CommandId),
    CONSTRAINT FK_Ac21IssueAccount FOREIGN KEY (TenantId,ScopeId,AdvanceId)
      REFERENCES ac21.AdvanceAccount(TenantId,ScopeId,AdvanceId)
);
CREATE TABLE ac21.AdvanceExpense (
    TenantId varchar(32) NOT NULL, ScopeId varchar(40) NOT NULL,
    ExpenseId varchar(40) NOT NULL, AdvanceId varchar(40) NOT NULL,
    ApprovedAmount decimal(28,6) NOT NULL CHECK (ApprovedAmount>0),
    CONSTRAINT PK_Ac21AdvanceExpense PRIMARY KEY (TenantId,ScopeId,ExpenseId),
    CONSTRAINT FK_Ac21ExpenseCommand FOREIGN KEY (TenantId,ScopeId,ExpenseId)
      REFERENCES ac21.Command(TenantId,ScopeId,CommandId),
    CONSTRAINT FK_Ac21ExpenseAccount FOREIGN KEY (TenantId,ScopeId,AdvanceId)
      REFERENCES ac21.AdvanceAccount(TenantId,ScopeId,AdvanceId)
);
CREATE TABLE ac21.AdvanceOffer (
    TenantId varchar(32) NOT NULL, ScopeId varchar(40) NOT NULL,
    OfferId varchar(40) NOT NULL, AdvanceId varchar(40) NOT NULL,
    Amount decimal(28,6) NOT NULL CHECK (Amount>0),
    CONSTRAINT PK_Ac21AdvanceOffer PRIMARY KEY (TenantId,ScopeId,OfferId),
    CONSTRAINT UQ_Ac21AdvanceOfferAccount UNIQUE (TenantId,ScopeId,OfferId,AdvanceId),
    CONSTRAINT FK_Ac21AdvanceOfferCommand FOREIGN KEY (TenantId,ScopeId,OfferId)
      REFERENCES ac21.Command(TenantId,ScopeId,CommandId),
    CONSTRAINT FK_Ac21AdvanceOfferAccount FOREIGN KEY (TenantId,ScopeId,AdvanceId)
      REFERENCES ac21.AdvanceAccount(TenantId,ScopeId,AdvanceId)
);
CREATE TABLE ac21.AdvanceAccept (
    TenantId varchar(32) NOT NULL, ScopeId varchar(40) NOT NULL,
    AcceptId varchar(40) NOT NULL, OfferId varchar(40) NOT NULL,
    AdvanceId varchar(40) NOT NULL, AcceptedAmount decimal(28,6) NOT NULL CHECK (AcceptedAmount>0),
    CONSTRAINT PK_Ac21AdvanceAccept PRIMARY KEY (TenantId,ScopeId,AcceptId),
    CONSTRAINT FK_Ac21AdvanceAcceptCommand FOREIGN KEY (TenantId,ScopeId,AcceptId)
      REFERENCES ac21.Command(TenantId,ScopeId,CommandId),
    CONSTRAINT FK_Ac21AdvanceAcceptOffer FOREIGN KEY
      (TenantId,ScopeId,OfferId,AdvanceId)
      REFERENCES ac21.AdvanceOffer(TenantId,ScopeId,OfferId,AdvanceId)
);
CREATE TABLE ac21.CustomerCheckpoint (
    StepOrdinal int NOT NULL PRIMARY KEY, Step varchar(32) NOT NULL UNIQUE,
    Ar decimal(28,6) NOT NULL, Credit decimal(28,6) NOT NULL,
    Custody decimal(28,6) NOT NULL, Fund decimal(28,6) NOT NULL,
    Allocated decimal(28,6) NOT NULL
);
CREATE TABLE ac21.AdvanceCheckpoint (
    StepOrdinal int NOT NULL PRIMARY KEY, Step varchar(32) NOT NULL UNIQUE,
    Issued decimal(28,6) NOT NULL, ApprovedExpenses decimal(28,6) NOT NULL,
    CashierAcceptedReturns decimal(28,6) NOT NULL, Outstanding decimal(28,6) NOT NULL
);
GO
-- Every receipt is a credit source. Available credit cannot be spent twice
-- because allocations serialize through Scope and are bounded per ReceiptId.
CREATE VIEW ac21.ReceiptCredit AS
SELECT r.TenantId,r.ScopeId,r.ReceiptId,r.CustomerId,r.Channel,r.ReceiptState,
       r.Amount,
       CAST(CASE WHEN r.ReceiptState='CONFIRMED'
                 THEN r.Amount-ISNULL(SUM(a.Amount),0) ELSE 0 END
            AS decimal(28,6)) AS AvailableCredit
FROM ac21.Receipt r
LEFT JOIN ac21.ArAllocation a
  ON a.TenantId=r.TenantId AND a.ScopeId=r.ScopeId AND a.ReceiptId=r.ReceiptId
GROUP BY r.TenantId,r.ScopeId,r.ReceiptId,r.CustomerId,r.Channel,r.ReceiptState,r.Amount;
GO
CREATE VIEW ac21.CustomerBalances AS
SELECT s.TenantId,s.ScopeId,
    CAST(ISNULL((SELECT SUM(OpeningAmount) FROM ac21.ArOpenItem x
      WHERE x.TenantId=s.TenantId AND x.ScopeId=s.ScopeId),0)
      -ISNULL((SELECT SUM(Amount) FROM ac21.ArAllocation x
      WHERE x.TenantId=s.TenantId AND x.ScopeId=s.ScopeId),0) AS decimal(28,6)) AS Ar,
    CAST(ISNULL((SELECT SUM(AvailableCredit) FROM ac21.ReceiptCredit x
      WHERE x.TenantId=s.TenantId AND x.ScopeId=s.ScopeId),0) AS decimal(28,6)) AS Credit,
    CAST(ISNULL((SELECT SUM(DeltaAmount) FROM ac21.CustodyPosting x
      WHERE x.TenantId=s.TenantId AND x.ScopeId=s.ScopeId),0) AS decimal(28,6)) AS Custody,
    CAST(ISNULL((SELECT SUM(Amount) FROM ac21.FundPosting x
      WHERE x.TenantId=s.TenantId AND x.ScopeId=s.ScopeId),0) AS decimal(28,6)) AS Fund,
    CAST(ISNULL((SELECT SUM(Amount) FROM ac21.ArAllocation x
      WHERE x.TenantId=s.TenantId AND x.ScopeId=s.ScopeId),0) AS decimal(28,6)) AS Allocated
FROM ac21.Scope s;
GO
CREATE VIEW ac21.AdvanceBalances AS
SELECT a.TenantId,a.ScopeId,a.AdvanceId,
    CAST(ISNULL((SELECT SUM(Amount) FROM ac21.AdvanceIssue x
      WHERE x.TenantId=a.TenantId AND x.ScopeId=a.ScopeId AND x.AdvanceId=a.AdvanceId),0)
      AS decimal(28,6)) AS Issued,
    CAST(ISNULL((SELECT SUM(ApprovedAmount) FROM ac21.AdvanceExpense x
      WHERE x.TenantId=a.TenantId AND x.ScopeId=a.ScopeId AND x.AdvanceId=a.AdvanceId),0)
      AS decimal(28,6)) AS ApprovedExpenses,
    CAST(ISNULL((SELECT SUM(AcceptedAmount) FROM ac21.AdvanceAccept x
      WHERE x.TenantId=a.TenantId AND x.ScopeId=a.ScopeId AND x.AdvanceId=a.AdvanceId),0)
      AS decimal(28,6)) AS CashierAcceptedReturns,
    CAST(ISNULL((SELECT SUM(Amount) FROM ac21.AdvanceIssue x
      WHERE x.TenantId=a.TenantId AND x.ScopeId=a.ScopeId AND x.AdvanceId=a.AdvanceId),0)
      -ISNULL((SELECT SUM(ApprovedAmount) FROM ac21.AdvanceExpense x
      WHERE x.TenantId=a.TenantId AND x.ScopeId=a.ScopeId AND x.AdvanceId=a.AdvanceId),0)
      -ISNULL((SELECT SUM(AcceptedAmount) FROM ac21.AdvanceAccept x
      WHERE x.TenantId=a.TenantId AND x.ScopeId=a.ScopeId AND x.AdvanceId=a.AdvanceId),0)
      AS decimal(28,6)) AS Outstanding
FROM ac21.AdvanceAccount a;
GO
