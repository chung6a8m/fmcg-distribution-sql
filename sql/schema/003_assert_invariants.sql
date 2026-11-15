-- SQL-02 invariant checks are called inside each accepted command transaction
-- and by the negative tests; they verify journal as well as derived balances.
SET NOCOUNT ON;
GO
CREATE PROCEDURE ac03.AssertInvariants
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @MainQty decimal(19,6),@TripQty decimal(19,6),@SoldQty decimal(19,6),
            @MainCost decimal(28,6),@TripCost decimal(28,6),@Cogs decimal(28,6),
            @AHold decimal(19,6),@BQuota decimal(19,6),
            @ArA decimal(28,6),@ArB decimal(28,6),@Custody decimal(28,6),@Fund decimal(28,6);
    SELECT @MainQty=MainQty,@TripQty=TripQty,@SoldQty=SoldQty,
           @MainCost=MainCost,@TripCost=TripCost,@Cogs=Cogs,
           @AHold=AHold,@BQuota=BQuota,@ArA=ArA,@ArB=ArB,@Custody=Custody,@Fund=Fund
    FROM ac03.LiveBalances;
    IF @MainQty<0 OR @TripQty<0 OR @SoldQty<0 OR @MainCost<0 OR @TripCost<0
       OR @Cogs<0 OR @AHold<0 OR @BQuota<0 OR @ArA<0 OR @ArB<0
       OR @Custody<0 OR @Fund<0
        THROW 51201, 'NEGATIVE_BALANCE', 1;
    IF @MainQty+@TripQty+@SoldQty<>100
        THROW 51202, 'STOCK_QUANTITY_CONSERVATION', 1;
    IF @MainCost+@TripCost+@Cogs<>1000
        THROW 51203, 'STOCK_VALUE_CONSERVATION', 1;

    -- Every transfer has exactly two balanced legs with the same source/SKU.
    IF EXISTS (
       SELECT 1 FROM ac03.StockMovement m
       OUTER APPLY (SELECT COUNT(*) Cnt,SUM(p.DeltaQty) SumQty,SUM(p.DeltaValue) SumValue
                    FROM ac03.StockPosting p
                    WHERE p.TenantId=m.TenantId AND p.SourceLineId=m.SourceLineId
                      AND p.MovementRole=m.MovementRole) legs
       WHERE m.MovementRole='TRANSFER'
         AND (legs.Cnt<>2 OR legs.SumQty<>0 OR legs.SumValue<>0
           OR NOT EXISTS (
                SELECT 1 FROM ac03.StockPosting p
                WHERE p.TenantId=m.TenantId AND p.SourceLineId=m.SourceLineId
                  AND p.MovementRole=m.MovementRole AND p.LegOrdinal=1
                  AND p.DeltaQty=-m.Qty AND p.DeltaValue=-m.CostValue AND p.SkuId=m.SkuId)
           OR NOT EXISTS (
                SELECT 1 FROM ac03.StockPosting p
                WHERE p.TenantId=m.TenantId AND p.SourceLineId=m.SourceLineId
                  AND p.MovementRole=m.MovementRole AND p.LegOrdinal=2
                  AND p.DeltaQty=m.Qty AND p.DeltaValue=m.CostValue AND p.SkuId=m.SkuId)))
        THROW 51204, 'TRANSFER_LEGS_MISMATCH', 1;
    IF EXISTS (
       SELECT 1 FROM ac03.StockMovement m
       OUTER APPLY (SELECT COUNT(*) Cnt,SUM(DeltaQty) Q,SUM(DeltaValue) V
                    FROM ac03.StockPosting p
                    WHERE p.TenantId=m.TenantId AND p.SourceLineId=m.SourceLineId
                      AND p.MovementRole=m.MovementRole) legs
       WHERE (m.MovementRole='OPENING' AND (legs.Cnt<>1 OR legs.Q<>m.Qty OR legs.V<>m.CostValue))
          OR (m.MovementRole='ISSUE' AND (legs.Cnt<>1 OR legs.Q<>-m.Qty OR legs.V<>-m.CostValue)))
        THROW 51205, 'OPENING_OR_DELIVERY_LEGS_MISMATCH', 1;
    IF EXISTS (
       SELECT 1 FROM ac03.ManifestLine m
       LEFT JOIN ac03.StockMovement mv ON mv.TenantId=m.TenantId
            AND mv.SourceLineId=m.SourceLineId AND mv.MovementRole='TRANSFER'
       LEFT JOIN ac03.StockPosting p1 ON p1.TenantId=m.TenantId
            AND p1.SourceLineId=m.SourceLineId AND p1.MovementRole='TRANSFER' AND p1.LegOrdinal=1
       LEFT JOIN ac03.StockPosting p2 ON p2.TenantId=m.TenantId
            AND p2.SourceLineId=m.SourceLineId AND p2.MovementRole='TRANSFER' AND p2.LegOrdinal=2
       LEFT JOIN ac03.RightPosting r1 ON r1.TenantId=m.TenantId
            AND r1.SourceLineId=m.SourceLineId AND r1.EffectOrdinal=1
       LEFT JOIN ac03.RightPosting r2 ON r2.TenantId=m.TenantId
            AND r2.SourceLineId=m.SourceLineId AND r2.EffectOrdinal=2
       WHERE mv.Qty IS NULL OR mv.Qty<>m.Qty OR mv.CostValue<>m.CostValue OR mv.SkuId<>m.SkuId
          OR p1.LocationId<>'MAIN' OR p2.LocationId<>'TRIP'
          OR p1.DeltaQty<>-m.Qty OR p1.DeltaValue<>-m.CostValue
          OR p2.DeltaQty<>m.Qty OR p2.DeltaValue<>m.CostValue
          OR r1.RightKind<>m.Pool OR r1.RightId<>m.RightId OR r1.LocationId<>'MAIN' OR r1.DeltaQty<>-m.Qty
          OR r2.RightKind<>m.Pool OR r2.RightId<>m.RightId OR r2.LocationId<>'TRIP' OR r2.DeltaQty<>m.Qty
          OR (SELECT COUNT(*) FROM ac03.RightPosting r WHERE r.TenantId=m.TenantId AND r.SourceLineId=m.SourceLineId)<>2)
        THROW 51206, 'MANIFEST_LINE_PROVENANCE_MISMATCH', 1;
    IF EXISTS (
       SELECT 1 FROM ac03.UnloadLine u
       JOIN ac03.ManifestLine m ON m.TenantId=u.TenantId AND m.SourceLineId=u.ManifestLineId
       LEFT JOIN ac03.StockMovement mv ON mv.TenantId=u.TenantId
            AND mv.SourceLineId=u.SourceLineId AND mv.MovementRole='TRANSFER'
       LEFT JOIN ac03.StockPosting p1 ON p1.TenantId=u.TenantId
            AND p1.SourceLineId=u.SourceLineId AND p1.MovementRole='TRANSFER' AND p1.LegOrdinal=1
       LEFT JOIN ac03.StockPosting p2 ON p2.TenantId=u.TenantId
            AND p2.SourceLineId=u.SourceLineId AND p2.MovementRole='TRANSFER' AND p2.LegOrdinal=2
       LEFT JOIN ac03.RightPosting r1 ON r1.TenantId=u.TenantId
            AND r1.SourceLineId=u.SourceLineId AND r1.EffectOrdinal=1
       LEFT JOIN ac03.RightPosting r2 ON r2.TenantId=u.TenantId
            AND r2.SourceLineId=u.SourceLineId AND r2.EffectOrdinal=2
       WHERE mv.Qty IS NULL OR mv.Qty<>u.Qty OR mv.CostValue<>u.CostValue OR mv.SkuId<>u.SkuId
          OR p1.LocationId<>'TRIP' OR p2.LocationId<>'MAIN'
          OR p1.DeltaQty<>-u.Qty OR p1.DeltaValue<>-u.CostValue
          OR p2.DeltaQty<>u.Qty OR p2.DeltaValue<>u.CostValue
          OR r1.RightKind<>u.Pool OR r1.RightId<>u.RightId OR r1.LocationId<>'TRIP' OR r1.DeltaQty<>-u.Qty
          OR (u.Pool='A' AND
              (r2.RightKind<>'A' OR r2.RightId<>u.RightId OR r2.LocationId<>'MAIN' OR r2.DeltaQty<>u.Qty))
          OR (u.Pool='B' AND r2.SourceLineId IS NOT NULL)
          OR (SELECT COUNT(*) FROM ac03.RightPosting r WHERE r.TenantId=u.TenantId AND r.SourceLineId=u.SourceLineId)
              <> CASE WHEN u.Pool='A' THEN 2 ELSE 1 END
          OR u.Pool<>m.Pool OR u.RightId<>m.RightId OR u.TripId<>m.TripId OR u.SkuId<>m.SkuId
          OR u.Qty>(m.Qty-ISNULL((SELECT SUM(x.Qty) FROM ac03.UnloadLine x
                                WHERE x.TenantId=u.TenantId AND x.ManifestLineId=m.SourceLineId
                                AND x.SourceLineId<>u.SourceLineId),0)))
        THROW 51207, 'UNLOAD_LINE_PROVENANCE_MISMATCH', 1;

    -- Any current position must be non-negative and covered by physical stock.
    IF EXISTS (
        SELECT 1 FROM (
            SELECT r.TenantId,r.LocationId,
                   COALESCE(a.SkuId,b.SkuId) AS SkuId,SUM(r.DeltaQty) AS RightsQty
            FROM ac03.RightPosting r
            LEFT JOIN ac03.AReservation a ON r.RightKind='A' AND a.TenantId=r.TenantId AND a.RightId=r.RightId
            LEFT JOIN ac03.BQuota b ON r.RightKind='B' AND b.TenantId=r.TenantId AND b.RightId=r.RightId
            GROUP BY r.TenantId,r.LocationId,COALESCE(a.SkuId,b.SkuId)
        ) p
        OUTER APPLY (SELECT ISNULL(SUM(s.DeltaQty),0) OnHand
                     FROM ac03.StockPosting s WHERE s.TenantId=p.TenantId
                     AND s.LocationId=p.LocationId AND s.SkuId=p.SkuId) stock
        WHERE p.SkuId IS NULL OR p.RightsQty<0 OR p.RightsQty>stock.OnHand)
        THROW 51208, 'RIGHT_PLACEMENT_EXCEEDS_STOCK', 1;
    IF EXISTS (
        SELECT 1 FROM ac03.RightPosting r
        LEFT JOIN ac03.AReservation a ON r.RightKind='A' AND a.TenantId=r.TenantId AND a.RightId=r.RightId
        LEFT JOIN ac03.BQuota b ON r.RightKind='B' AND b.TenantId=r.TenantId AND b.RightId=r.RightId
        WHERE (r.RightKind='A' AND a.RightId IS NULL) OR (r.RightKind='B' AND b.RightId IS NULL))
        THROW 51209, 'RIGHT_POOL_REFERENCE_INVALID', 1;
    IF EXISTS (
        SELECT 1 FROM ac03.AReservation a OUTER APPLY
           (SELECT ISNULL(SUM(r.DeltaQty),0) Held FROM ac03.RightPosting r
            WHERE r.TenantId=a.TenantId AND r.RightKind='A' AND r.RightId=a.RightId) q
        WHERE q.Held<0 OR q.Held>a.GrantedQty)
        THROW 51210, 'A_RESERVATION_BOUNDS', 1;
    IF EXISTS (
        SELECT 1 FROM ac03.BQuota a OUTER APPLY
           (SELECT ISNULL(SUM(r.DeltaQty),0) Remaining FROM ac03.RightPosting r
            WHERE r.TenantId=a.TenantId AND r.RightKind='B' AND r.RightId=a.RightId) q
        WHERE q.Remaining<0 OR q.Remaining>a.GrantedQty)
        THROW 51211, 'B_QUOTA_BOUNDS', 1;
    IF EXISTS (
        SELECT 1 FROM ac03.AOrderLine a OUTER APPLY
          (SELECT ISNULL(SUM(d.Qty),0) Delivered FROM ac03.DeliveryLine d
           WHERE d.TenantId=a.TenantId AND d.Module='A' AND d.AOrderLineId=a.OrderLineId) q
        WHERE q.Delivered>a.ConfirmedQty)
        THROW 51212, 'A_DELIVERY_EXCEEDS_CONFIRMED', 1;
    IF EXISTS (
        SELECT 1 FROM ac03.DeliveryLine d
        LEFT JOIN ac03.StockMovement m ON m.TenantId=d.TenantId
            AND m.SourceLineId=d.SourceLineId AND m.MovementRole='ISSUE'
        LEFT JOIN ac03.CogsEffect c ON c.TenantId=d.TenantId AND c.SourceLineId=d.SourceLineId
        LEFT JOIN ac03.ArOpenItem a ON a.TenantId=d.TenantId AND a.SourceLineId=d.SourceLineId
        WHERE m.SourceLineId IS NULL OR c.SourceLineId IS NULL OR a.SourceLineId IS NULL
           OR m.Qty<>d.Qty OR m.CostValue<>CONVERT(decimal(28,6),d.Qty*d.CostBasisSnapshot)
           OR c.CostAmount<>m.CostValue
           OR a.CustomerId<>d.CustomerId OR a.Module<>d.Module
           OR a.GrossDue<>CONVERT(decimal(28,6),d.Qty*d.UnitPriceSnapshot))
        THROW 51213, 'DELIVERY_STOCK_AR_COST_MISMATCH', 1;
    IF EXISTS (
        SELECT 1 FROM ac03.ArOpenItem a OUTER APPLY
          (SELECT ISNULL(SUM(x.Amount),0) Applied FROM ac03.ReceiptAllocation x
           WHERE x.TenantId=a.TenantId AND x.OpenItemId=a.OpenItemId) q
        WHERE q.Applied>a.GrossDue)
        THROW 51214, 'AR_OVERALLOCATION', 1;
    IF EXISTS (
        SELECT 1 FROM ac03.Receipt r OUTER APPLY
          (SELECT ISNULL(SUM(x.Amount),0) Applied FROM ac03.ReceiptAllocation x
           WHERE x.TenantId=r.TenantId AND x.ReceiptId=r.ReceiptId) q
        WHERE q.Applied>r.Amount OR (q.Applied>0 AND r.State<>'CONFIRMED'))
        THROW 51215, 'RECEIPT_NOT_CONFIRMED_OR_OVERALLOCATED', 1;
    IF EXISTS (
        SELECT 1 FROM ac03.BCreditGrant a OUTER APPLY
           (SELECT ISNULL(SUM(e.DeltaAmount),0) Remaining FROM ac03.GrantEffect e
            WHERE e.TenantId=a.TenantId AND e.GrantId=a.GrantId) q
        WHERE q.Remaining<0 OR q.Remaining>a.GrantedAmount)
        THROW 51216, 'GRANT_EXPOSURE_BOUNDS', 1;
    IF EXISTS (
        SELECT 1 FROM ac03.BusinessEvent e
        JOIN ac03.SourceLine s ON s.TenantId=e.TenantId AND s.EventId=e.EventId
        WHERE e.Outcome='REJECTED')
        THROW 51217, 'REJECTED_COMMAND_CREATED_SOURCE', 1;
    IF @Custody+@Fund <>
       ISNULL((SELECT SUM(Amount) FROM ac03.Receipt WHERE State='CONFIRMED' AND Channel='CASH'),0)
        THROW 51218, 'CASH_CUSTODY_FUND_MISMATCH', 1;
    IF EXISTS (
        SELECT 1 FROM ac03.CashierAcceptance a
        LEFT JOIN ac03.CustodyEffect c ON c.TenantId=a.TenantId AND c.SourceLineId=a.SourceLineId
        LEFT JOIN ac03.FundEffect f ON f.TenantId=a.TenantId AND f.SourceLineId=a.SourceLineId
        WHERE c.SourceLineId IS NULL OR f.SourceLineId IS NULL
           OR c.DeltaAmount<>-a.AcceptedAmount OR f.DeltaAmount<>a.AcceptedAmount)
        THROW 51219, 'HANDOVER_CUSTODY_FUND_NOT_PAIRED', 1;
END;
GO
