# SQL-01 — Bất biến, khóa logic và điều kiện kiểm chứng AC-03

**Phạm vi:** [Logical ERD](logical-erd.md) cho AC-03; **DESIGN_CANDIDATE / MODEL_ONLY / NOT_RUN**. Các ràng buộc dưới đây là yêu cầu cho physical schema và transaction SQL-02, **chưa phải kết quả test**. Nguồn chính: [BR](../../business/business-rules.md), [công thức](../../business/calculations.md), [SOP-04](../../business/workflows/mixed.md), [AC-03 oracle](../../business/reference-data/expected-results/golden-oracles.json).

## 1. Tập bất biến phải luôn đúng

| ID | Bất biến có thể assert | Nguồn | Chiến lược enforce ở SQL-02 |
|---|---|---|---|
| I-01 | FK và quyền truy cập không xuyên tenant; đúng **một seller thương mại chính/tenant** trong MVP, Customer chịu AR | BR-01/02 | Composite FK tenantId+ID; unique seller-per-tenant; auth/scope precondition của command; test negative cross-tenant (FK không thay auth) |
| I-02 | A Confirm tạo A hold nhưng **không** AR, revenue, COGS hay giảm hàng vật lý | BR-03 | Chỉ RIGHT_POSTING +40, snapshot A; test T0 không có Delivery/AR/COGS |
| I-03 | Cho mọi SKU/location: onHandEligible ≥ tổng quyền A/B (cùng scope) ≥ 0; A/B placement không chồng | BR-04/06 | Entitlement IDs A hoặc B XOR; transaction khóa source location/buckets khi cấp quyền; right-position reconcile với physical qty; constraint non-negative trên projection |
| I-04 | A hold = grantedA − deliveredA − releasedA; B quota = grantedB − soldB − releasedB; mỗi consumption chỉ từ **đúng pool** | BR-03/04/11 | RIGHT_POSTING nguồn + vị trí; atomic check-and-decrement dưới khóa; FK right từ delivery/manifest; test B31 reject |
| I-05 | MAIN→TRIP và TRIP→MAIN không làm đổi **tổng stockQty/stockValue** của tập location, không tạo AR/COGS/receipt | BR-04/07 | Paired STOCK_POSTING legs trong một source event/transaction; delta tổng bằng 0; test T1 và T6 |
| I-06 | openingQty + inboundExternal − delivered = onHandAllLocations; không âm từng physical location. “soldQty” đếm DeliveryLine **thực giao**, không đếm load/retry | BR-03/04 | STOCK_POSTING và DELIVERY_LINE; check non-negative dưới lock; compare từng checkpoint |
| I-07 | openingStockValue + inboundExternalValue − COGS = sum stockValue (trong AC-03 không có adjustment/return khách). Transfer không sinh COGS; delivery COGS dùng cost snapshot nguồn | BR-07 | COGS_EFFECT chỉ từ DELIVERY_LINE; moving-average theo SKU×location, lock qty/value cùng lúc; reconcile | 
| I-08 | Tổng baseQty của từng A_ORDER_LINE đã giao ≤ confirmedBaseQty; A held không dùng để bán B, kể cả sau unload | BR-03/04 | Lock A order line + reservation; source FK / remaining; kiểm tổng + concurrency |
| I-09 | B command **atomic**: delivery, B quota, stock/cost, AR, confirmed receipt/allocations, custody và grant cùng commit/cùng rollback | BR-11/12/13 | Một transaction; idempotency envelope; fault-injection trong SQL-02/03A |
| I-10 | Với B: P ≥ 0, R ≥ 0, C ≥ 0, R+C ≤ P; creditExposure = P−R−C ≥ 0; grantRemaining = granted−consumed−released ≥ 0 | BR-12 | Decimal exact; confirmed receipt mới là R; CustomerCredit phải reserved; lock grant và credit; không suy UNSET=APPROVED |
| I-11 | AR theo open item = grossDue − phân bổ confirmed hợp lệ − các adjustment được duyệt ≥ 0. A Confirm/load/handover không tạo/trừ AR | BR-03/13/14 | FK allocations tới receipt confirmed và item; transaction lock item/credit; phép cân tại T3–T5 |
| I-12 | Receipt cash được **verified thực** mới tạo custody; bank pending/ảnh chuyển tiền không là receipt confirmed hay cash | BR-12/13 | Receipt verification state + source; check pending không được allocate; cash-only effect vào custody |
| I-13 | OFFERED không đổi ledger. CashierAccepted(x) ⇒ custody−x, fund+x cùng transaction, **không trừ AR lần hai**; cashier độc lập người giao khi policy yêu cầu | BR-13/14 | Handover state + acceptance source, maker/checker authorization; paired ledger effects; test T5 |
| I-14 | Cùng tenant/producer/commandId + canonical payload giống: **một hiệu ứng**; identity cũ/payload khác: CONFLICT; các ledger effect có source line duy nhất theo vai/leg | BR-16 | Unique command key/hash; unique effect ID/role/ordinal; replay result, không re-post |
| I-15 | Các snapshot price/UoM/ShipTo/terms/cost sau mốc nguồn không đổi vì master đổi; dueDate A theo ngày giao và N terms snapshot approved | BR-02/07/08/10 | Snapshot tại chứng từ, source cost version; không dynamic master join; synthetic terms phải khai rõ |
| I-16 | T6 trả hàng **xe còn dư** (không phải Customer Return): A15 giữ tại MAIN, B10 release, total returned25; không quarantine hay giảm AR/COGS | BR-04/20; AC-03 | Stock transfer A15+B10 + RIGHT_POSTING move A/release B trong cùng boundary; test physical/right balance |

