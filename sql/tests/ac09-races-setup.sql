-- Two independent competition scopes:
-- RACE_GRANT has enough stock/quota for both, grant100 limits 2*exposure80.
-- RACE_QUOTA has enough stock/grant, quota100 limits 2*qty80.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF EXISTS(SELECT 1 FROM ac09.RaceGate) THROW 53500, 'RACES_ALREADY_SET_UP', 1;
INSERT ac09.Pool VALUES
 ('T09','RACE_GRANT','TR_RG','SKU01','C_B',200,100,100,0,10),
 ('T09','RACE_QUOTA','TR_RQ','SKU01','C_B',200,100,1000,0,10);
INSERT ac09.RaceGate VALUES
 ('RACE_GRANT','T09','RACE_GRANT',1,80,0),
 ('RACE_QUOTA','T09','RACE_QUOTA',80,1,80);
SELECT 'RACES_READY';
