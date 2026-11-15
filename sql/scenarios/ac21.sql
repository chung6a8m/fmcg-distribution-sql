-- SQL-03B fixture commands. Values are GIVEN inputs from frozen AC-21 / AC-20.
-- Expected balances are NOT embedded here: runner compares the original JSON.
SET NOCOUNT ON;
SET XACT_ABORT ON;
INSERT ac21.Scope(TenantId,ScopeId,CustomerId,CollectorId)
VALUES('T21','MAIN','CUSTOMER01','COLLECTOR01');
INSERT ac21.ArOpenItem(TenantId,ScopeId,ItemId,CustomerId,OpeningAmount)
VALUES('T21','MAIN','AR_OPEN_01','CUSTOMER01',140000);
INSERT ac21.AdvanceAccount(TenantId,ScopeId,AdvanceId,EmployeeId)
VALUES('T21','MAIN','ADV_01','EMPLOYEE01');
DECLARE @Result varchar(32);
-- AC-21: one confirmed cash receipt, two allocations, OFFER, cashier ACCEPT.
EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='RECEIPT_60K',@Kind='RECEIPT',@Amount=60000,
 @Channel='CASH',@ReceiptState='CONFIRMED',@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53700, 'RECEIPT_NOT_ACCEPTED', 1;
EXEC ac21.CaptureCustomer 1,'CONFIRMED','T21','MAIN';

EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='ALLOC_20K',@Kind='ALLOCATE',@Amount=20000,
 @RefId='RECEIPT_60K',@TargetId='AR_OPEN_01',@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53701, 'FIRST_ALLOCATION_NOT_ACCEPTED', 1;
EXEC ac21.CaptureCustomer 2,'ALLOC_20K','T21','MAIN';

EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='ALLOC_15K',@Kind='ALLOCATE',@Amount=15000,
 @RefId='RECEIPT_60K',@TargetId='AR_OPEN_01',@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53702, 'SECOND_ALLOCATION_NOT_ACCEPTED', 1;
EXEC ac21.CaptureCustomer 3,'ALLOC_15K','T21','MAIN';

EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='OFFER_50K',@Kind='HANDOVER_OFFER',@Amount=50000,
 @Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53703, 'HANDOVER_OFFER_NOT_RECORDED', 1;
IF EXISTS(SELECT 1 FROM ac21.CustodyPosting WHERE SourceId='OFFER_50K')
 OR EXISTS(SELECT 1 FROM ac21.FundPosting WHERE AcceptId='OFFER_50K')
 THROW 53704, 'OFFER_CREATED_POSTING', 1;
EXEC ac21.CaptureCustomer 4,'OFFER_50K','T21','MAIN';

EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='ACCEPT_50K',@Kind='HANDOVER_ACCEPT',@Amount=50000,
 @RefId='OFFER_50K',@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53705, 'CASHIER_ACCEPT_NOT_RECORDED', 1;
EXEC ac21.CaptureCustomer 5,'ACCEPT_50K','T21','MAIN';
-- A handover is NOT another receipt allocation against AR.
IF (SELECT COUNT(*) FROM ac21.ArAllocation WHERE TenantId='T21' AND ScopeId='MAIN')<>2
 THROW 53706, 'HANDOVER_DOUBLE_ALLOCATED_AR', 1;

-- Optional AC-20, in distinct employee-advance ledgers on the same scope.
EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='ADV_ISSUE_500K',@Kind='ADV_ISSUE',@Amount=500000,
 @TargetId='ADV_01',@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53707, 'ADV_ISSUE_NOT_ACCEPTED', 1;
EXEC ac21.CaptureAdvance 1,'ISSUE','T21','MAIN','ADV_01';

EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='ADV_EXPENSE_300K',@Kind='ADV_EXPENSE',@Amount=300000,
 @TargetId='ADV_01',@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53708, 'ADV_EXPENSE_NOT_ACCEPTED', 1;
EXEC ac21.CaptureAdvance 2,'EXPENSE','T21','MAIN','ADV_01';

EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='ADV_OFFER_200K',@Kind='ADV_OFFER',@Amount=200000,
 @TargetId='ADV_01',@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53709, 'ADV_OFFER_NOT_RECORDED', 1;
EXEC ac21.CaptureAdvance 3,'OFFER','T21','MAIN','ADV_01';

EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='ADV_ACCEPT_1',@Kind='ADV_ACCEPT',@Amount=100000,
 @RefId='ADV_OFFER_200K',@TargetId='ADV_01',@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53710, 'ADV_ACCEPT_1_NOT_RECORDED', 1;
EXEC ac21.CaptureAdvance 4,'ACCEPT_1','T21','MAIN','ADV_01';

EXEC ac21.PostCommand @TenantId='T21',@ScopeId='MAIN',
 @CommandId='ADV_ACCEPT_2',@Kind='ADV_ACCEPT',@Amount=100000,
 @RefId='ADV_OFFER_200K',@TargetId='ADV_01',@Result=@Result OUTPUT;
IF @Result<>'ACCEPTED' THROW 53711, 'ADV_ACCEPT_2_NOT_RECORDED', 1;
EXEC ac21.CaptureAdvance 5,'ACCEPT_2','T21','MAIN','ADV_01';
EXEC ac21.AssertScope 'T21','MAIN';

-- Advance movements cannot alter customer AR/credit/custody/fund.
IF EXISTS(SELECT 1 FROM ac21.CustomerBalances b
 JOIN ac21.CustomerCheckpoint c ON c.StepOrdinal=5
 WHERE b.TenantId='T21' AND b.ScopeId='MAIN'
   AND (b.Ar<>c.Ar OR b.Credit<>c.Credit OR b.Custody<>c.Custody
        OR b.Fund<>c.Fund OR b.Allocated<>c.Allocated))
 THROW 53712, 'ADVANCE_POLLUTED_CUSTOMER_LEDGERS', 1;
IF (SELECT COUNT(*) FROM ac21.Command WHERE TenantId='T21' AND ScopeId='MAIN')<>10
 THROW 53713, 'WRONG_SOURCE_COMMAND_COUNT', 1;
