-- SQL-02 AC-03 checkpoints. Expected numbers are NOT embedded here:
-- run-tests.ps1 reads the frozen business golden-oracles.json at runtime.
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Result varchar(32),@Hash char(64);
IF (SELECT COUNT(*) FROM ac03.CheckpointActual)<>1
    THROW 51310, 'AC03_REQUIRES_T0_SEED', 1;

-- N-03: exceed A hold at MAIN while physical stock is sufficient.
BEGIN TRY
    EXEC ac03.ExecuteTransfer 'LOAD','NEG_OVERHOLD',
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        41,30,0,@Result OUTPUT;
    THROW 51311, 'N03_UNEXPECTED_SUCCESS', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>51102 THROW;
END CATCH;
IF EXISTS(SELECT 1 FROM ac03.BusinessEvent WHERE EventId='NEG_OVERHOLD')
    THROW 51312, 'N03_PARTIAL_EVENT', 1;

-- N-09: fault after source/stock movements, before right ledger, must rollback everything.
BEGIN TRY
    EXEC ac03.ExecuteTransfer 'LOAD','FAULT_LOAD',
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        40,30,1,@Result OUTPUT;
    THROW 51313, 'TRANSFER_FAULT_NOT_TRIGGERED', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>51106 THROW;
END CATCH;
IF EXISTS(SELECT 1 FROM ac03.BusinessEvent WHERE EventId='FAULT_LOAD')
    OR EXISTS(SELECT 1 FROM ac03.StockPosting WHERE SourceLineId LIKE 'FAULT_LOAD%')
    OR EXISTS(SELECT 1 FROM ac03.ManifestLine WHERE SourceLineId LIKE 'FAULT_LOAD%')
    THROW 51314, 'TRANSFER_FAULT_NOT_ROLLED_BACK', 1;
EXEC ac03.AssertInvariants;

-- T1: two independent manifest sources/movements, four transfer stock legs.
SET @Hash='cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
EXEC ac03.ExecuteTransfer 'LOAD','LOAD1',@Hash,40,30,0,@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 51315, 'T1_LOAD_FAILED', 1;
EXEC ac03.CaptureCheckpoint 2,'T1_LOAD';
IF (SELECT COUNT(*) FROM ac03.ManifestLine WHERE TenantId='T01')<>2
   OR (SELECT COUNT(*) FROM ac03.StockMovement WHERE MovementRole='TRANSFER')<>2
   OR (SELECT COUNT(*) FROM ac03.StockPosting WHERE MovementRole='TRANSFER')<>4
    THROW 51316, 'T1_MANIFEST_2_MOVEMENTS_4_LEGS_EXPECTED', 1;

-- N-04: same identity+hash is replay, different hash is conflict.
EXEC ac03.ExecuteTransfer 'LOAD','LOAD1',@Hash,40,30,0,@Result OUTPUT;
IF @Result<>'REPLAY_ACCEPTED' THROW 51317, 'T1_REPLAY_FAILED', 1;
BEGIN TRY
    EXEC ac03.ExecuteTransfer 'LOAD','LOAD1',
         'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
         40,30,0,@Result OUTPUT;
    THROW 51318, 'N04_CONFLICT_NOT_DETECTED', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>51100 THROW;
END CATCH;

-- T2: B31 full offered/verified cash465 makes grant exposure zero,
-- isolating the real failure condition BQuota TRIP=30. Nothing is received on reject.
EXEC ac03.ExecuteSaleB 'B31',
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    31,465,'C_B',0,@Result OUTPUT;
IF @Result<>'REJECTED_QUOTA' THROW 51319, 'T2_B31_NOT_REJECTED_FOR_QUOTA', 1;
IF NOT EXISTS(SELECT 1 FROM ac03.BusinessEvent WHERE EventId='B31'
             AND Outcome='REJECTED' AND Reason='B_QUOTA_INSUFFICIENT')
    OR EXISTS(SELECT 1 FROM ac03.SourceLine WHERE EventId='B31')
    OR EXISTS(SELECT 1 FROM ac03.Receipt WHERE SourceLineId LIKE 'B31%')
    THROW 51320, 'T2_REJECT_CREATED_SOURCE_OR_RECEIPT', 1;
IF EXISTS (
    SELECT MainQty,TripQty,SoldQty,MainCost,TripCost,Cogs,AHold,BQuota,ArA,ArB,Custody,Fund
    FROM ac03.LiveBalances
    EXCEPT
    SELECT MainQty,TripQty,SoldQty,MainCost,TripCost,Cogs,AHold,BQuota,ArA,ArB,Custody,Fund
    FROM ac03.CheckpointActual WHERE StepOrdinal=2)
    THROW 51321, 'T2_REJECT_CHANGED_BUSINESS_STATE', 1;
