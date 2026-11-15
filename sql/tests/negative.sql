-- SQL-02 negative/provenance tests, executed after T6 and before oracle export.
-- All intentional mutations are rolled back; unexpected successes throw.
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Err int,@Result varchar(32),@BeforeCount int;
EXEC ac03.AssertInvariants;

-- N-11: local lineOrdinal=1 may repeat on separate events, sourceLineId may not.
IF (SELECT COUNT(*) FROM ac03.SourceLine
    WHERE TenantId='T01' AND LineOrdinal=1)<6
   OR NOT EXISTS(SELECT 1 FROM ac03.SourceLine WHERE EventId='OPEN1'
                 AND SourceLineId='OPEN1-01' AND LineOrdinal=1)
   OR NOT EXISTS(SELECT 1 FROM ac03.SourceLine WHERE EventId='CONF1'
                 AND SourceLineId='CONF1-01' AND LineOrdinal=1)
    THROW 51401, 'N11_SOURCE_ORDINAL_SEMANTICS_BROKEN', 1;
BEGIN TRY
    INSERT ac03.SourceLine VALUES('T01','OPEN1-01','CONF1',2,'ILLEGAL_REUSED_ID');
    THROW 51402, 'N11_DUPLICATE_SOURCE_ID_WAS_ACCEPTED', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() NOT IN (2601,2627) THROW;
END CATCH;

-- N-08: the same EventId in another tenant must not be a legal FK.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT ac03.Tenant VALUES('T02');
    INSERT ac03.SourceLine VALUES('T02','CROSS_TENANT_SOURCE','OPEN1',2,'ILLEGAL');
    THROW 51403, 'N08_CROSS_TENANT_SOURCE_WAS_ACCEPTED', 1;
END TRY
BEGIN CATCH
    SET @Err=ERROR_NUMBER();
    IF @@TRANCOUNT>0 ROLLBACK;
    IF @Err<>547 THROW;
END CATCH;
IF EXISTS(SELECT 1 FROM ac03.Tenant WHERE TenantId='T02')
    THROW 51404, 'N08_FAILED_TO_ROLLBACK', 1;

-- N-12a: receipt owned by Customer B cannot allocate to Customer A open item.
BEGIN TRY
    INSERT ac03.ReceiptAllocation
        VALUES('T01','WRONG_ALLOC','B20-01','C_B','B20-RC','A25-AR',1);
    THROW 51405, 'N12_CROSS_CUSTOMER_ALLOCATION_ACCEPTED', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>547 THROW;
END CATCH;
IF EXISTS(SELECT 1 FROM ac03.ReceiptAllocation WHERE AllocationId='WRONG_ALLOC')
    THROW 51406, 'N12_ALLOCATION_PARTIAL_EFFECT', 1;

-- N-12b: source A order belongs to C_A; deliver to C_B must fail composite FK.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT ac03.BusinessEvent(TenantId,EventId,ProducerId,CommandId,PayloadHash,Outcome)
    VALUES('T01','WRONG_DEL','SQL02','WRONG_DEL',
           '6666666666666666666666666666666666666666666666666666666666666666','ACCEPTED');
    INSERT ac03.SourceLine VALUES('T01','WRONG_DEL-01','WRONG_DEL',1,'A_DELIVERY');
    INSERT ac03.DeliveryLine(TenantId,SourceLineId,Module,CustomerId,SkuId,AOrderLineId,
                             BSaleLineId,Qty,UnitPriceSnapshot,CostBasisSnapshot,BusinessDate,ShipToSnapshot)
    VALUES('T01','WRONG_DEL-01','A','C_B','SKU01','OA01',NULL,1,15,10,
           CONVERT(date,'2026-11-15'),N'Wrong debtor');
    THROW 51407, 'N12_CROSS_CUSTOMER_DELIVERY_ACCEPTED', 1;
END TRY
BEGIN CATCH
    SET @Err=ERROR_NUMBER();
    IF @@TRANCOUNT>0 ROLLBACK;
    IF @Err<>547 THROW;
END CATCH;
IF EXISTS(SELECT 1 FROM ac03.BusinessEvent WHERE EventId='WRONG_DEL')
    THROW 51408, 'N12_DELIVERY_NOT_ROLLED_BACK', 1;

-- N-13a: global manifest still adds to 70, but A41/B29 misstates each source.
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE ac03.ManifestLine SET Qty=41 WHERE SourceLineId='LOAD1-A';
    UPDATE ac03.ManifestLine SET Qty=29 WHERE SourceLineId='LOAD1-B';
    EXEC ac03.AssertInvariants;
    THROW 51409, 'N13_PER_LINE_QTY_CORRUPTION_PASSED', 1;
