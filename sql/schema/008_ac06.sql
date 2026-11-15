-- SQL-03C / AC-06, BR-07/20. SQL Server 2017+ executable specification.
-- Isolated from AC-03/09/21; never a production costing schema.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE N'fmcg_sql02[_]%'
   OR OBJECT_ID(N'dbo.__Ac03ScratchMarker',N'U') IS NULL
    THROW 53880, 'AC06_REQUIRES_GUARDED_SCRATCH', 1;
IF SCHEMA_ID(N'ac06') IS NOT NULL THROW 53881, 'AC06_ALREADY_INSTALLED', 1;
GO
CREATE SCHEMA ac06;
GO
CREATE TABLE ac06.Period (
    TenantId varchar(32) NOT NULL,
    PeriodId varchar(16) NOT NULL,
    PeriodState varchar(8) NOT NULL CHECK(PeriodState IN ('OPEN','LOCKED')),
    ClosedBy varchar(40) NULL,
    CONSTRAINT PK_Ac06Period PRIMARY KEY(TenantId,PeriodId),
    CONSTRAINT CK_Ac06PeriodClose CHECK
      ((PeriodState='OPEN' AND ClosedBy IS NULL) OR
       (PeriodState='LOCKED' AND ClosedBy IS NOT NULL))
);
CREATE TABLE ac06.StockLocation (
    TenantId varchar(32) NOT NULL,
    SkuId varchar(32) NOT NULL,
    LocationId varchar(32) NOT NULL,
    LocationKind varchar(12) NOT NULL
      CHECK(LocationKind IN ('AVAILABLE','QUARANTINE')),
    CONSTRAINT PK_Ac06StockLocation PRIMARY KEY(TenantId,SkuId,LocationId)
);
CREATE TABLE ac06.Command (
    TenantId varchar(32) NOT NULL,
    CommandId varchar(40) NOT NULL,
    Kind varchar(12) NOT NULL CHECK (Kind IN ('RECEIVE','ISSUE','RETURN','REVALUE')),
    PeriodId varchar(16) NOT NULL,
    PayloadHash char(64) NOT NULL,
    AcceptedUtc datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Ac06Command PRIMARY KEY(TenantId,CommandId),
    CONSTRAINT FK_Ac06CommandPeriod FOREIGN KEY(TenantId,PeriodId)
      REFERENCES ac06.Period(TenantId,PeriodId)
);
-- Physical stock and value are append-only deltas; one command may create
-- multiple value-only corrections to previously accepted return lines.
CREATE TABLE ac06.StockPosting (
    TenantId varchar(32) NOT NULL,
    CommandId varchar(40) NOT NULL,
    EntryNo int NOT NULL CHECK(EntryNo>0),
    SkuId varchar(32) NOT NULL,
    LocationId varchar(32) NOT NULL,
    Kind varchar(12) NOT NULL
      CHECK(Kind IN ('RECEIVE','ISSUE','RETURN','RETURN_REVAL')),
    QtyDelta int NOT NULL,
    ValueDelta decimal(28,0) NOT NULL,
    CONSTRAINT PK_Ac06StockPosting PRIMARY KEY(TenantId,CommandId,EntryNo),
    CONSTRAINT FK_Ac06StockCommand FOREIGN KEY(TenantId,CommandId)
      REFERENCES ac06.Command(TenantId,CommandId),
    CONSTRAINT FK_Ac06StockLocation FOREIGN KEY(TenantId,SkuId,LocationId)
      REFERENCES ac06.StockLocation(TenantId,SkuId,LocationId),
    CONSTRAINT CK_Ac06StockSign CHECK(
       (Kind='RECEIVE' AND QtyDelta>0 AND ValueDelta>0)
       OR (Kind='ISSUE' AND QtyDelta<0 AND ValueDelta<0)
       OR (Kind='RETURN' AND QtyDelta>0 AND ValueDelta>=0)
       OR (Kind='RETURN_REVAL' AND QtyDelta=0 AND ValueDelta<>0))
);
-- The historical ISSUE never changes; OriginalCost and avg snapshot belong to
-- that event. The current revised cost is derived from immutable versions.
CREATE TABLE ac06.IssueSource (
    TenantId varchar(32) NOT NULL,
    SourceId varchar(40) NOT NULL,
    SkuId varchar(32) NOT NULL,
    FromLocationId varchar(32) NOT NULL,
    SourcePeriodId varchar(16) NOT NULL,
    IssueQty int NOT NULL CHECK(IssueQty>0),
    OriginalCost decimal(28,0) NOT NULL CHECK(OriginalCost>0),
    UnitAverageSnapshot decimal(28,6) NOT NULL CHECK(UnitAverageSnapshot>0),
    CONSTRAINT PK_Ac06IssueSource PRIMARY KEY(TenantId,SourceId),
    CONSTRAINT UQ_Ac06IssueSku UNIQUE(TenantId,SourceId,SkuId),
    CONSTRAINT FK_Ac06IssueCommand FOREIGN KEY(TenantId,SourceId)
      REFERENCES ac06.Command(TenantId,CommandId),
    CONSTRAINT FK_Ac06IssueLocation FOREIGN KEY(TenantId,SkuId,FromLocationId)
      REFERENCES ac06.StockLocation(TenantId,SkuId,LocationId),
    CONSTRAINT FK_Ac06IssuePeriod FOREIGN KEY(TenantId,SourcePeriodId)
      REFERENCES ac06.Period(TenantId,PeriodId)
);
CREATE TABLE ac06.SourceCostVersion (
    TenantId varchar(32) NOT NULL,
    SourceId varchar(40) NOT NULL,
    VersionNo int NOT NULL CHECK(VersionNo>=1),
    TotalCost decimal(28,0) NOT NULL CHECK(TotalCost>0),
    DeltaCost decimal(28,0) NOT NULL,
    EffectivePeriodId varchar(16) NOT NULL,
    ChangeCommandId varchar(40) NOT NULL,
    CONSTRAINT PK_Ac06CostVersion PRIMARY KEY(TenantId,SourceId,VersionNo),
    CONSTRAINT UQ_Ac06CostChangeCommand UNIQUE(TenantId,ChangeCommandId),
    CONSTRAINT FK_Ac06CostIssue FOREIGN KEY(TenantId,SourceId)
      REFERENCES ac06.IssueSource(TenantId,SourceId),
    CONSTRAINT FK_Ac06CostCommand FOREIGN KEY(TenantId,ChangeCommandId)
      REFERENCES ac06.Command(TenantId,CommandId),
    CONSTRAINT FK_Ac06CostPeriod FOREIGN KEY(TenantId,EffectivePeriodId)
      REFERENCES ac06.Period(TenantId,PeriodId)
);
CREATE TABLE ac06.ReturnLine (
    TenantId varchar(32) NOT NULL,
    ReturnId varchar(40) NOT NULL,
    SourceId varchar(40) NOT NULL,
    SkuId varchar(32) NOT NULL,
    ReturnOrdinal int NOT NULL CHECK(ReturnOrdinal>0),
    ToLocationId varchar(32) NOT NULL,
    ReceivedQty int NOT NULL CHECK(ReceivedQty>0),
    RefundBase decimal(28,0) NOT NULL CHECK(RefundBase>=0),
    CostVersionNo int NOT NULL,
    PeriodId varchar(16) NOT NULL,
    CONSTRAINT PK_Ac06Return PRIMARY KEY(TenantId,ReturnId),
    CONSTRAINT UQ_Ac06ReturnOrdinal UNIQUE(TenantId,SourceId,ReturnOrdinal),
    CONSTRAINT UQ_Ac06ReturnSource UNIQUE(TenantId,ReturnId,SourceId),
    CONSTRAINT FK_Ac06ReturnCommand FOREIGN KEY(TenantId,ReturnId)
      REFERENCES ac06.Command(TenantId,CommandId),
    CONSTRAINT FK_Ac06ReturnIssueSku FOREIGN KEY(TenantId,SourceId,SkuId)
      REFERENCES ac06.IssueSource(TenantId,SourceId,SkuId),
    CONSTRAINT FK_Ac06ReturnCostVersion FOREIGN KEY(TenantId,SourceId,CostVersionNo)
      REFERENCES ac06.SourceCostVersion(TenantId,SourceId,VersionNo),
    CONSTRAINT FK_Ac06ReturnLocation FOREIGN KEY(TenantId,SkuId,ToLocationId)
      REFERENCES ac06.StockLocation(TenantId,SkuId,LocationId),
    CONSTRAINT FK_Ac06ReturnPeriod FOREIGN KEY(TenantId,PeriodId)
      REFERENCES ac06.Period(TenantId,PeriodId)
);
CREATE TABLE ac06.ReturnCostAdjustment (
    TenantId varchar(32) NOT NULL,
    AdjustmentId varchar(40) NOT NULL,
    ReturnId varchar(40) NOT NULL,
    SourceId varchar(40) NOT NULL,
    VersionNo int NOT NULL,
    DeltaRefund decimal(28,0) NOT NULL CHECK(DeltaRefund<>0),
    PeriodId varchar(16) NOT NULL,
    CONSTRAINT PK_Ac06ReturnCostAdjustment PRIMARY KEY(TenantId,AdjustmentId,ReturnId),
    CONSTRAINT FK_Ac06AdjustmentCommand FOREIGN KEY(TenantId,AdjustmentId)
      REFERENCES ac06.Command(TenantId,CommandId),
    CONSTRAINT FK_Ac06AdjustmentReturn FOREIGN KEY(TenantId,ReturnId,SourceId)
      REFERENCES ac06.ReturnLine(TenantId,ReturnId,SourceId),
    CONSTRAINT FK_Ac06AdjustmentVersion FOREIGN KEY(TenantId,SourceId,VersionNo)
      REFERENCES ac06.SourceCostVersion(TenantId,SourceId,VersionNo),
    CONSTRAINT FK_Ac06AdjustmentPeriod FOREIGN KEY(TenantId,PeriodId)
      REFERENCES ac06.Period(TenantId,PeriodId)
);
-- COGS effects are separate from the location stock/value ledger.
-- ISSUE and ISSUE_REVAL increase source COGS; returned value decreases it.
CREATE TABLE ac06.CostEffect (
    TenantId varchar(32) NOT NULL,
    CommandId varchar(40) NOT NULL,
    EntryNo int NOT NULL CHECK(EntryNo>0),
    SourceId varchar(40) NOT NULL,
    Kind varchar(16) NOT NULL
      CHECK(Kind IN ('ISSUE','REFUND','ISSUE_REVAL','REFUND_REVAL')),
    DeltaCogs decimal(28,0) NOT NULL,
    CONSTRAINT PK_Ac06CostEffect PRIMARY KEY(TenantId,CommandId,EntryNo),
    CONSTRAINT FK_Ac06EffectCommand FOREIGN KEY(TenantId,CommandId)
      REFERENCES ac06.Command(TenantId,CommandId),
    CONSTRAINT FK_Ac06EffectSource FOREIGN KEY(TenantId,SourceId)
      REFERENCES ac06.IssueSource(TenantId,SourceId)
);
CREATE TABLE ac06.CostCheckpoint (
    StepOrdinal int NOT NULL PRIMARY KEY,
    StepName varchar(24) NOT NULL UNIQUE,
    SourceVersion int NOT NULL,
    SourceTotalCost decimal(28,0) NOT NULL,
    ReturnedQty int NOT NULL,
    RefundTotal decimal(28,0) NOT NULL,
    Cogs decimal(28,0) NOT NULL,
    MainQty int NOT NULL,
    MainValue decimal(28,0) NOT NULL,
    QuarantineQty int NOT NULL,
    QuarantineValue decimal(28,0) NOT NULL
);
-- A negative probe is persisted as factual evidence, not a hardcoded boolean oracle.
CREATE TABLE ac06.TestProbe (
    ProbeId varchar(40) NOT NULL PRIMARY KEY,
    Attempted bit NOT NULL,
    WasMutationAllowed bit NOT NULL
);
GO
CREATE VIEW ac06.StockBalances AS
SELECT l.TenantId,l.SkuId,l.LocationId,l.LocationKind,
       CONVERT(int,ISNULL(SUM(p.QtyDelta),0)) AS Qty,
       CONVERT(decimal(28,0),ISNULL(SUM(p.ValueDelta),0)) AS StockValue,
       CONVERT(decimal(28,6),CASE WHEN ISNULL(SUM(p.QtyDelta),0)>0
          THEN SUM(p.ValueDelta)/CONVERT(decimal(18,6),SUM(p.QtyDelta))
          ELSE NULL END) AS MovingAverage