EXEC ac03.CaptureCheckpoint 3,'T2_REJECT';

-- N-09 again: an eligible B sale fails after stock/cost; neither AR nor
-- verified receipt/grant/ledger may survive the rollback.
BEGIN TRY
    EXEC ac03.ExecuteSaleB 'FAULT_B',
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
        1,15,'C_B',1,@Result OUTPUT;
    THROW 51322, 'B_FAULT_NOT_TRIGGERED', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>51114 THROW;
END CATCH;
IF EXISTS(SELECT 1 FROM ac03.BusinessEvent WHERE EventId='FAULT_B')
   OR EXISTS(SELECT 1 FROM ac03.DeliveryLine WHERE SourceLineId LIKE 'FAULT_B%')
   OR EXISTS(SELECT 1 FROM ac03.CogsEffect WHERE SourceLineId LIKE 'FAULT_B%')
   OR EXISTS(SELECT 1 FROM ac03.Receipt WHERE SourceLineId LIKE 'FAULT_B%')
    THROW 51323, 'B_FAULT_LEFT_PARTIAL_EFFECTS', 1;
EXEC ac03.AssertInvariants;

-- T3: B20 payable300, confirmed cash200, AR100, COGS200, grant consume100.
EXEC ac03.ExecuteSaleB 'B20',
     '1111111111111111111111111111111111111111111111111111111111111111',
     20,200,'C_B',0,@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 51324, 'T3_B20_FAILED', 1;
EXEC ac03.CaptureCheckpoint 4,'T3_B20';

-- T4: A25 with immutable order price15/terms N7/ShipTo snapshot.
EXEC ac03.ExecuteDeliveryA 'A25',
     '2222222222222222222222222222222222222222222222222222222222222222',
     25,'C_A',@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 51325, 'T4_A25_FAILED', 1;
EXEC ac03.CaptureCheckpoint 5,'T4_A25';

-- T5: OFFER is not cashier acceptance and must not mutate financial ledgers.
EXEC ac03.OfferHandover 'OFFER1',
     '3333333333333333333333333333333333333333333333333333333333333333',
     200,@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 51326, 'HANDOVER_OFFER_FAILED', 1;
IF EXISTS (
    SELECT MainQty,TripQty,SoldQty,MainCost,TripCost,Cogs,AHold,BQuota,ArA,ArB,Custody,Fund
    FROM ac03.LiveBalances
    EXCEPT
    SELECT MainQty,TripQty,SoldQty,MainCost,TripCost,Cogs,AHold,BQuota,ArA,ArB,Custody,Fund
    FROM ac03.CheckpointActual WHERE StepOrdinal=5)
    THROW 51327, 'OFFER_MUTATED_LEDGER', 1;
EXEC ac03.AcceptHandover 'ACCEPT1',
     '4444444444444444444444444444444444444444444444444444444444444444',
     'OFFER1',200,'CASHIER',@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 51328, 'HANDOVER_ACCEPT_FAILED', 1;
EXEC ac03.CaptureCheckpoint 6,'T5_HANDOVER';

-- T6: unload two lines referencing two original manifest lines;
-- A right returns to MAIN, B right is released rather than moved.
EXEC ac03.ExecuteTransfer 'UNLOAD','UNLOAD1',
     '5555555555555555555555555555555555555555555555555555555555555555',
     15,10,0,@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 51329, 'T6_UNLOAD_FAILED', 1;
EXEC ac03.CaptureCheckpoint 7,'T6_RETURN';
IF (SELECT COUNT(*) FROM ac03.UnloadLine)<>2
   OR (SELECT COUNT(*) FROM ac03.StockMovement WHERE MovementRole='TRANSFER')<>4
   OR (SELECT COUNT(*) FROM ac03.StockPosting WHERE MovementRole='TRANSFER')<>8
    THROW 51330, 'T6_PER_SOURCE_TWO_MOVEMENTS_FOUR_LEGS_EXPECTED', 1;
IF (SELECT ISNULL(SUM(DeltaQty),0) FROM ac03.RightPosting
    WHERE RightKind='A' AND LocationId='MAIN')<>15
   OR (SELECT ISNULL(SUM(DeltaQty),0) FROM ac03.RightPosting
    WHERE RightKind='A' AND LocationId='TRIP')<>0
   OR (SELECT ISNULL(SUM(DeltaQty),0) FROM ac03.RightPosting
    WHERE RightKind='B')<>0
    THROW 51331, 'T6_A_HELD_OR_B_QUOTA_NOT_RECONCILED', 1;
EXEC ac03.AssertInvariants;
IF (SELECT COUNT(*) FROM ac03.CheckpointActual)<>7
    THROW 51332, 'AC03_EXPECTS_SEVEN_CHECKPOINTS', 1;