END TRY
BEGIN CATCH
    SET @Err=ERROR_NUMBER();
    IF @@TRANCOUNT>0 ROLLBACK;
    IF @Err<>51206 THROW;
END CATCH;

-- N-13b: swap A/B right ownership for BOTH original load lines. Each
-- transfer still has balanced rights and global A/B totals are unchanged;
-- only line-level pool provenance can catch the corruption.
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE ac03.RightPosting
    SET RightKind=CASE WHEN RightKind='A' THEN 'B' ELSE 'A' END,
        RightId=CASE WHEN RightKind='A' THEN 'QB01' ELSE 'RA01' END
    WHERE SourceLineId IN ('LOAD1-A','LOAD1-B');
    EXEC ac03.AssertInvariants;
    THROW 51410, 'N13_WRONG_POOL_PROVENANCE_PASSED', 1;
END TRY
BEGIN CATCH
    SET @Err=ERROR_NUMBER();
    IF @@TRANCOUNT>0 ROLLBACK;
    IF @Err<>51206 THROW;
END CATCH;

-- N-13c: shift A/B manifest cost but preserve total value 700.
-- All affected movement and stock legs are changed consistently;
-- source cost provenance (not the oracle totals) must catch the corruption.
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE ac03.ManifestLine
       SET CostValue=CASE SourceLineId WHEN 'LOAD1-A' THEN 500 ELSE 200 END
     WHERE SourceLineId IN ('LOAD1-A','LOAD1-B');
    UPDATE ac03.StockMovement
       SET CostValue=CASE SourceLineId WHEN 'LOAD1-A' THEN 500 ELSE 200 END
     WHERE MovementRole='TRANSFER' AND SourceLineId IN ('LOAD1-A','LOAD1-B');
    UPDATE ac03.StockPosting
       SET DeltaValue=(CASE WHEN LegOrdinal=1 THEN -1 ELSE 1 END)
                      *(CASE SourceLineId WHEN 'LOAD1-A' THEN 500 ELSE 200 END)
     WHERE MovementRole='TRANSFER' AND SourceLineId IN ('LOAD1-A','LOAD1-B');
    EXEC ac03.AssertInvariants;
    THROW 51416, 'N13_MANIFEST_VALUE_SHIFT_PASSED', 1;
END TRY
BEGIN CATCH
    SET @Err=ERROR_NUMBER();
    IF @@TRANCOUNT>0 ROLLBACK;
    IF @Err<>51206 THROW;
END CATCH;

-- N-13d: unload A150->200 and B100->50 while retaining total 250.
-- Original manifest source cost must be used, not reallocated to the other pool.
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE ac03.UnloadLine
       SET CostValue=CASE SourceLineId WHEN 'UNLOAD1-A' THEN 200 ELSE 50 END
     WHERE SourceLineId IN ('UNLOAD1-A','UNLOAD1-B');
    UPDATE ac03.StockMovement
       SET CostValue=CASE SourceLineId WHEN 'UNLOAD1-A' THEN 200 ELSE 50 END
     WHERE MovementRole='TRANSFER' AND SourceLineId IN ('UNLOAD1-A','UNLOAD1-B');
    UPDATE ac03.StockPosting
       SET DeltaValue=(CASE WHEN LegOrdinal=1 THEN -1 ELSE 1 END)
                      *(CASE SourceLineId WHEN 'UNLOAD1-A' THEN 200 ELSE 50 END)
     WHERE MovementRole='TRANSFER' AND SourceLineId IN ('UNLOAD1-A','UNLOAD1-B');
    EXEC ac03.AssertInvariants;
    THROW 51417, 'N13_UNLOAD_VALUE_SHIFT_PASSED', 1;
END TRY
BEGIN CATCH
    SET @Err=ERROR_NUMBER();
    IF @@TRANCOUNT>0 ROLLBACK;
    IF @Err<>51207 THROW;
END CATCH;

