-- SQL-03B: real negative/fault/idempotency assertions executed inside scratch DB.
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
CREATE PROCEDURE ac21.ExpectReject
    @CommandId varchar(40),@Kind varchar(20),@Amount decimal(28,6),
    @ExpectedError int,
    @RefId varchar(40)=NULL,@TargetId varchar(40)=NULL,
    @Channel varchar(8)=NULL,@ReceiptState varchar(12)=NULL,
    @InjectFault bit=0,@TenantId varchar(32)='T21',@ScopeId varchar(40)='MAIN'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Observed int=0,@Result varchar(32),
            @BeforeAR decimal(28,6),@BeforeCredit decimal(28,6),
            @BeforeCustody decimal(28,6),@BeforeFund decimal(28,6),
            @BeforeAlloc decimal(28,6),@BeforeAdvance decimal(28,6);
    SELECT @BeforeAR=Ar,@BeforeCredit=Credit,@BeforeCustody=Custody,
           @BeforeFund=Fund,@BeforeAlloc=Allocated
      FROM ac21.CustomerBalances WHERE TenantId='T21' AND ScopeId='MAIN';
    SELECT @BeforeAdvance=Outstanding FROM ac21.AdvanceBalances
      WHERE TenantId='T21' AND ScopeId='MAIN' AND AdvanceId='ADV_01';
    BEGIN TRY
        EXEC ac21.PostCommand @TenantId=@TenantId,@ScopeId=@ScopeId,
             @CommandId=@CommandId,@Kind=@Kind,@Amount=@Amount,
             @RefId=@RefId,@TargetId=@TargetId,@Channel=@Channel,
             @ReceiptState=@ReceiptState,@InjectFault=@InjectFault,
             @Result=@Result OUTPUT;
    END TRY
    BEGIN CATCH
        SET @Observed=ERROR_NUMBER();
    END CATCH;
    IF @Observed<>@ExpectedError
       THROW 53750, 'REJECT_ERROR_CODE_UNEXPECTED', 1;
    IF EXISTS(SELECT 1 FROM ac21.Command WHERE TenantId=@TenantId
       AND ScopeId=@ScopeId AND CommandId=@CommandId)
       THROW 53751, 'REJECTED_COMMAND_LEFT_SOURCE', 1;
    IF EXISTS(SELECT 1 FROM ac21.CustomerBalances
      WHERE TenantId='T21' AND ScopeId='MAIN'
        AND (Ar<>@BeforeAR OR Credit<>@BeforeCredit OR Custody<>@BeforeCustody
             OR Fund<>@BeforeFund OR Allocated<>@BeforeAlloc))
       THROW 53752, 'REJECTION_CHANGED_CUSTOMER_BALANCES', 1;
    IF EXISTS(SELECT 1 FROM ac21.AdvanceBalances
      WHERE TenantId='T21' AND ScopeId='MAIN' AND AdvanceId='ADV_01'
        AND Outstanding<>@BeforeAdvance)
       THROW 53753, 'REJECTION_CHANGED_ADVANCE_BALANCE', 1;
    EXEC ac21.AssertScope 'T21','MAIN';
END;
GO
DECLARE @Result varchar(32),@N int;
-- Idempotent retry of confirmed receipt / allocation / cashier / advance.
SELECT @N=COUNT(*) FROM ac21.ArAllocation WHERE TenantId='T21' AND ScopeId='MAIN';
EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='ALLOC_20K',@Kind='ALLOCATE',@Amount=20000,
 @RefId='RECEIPT_60K',@TargetId='AR_OPEN_01',@Result=@Result OUTPUT;
IF @Result<>'REPLAY_ACCEPTED' OR
   @N<>(SELECT COUNT(*) FROM ac21.ArAllocation WHERE TenantId='T21' AND ScopeId='MAIN')
 THROW 53754, 'ALLOCATION_REPLAY_DUPLICATED', 1;
EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='RECEIPT_60K',@Kind='RECEIPT',@Amount=60000,
 @Channel='CASH',@ReceiptState='CONFIRMED',@Result=@Result OUTPUT;
IF @Result<>'REPLAY_ACCEPTED' THROW 53755, 'RECEIPT_REPLAY_FAILED', 1;
EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='ACCEPT_50K',@Kind='HANDOVER_ACCEPT',@Amount=50000,
 @RefId='OFFER_50K',@Result=@Result OUTPUT;
IF @Result<>'REPLAY_ACCEPTED' THROW 53756, 'HANDOVER_REPLAY_FAILED', 1;
EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='ADV_ACCEPT_2',@Kind='ADV_ACCEPT',@Amount=100000,
 @RefId='ADV_OFFER_200K',@TargetId='ADV_01',@Result=@Result OUTPUT;
IF @Result<>'REPLAY_ACCEPTED' THROW 53757, 'ADVANCE_REPLAY_FAILED', 1;
-- Conflicts use already-accepted IDs; they MUST not mutate their original source.
BEGIN TRY
 EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
  @CommandId='ALLOC_20K',@Kind='ALLOCATE',@Amount=20001,
  @RefId='RECEIPT_60K',@TargetId='AR_OPEN_01',@Result=@Result OUTPUT;
 THROW 53758, 'ALLOCATE_PAYLOAD_CONFLICT_NOT_REJECTED', 1;