FROM ac06.StockLocation l
LEFT JOIN ac06.StockPosting p ON p.TenantId=l.TenantId
 AND p.SkuId=l.SkuId AND p.LocationId=l.LocationId
GROUP BY l.TenantId,l.SkuId,l.LocationId,l.LocationKind;
GO
CREATE VIEW ac06.CurrentSourceCost AS
SELECT s.TenantId,s.SourceId,s.SkuId,s.FromLocationId,s.SourcePeriodId,
       s.IssueQty,s.OriginalCost,s.UnitAverageSnapshot,
       cv.VersionNo,cv.TotalCost,cv.EffectivePeriodId
FROM ac06.IssueSource s
CROSS APPLY (
    SELECT TOP (1) VersionNo,TotalCost,EffectivePeriodId
    FROM ac06.SourceCostVersion v
    WHERE v.TenantId=s.TenantId AND v.SourceId=s.SourceId
    ORDER BY v.VersionNo DESC
) cv;
GO
-- Exact cumulative whole-VND proration; avoid rounding a decimal
-- division to 6 fractional digits before ROUND(...,0).
-- The remainder (less than INT_MAX) times cumulativeQty (at most INT_MAX)
-- fits BIGINT; the final rounded result is never above TotalCost.
CREATE FUNCTION ac06.RoundProratedCost
(
    @TotalCost decimal(28,0), @CumulativeQty int, @SourceQty int
)
RETURNS decimal(28,0)
WITH SCHEMABINDING
AS
BEGIN
    IF @TotalCost IS NULL OR @TotalCost<0 OR
       @CumulativeQty IS NULL OR @SourceQty IS NULL OR
       @SourceQty<=0 OR @CumulativeQty<0 OR @CumulativeQty>@SourceQty
        RETURN NULL;
    DECLARE @Remainder bigint,
            @WholePerUnit decimal(28,0),
            @FractionNumerator bigint,
            @FractionWhole bigint,
            @FractionRemainder bigint;
    SET @Remainder=CONVERT(bigint,@TotalCost % @SourceQty);
    -- Division is exact because the remainder has already been removed.
    SET @WholePerUnit=(@TotalCost-CONVERT(decimal(28,0),@Remainder))/@SourceQty;
    SET @FractionNumerator=@Remainder*CONVERT(bigint,@CumulativeQty);
    SET @FractionWhole=@FractionNumerator/CONVERT(bigint,@SourceQty);
    SET @FractionRemainder=@FractionNumerator%CONVERT(bigint,@SourceQty);
    -- For nonnegative amounts, exact half rounds up (away from zero).
    RETURN CONVERT(decimal(28,0),
       @WholePerUnit*CONVERT(decimal(28,0),@CumulativeQty)
       +@FractionWhole
       +CASE WHEN @FractionRemainder*CONVERT(bigint,2)>=@SourceQty
          THEN 1 ELSE 0 END);