**Cân cho AC-03:** tổng stockQty + soldQty = **100**; tổng stockValue + COGS = **1.000** (unitless), ở từng T0..T6. Đây là quan hệ suy ra từ fixture có **không inbound/outbound khác**, không phải công thức tổng quát cho return, adjustment, shrinkage, sales tax hay accounting. Không dùng số liệu AC-03 như rule mặc định tenant khác.

### Bất biến không chỉ kiểm ở cuối

- **Không âm tại commit:** physical qty/value trong trường hợp AC-03; quyền theo từng location và grant/AR/custody; không cho hai command cạnh tranh cùng vượt quyền.
- **Right placement phải có hàng vật lý hợp lệ tại nơi đó:** ΣA_rightPlacement + ΣB_rightPlacement ≤ onHandEligible(location, SKU) (nếu cần lot, mở rộng cùng scope). Không trừ các right lại lần hai khi đã chuyển lên xe.
- **Giá trị balance phải đối chiếu nguồn:** trong slice, positive stock value ở mỗi location với unit cost10; trong thực tế có rounding/residual cần policy riêng, không mặc định stock value phải luôn tỷ lệ cố định.
- **Một lần giao có nguồn:** DeliveryLine / SourceLine không được ghi trùng. Trong A, partial delivery có thể nhiều lần nhưng cùng một line giao không lặp effect; B một SaleDeliveryReceipt chốt source event duy nhất.
- **Approval không thể là DB CHECK:** seller mode admission, quyền writer theo Trip, cashier accept, terms và chính sách credit cần kiểm trước khi post, audit và chứng cứ phù hợp; physical prototype không chứng minh security trên toàn ứng dụng.

## 2. Khóa logic, unique và cardinality dự kiến

Định dạng identity ở đây là **đề xuất hợp đồng logic**, không chỉ định GUID/sequence hay migration tool.

