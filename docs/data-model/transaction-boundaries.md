# SQL-01 — Transaction boundaries và concurrency contract cho AC-03

**Trạng thái:** DESIGN_CANDIDATE / MODEL_ONLY. Mô tả **đơn vị hiệu lực nghiệp vụ**, không quy định phải dùng stored procedure hay application service ở production. SQL-02 có thể dùng T-SQL để mô phỏng, SQL-03A sẽ kiểm hai kết nối tranh quyền thật. Đọc cùng [logical-erd.md](logical-erd.md) và [invariants.md](invariants.md).

## 1. Bảng command → atomic boundary

| Command | Preconditions và quyền logic | Một transaction phải ghi cùng nhau | Không được phát sinh |
|---|---|---|---|
| **T0 / SeedOpening + ConfirmA + GrantBQuota + GrantBCredit** (fixture setup bằng các nguồn rõ ràng) | Tenant/Seller giả lập; nguồn opening; SKU/UoM/location; A terms snapshot hợp lệ ở mức fixture; Warehouse có quyền cấp | Opening stock MAIN +100/value1000; A order Confirm/hold40 với right placement MAIN; B quota30 placement MAIN; B credit grant100 với source ID; tổng rights70 ≤ stock100 | Stock move ra khách, COGS, AR, receipt/custody/fund. Không coi toàn bộ T0 bắt buộc là **một** transaction business ngoài fixture |
| **T1 / LoadManifest A40 + B30** | Trip, AReservation40, BQuota30 và manifest được phép; MAIN tồn/giá trị đủ, quyền đúng nguồn, TripCustody location đúng trip | Một manifest release/load: một StockMovement transfer với MAIN −70/−700, TRIP +70/+700 (2 stock posting legs); A right MAIN−40/TRIP+40; B right MAIN−30/TRIP+30; source cost snapshot | AR, COGS, receipt, revenue, grant exposure |
| **T2 / BSaleDeliveryReceipt qty31** | B quota đang30; validate quota trước post (không nhận thay bằng A). Các preconditions khác phải hợp lệ hoặc được kiểm độc lập khi kiểm quota | **Reject**. Có thể lưu command rejection/audit durable với source/payload/reason; ledger effects = 0 | B sale, delivery, stock, right consume, AR, receipt/credit, COGS, grant consume, custody |
| **T3 / BSaleDeliveryReceipt qty20, P300, cash confirmed200** | Writer được gán cho Trip; B_ONLINE admission/Invoice channel nếu giao dịch **thực**; B quota≥20, TRIP qty≥20; credit grant remaining≥100; cash receipt verified | Trong **cùng** transaction: B sale/line + Delivery/Line; StockMovement issue + TRIP stock posting −20/value−200; B right−20; COGS+200; AR openItem gross300; Receipt cash200 + Allocation200 vào item; Custody+200; grant consume100; event/effect IDs duy nhất | Partial sale/receipt/cost, tách grant thành một bước commit khác, tạo AR âm hoặc dùng A hold |
| **T4 / DeliverA qty25, P375, unpaid** | A order Confirm; held A40 tại TRIP; chưa giao quá confirmed qty; Customer/ShipTo/terms snapshot hợp lệ; credit terms cho nợ A phải approved ở fixture | Delivery/Line tham chiếu AOrderLine; StockMovement issue + TRIP stock posting−25/value−250; A right−25; COGS+250; AR openItem375 (dueDate per delivery từ terms snapshot) | Dùng B quota; ghi receipt giả; sửa Order Confirm và tính lại giá/terms từ master |
| **T5 / HandoverOffer → CashierAccept200** | Có custody cash200; OFFER từ người giao và **ACCEPT bởi cashier thực nhận** có authority độc lập; amount≤custody available | OFFER lưu trạng thái/source nhưng **không ledger**; riêng ACCEPT tạo acceptance source, custody−200 và fund+200, cùng transaction | Trừ AR/receipt lần nữa, giảm custody từ OFFER, tự ký nhận thay cashier |
| **T6 / UnloadRemaining A15+B10** | Xe có tổng25/value250; A placement15+B placement10 ở TRIP; manifest/return source hợp lệ; release B10 có nguồn, A hold giữ lại | Một StockMovement unload với hai posting legs TRIP−25/−250, MAIN+25/+250; A right TRIP−15/MAIN+15; B right TRIP−10 qua RELEASE (không chuyển B entitlement sang MAIN); B quota remaining0 | COGS/AR/receipt mới; Customer Return/QA; tự release A15; auto-release B credit grant vì nộp quỹ |