END;
GO
-- AC-06 oracle-facing actuals: original second refund is a counterfactual
-- computed at historical cost, not an additional posted return.
CREATE VIEW ac06.CaseActual AS
SELECT s.TenantId,s.SourceId,
       s.IssueQty AS SourceQty,
       s.OriginalCost AS SourceOriginalCost,
       firstReturn.RefundBase AS FirstRefund,
       (ac06.RoundProratedCost(s.OriginalCost,
           firstReturn.ReceivedQty+secondReturn.ReceivedQty,s.IssueQty)
         -ac06.RoundProratedCost(s.OriginalCost,
           firstReturn.ReceivedQty,s.IssueQty)) AS OriginalSecondRefund,
       cv.TotalCost AS SourceAdjustedCost,
       ISNULL(firstCorrection.DeltaRefund,CONVERT(decimal(28,0),0))
           AS FirstRefundAdjustment,
       secondReturn.RefundBase AS FinalSecondRefund,
       CONVERT(decimal(28,0),firstReturn.RefundBase +
           ac06.RoundProratedCost(s.OriginalCost,
             firstReturn.ReceivedQty+secondReturn.ReceivedQty,s.IssueQty)
          -ac06.RoundProratedCost(s.OriginalCost,
             firstReturn.ReceivedQty,s.IssueQty)) AS ExpectedOriginalSum,
       CONVERT(decimal(28,0),firstReturn.RefundBase +
           ISNULL(firstCorrection.DeltaRefund,0) + secondReturn.RefundBase)
           AS ExpectedAdjustedSum,
       CONVERT(bit,CASE WHEN p.Attempted=1 THEN p.WasMutationAllowed
          ELSE 1 END) AS LockedPeriodMutationAllowed