| Đối tượng | Candidate key / unique | Điều kiện thêm |
|---|---|---|
| Tenant và seller | TENANT(tenantId); LEGAL_SELLER(tenantId, sellerId), UNIQUE(tenantId) cho seller chính | TenantId bắt buộc trên toàn bộ nguồn, projection và FK |
| Customer/Outlet/Assignment | (tenantId, customerId), (tenantId, outletId), (tenantId, linkId) | Outlet relationship có validFrom/To, không bắt Outlet trên chứng từ |
| SKU/UoM | (tenantId, skuId), (tenantId, skuId, uomCode, effectiveVersion) | Một base UoM hợp lệ tại mốc source; factor>0, step>0 |
| Location/Trip | (tenantId, locationId), (tenantId, tripId) | Trip-custody location gắn Trip, MAIN có thể chung nhiều chuyến nhưng quyền lượng không trùng |
| A Order/Line | (tenantId, orderId), (tenantId, orderLineId), FK (tenantId, orderId) | Confirmed qty>0; giao partial không vượt theo source |
| AReservation | (tenantId, reservationId), unique sourceLine của lần grant | Một order line có thể nhiều reservation (không unique orderLine+trip toàn cục); heldQty derived |
| BQuota | (tenantId, quotaId), unique sourceLine của lần grant | Không unique cứng (tripId,skuId) nếu có nhiều nguồn grant; quyền active tách entitlement |
| BGrant | (tenantId, grantId), unique sourceLine cấp grant | Scope hợp lệ trên grant; không giả định grant chỉ per Customer |
| ManifestLine | (tenantId, manifestLineId), unique (tenantId, sourceLineId, effectRole) | XOR AReservation/BQuota; qty>0; each manifest source id stable |
| Sale/Delivery/Line | (tenantId, saleId/deliveryId/lineId); unique source effect identity | XOR AOrderLine/BSaleLine trên DELIVERY_LINE; businessDate/ShipTo snapshot required |
| BusinessEvent/SourceLine | (tenantId, producerId, commandId) unique + payloadHash; (tenantId, eventId, sourceLineId) | Same identity+hash replay; khác hash conflict; accepted/rejected khác với business effects |
| Stock/right/cost/financial effects | (tenantId, sourceLineId, effectKind, ordinal) unique; mỗi effect có own stable ID | Cho phép nhiều leg có ordinal khác nhau trong **cùng** source; FK từ effect→source luôn cùng tenant |
| StockCostBalance (projection) | (tenantId, skuId, locationId) | Với lot/quality về sau: eligibility theo lot/quality là chiều khác; cost vẫn theo SKU×location |
| RightPosition (projection) | (tenantId, rightKind, rightId, locationId) | rightKind A/B XOR target; count per location không âm |
| ReceivableOpenItem | (tenantId, openItemId), unique source delivery line + obligation role | Có Customer, dueDate nguồn; A/B theo DeliveryLine (không theo order/header) |
| Receipt/Allocation | (tenantId, receiptId), (tenantId, allocationId), unique source effect | **Không unique receiptId+openItemId**: cho phép phân bổ nhiều lần có source khác |
| Handover/Acceptance | (tenantId, handoverId), (tenantId, acceptanceId), unique acceptance source effect | Cho phép accept từng phần khi có source/authorization, không post hai lần |

Nếu SQL-02 chọn composite FK (tenantId, entityId), cần tránh FK chỉ dùng ID không tenant; đối với loại chứng từ có CustomerId và TripId phải kiểm cùng tenant ngay cả khi ID trùng text ở tenant khác. UNIQUE và CHECK không thay được serialization khi cùng trừ quota/grant/stock.

## 3. Kiểu số chính xác và kiểm tra miền

**Phương án SQL Server 2017+ cho SQL-02, chưa phải quyết định production:**

| Giá trị | Candidate type | Ràng buộc |
|---|---|---|
| baseQty, deltaQty, granted/consumed/released | DECIMAL(19,6) | >0 với source positive; ký dấu cho ledger; non-negative ở projection sau transaction |
| unitPrice, unitCost snapshot | DECIMAL(28,10) | ≥0, source version và rounding profile; không dùng FLOAT/REAL |
| stockValue, COGS, salePayable, AR, receipt, grant, custody, fund | DECIMAL(28,6) | ≥0 với amount nguồn hợp lệ; ledger có signed deltas; overflow explicit check và cast trước cộng/nhân |
| conversionFactorSnapshot, unitStep | DECIMAL(28,10) | factor>0, step>0; baseQty phải chia hết step theo quy tắc SKU |
| businessDate/dueDate | date theo seller local business calendar | Không tự lấy ngày thiết bị; N chỉ chấp nhận nếu policy APPROVED |
| ID/source/hash | stable text/UUID hoặc native keys phù hợp | Scope tenant, producer và source; canonical payload hash không phụ thuộc JSON property order |