END TRY
BEGIN CATCH
 IF ERROR_NUMBER()<>53301 THROW;
END CATCH;
BEGIN TRY
 EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
  @CommandId='ACCEPT_50K',@Kind='HANDOVER_ACCEPT',@Amount=49999,
  @RefId='OFFER_50K',@Result=@Result OUTPUT;
 THROW 53759, 'HANDOVER_PAYLOAD_CONFLICT_NOT_REJECTED', 1;
END TRY
BEGIN CATCH
 IF ERROR_NUMBER()<>53301 THROW;
END CATCH;
BEGIN TRY
 EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
  @CommandId='ADV_ACCEPT_2',@Kind='ADV_ACCEPT',@Amount=99999,
  @RefId='ADV_OFFER_200K',@TargetId='ADV_01',@Result=@Result OUTPUT;
 THROW 53760, 'ADVANCE_PAYLOAD_CONFLICT_NOT_REJECTED', 1;
END TRY
BEGIN CATCH
 IF ERROR_NUMBER()<>53301 THROW;
END CATCH;
BEGIN TRY
 EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
  @CommandId='ALLOC_20K',@Kind='HANDOVER_OFFER',@Amount=20000,
  @Result=@Result OUTPUT;
 THROW 53761, 'CROSS_KIND_COMMAND_CONFLICT_NOT_REJECTED', 1;
END TRY
BEGIN CATCH
 IF ERROR_NUMBER()<>53301 THROW;
END CATCH;

-- PENDING bank/cash evidence is durable, but not confirmed credit/custody.
EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='BANK_PENDING',@Kind='RECEIPT',@Amount=90000,
 @Channel='BANK',@ReceiptState='PENDING',@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53762, 'PENDING_BANK_NOT_RECORDED', 1;
EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='CASH_PENDING',@Kind='RECEIPT',@Amount=1000,
 @Channel='CASH',@ReceiptState='PENDING',@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53763, 'PENDING_CASH_NOT_RECORDED', 1;
IF EXISTS(SELECT 1 FROM ac21.ReceiptCredit
          WHERE ReceiptId IN ('BANK_PENDING','CASH_PENDING')
            AND AvailableCredit<>0)
 OR EXISTS(SELECT 1 FROM ac21.CustodyPosting
          WHERE SourceId IN ('BANK_PENDING','CASH_PENDING'))
 THROW 53764, 'PENDING_RECEIPT_POSTED_CONFIRMED_EFFECT', 1;
EXEC ac21.ExpectReject 'ALLOC_PENDING_BANK','ALLOCATE',1000,53320,
 @RefId='BANK_PENDING',@TargetId='AR_OPEN_01';
EXEC ac21.ExpectReject 'ALLOC_PENDING_CASH','ALLOCATE',1,53320,
 @RefId='CASH_PENDING',@TargetId='AR_OPEN_01';

-- AC-21 ending credit=25k: cannot allocate 25,001 from the same receipt.
EXEC ac21.ExpectReject 'ALLOC_OVER_RECEIPT','ALLOCATE',25001,53321,
 @RefId='RECEIPT_60K',@TargetId='AR_OPEN_01';
EXEC ac21.ExpectReject 'ALLOC_NO_ITEM','ALLOCATE',100,53322,
 @RefId='RECEIPT_60K',@TargetId='NOT_OUR_AR_ITEM';
EXEC ac21.ExpectReject 'OFFER_OVER_CUSTODY','HANDOVER_OFFER',10001,53330;
EXEC ac21.ExpectReject 'ACCEPT_OVER_OFFER','HANDOVER_ACCEPT',1,53332,
 @RefId='OFFER_50K';
EXEC ac21.ExpectReject 'ACCEPT_UNKNOWN_OFFER','HANDOVER_ACCEPT',1,53331,
 @RefId='UNKNOWN_OFFER';

-- Fault after source/ledger write must roll back EVERY effect and identity.
EXEC ac21.ExpectReject 'FAULT_RECEIPT','RECEIPT',100,53390,
 @Channel='CASH',@ReceiptState='CONFIRMED',@InjectFault=1;
EXEC ac21.ExpectReject 'FAULT_ALLOC','ALLOCATE',100,53390,
 @RefId='RECEIPT_60K',@TargetId='AR_OPEN_01',@InjectFault=1;
EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='FAULT_OFFER',@Kind='HANDOVER_OFFER',@Amount=1000,
 @Result=@Result OUTPUT;
EXEC ac21.ExpectReject 'FAULT_ACCEPT','HANDOVER_ACCEPT',500,53390,
 @RefId='FAULT_OFFER',@InjectFault=1;
IF EXISTS(SELECT 1 FROM ac21.FundPosting WHERE AcceptId='FAULT_ACCEPT')
 OR EXISTS(SELECT 1 FROM ac21.CustodyPosting WHERE SourceId='FAULT_ACCEPT')
 THROW 53765, 'CASHIER_FAULT_LEFT_PARTIAL_POSTING', 1;