**Giải thích B ở T3:** payable P=20×15=300; verified R=200, credit C=0; exposure=300−200=100. AR_OPEN_ITEM ghi gross300, RECEIPT_ALLOCATION ghi200, AR còn100. B grant khởi tạo100 chỉ còn0. Đây là một diễn giải ledger tách nguồn hợp lệ cho oracle, không phải ghi AR100 rồi lại trừ receipt200.

**Giải thích T6:** “trả hàng còn trên xe” là **Trip stock unload**, không phải khách hàng trả hàng sau bán; không giảm sale/AR/COGS. A15 chuyển quyền placement về MAIN; B10 chuyển hàng vật lý về MAIN như free stock và release quyền B. Trip với A hold còn phải có cách reconcile/reassign/record case trước khi quyết định trạng thái đóng cuối — không mặc định CLOSED sạch.

## 2. Transaction preflight, commit và audit

~~~text
Receive(commandId, producerId, tenantId, canonicalPayloadHash)
  -> kiểm tra command identity: same hash => trả durable outcome cũ;
                              different hash => CONFLICT (không effect)
  -> đọc phiên bản policy/actor/seller/trip/mode và source references
  -> khóa và kiểm đủ quyền lượng/stock/grant/AR/confirmed receipt
  -> kiểm business preconditions, snapshot, amount/baseQty/cost
  -> append BusinessEvent/SourceLine + tất cả ledger effects trong transaction
  -> update projection cân với events (nếu có), validate non-negative
  -> COMMIT cùng durable command result
       (bất kỳ lỗi => ROLLBACK toàn bộ business effects)
~~~

- **Source/event identity:** khóa logic (tenantId, producerId, commandId); payload hash dựa trên dạng chuẩn hóa ổn định. Mỗi effect có identity (sourceLineId, effectKind, ordinal) và FK same-tenant. “ACK đã lưu” khác “business ACCEPTED”/posted; pending dependency không bị đánh rơi khi mở rộng AC-11.
- **Replay:** command đã ACCEPTED, gửi lại giống payload không được tạo stock, AR, receipt, grant hay custody effect nữa. Command REJECTED với same identity/payload cũng trả outcome nhất quán; input sửa cần identity mới hoặc xử lý theo quy tắc command.
- **T2 reject:** log intent/reason có thể commit riêng theo chính sách audit mà vẫn bảo đảm mọi **business ledger effect** không đổi; không được viết một phần sale rồi “bù ngược” và gọi là reject sạch.
- **Pre- vs post-event:** thiếu quota/grant/authorization trước giao thì reject intent. Hàng/tiền **đã thực trao** ngoài hệ thống là một occurred-event/case riêng có nguồn, không xóa sự thật để giả trạng thái sạch (BR-11/15/16).
- **B admission:** AC-03 là simulation synthetic với invoiceEligible=false. Không dùng kết quả SQL pass để cấp B_ONLINE thật; runtime B_ONLINE vẫn đòi seller/channel/mode admission riêng (BR-18).

## 3. Điểm cần serialization