FROM ac06.IssueSource s
JOIN ac06.CurrentSourceCost cv ON cv.TenantId=s.TenantId AND cv.SourceId=s.SourceId
LEFT JOIN ac06.ReturnLine firstReturn ON firstReturn.TenantId=s.TenantId
 AND firstReturn.SourceId=s.SourceId AND firstReturn.ReturnOrdinal=1
LEFT JOIN ac06.ReturnLine secondReturn ON secondReturn.TenantId=s.TenantId
 AND secondReturn.SourceId=s.SourceId AND secondReturn.ReturnOrdinal=2
OUTER APPLY (
    SELECT SUM(a.DeltaRefund) AS DeltaRefund
    FROM ac06.ReturnCostAdjustment a
    WHERE a.TenantId=s.TenantId AND a.SourceId=s.SourceId
      AND a.ReturnId=firstReturn.ReturnId
) firstCorrection
LEFT JOIN ac06.TestProbe p ON p.ProbeId='LOCKED_MUTATION_DENIED';
GO
-- Reject all UPDATE/DELETE on historical financial/stock events even if open.
-- Only new source-identified adjustments may change effective balances.
CREATE TRIGGER ac06.TrgNoModifyIssue ON ac06.IssueSource
AFTER UPDATE,DELETE AS BEGIN SET NOCOUNT ON; THROW 53870,'IMMUTABLE_COST_SOURCE',1; END;
GO
CREATE TRIGGER ac06.TrgNoModifyCostVersion ON ac06.SourceCostVersion
AFTER UPDATE,DELETE AS BEGIN SET NOCOUNT ON; THROW 53870,'IMMUTABLE_COST_VERSION',1; END;
GO
CREATE TRIGGER ac06.TrgNoModifyReturn ON ac06.ReturnLine
AFTER UPDATE,DELETE AS BEGIN SET NOCOUNT ON; THROW 53870,'IMMUTABLE_RETURN',1; END;
GO
CREATE TRIGGER ac06.TrgNoModifyReturnAdjustment ON ac06.ReturnCostAdjustment
AFTER UPDATE,DELETE AS BEGIN SET NOCOUNT ON; THROW 53870,'IMMUTABLE_RETURN_ADJUSTMENT',1; END;
GO
CREATE TRIGGER ac06.TrgNoModifyStock ON ac06.StockPosting
AFTER UPDATE,DELETE AS BEGIN SET NOCOUNT ON; THROW 53870,'IMMUTABLE_STOCK_POSTING',1; END;
GO
CREATE TRIGGER ac06.TrgNoModifyCostEffect ON ac06.CostEffect
AFTER UPDATE,DELETE AS BEGIN SET NOCOUNT ON; THROW 53870,'IMMUTABLE_COGS_POSTING',1; END;
GO
CREATE TRIGGER ac06.TrgNoModifyCommand ON ac06.Command
AFTER UPDATE,DELETE AS BEGIN SET NOCOUNT ON; THROW 53870,'IMMUTABLE_COMMAND',1; END;
GO
-- An OPEN period may close once; a LOCKED period cannot reopen or be deleted.
CREATE TRIGGER ac06.TrgNoReopenPeriod ON ac06.Period
AFTER UPDATE,DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS(SELECT 1 FROM deleted WHERE PeriodState='LOCKED')
       THROW 53871,'LOCKED_PERIOD_IMMUTABLE',1;
END;
GO