-- Over-AR even when a receipt has abundant credit (separate customer scope).
INSERT ac21.Scope VALUES('T21','SMALL_AR','CUSTOMER02','COLLECTOR02');
INSERT ac21.ArOpenItem VALUES('T21','SMALL_AR','AR_TINY','CUSTOMER02',100);
EXEC ac21.PostCommand @TenantId='T21',@ScopeId='SMALL_AR',
 @CommandId='R_LARGE',@Kind='RECEIPT',@Amount=200,
 @Channel='BANK',@ReceiptState='CONFIRMED',@Result=@Result OUTPUT;
EXEC ac21.ExpectReject 'ALLOC_OVER_AR','ALLOCATE',101,53323,
 @RefId='R_LARGE',@TargetId='AR_TINY',@ScopeId='SMALL_AR';
-- A different customer's receipt, item or tenant cannot be borrowed.
EXEC ac21.ExpectReject 'ALLOC_WRONG_CUSTOMER','ALLOCATE',1,53322,
 @RefId='RECEIPT_60K',@TargetId='AR_TINY';
EXEC ac21.ExpectReject 'ALLOC_OTHER_RECEIPT','ALLOCATE',1,53320,
 @RefId='R_LARGE',@TargetId='AR_OPEN_01';
INSERT ac21.Scope VALUES('T22','MAIN','CUSTOMER01','COLLECTOR_OTHER');
INSERT ac21.ArOpenItem VALUES('T22','MAIN','AR_OTHER_TENANT','CUSTOMER01',100);
EXEC ac21.ExpectReject 'ALLOC_OTHER_TENANT','ALLOCATE',1,53320,
 @RefId='RECEIPT_60K',@TargetId='AR_OTHER_TENANT',
 @TenantId='T22',@ScopeId='MAIN';
-- Test direct DML FK ties allocation to confirmed receipt + matching customer.
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT ac21.Command(TenantId,ScopeId,CommandId,Kind,PayloadHash)
 VALUES('T21','MAIN','FORGE_PENDING','ALLOCATE',REPLICATE('0',64));
 INSERT ac21.ArAllocation
 (TenantId,ScopeId,AllocationId,ReceiptId,ItemId,CustomerId,
  RequiredReceiptState,Amount)
 VALUES('T21','MAIN','FORGE_PENDING','BANK_PENDING','AR_OPEN_01',
        'CUSTOMER01','CONFIRMED',1);
 ROLLBACK;
 THROW 53766, 'PENDING_RECEIPT_FK_BYPASSED', 1;
END TRY
BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 IF ERROR_NUMBER()<>547 THROW;
END CATCH;

-- Employee advance cannot become negative, over-accept offer or affect AR.
EXEC ac21.ExpectReject 'ADV_OVER_EXPENSE','ADV_EXPENSE',1,53341,
 @TargetId='ADV_01';
EXEC ac21.ExpectReject 'ADV_OVER_OFFER','ADV_OFFER',1,53342,
 @TargetId='ADV_01';
EXEC ac21.ExpectReject 'ADV_OVER_ACCEPT','ADV_ACCEPT',1,53343,
 @RefId='ADV_OFFER_200K',@TargetId='ADV_01';
EXEC ac21.ExpectReject 'ADV_FAULT_ISSUE','ADV_ISSUE',100,53390,
 @TargetId='ADV_01',@InjectFault=1;
EXEC ac21.AssertScope 'T21','MAIN';
EXEC ac21.AssertScope 'T21','SMALL_AR';
EXEC ac21.AssertScope 'T22','MAIN';
-- End-state must still match captured actual checkpoints after all negative tests.
IF EXISTS(SELECT 1 FROM ac21.CustomerBalances b
 JOIN ac21.CustomerCheckpoint c ON c.StepOrdinal=5
 WHERE b.TenantId='T21' AND b.ScopeId='MAIN'
 AND (b.Ar<>c.Ar OR b.Credit<>c.Credit OR b.Custody<>c.Custody
      OR b.Fund<>c.Fund OR b.Allocated<>c.Allocated))
 THROW 53767, 'NEGATIVE_TEST_CHANGED_CUSTOMER_FINAL', 1;
IF EXISTS(SELECT 1 FROM ac21.AdvanceBalances b
 JOIN ac21.AdvanceCheckpoint a ON a.StepOrdinal=5
 WHERE b.TenantId='T21' AND b.ScopeId='MAIN' AND b.AdvanceId='ADV_01'
 AND (b.Issued<>a.Issued OR b.ApprovedExpenses<>a.ApprovedExpenses
      OR b.CashierAcceptedReturns<>a.CashierAcceptedReturns
      OR b.Outstanding<>a.Outstanding))
 THROW 53768, 'NEGATIVE_TEST_CHANGED_ADVANCE_FINAL', 1;
PRINT 'AC21_NEGATIVE_REPLAY_FAULT_ISOLATION_PASS';
