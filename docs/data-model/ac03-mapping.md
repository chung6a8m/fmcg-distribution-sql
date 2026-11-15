# SQL-01 — Mapping AC-03 T0..T6 → nguồn, effect và 13 oracle columns

**Trạng thái:** MODEL_ONLY / NOT_RUN — đây là thiết kế cho SQL-02, **không phải actual SQL output**.

**Ground truth duy nhất:** [business/reference-data/expected-results/golden-oracles.json#AC-03](../../business/reference-data/expected-results/golden-oracles.json), kết hợp [AC-03 case](../../business/reference-data/scenarios/business-cases.json), [AC-03 acceptance](../../business/acceptance.md), [SOP-04](../../business/workflows/mixed.md) và [công thức](../../business/calculations.md). Bảng oracle có **7 checkpoints và đúng 13 cột**; expected phải được harness SQL-02 đọc trực tiếp từ JSON gốc hoặc derive xác định, không copy và sửa một bộ expected riêng.

## 1. Opening độc lập và luồng nguồn

Fixture AC-03 là một “sổ nhỏ” độc lập, không dùng mặc định seed.json của cả repository: **MAIN 100 đơn vị, cost value1.000, unit moving average10, giá bán15**, A hold40, B quota30, B grant100; không có delivered sale/AR/custody/fund trước T0. **Đơn vị giá trị là SYNTHETIC_UNITLESS; invoiceEligible=false.** Không suy VAT, currency, credit policy, seller legal status hay N ngày terms thực từ các con số này.

Các source cần có định danh bền trong fixture SQL-02:

1. Opening source cho StockLocation MAIN, SKU hợp lệ trong tenant và qty/value +100/+1.000.
2. AOrder Confirm source: AOrderLine qty40, price snapshot15 và AReservation grant40 tại MAIN; Customer chịu nợ và ShipTo snapshot phải xác định trong fixture, không lấy địa chỉ master hiện tại khi giao.
3. BQuota grant source30 theo Trip/SKU, đặt quyền B tại MAIN; BCreditGrant source100 theo scope được chấp nhận cho simulation, không thay quyền hàng.
4. Manifest source load A40+B30 cùng giá vốn từ MAIN sang TRIP.
5. B31 command source bị reject; giữ identity/reason, không post effect. Không biến rejected attempt thành B sale.
6. B20 SaleDeliveryReceipt source: qty20, P300, cash receipt confirmed200 và allocation200; B grant consumed100.
7. A Delivery source: qty25, P375, chưa thu; dùng giá/terms từ AOrder Confirm, AR riêng.
8. Cash handover source OFFER và source Cashier ACCEPT200; OFFER không có ledger; ACCEPT có custody/fund effects.
9. Trip unload/return stock source: A15+B10 trở về MAIN, B quota release10, A held15 còn hiệu lực. Không là Customer Return.

**Nguồn và effect khác nhau:** ví dụ B20 có một command envelope/durable business event, nhiều SOURCE_LINE hoặc effect roles (stock leg, right consumption, cost, receivable, receipt, allocation, custody, grant). Mỗi effect có ID riêng nhưng cùng trace về B20; chỉ ghi một lần khi retry.

## 2. Ánh xạ từng checkpoint

| Checkpoint | Command, source và mutation được phép | Assert/postcondition theo oracle | Negative / không được suy |
|---|---|---|---|
| **T0** | Opening MAIN +100/value+1.000; ConfirmA +40 right position MAIN; GrantBQuota +30 right position MAIN; GrantBCredit +100. Tạo AOrder snapshot, Customer/ShipTo context | mainQty100, mainCost1000; tripQty/tripCost/soldQty/cogs=0; aHold40, bQuota30; arA/arB/custody/fund=0 | A Confirm và quyền cấp **không** tạo stock issue ra khách, AR, COGS hay sale |
| **T1_LOAD** | Manifest 2 lines A40/cost400 và B30/cost300; một StockMovement transfer có 2 stock posting legs MAIN−70/−700, TRIP+70/+700; right placements MAIN−40 A/−30 B, TRIP+40 A/+30 B | mainQty30/tripQty70; mainCost300/tripCost700; soldQty0/cogs0; aHold40/bQuota30; AR/custody/fund0 | Transfer không là revenue, sale, receipt hay AR; không giữ quyền song song ở MAIN và TRIP |
| **T2_REJECT** | Try B31, nhưng B quota available30, **reject trước ledger**, optional audit source/command result | **Tất cả 12 giá trị số** phải bằng T1_LOAD; step là T2_REJECT | Không có bán31, không âm B, không partial stock/AR/receipt/COGS/grant/custody; không ăn A40 |
| **T3_B20** | B SaleDeliveryReceipt qty20 @ price15 → P300; StockMovement issue và TRIP stock−20/value−200, right B−20, COGS+200; AR open item gross300, receipt cash200 confirmed + allocation200; custody+200; credit grant consumption100 | tripQty50, tripCost500; soldQty20/cogs200; bQuota10; arB100/custody200; mainQty30/mainCost300; aHold40, arA/fund0 | R=200 chỉ vì verified cash; AR_B=300−200=100. Không trừ B grant300 hay trừ cả “held+AR” |
| **T4_A25** | DeliverA qty25 @ confirmed price15 → P375; StockMovement issue và TRIP stock−25/value−250; A right−25; COGS+250; AR_A item gross375 (dueDate per approved terms snapshot) | tripQty25/tripCost250; soldQty45/cogs450; aHold15, bQuota10; arA375/arB100; custody200/fund0 | Không consume B quota, không lấy terms mới từ Customer, không ghi receipt chưa thu |
| **T5_HANDOVER** | OFFER tiền nộp (không effect), cashier ACCEPT200 có source; custody−200 và FUND+200 cùng transaction | custody0/fund200; mọi số stock, soldQty, cogs, holds, quota, AR không đổi so T4 | OFFER chưa đủ; handover không làm AR_B giảm100 lần nữa |
| **T6_RETURN** | Trip unload stock A15+B10 (25 units/value250) về MAIN: một StockMovement unload có 2 stock posting legs MAIN+25/+250, TRIP−25/−250; A placement TRIP−15/MAIN+15; B placement TRIP−10 bằng RELEASE source; BQuota remaining0 | mainQty55/mainCost550; tripQty/tripCost0; soldQty45/cogs450; aHold15/bQuota0; AR_A375/AR_B100; custody0/fund200 | Không phải khách trả hàng, không reverse COGS/AR; không release A15 và không để B10 là quota active |

**Điểm T2:** Để test riêng ràng buộc BQuota (31 > 30), SQL-02 cần chuẩn bị các input thanh toán/quyền khác của attempted sale sao cho **không** bị lỗi grant/receipt trước; baseline không định nghĩa chi tiết B31 payment. Ghi rõ input bổ sung là **synthetic test setup**, không sửa oracle hay tự kết luận B31 đã từng bán/giao thực.

## 3. Duy nhất 13 cột: provenance và công thức derive

| Oracle column | Định nghĩa phép đọc actual ở mỗi checkpoint | Source/effect sở hữu |
|---|---|---|
| **step** | Tên checkpoint theo đúng thứ tự từ JSON oracle, không phát sinh từ timestamp thiết bị | SQL-02 harness step runner |
| **mainQty** | ΣdeltaQty của StockPosting ở location MAIN, SKU thuộc AC-03 | Opening, manifest transfer, unload |
| **tripQty** | ΣdeltaQty của StockPosting ở TRIP_CUSTODY location của Trip | Manifest, B/A deliveries, unload |
| **soldQty** | ΣbaseQty các DeliveryLine **đã giao thực** A+B, không đếm A Confirm, load, rejected attempt, resend | B DeliveryLine và A DeliveryLine |
| **mainCost** | ΣdeltaStockValue của StockPosting ở MAIN (đơn vị value synthetic), exact decimal | Opening, manifest transfer, unload |
| **tripCost** | ΣdeltaStockValue của StockPosting ở TRIP (exact decimal) | Load, delivery issue cost, unload |
| **cogs** | ΣcostAmount của COGS_EFFECT cho DeliveryLine A/B; load/unload không có | CostBasisSnapshot của B20/A25 delivery |
| **aHold** | ΣsignedQty của RIGHT_POSTING kind=A ở **mọi location** (grant−consume−release) | AReservation + A Delivery + vị trí load/unload |
| **bQuota** | ΣsignedQty của RIGHT_POSTING kind=B ở **mọi location** (grant−consume−release) | BQuota + B Sale + T6 RELEASE |
| **arA** | ΣopenItem.grossDue(A) − ΣapprovedAllocationToItem(A) (và adjustments nếu có, AC-03 không có) | DeliveryLine A25 + AR open item |
| **arB** | ΣopenItem.grossDue(B) − ΣconfirmedAllocationsToItem(B) | B20 DeliveryLine AR300 + receipt allocation200 |
| **custody** | ΣsignedAmount CUSTODY_EFFECT cash theo Trip/custodian (AC-03: +cash receipt−cashier accepted) | Cash receipt B20 và cashier accept T5 |
| **fund** | Σamount FUND_EFFECT ghi từ cashier accepted handovers (AC-03 opening0) | Cashier acceptance T5 |

Không tính **aHold** hoặc **bQuota** bằng cách trừ chúng khỏi physical stock lần nữa. Chúng là quyền trên phần hàng **đang nằm trong** mainQty/tripQty. Không tính custody từ AR; không tính AR từ stock cost; không tính fund từ handover OFFERED.

### Quy tắc reconciliation giữa sổ

- **Stock:** mainQty + tripQty + soldQty = 100, bởi opening100 và không có inbound/outbound khác trong AC-03. T1 và T6 là internal transfer, không đổi tổng hàng còn + đã giao.
- **Value:** mainCost + tripCost + cogs = 1.000, vì opening value1.000 và cost issue200+250 theo cùng cost basis; không có adjustment khác.
- **Rights at location:** T1 TRIP có A40+B30=70 ≤ tripQty70; T3 A40+B10=50; T4/T5 A15+B10=25; T6 MAIN có A15+B0 ≤ mainQty55, TRIP0.
- **AR and cash:** B payable300 = AR B100 + confirmed receipt applied200. A payable375 = AR A375 + applied0. Cash receipt200 = custody200 + fund0 trước handover, = custody0+fund200 sau accept.
- **Credit:** B grant initial100 = consumed exposure100 + remaining0 tại T3 (không có release nguồn khác). Grant khác BQuota.
- **T2:** trạng thái nghiệp vụ và tất cả 12 numeric fields bằng T1; rejected command có thể được audit mà không tạo ledger effect.

## 4. Hợp đồng đầu vào/đầu ra cho SQL-02

**Input độc lập:** một schema/DB scratch có guard; fixture opening và grants T0 rõ tenant/trip/sku/customer/ship-to, snapshots A/B đủ tính toán; oracle đọc gốc đúng thứ tự 7 checkpoints. Seed.json **chỉ** tham khảo danh mục, không phải opening AC-03. Oracle **không** thay khi bổ sung trường source/actor/terms synthetic cần để vận hành command.

**Actual:** snapshot query sau **mỗi** checkpoint lấy đúng 13 tên cột trên; giữ số decimal chính xác (không FLOAT), so numeric theo giá trị, so step theo string; hiển thị expected/actual/diff; fail → exit code khác0. Thêm assert effect lineage/negative riêng, không chỉ khớp tổng cuối.

**Kết quả SQL-02 phải lưu:** command một bước trên Windows, SQL Server version/compatibility, DB guard test (refuse unsafe/reset foreign DB), SQL tests thật, logs + testRunId, source ref, trạng thái PASS/FAIL/BLOCKED/NOT_RUN. SQL PASS tại local **không** sửa trạng thái MODEL_ONLY trong business oracle và không chứng minh E2E/app/go-live.

## 5. OPEN QUESTION / review disposition cần ghi

| ID | Khoảng trống trong Business Baseline AC-03 | Đề xuất tối thiểu, **chưa tự phê duyệt** |
|---|---|---|
| OQ-01 | AOrder Confirm cần approved N/terms, nhưng AC-03 không nêu | Cho SQL-02 dùng terms snapshot **synthetic explicit approved** để tính dueDate; không gán mặc định UNSET→0; không thay oracle |
| OQ-02 | Payment breakdown/reject reason của attempted B31 chưa có | SQL-02 tạo test input đủ điều kiện ở phần credit/payment để isolate BQuota=30, log reason; không ghi receipt dù intent có offer |
| OQ-03 | B grant100 scope/counterparty chưa đủ trong case | Grant có grantId, tripId, owner/scope và source; chưa unique cứng theo Customer hoặc writer |
| OQ-04 | A hold15 còn ở T6 dù Trip stock0 | Right placement chuyển về MAIN và giữ AReservation; cần quyết định reassignment/Trip close status sau đó |
| OQ-05 | Currency/rounding/lot/expiry/invoice không đầy đủ | Với AC-03 chỉ dùng decimal exact, baseQty fixed/giá fixed, synthetic invoiceEligible=false; không chứng minh VAT, legal seller, FEFO |

**Review gate SQL-01:** từng checkpoint truy được command→nguồn→các effect→formula của 13 cột→ít nhất một ràng buộc enforce. OQ có chủ sở hữu/disposition trước khi SQL-02 chốt schema; không suy OQ là quyết định nghiệp vụ mới.