-- N-14a: swap A/B delivery right ownership, preserving aggregate rights:
-- A still held15 and B remaining0, but each delivery consumes wrong pool.
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE ac03.RightPosting
       SET RightKind=CASE SourceLineId WHEN 'B20-01' THEN 'A' ELSE 'B' END,
           RightId=CASE SourceLineId WHEN 'B20-01' THEN 'RA01' ELSE 'QB01' END,
           DeltaQty=CASE SourceLineId WHEN 'B20-01' THEN -25 ELSE -20 END
     WHERE EffectOrdinal=1 AND SourceLineId IN ('B20-01','A25-01');
    EXEC ac03.AssertInvariants;
    THROW 51418, 'N14_WRONG_DELIVERY_RIGHT_POOL_PASSED', 1;
END TRY
BEGIN CATCH
    SET @Err=ERROR_NUMBER();
    IF @@TRANCOUNT>0 ROLLBACK;
    IF @Err<>51220 THROW;
END CATCH;

-- N-14b: ISSUE for B20 debits MAIN instead of TRIP, with total stock/value
-- conservation unchanged. Per-delivery location provenance must catch it.
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE ac03.StockPosting SET LocationId='MAIN'
     WHERE SourceLineId='B20-01' AND MovementRole='ISSUE' AND LegOrdinal=1;
    EXEC ac03.AssertInvariants;
    THROW 51419, 'N14_WRONG_DELIVERY_STOCK_LOCATION_PASSED', 1;
END TRY
BEGIN CATCH
    SET @Err=ERROR_NUMBER();
    IF @@TRANCOUNT>0 ROLLBACK;
    IF @Err<>51220 THROW;
END CATCH;
EXEC ac03.AssertInvariants;

-- N-14c: a B issue points at the wrong (same-tenant) SKU while its
-- movement, delivery, and right all still point at SKU01.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT ac03.Sku VALUES('T01','SKU_WRONG',10);
    UPDATE ac03.StockPosting SET SkuId='SKU_WRONG'
     WHERE SourceLineId='B20-01' AND MovementRole='ISSUE' AND LegOrdinal=1;
    EXEC ac03.AssertInvariants;
    THROW 51420, 'N14_WRONG_DELIVERY_STOCK_SKU_PASSED', 1;
END TRY
BEGIN CATCH
    SET @Err=ERROR_NUMBER();
    IF @@TRANCOUNT>0 ROLLBACK;
    IF @Err<>51220 THROW;
END CATCH;

-- N-14d: balance B/A ISSUE quantity errors across two sources so total
-- physical stock remains right; per-movement leg quantity must fail.
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE ac03.StockPosting
       SET DeltaQty=CASE SourceLineId WHEN 'B20-01' THEN -21 ELSE -24 END
     WHERE MovementRole='ISSUE' AND SourceLineId IN ('B20-01','A25-01');
    EXEC ac03.AssertInvariants;
    THROW 51421, 'N14_WRONG_DELIVERY_ISSUE_QTY_PASSED', 1;
END TRY
BEGIN CATCH
    SET @Err=ERROR_NUMBER();
    IF @@TRANCOUNT>0 ROLLBACK;
    IF @Err<>51205 THROW;
END CATCH;
EXEC ac03.AssertInvariants;

-- N-04: replay previously accepted B/A/acceptance after rights and custody
-- have decreased to zero. A replay must be checked BEFORE new preconditions.
SELECT @BeforeCount=COUNT(*) FROM ac03.StockPosting;
EXEC ac03.ExecuteSaleB 'B20',
    '1111111111111111111111111111111111111111111111111111111111111111',
    20,200,'C_B',0,@Result OUTPUT;
IF @Result<>'REPLAY_ACCEPTED' THROW 51411, 'N04_B_REPLAY_FAILED', 1;
EXEC ac03.ExecuteDeliveryA 'A25',
    '2222222222222222222222222222222222222222222222222222222222222222',
    25,'C_A',@Result OUTPUT;
IF @Result<>'REPLAY_ACCEPTED' THROW 51412, 'N04_A_REPLAY_FAILED', 1;
EXEC ac03.AcceptHandover 'ACCEPT1',
    '4444444444444444444444444444444444444444444444444444444444444444',
    'OFFER1',200,'CASHIER',@Result OUTPUT;
IF @Result<>'REPLAY_ACCEPTED' THROW 51413, 'N04_HANDOVER_REPLAY_FAILED', 1;
IF @BeforeCount<>(SELECT COUNT(*) FROM ac03.StockPosting)
    THROW 51414, 'N04_REPLAY_DUPLICATED_EFFECT', 1;
EXEC ac03.AssertInvariants;
IF (SELECT COUNT(*) FROM ac03.CheckpointActual)<>7
    THROW 51415, 'NEGATIVE_TESTS_MUTATED_CHECKPOINTS', 1;