AC-03 dùng số nguyên trừu tượng (100 đơn vị @ cost1.000, price15), không áp một currency rounding rule VND. Scale nêu trên là **candidate capacity** cần stress/rounding tests trước physical decision. Định nghĩa rounding policy thật, currency treatment, lot/FEFO và source-cost adjustment sẽ được hoàn thiện ở các slice liên quan, không tự “chốt” từ oracle AC-03.

**CHECK có thể enforce ngay:** factor/step dương, source qty/amount hợp lệ, trạng thái kind thuộc tập, XOR source FK, source/effect unique, physical/projection qty non-negative sau transaction. **Logic cần locking/test:** available sau khi trừ A/B, consumed ≤ granted, C/R confirmed, credit grant non-negative, AR allocation ≤ openItem remaining, maker/checker, atomic transfer/sale/accept.

## 4. Negative/fault checklist đưa vào SQL-02

| Test ID | Đầu vào/hành động | Hậu điều kiện cần assert |
|---|---|---|
| N-01 | B Sale qty31 khi BQuota chỉ30 (T2) | Reject với lý do quota; mọi cột oracle bằng T1; không Delivery/Stock/AR/Receipt/COGS/Grant/Custody effect; audit reject có thể tồn tại |
| N-02 | B cố dùng A hold khi BQuota không đủ | Không consume A; quota và kho không âm, không partial sale |
| N-03 | Thử load/quyền vượt available hoặc tiêu A vượt confirmed/remaining | Reject toàn transaction, không movement/right posting dở |
| N-04 | Gửi lại cùng commandId+payload | Kết quả y hệt, không tăng số effects; khác payload cùng id => CONFLICT |
| N-05 | Nhận bank pending hoặc ảnh chuyển khoản làm R; thử negative/over allocation | Không được coi confirmed; R không tăng; grant/AR không bị ghi sai |
| N-06 | OFFER nộp quỹ 200 nhưng chưa cashier ACCEPT | Custody còn200, fund0, AR giữ nguyên |
| N-07 | Handover accept vượt custody hoặc không có quyền/khác tenant | Reject/record case theo trạng thái đời thực; không sinh ledger dở |
| N-08 | Cross-tenant source FK hoặc location/trip lệch tenant | Reject trước ledger, không rò dữ liệu qua lookup và không create effect |
| N-09 | Fault sau vài effects của B sale hoặc paired transfer | Rollback đủ effect đã thử ghi; không commit partial |
| N-10 | T6 unload B10 nhưng cố giữ BQuota10 hoặc release A15 | Không được coi checkpoint T6 PASS; right positions không khớp oracle |

SQL-02 gate chính bắt buộc bao gồm N-01, N-03, N-04 và N-09 ở mức tối thiểu theo roadmap; N-08 cần thực thi khi schema support. **Kiểm thử hai session tranh quota/grant thật thuộc SQL-03A**, không gọi một test tuần tự là concurrency verified.

## 5. Tiêu chí review và giới hạn

- Cần đối chiếu **13 cột × 7 checkpoint** AC-03 qua [ac03-mapping.md](ac03-mapping.md) và oracle **nguyên trạng**.
- Cần review rằng các *right placement* rời khỏi TRIP khi unload, A hold15 vẫn MAIN, B quota0; không có thuộc tính “xe còn hàng” ngầm thay A hold.
- Không dùng SQL-01 để chấp nhận invoice/tenant admission, quyền tài khoản/credit policy, accounting, cutover hay go-live.
- **OPEN QUESTION:** scope grant B, N ngày terms synthetic, phương thức thanh toán của rejected B31, A reservation sau Trip close và rounding profile. Xem [logical-erd.md §7](logical-erd.md).