| Resource bị tranh chấp | Nếu không khóa sẽ sai gì | Cách kiểm cụ thể |
|---|---|---|
| SKU×StockLocation (qty/value) | Hai load/giao đồng thời cùng tiêu on-hand, negative qty hoặc costValue drift | Khóa nguồn vị trí và vị trí đích khi transfer; tính moving average/issued cost từ snapshot đã khóa |
| A_ORDER_LINE / A_RESERVATION | Hai Delivery A cùng tiêu phần chưa giao hoặc A hold bị B lấy | Check confirmed/remaining và RightPosition trước consume; update atomically |
| B_QUOTA / RightPosition | Hai Sale B cùng bán quota80 từ quota100 | Atomic consume theo version/lock; **SQL-03A** chạy 2 session thật |
| B_CREDIT_GRANT | Hai Sale cùng dùng grant100 với exposure80 mỗi lệnh | Reserve/consume dưới transaction + concurrency; **SQL-03A** chạy 2 session thật |
| RECEIPT / CUSTOMER_CREDIT / AR_OPEN_ITEM | Double-allocation, credit âm, AR âm, receipt chưa confirmed vẫn giảm debt | Lock source credit, item, verified state; tổng allocation không vượt nguồn/AR |
| CUSTODY / HANDOVER | Hai cashier accepts cùng trừ số đã nộp, hoặc OFFER trừ sớm | Acceptance identity & amountRemaining dưới lock; paired custody/fund effects |
| BUSINESS_EVENT identity | Retry sau lost ACK ghi đôi | Unique tenant+producer+commandId và transaction lưu result cùng effects |

**Thứ tự lock khuyến nghị để SQL-02/03 giảm deadlock:** sau identity của command, khóa Trip/assignment; sau đó AReservation/BQuota và grant/credit source theo khóa ổn định; tiếp đến stock positions theo (tenant, SKU, locationId) tăng dần; sau đó open items/receipt/custody theo ID tăng dần. Phải dùng cùng thứ tự trên các command giao nhau, tránh khóa entitlement ở sale nhưng stock trước entitlement ở unload. Đây chỉ là hướng thiết kế, còn phải kiểm execution plan/isolation và test concurrent **thực**.

Khi engine SQL-02 dùng cached StockCostBalance/RightPosition, logic phải sửa cache và append posting **trong cùng transaction**; không được cho cache lệch journal qua crash. Sử dụng constraints + row lock hoặc compare-and-swap đều có thể hợp lệ nếu chứng minh bằng test; **không** tự khẳng định một mức isolation đủ khi chưa chạy.

## 4. Chia đôi quyền và nghĩa vụ không được gộp

- AReservation/BQuota là **quyền hàng**, không phải hai location và không phải hai lần trừ on-hand. Grant B là **quyền tín dụng**, không phải CustomerCredit (tiền khách dư), và không phải AR.
- Stock movement là quantity/value đang giữ, COGS chỉ xuất ở Delivery; transfer không bán. Return unload xe không phải Customer Return vào quarantine.
- Receipt được verified và phân bổ tạo giảm AR; cash receipt đồng thời tăng custody. Handover cashier accept chỉ chuyển custody sang fund, không thu Customer hay giảm AR thêm lần nữa.
- Sale/Delivery có sourceLine riêng để invoice/accounting hook sau này; chính SQL-01 không quyết định provider legal, external API, status POSTED hay tenant Go-Live.
- A businessDate dùng seller-local calendar và terms snapshot; receipt/handover có occurredAt và recordedAt riêng để audit, không tin giờ thiết bị tuyệt đối.

## 5. Test plan và quyết định còn mở

**SQL-02 phải kiểm:** 13 oracle columns × 7 steps, T2 trước/sau giống nhau, no side effect (ngoại trừ audit reject), transfer qty/value0 netto, B operation fault rollback, retry identity, A/B bounds, custody/fund cashier accept, wrong DB guard riêng theo roadmap. SQL-03A mới xác nhận hai session tranh BQuota và grant (độc lập) cùng fault/retry sâu hơn.

**OPEN QUESTION SQL-02:** (1) bản synthetic A terms N/approved source; (2) B31 receipt/grant test input để isolate quota; (3) scope grant B và approval; (4) cách chuyển A held15 sau Trip close; (5) scale/rounding policy ngoài AC-03. Xem [ac03-mapping.md](ac03-mapping.md) để trace từng checkpoint. Không tự hợp thức hóa các điểm thiếu bằng default business.
