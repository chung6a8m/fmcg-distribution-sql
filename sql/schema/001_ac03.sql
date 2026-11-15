-- SQL-02 / AC-03: disposable SQL Server 2017+ physical slice.
-- Requires dbo.__Ac03ScratchMarker installed and verified by run-tests.ps1.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
    THROW 51000, 'SQL-02 refuses a system database', 1;
IF DB_NAME() NOT LIKE N'fmcg_sql02[_]%'
    THROW 51001, 'SQL-02 requires a dedicated fmcg_sql02 scratch database', 1;
IF OBJECT_ID(N'dbo.__Ac03ScratchMarker', N'U') IS NULL
    THROW 51002, 'SQL-02 scratch marker missing', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.__Ac03ScratchMarker
               WHERE Harness = 'fmcg-distribution-sql/SQL-02/AC-03'
                 AND DatabaseName = DB_NAME()
                 AND InstanceName = CONVERT(nvarchar(128), SERVERPROPERTY('ServerName')))
    THROW 51003, 'SQL-02 scratch marker/instance mismatch', 1;
IF SCHEMA_ID(N'ac03') IS NOT NULL
    THROW 51004, 'AC-03 schema already exists: use a fresh scratch database', 1;
GO
CREATE SCHEMA ac03;
GO
CREATE TABLE ac03.Tenant (
    TenantId varchar(32) NOT NULL PRIMARY KEY
);
CREATE TABLE ac03.Seller (
    TenantId varchar(32) NOT NULL,
    SellerId varchar(64) NOT NULL,
    CONSTRAINT PK_Seller PRIMARY KEY (TenantId, SellerId),
    CONSTRAINT UQ_Seller_Tenant UNIQUE (TenantId),
    CONSTRAINT FK_Seller_Tenant FOREIGN KEY (TenantId) REFERENCES ac03.Tenant(TenantId)
);
CREATE TABLE ac03.Customer (
    TenantId varchar(32) NOT NULL,
    CustomerId varchar(64) NOT NULL,
    CONSTRAINT PK_Customer PRIMARY KEY (TenantId, CustomerId),
    CONSTRAINT FK_Customer_Tenant FOREIGN KEY (TenantId) REFERENCES ac03.Tenant(TenantId)
);
CREATE TABLE ac03.Sku (
    TenantId varchar(32) NOT NULL,
    SkuId varchar(64) NOT NULL,
    UnitCost decimal(28,10) NOT NULL CHECK (UnitCost >= 0),
    CONSTRAINT PK_Sku PRIMARY KEY (TenantId, SkuId),
    CONSTRAINT FK_Sku_Tenant FOREIGN KEY (TenantId) REFERENCES ac03.Tenant(TenantId)
);
CREATE TABLE ac03.StockLocation (
    TenantId varchar(32) NOT NULL,
    LocationId varchar(64) NOT NULL,
    LocationKind varchar(12) NOT NULL CHECK (LocationKind IN ('MAIN','TRIP')),
    CONSTRAINT PK_Location PRIMARY KEY (TenantId, LocationId),
    CONSTRAINT FK_Location_Tenant FOREIGN KEY (TenantId) REFERENCES ac03.Tenant(TenantId)
);
CREATE TABLE ac03.Trip (
    TenantId varchar(32) NOT NULL,
    TripId varchar(64) NOT NULL,
    CustodyLocationId varchar(64) NOT NULL,
    BusinessDate date NOT NULL,
    CONSTRAINT PK_Trip PRIMARY KEY (TenantId, TripId),
    CONSTRAINT FK_Trip_Location FOREIGN KEY (TenantId, CustodyLocationId)
        REFERENCES ac03.StockLocation(TenantId, LocationId),
    CONSTRAINT UQ_Trip_Custody UNIQUE (TenantId, CustodyLocationId)
);
CREATE TABLE ac03.BusinessEvent (
    TenantId varchar(32) NOT NULL,
    EventId varchar(64) NOT NULL,
    ProducerId varchar(64) NOT NULL,
    CommandId varchar(64) NOT NULL,
    PayloadHash char(64) NOT NULL,
    Outcome varchar(16) NOT NULL CHECK (Outcome IN ('ACCEPTED','REJECTED')),
    Reason varchar(64) NULL,
    RecordedAtUtc datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Event PRIMARY KEY (TenantId, EventId),
    CONSTRAINT UQ_Event_Command UNIQUE (TenantId, ProducerId, CommandId),
    CONSTRAINT FK_Event_Tenant FOREIGN KEY (TenantId) REFERENCES ac03.Tenant(TenantId)
);
CREATE TABLE ac03.SourceLine (
    TenantId varchar(32) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    EventId varchar(64) NOT NULL,
    LineOrdinal int NOT NULL CHECK (LineOrdinal >= 1),
    SourceRole varchar(32) NOT NULL,
    CONSTRAINT PK_SourceLine PRIMARY KEY (TenantId, SourceLineId),
    CONSTRAINT UQ_SourceLine_Ordinal UNIQUE (TenantId, EventId, LineOrdinal),
    CONSTRAINT FK_SourceLine_Event FOREIGN KEY (TenantId, EventId)
        REFERENCES ac03.BusinessEvent(TenantId, EventId)
);
CREATE TABLE ac03.AOrderLine (
    TenantId varchar(32) NOT NULL,
    OrderLineId varchar(64) NOT NULL,
    CustomerId varchar(64) NOT NULL,
    SkuId varchar(64) NOT NULL,
    ConfirmedQty decimal(19,6) NOT NULL CHECK (ConfirmedQty > 0),
    UnitPriceSnapshot decimal(28,10) NOT NULL CHECK (UnitPriceSnapshot >= 0),
    ShipToSnapshot nvarchar(200) NOT NULL,
    TermsDaysSnapshot int NOT NULL CHECK (TermsDaysSnapshot >= 0),
    TermsApproved bit NOT NULL CHECK (TermsApproved = 1),
    CONSTRAINT PK_AOrderLine PRIMARY KEY (TenantId, OrderLineId),
    CONSTRAINT UQ_AOrderLine_Customer UNIQUE (TenantId, CustomerId, OrderLineId),
    CONSTRAINT FK_AOrderLine_Customer FOREIGN KEY (TenantId, CustomerId)
        REFERENCES ac03.Customer(TenantId, CustomerId),
    CONSTRAINT FK_AOrderLine_Sku FOREIGN KEY (TenantId, SkuId)
        REFERENCES ac03.Sku(TenantId, SkuId)
);
CREATE TABLE ac03.AReservation (
    TenantId varchar(32) NOT NULL,
    RightId varchar(64) NOT NULL,
    OrderLineId varchar(64) NOT NULL,
    TripId varchar(64) NOT NULL,
    SkuId varchar(64) NOT NULL,
    GrantedQty decimal(19,6) NOT NULL CHECK (GrantedQty > 0),
    CONSTRAINT PK_AReservation PRIMARY KEY (TenantId, RightId),
    CONSTRAINT FK_AReservation_Order FOREIGN KEY (TenantId, OrderLineId)
        REFERENCES ac03.AOrderLine(TenantId, OrderLineId),
    CONSTRAINT FK_AReservation_Trip FOREIGN KEY (TenantId, TripId)
        REFERENCES ac03.Trip(TenantId, TripId),
    CONSTRAINT FK_AReservation_Sku FOREIGN KEY (TenantId, SkuId)
        REFERENCES ac03.Sku(TenantId, SkuId)
);
CREATE TABLE ac03.BQuota (
    TenantId varchar(32) NOT NULL,
    RightId varchar(64) NOT NULL,
    TripId varchar(64) NOT NULL,
    SkuId varchar(64) NOT NULL,
    GrantedQty decimal(19,6) NOT NULL CHECK (GrantedQty > 0),
    CONSTRAINT PK_BQuota PRIMARY KEY (TenantId, RightId),
    CONSTRAINT FK_BQuota_Trip FOREIGN KEY (TenantId, TripId)
        REFERENCES ac03.Trip(TenantId, TripId),
    CONSTRAINT FK_BQuota_Sku FOREIGN KEY (TenantId, SkuId)
        REFERENCES ac03.Sku(TenantId, SkuId)
);
CREATE TABLE ac03.BCreditGrant (
    TenantId varchar(32) NOT NULL,
    GrantId varchar(64) NOT NULL,
    TripId varchar(64) NOT NULL,
    ScopeSnapshot varchar(64) NOT NULL,
    GrantedAmount decimal(28,6) NOT NULL CHECK (GrantedAmount > 0),
    CONSTRAINT PK_BCreditGrant PRIMARY KEY (TenantId, GrantId),
    CONSTRAINT FK_Grant_Trip FOREIGN KEY (TenantId, TripId)
        REFERENCES ac03.Trip(TenantId, TripId)
);
CREATE TABLE ac03.ManifestLine (
    TenantId varchar(32) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    TripId varchar(64) NOT NULL,
    SkuId varchar(64) NOT NULL,
    Pool char(1) NOT NULL CHECK (Pool IN ('A','B')),
    RightId varchar(64) NOT NULL,
    AReservationId varchar(64) NULL,
    BQuotaId varchar(64) NULL,
    Qty decimal(19,6) NOT NULL CHECK (Qty > 0),
    CostValue decimal(28,6) NOT NULL CHECK (CostValue >= 0),
    CONSTRAINT PK_Manifest PRIMARY KEY (TenantId, SourceLineId),
    CONSTRAINT UQ_Manifest_Link UNIQUE (TenantId, SourceLineId, TripId, SkuId, Pool, RightId),
    CONSTRAINT CK_Manifest_XOR CHECK (
       (Pool='A' AND AReservationId=RightId AND BQuotaId IS NULL)
       OR (Pool='B' AND BQuotaId=RightId AND AReservationId IS NULL)),
    CONSTRAINT FK_Manifest_Source FOREIGN KEY (TenantId, SourceLineId)
        REFERENCES ac03.SourceLine(TenantId, SourceLineId),
    CONSTRAINT FK_Manifest_A FOREIGN KEY (TenantId, AReservationId)
        REFERENCES ac03.AReservation(TenantId, RightId),
    CONSTRAINT FK_Manifest_B FOREIGN KEY (TenantId, BQuotaId)
        REFERENCES ac03.BQuota(TenantId, RightId),
    CONSTRAINT FK_Manifest_Trip FOREIGN KEY (TenantId, TripId)
        REFERENCES ac03.Trip(TenantId, TripId),
    CONSTRAINT FK_Manifest_Sku FOREIGN KEY (TenantId, SkuId)
        REFERENCES ac03.Sku(TenantId, SkuId)
);
CREATE TABLE ac03.UnloadLine (
    TenantId varchar(32) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    ManifestLineId varchar(64) NOT NULL,
    TripId varchar(64) NOT NULL,
    SkuId varchar(64) NOT NULL,
    Pool char(1) NOT NULL,
    RightId varchar(64) NOT NULL,
    Qty decimal(19,6) NOT NULL CHECK (Qty > 0),
    CostValue decimal(28,6) NOT NULL CHECK (CostValue >= 0),
    CONSTRAINT PK_Unload PRIMARY KEY (TenantId, SourceLineId),
    CONSTRAINT FK_Unload_Source FOREIGN KEY (TenantId, SourceLineId)
        REFERENCES ac03.SourceLine(TenantId, SourceLineId),
    CONSTRAINT FK_Unload_Manifest FOREIGN KEY (TenantId, ManifestLineId, TripId, SkuId, Pool, RightId)
        REFERENCES ac03.ManifestLine(TenantId, SourceLineId, TripId, SkuId, Pool, RightId)
);
CREATE TABLE ac03.BSaleLine (
    TenantId varchar(32) NOT NULL,
    SaleLineId varchar(64) NOT NULL,
    CustomerId varchar(64) NOT NULL,
    QuotaId varchar(64) NOT NULL,
    Qty decimal(19,6) NOT NULL CHECK (Qty > 0),
    UnitPriceSnapshot decimal(28,10) NOT NULL CHECK (UnitPriceSnapshot >= 0),
    ShipToSnapshot nvarchar(200) NOT NULL,
    CONSTRAINT PK_BSaleLine PRIMARY KEY (TenantId, SaleLineId),
    CONSTRAINT UQ_BSale_Customer UNIQUE (TenantId, CustomerId, SaleLineId),
    CONSTRAINT FK_BSale_Customer FOREIGN KEY (TenantId, CustomerId)
        REFERENCES ac03.Customer(TenantId, CustomerId),
    CONSTRAINT FK_BSale_Quota FOREIGN KEY (TenantId, QuotaId)
        REFERENCES ac03.BQuota(TenantId, RightId)
);
CREATE TABLE ac03.DeliveryLine (
    TenantId varchar(32) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    Module char(1) NOT NULL CHECK (Module IN ('A','B')),
    CustomerId varchar(64) NOT NULL,
    SkuId varchar(64) NOT NULL,
    AOrderLineId varchar(64) NULL,
    BSaleLineId varchar(64) NULL,
    Qty decimal(19,6) NOT NULL CHECK (Qty > 0),
    UnitPriceSnapshot decimal(28,10) NOT NULL CHECK (UnitPriceSnapshot >= 0),
    CostBasisSnapshot decimal(28,10) NOT NULL CHECK (CostBasisSnapshot >= 0),
    BusinessDate date NOT NULL,
    ShipToSnapshot nvarchar(200) NOT NULL,
    CONSTRAINT PK_Delivery PRIMARY KEY (TenantId, SourceLineId),
    CONSTRAINT UQ_Delivery_Customer UNIQUE (TenantId, CustomerId, SourceLineId),
    CONSTRAINT CK_Delivery_XOR CHECK (
       (Module='A' AND AOrderLineId IS NOT NULL AND BSaleLineId IS NULL)
       OR (Module='B' AND BSaleLineId IS NOT NULL AND AOrderLineId IS NULL)),
    CONSTRAINT FK_Delivery_Source FOREIGN KEY (TenantId, SourceLineId)
        REFERENCES ac03.SourceLine(TenantId, SourceLineId),
    CONSTRAINT FK_Delivery_A_Customer FOREIGN KEY (TenantId, CustomerId, AOrderLineId)
        REFERENCES ac03.AOrderLine(TenantId, CustomerId, OrderLineId),
    CONSTRAINT FK_Delivery_B_Customer FOREIGN KEY (TenantId, CustomerId, BSaleLineId)
        REFERENCES ac03.BSaleLine(TenantId, CustomerId, SaleLineId),
    CONSTRAINT FK_Delivery_Sku FOREIGN KEY (TenantId, SkuId)
        REFERENCES ac03.Sku(TenantId, SkuId)
);
CREATE TABLE ac03.StockMovement (
    TenantId varchar(32) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    MovementRole varchar(16) NOT NULL CHECK (MovementRole IN ('OPENING','TRANSFER','ISSUE')),
    SkuId varchar(64) NOT NULL,
    Qty decimal(19,6) NOT NULL CHECK (Qty > 0),
    CostValue decimal(28,6) NOT NULL CHECK (CostValue >= 0),
    CONSTRAINT PK_Movement PRIMARY KEY (TenantId, SourceLineId, MovementRole),
    CONSTRAINT FK_Movement_Source FOREIGN KEY (TenantId, SourceLineId)
        REFERENCES ac03.SourceLine(TenantId, SourceLineId),
    CONSTRAINT FK_Movement_Sku FOREIGN KEY (TenantId, SkuId)
        REFERENCES ac03.Sku(TenantId, SkuId)
);
CREATE TABLE ac03.StockPosting (
    TenantId varchar(32) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    MovementRole varchar(16) NOT NULL,
    LegOrdinal tinyint NOT NULL CHECK (LegOrdinal IN (1,2)),
    LocationId varchar(64) NOT NULL,
    SkuId varchar(64) NOT NULL,
    DeltaQty decimal(19,6) NOT NULL CHECK (DeltaQty <> 0),
    DeltaValue decimal(28,6) NOT NULL,
    CONSTRAINT PK_StockPosting PRIMARY KEY (TenantId, SourceLineId, MovementRole, LegOrdinal),
    CONSTRAINT FK_StockPosting_Movement FOREIGN KEY (TenantId, SourceLineId, MovementRole)
        REFERENCES ac03.StockMovement(TenantId, SourceLineId, MovementRole),
    CONSTRAINT FK_StockPosting_Location FOREIGN KEY (TenantId, LocationId)
        REFERENCES ac03.StockLocation(TenantId, LocationId),
    CONSTRAINT FK_StockPosting_Sku FOREIGN KEY (TenantId, SkuId)
        REFERENCES ac03.Sku(TenantId, SkuId)
);
CREATE TABLE ac03.RightPosting (
    TenantId varchar(32) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    EffectOrdinal tinyint NOT NULL,
    RightKind char(1) NOT NULL CHECK (RightKind IN ('A','B')),
    RightId varchar(64) NOT NULL,
    LocationId varchar(64) NOT NULL,
    DeltaQty decimal(19,6) NOT NULL CHECK (DeltaQty <> 0),
    CONSTRAINT PK_RightPosting PRIMARY KEY (TenantId, SourceLineId, EffectOrdinal),
    CONSTRAINT FK_RightPosting_Source FOREIGN KEY (TenantId, SourceLineId)
        REFERENCES ac03.SourceLine(TenantId, SourceLineId),
    CONSTRAINT FK_RightPosting_Location FOREIGN KEY (TenantId, LocationId)
        REFERENCES ac03.StockLocation(TenantId, LocationId)
);
CREATE TABLE ac03.CogsEffect (
    TenantId varchar(32) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    CostAmount decimal(28,6) NOT NULL CHECK (CostAmount >= 0),
    CONSTRAINT PK_Cogs PRIMARY KEY (TenantId, SourceLineId),
    CONSTRAINT FK_Cogs_Delivery FOREIGN KEY (TenantId, SourceLineId)
        REFERENCES ac03.DeliveryLine(TenantId, SourceLineId)
);
CREATE TABLE ac03.ArOpenItem (
    TenantId varchar(32) NOT NULL,
    OpenItemId varchar(64) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    CustomerId varchar(64) NOT NULL,
    Module char(1) NOT NULL CHECK (Module IN ('A','B')),
    GrossDue decimal(28,6) NOT NULL CHECK (GrossDue >= 0),
    DueDate date NOT NULL,
    CONSTRAINT PK_AR PRIMARY KEY (TenantId, OpenItemId),
    CONSTRAINT UQ_AR_Customer UNIQUE (TenantId, CustomerId, OpenItemId),
    CONSTRAINT UQ_AR_Delivery UNIQUE (TenantId, SourceLineId),
    CONSTRAINT FK_AR_DeliveryCustomer FOREIGN KEY (TenantId, CustomerId, SourceLineId)
        REFERENCES ac03.DeliveryLine(TenantId, CustomerId, SourceLineId)
);
CREATE TABLE ac03.Receipt (
    TenantId varchar(32) NOT NULL,
    ReceiptId varchar(64) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    CustomerId varchar(64) NOT NULL,
    Amount decimal(28,6) NOT NULL CHECK (Amount > 0),
    Channel varchar(10) NOT NULL CHECK (Channel IN ('CASH','BANK')),
    State varchar(16) NOT NULL CHECK (State IN ('CONFIRMED','PENDING')),
    CONSTRAINT PK_Receipt PRIMARY KEY (TenantId, ReceiptId),
    CONSTRAINT UQ_Receipt_Customer UNIQUE (TenantId, CustomerId, ReceiptId),
    CONSTRAINT UQ_Receipt_Source UNIQUE (TenantId, SourceLineId),
    CONSTRAINT FK_Receipt_Source FOREIGN KEY (TenantId, SourceLineId)
        REFERENCES ac03.SourceLine(TenantId, SourceLineId),
    CONSTRAINT FK_Receipt_Customer FOREIGN KEY (TenantId, CustomerId)
        REFERENCES ac03.Customer(TenantId, CustomerId)
);
CREATE TABLE ac03.ReceiptAllocation (
    TenantId varchar(32) NOT NULL,
    AllocationId varchar(64) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    CustomerId varchar(64) NOT NULL,
    ReceiptId varchar(64) NOT NULL,
    OpenItemId varchar(64) NOT NULL,
    Amount decimal(28,6) NOT NULL CHECK (Amount > 0),
    CONSTRAINT PK_Allocation PRIMARY KEY (TenantId, AllocationId),
    CONSTRAINT FK_Allocation_Source FOREIGN KEY (TenantId, SourceLineId)
        REFERENCES ac03.SourceLine(TenantId, SourceLineId),
    CONSTRAINT FK_Allocation_ReceiptCustomer FOREIGN KEY (TenantId, CustomerId, ReceiptId)
        REFERENCES ac03.Receipt(TenantId, CustomerId, ReceiptId),
    CONSTRAINT FK_Allocation_ARCustomer FOREIGN KEY (TenantId, CustomerId, OpenItemId)
        REFERENCES ac03.ArOpenItem(TenantId, CustomerId, OpenItemId)
);
CREATE TABLE ac03.GrantEffect (
    TenantId varchar(32) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    GrantId varchar(64) NOT NULL,
    DeltaAmount decimal(28,6) NOT NULL CHECK (DeltaAmount <> 0),
    CONSTRAINT PK_GrantEffect PRIMARY KEY (TenantId, SourceLineId),
    CONSTRAINT FK_GrantEffect_Source FOREIGN KEY (TenantId, SourceLineId)
        REFERENCES ac03.SourceLine(TenantId, SourceLineId),
    CONSTRAINT FK_GrantEffect_Grant FOREIGN KEY (TenantId, GrantId)
        REFERENCES ac03.BCreditGrant(TenantId, GrantId)
);
CREATE TABLE ac03.CustodyEffect (
    TenantId varchar(32) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    DeltaAmount decimal(28,6) NOT NULL CHECK (DeltaAmount <> 0),
    CONSTRAINT PK_CustodyEffect PRIMARY KEY (TenantId, SourceLineId),
    CONSTRAINT FK_CustodyEffect_Source FOREIGN KEY (TenantId, SourceLineId)
        REFERENCES ac03.SourceLine(TenantId, SourceLineId)
);
CREATE TABLE ac03.FundEffect (
    TenantId varchar(32) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    DeltaAmount decimal(28,6) NOT NULL CHECK (DeltaAmount <> 0),
    CONSTRAINT PK_FundEffect PRIMARY KEY (TenantId, SourceLineId),
    CONSTRAINT FK_FundEffect_Source FOREIGN KEY (TenantId, SourceLineId)
        REFERENCES ac03.SourceLine(TenantId, SourceLineId)
);
CREATE TABLE ac03.Handover (
    TenantId varchar(32) NOT NULL,
    HandoverId varchar(64) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    OfferedAmount decimal(28,6) NOT NULL CHECK (OfferedAmount > 0),
    OfferedBy varchar(64) NOT NULL,
    CONSTRAINT PK_Handover PRIMARY KEY (TenantId, HandoverId),
    CONSTRAINT FK_Handover_Source FOREIGN KEY (TenantId, SourceLineId)
        REFERENCES ac03.SourceLine(TenantId, SourceLineId)
);
CREATE TABLE ac03.CashierAcceptance (
    TenantId varchar(32) NOT NULL,
    AcceptanceId varchar(64) NOT NULL,
    SourceLineId varchar(64) NOT NULL,
    HandoverId varchar(64) NOT NULL,
    AcceptedAmount decimal(28,6) NOT NULL CHECK (AcceptedAmount > 0),
    CashierId varchar(64) NOT NULL,
    CONSTRAINT PK_Acceptance PRIMARY KEY (TenantId, AcceptanceId),
    CONSTRAINT FK_Acceptance_Source FOREIGN KEY (TenantId, SourceLineId)
        REFERENCES ac03.SourceLine(TenantId, SourceLineId),
    CONSTRAINT FK_Acceptance_Handover FOREIGN KEY (TenantId, HandoverId)
        REFERENCES ac03.Handover(TenantId, HandoverId)
);
CREATE TABLE ac03.CheckpointActual (
    StepOrdinal int NOT NULL PRIMARY KEY CHECK (StepOrdinal BETWEEN 1 AND 7),
    Step varchar(20) NOT NULL UNIQUE,
    MainQty decimal(19,6) NOT NULL,
    TripQty decimal(19,6) NOT NULL,
    SoldQty decimal(19,6) NOT NULL,
    MainCost decimal(28,6) NOT NULL,
    TripCost decimal(28,6) NOT NULL,
    Cogs decimal(28,6) NOT NULL,
    AHold decimal(19,6) NOT NULL,
    BQuota decimal(19,6) NOT NULL,
    ArA decimal(28,6) NOT NULL,
    ArB decimal(28,6) NOT NULL,
    Custody decimal(28,6) NOT NULL,
    Fund decimal(28,6) NOT NULL
);
GO
CREATE VIEW ac03.LiveBalances AS
SELECT
    CAST(ISNULL((SELECT SUM(DeltaQty) FROM ac03.StockPosting WHERE LocationId='MAIN'),0) AS decimal(19,6)) AS MainQty,
    CAST(ISNULL((SELECT SUM(DeltaQty) FROM ac03.StockPosting WHERE LocationId='TRIP'),0) AS decimal(19,6)) AS TripQty,
    CAST(ISNULL((SELECT SUM(Qty) FROM ac03.DeliveryLine),0) AS decimal(19,6)) AS SoldQty,
    CAST(ISNULL((SELECT SUM(DeltaValue) FROM ac03.StockPosting WHERE LocationId='MAIN'),0) AS decimal(28,6)) AS MainCost,
    CAST(ISNULL((SELECT SUM(DeltaValue) FROM ac03.StockPosting WHERE LocationId='TRIP'),0) AS decimal(28,6)) AS TripCost,
    CAST(ISNULL((SELECT SUM(CostAmount) FROM ac03.CogsEffect),0) AS decimal(28,6)) AS Cogs,
    CAST(ISNULL((SELECT SUM(DeltaQty) FROM ac03.RightPosting WHERE RightKind='A'),0) AS decimal(19,6)) AS AHold,
    CAST(ISNULL((SELECT SUM(DeltaQty) FROM ac03.RightPosting WHERE RightKind='B'),0) AS decimal(19,6)) AS BQuota,
    CAST(ISNULL((SELECT SUM(GrossDue) FROM ac03.ArOpenItem WHERE Module='A'),0)
       - ISNULL((SELECT SUM(x.Amount) FROM ac03.ReceiptAllocation x
                 JOIN ac03.ArOpenItem a ON a.TenantId=x.TenantId AND a.OpenItemId=x.OpenItemId
                 WHERE a.Module='A'),0) AS decimal(28,6)) AS ArA,
    CAST(ISNULL((SELECT SUM(GrossDue) FROM ac03.ArOpenItem WHERE Module='B'),0)
       - ISNULL((SELECT SUM(x.Amount) FROM ac03.ReceiptAllocation x
                 JOIN ac03.ArOpenItem a ON a.TenantId=x.TenantId AND a.OpenItemId=x.OpenItemId
                 WHERE a.Module='B'),0) AS decimal(28,6)) AS ArB,
    CAST(ISNULL((SELECT SUM(DeltaAmount) FROM ac03.CustodyEffect),0) AS decimal(28,6)) AS Custody,
    CAST(ISNULL((SELECT SUM(DeltaAmount) FROM ac03.FundEffect),0) AS decimal(28,6)) AS Fund;
GO
CREATE PROCEDURE ac03.CaptureCheckpoint @StepOrdinal int, @Step varchar(20)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT ac03.CheckpointActual
       (StepOrdinal, Step, MainQty, TripQty, SoldQty, MainCost, TripCost, Cogs,
        AHold, BQuota, ArA, ArB, Custody, Fund)
    SELECT @StepOrdinal, @Step, MainQty, TripQty, SoldQty, MainCost, TripCost,
           Cogs, AHold, BQuota, ArA, ArB, Custody, Fund
    FROM ac03.LiveBalances;
END;
GO
