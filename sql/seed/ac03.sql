-- AC-03 T0 opening: isolated from business/reference-data/master-data/seed.json.
-- Synthetic quantity/value, not VND; invoiceEligible=false, no legal/admission claim.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF SCHEMA_ID(N'ac03') IS NULL OR OBJECT_ID(N'dbo.__Ac03ScratchMarker',N'U') IS NULL
    THROW 51300, 'AC03_SEED_REQUIRES_GUARDED_SCRATCH_SCHEMA', 1;
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT ac03.Tenant VALUES('T01');
    INSERT ac03.Seller VALUES('T01','SELLER_SYNTHETIC');
    INSERT ac03.Customer VALUES('T01','C_A'),('T01','C_B');
    INSERT ac03.Sku VALUES('T01','SKU01',10);
    INSERT ac03.StockLocation VALUES('T01','MAIN','MAIN'),('T01','TRIP','TRIP');
    INSERT ac03.Trip VALUES('T01','TR01','TRIP',CONVERT(date,'2026-11-15'));
    -- OQ-01: explicit APPROVED synthetic terms N=7 solely for this SQL scenario.
    INSERT ac03.AOrderLine VALUES('T01','OA01','C_A','SKU01',40,15,
                                 N'Synthetic ShipTo A',7,1);
    INSERT ac03.AReservation VALUES('T01','RA01','OA01','TR01','SKU01',40);
    INSERT ac03.BQuota VALUES('T01','QB01','TR01','SKU01',30);
    -- OQ-03: scope is explicit simulation-only, not production grant policy.
    INSERT ac03.BCreditGrant VALUES('T01','GB01','TR01','AC03_SYNTHETIC_TRIP',100);
    INSERT ac03.BusinessEvent(TenantId,EventId,ProducerId,CommandId,PayloadHash,Outcome)
    VALUES
      ('T01','OPEN1','SQL02','OPEN1',CONVERT(varchar(64),HASHBYTES('SHA2_256','AC03:OPEN100:VALUE1000'),2),'ACCEPTED'),
      ('T01','CONF1','SQL02','CONF1',CONVERT(varchar(64),HASHBYTES('SHA2_256','AC03:A40:CONFIRMED:N7_APPROVED_SYNTHETIC'),2),'ACCEPTED'),
      ('T01','QGR1','SQL02','QGR1',CONVERT(varchar(64),HASHBYTES('SHA2_256','AC03:B_QUOTA30'),2),'ACCEPTED'),
      ('T01','CGR1','SQL02','CGR1',CONVERT(varchar(64),HASHBYTES('SHA2_256','AC03:B_CREDIT_GRANT100'),2),'ACCEPTED');
    INSERT ac03.SourceLine VALUES
      ('T01','OPEN1-01','OPEN1',1,'OPENING'),
      ('T01','CONF1-01','CONF1',1,'A_CONFIRM'),
      ('T01','QGR1-01','QGR1',1,'B_QUOTA_GRANT'),
      ('T01','CGR1-01','CGR1',1,'B_CREDIT_GRANT');
    INSERT ac03.StockMovement VALUES('T01','OPEN1-01','OPENING','SKU01',100,1000);
    INSERT ac03.StockPosting VALUES('T01','OPEN1-01','OPENING',1,'MAIN','SKU01',100,1000);
    INSERT ac03.RightPosting VALUES('T01','CONF1-01',1,'A','RA01','MAIN',40);
    INSERT ac03.RightPosting VALUES('T01','QGR1-01',1,'B','QB01','MAIN',30);
    INSERT ac03.GrantEffect VALUES('T01','CGR1-01','GB01',100);
    EXEC ac03.AssertInvariants;
    EXEC ac03.CaptureCheckpoint 1,'T0';
    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK;
    THROW;
END CATCH;
