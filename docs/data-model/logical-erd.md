# SQL-01 — Logical ERD cho AC-03 Mixed A+B_ONLINE

- **Trạng thái:** DESIGN_CANDIDATE / MODEL_ONLY — chờ review; **không phải** physical schema, SQL test PASS hoặc Owner/Product Verification.
- **Phạm vi:** chỉ vertical slice AC-03, 7 checkpoint T0..T6. SQL-02 sẽ lựa chọn cách lưu/projection và dựng DDL tối thiểu.
- **Nguồn cố định:** [Business Baseline](../../business/README.md), [domain model](../../business/domain-model.md), [BR-03/04/07/11/12/13](../../business/business-rules.md), [calculations](../../business/calculations.md), [SOP-04](../../business/workflows/mixed.md), [AC-03](../../business/acceptance.md), [golden oracle](../../business/reference-data/expected-results/golden-oracles.json).
- **Fixture:** AC-03 có opening **riêng**, đơn vị giá trị **SYNTHETIC_UNITLESS**, **invoiceEligible=false**; không nhập chung [seed danh mục](../../business/reference-data/master-data/seed.json) và không mặc định là VND.

## 1. Nguyên tắc đọc mô hình

- **Master:** Tenant/Seller, Customer, SKU/UoM, StockLocation. Outlet tùy chọn, không phải Customer chịu nợ.
- **Snapshot chứng từ:** CustomerId chịu nợ, ShipTo (tên/địa chỉ/nguồn), UoM và hệ số quy đổi, giá/discount/tax profile, terms/policy version, businessDate. Snapshot bất biến sau mốc chốt; không join master hiện tại để tính lại.
- **Source/event:** AOrder Confirm, grant/hold, manifest load, B SaleDeliveryReceipt, A Delivery, receipt, handover accept, trip unload và opening. Mỗi sự kiện/dòng có identity, actor, nguồn, mốc thực tế và thời điểm ghi nhận.
- **Ledger effect:** stock quantity/value postings, quyền lượng A/B, COGS, khoản phải thu, phân bổ thu, grant tín dụng B, custody, quỹ. Mỗi effect định danh được source line; retry không sinh bản sao.
- **Derived balance:** tồn/vốn theo SKU × StockLocation, quyền lượng còn lại và vị trí đang được giữ, AR còn mở, grant còn lại, custody và quỹ. Projection có thể lưu cache nhưng **nguồn chân lý phải truy lại được từ event/effect**.

Các entity dưới đây là **logic**, không cam kết mỗi ô là một bảng vật lý. Sơ đồ tách hai phần để tránh ERD toàn hệ thống và tránh diễn giải nhầm ràng buộc XOR thành hai FK bắt buộc.

## 2. ERD — Chủ thể, chứng từ, phân quyền lượng

~~~mermaid
erDiagram
    TENANT ||--|| LEGAL_SELLER : "seller chinh"
    TENANT ||--o{ CUSTOMER : "quan ly"
    CUSTOMER ||--o{ CUSTOMER_OUTLET_LINK : "hieu luc"
    OUTLET ||--o{ CUSTOMER_OUTLET_LINK : "lien ket"
    TENANT ||--o{ SKU : "danh muc"
    SKU ||--|{ SKU_UOM : "quy doi"
    TENANT ||--o{ STOCK_LOCATION : "so huu"
    TENANT ||--o{ TRIP : "to chuc"
    TRIP o|--|| STOCK_LOCATION : "vi tri xe"
    TRIP ||--o{ TRIP_ASSIGNMENT : "nguoi theo vai"
    CUSTOMER ||--o{ A_ORDER : "ben chiu no"
    A_ORDER ||--|{ A_ORDER_LINE : "dong da confirm"
    A_ORDER_LINE ||--o{ A_RESERVATION : "giu rieng"
    TRIP ||--o{ A_RESERVATION : "cap A"
    TRIP ||--o{ B_QUOTA : "cap B"
    SKU ||--o{ B_QUOTA : "theo SKU"
    TRIP ||--o{ MANIFEST_LINE : "cap hang"
    A_RESERVATION o|--o{ MANIFEST_LINE : "nguon A"
    B_QUOTA o|--o{ MANIFEST_LINE : "nguon B"
    TRIP ||--o{ B_CREDIT_GRANT : "grant co nguon"
    CUSTOMER ||--o{ B_SALE : "ben chiu no"
    TRIP ||--o{ B_SALE : "ban theo xe"
    B_SALE ||--|{ B_SALE_LINE : "dong ban"
    TRIP ||--o{ DELIVERY : "giao thuc"
    DELIVERY ||--|{ DELIVERY_LINE : "dong giao"
    A_ORDER_LINE o|--o{ DELIVERY_LINE : "A source"
    B_SALE_LINE o|--o{ DELIVERY_LINE : "B source"
~~~

**Ràng buộc XOR:** mỗi MANIFEST_LINE thuộc **đúng một** A_RESERVATION hoặc B_QUOTA; mỗi DELIVERY_LINE thuộc **đúng một** A_ORDER_LINE hoặc B_SALE_LINE. Hai FK tùy chọn ở bản vẽ chỉ diễn đạt quan hệ, không có nghĩa được bỏ kiểm XOR. Một StockLocation loại TRIP_CUSTODY thuộc tối đa một Trip trong slice; kho MAIN không thuộc Trip.

### Danh mục logic tối thiểu

| Nhóm | Entity / identity (luôn có tenantId) | Dữ liệu/quan hệ không được thiếu |
|---|---|---|
| Chủ thể | TENANT, LEGAL_SELLER, CUSTOMER | Một seller thương mại chính/tenant; CustomerId chịu AR. Subscriber không phải Customer |
| Tùy chọn ngoài trọng tâm | OUTLET, CUSTOMER_OUTLET_LINK | Customer có 0..n Outlet theo khoảng hiệu lực; ShipTo trên chứng từ vẫn là snapshot độc lập |
| Danh mục | SKU, SKU_UOM | SKU base UoM, conversionFactor và unitStep hợp lệ; dòng chứng từ snapshot factor/step |
| Nơi tồn | STOCK_LOCATION | MAIN, TRIP_CUSTODY (theo chuyến); QUARANTINE chỉ cần khi mở AC-05 |
| Chuyến | TRIP, TRIP_ASSIGNMENT | TripId, vehicle, businessDate, actor/role/writer có hiệu lực; Driver không mặc nhiên có quyền writer |
| A | A_ORDER, A_ORDER_LINE | CustomerId + ShipToSnapshot; CONFIRMED, confirmedBaseQty, unitPrice/terms/policy snapshot; Confirm không phát sinh AR/COGS |
| Quyền A | A_RESERVATION | ReservationId, orderLineId, tripId, SKU, grantedQty; lượng đã giao / release phải có source; heldQty còn lại có thể chuyển vị trí |
| Quyền B | B_QUOTA | QuotaId, tripId, SKU, grantedQty; consumedQty/releasedQty theo source; không dùng lượng đã giữ cho A |
| Cấp xe | MANIFEST_LINE | ManifestLineId, tripId, SKU, poolType A/B, quyền nguồn (XOR), baseQty, cost transfer snapshot; load/unload không phải sale |
| B | B_CREDIT_GRANT, B_SALE, B_SALE_LINE | GrantId, phạm vi quyền/nguồn; SaleId, CustomerId + ShipToSnapshot, payable snapshot; B line gắn quota và giá |
| Giao thực | DELIVERY, DELIVERY_LINE | DeliveryId, CustomerId, businessDate, module A/B; source order/sale line XOR, baseQty, cost snapshot; có thể giao A nhiều đợt |

**Snapshot cụ thể:** A_ORDER khi Confirm giữ ShipTo, price/discount và terms policy version; DELIVERY giữ bản sao/ngữ cảnh ShipTo tại lần giao và tham chiếu terms snapshot nguồn để tính dueDate. B_SALE/DELIVERY khóa ShipTo, price/tax/UoM, payable, phần nhận thực và policy version tại transaction B. Không coi các snapshot này là quan hệ FK động vào địa chỉ/giá/terms master.

## 3. ERD — Source và các sổ hiệu ứng

~~~mermaid
erDiagram
    TENANT ||--o{ BUSINESS_EVENT : "nhat ky nguon"
    BUSINESS_EVENT ||--|{ SOURCE_LINE : "chi tiet nguon"
    SOURCE_LINE ||--o{ STOCK_POSTING : "tang giam kho"
    SOURCE_LINE ||--o{ RIGHT_POSTING : "di chuyen quyen"
    SOURCE_LINE ||--o{ COGS_EFFECT : "gia von ban"
    SOURCE_LINE ||--o{ GRANT_EFFECT : "han muc B"
    SOURCE_LINE ||--o{ CUSTODY_EFFECT : "tien giu ho"
    SOURCE_LINE ||--o{ FUND_EFFECT : "quy nhan"
    STOCK_LOCATION ||--o{ STOCK_POSTING : "ton va gia tri"
    SKU ||--o{ STOCK_POSTING : "hang"
    A_RESERVATION o|--o{ RIGHT_POSTING : "giu A"
    B_QUOTA o|--o{ RIGHT_POSTING : "giu B"
    STOCK_LOCATION ||--o{ RIGHT_POSTING : "tai vi tri"
    DELIVERY_LINE ||--o{ COGS_EFFECT : "gia von nguon"
    DELIVERY_LINE ||--o{ AR_OPEN_ITEM : "nghia vu no"
    CUSTOMER ||--o{ AR_OPEN_ITEM : "ben no"
    CUSTOMER ||--o{ RECEIPT : "da nhan"
    RECEIPT ||--o{ RECEIPT_ALLOCATION : "phan bo"
    AR_OPEN_ITEM ||--o{ RECEIPT_ALLOCATION : "trich tru"
    CUSTOMER ||--o{ CUSTOMER_CREDIT_EFFECT : "tien du"
    RECEIPT ||--o{ CUSTOMER_CREDIT_EFFECT : "nguon credit"
    B_CREDIT_GRANT ||--o{ GRANT_EFFECT : "consume release"
    RECEIPT ||--o{ CUSTODY_EFFECT : "cash confirmed"
    HANDOVER ||--o{ CASHIER_ACCEPTANCE : "xac nhan thuc"
    CASHIER_ACCEPTANCE ||--o{ CUSTODY_EFFECT : "giam giu ho"
    CASHIER_ACCEPTANCE ||--o{ FUND_EFFECT : "tang quy"
~~~

| Entity/effect | Ý nghĩa và cách diễn giải AC-03 |
|---|---|
| BUSINESS_EVENT + SOURCE_LINE | Định danh command + canonical payload hash, source document/line, xảy ra lúc nào/ghi nhận lúc nào, actor/tenant/trip, event kind; kết quả ACCEPTED/REJECTED được tách khỏi posted ledger |
| STOCK_POSTING | **Leg có dấu** (location, SKU, deltaQty, deltaStockValue, sourceLine, ordinal). Transfer có hai leg bù nhau; giao/bán có leg âm. Opening là leg dương có nguồn. Không trừ A/B hai lần từ tồn |
| RIGHT_POSTING | (rightKind=A/B, rightId, location, deltaQty, reason, sourceLine). Tổng tất cả location là A held/B quota remaining; mỗi location tạo RIGHT_POSITION **derived**. RELEASE B ở T6 không chuyển entitlement thành A |
| COGS_EFFECT | Giá vốn xuất giao theo **CostBasisSnapshot** của DELIVERY_LINE; chuyển kho/xe không ghi COGS |
| AR_OPEN_ITEM | Nghĩa vụ gốc từ DELIVERY_LINE (A hoặc B), CustomerId, grossDue, dueDate theo terms snapshot; **không** sinh từ A Confirm/load |
| RECEIPT, RECEIPT_ALLOCATION | Receipt cash phải CONFIRMED bằng tiền thật; allocation tới open item có nguồn riêng. B sale tạo item gốc 300 và áp receipt 200 → AR B còn 100 |
| CUSTOMER_CREDIT_EFFECT | Chỉ phần receipt đã confirmed nhưng chưa áp thành credit có nguồn; AC-03 cash 200 áp đủ nên không tăng credit. Không trộn với B_CREDIT_GRANT |
| B_CREDIT_GRANT, GRANT_EFFECT | Grant ban đầu 100, B exposure 100 tiêu dùng; remaining=0; cash thu nợ hoặc nộp quỹ không tự nạp lại grant |
| CUSTODY_EFFECT | Ledger tiền mặt nhân viên giữ: +200 khi cash CONFIRMED, −200 khi cashier thực nhận handover |
| HANDOVER, CASHIER_ACCEPTANCE, FUND_EFFECT | OFFERED không tạo effect; CASHIER_ACCEPTED 200 tạo custody−200 và fund+200 **cùng một transaction**, không động AR |

**Balances không phải nghiệp vụ nguồn mới:** STOCK_COST_BALANCE = SUM STOCK_POSTING theo (tenant, SKU, StockLocation); RIGHT_POSITION = SUM RIGHT_POSTING theo (tenant, kind, rightId, StockLocation); COGS = SUM COGS_EFFECT; AR = SUM openItem.grossDue − SUM allocations hợp lệ; custody/fund/grant = tổng các effect tương ứng. Nếu SQL-02 materialize các balances để khóa nhanh, phải chứng minh reconcile về nguồn.

## 4. Quyền lượng không chồng — trạng thái vị trí

Quyền lượng và hàng nằm ở đâu là **hai trục khác nhau**. Với SKU AC-03, không có Lot/UoM thay đổi, mọi giá vốn tương đương 10/đơn vị. Bảng sau mô tả **placement theo vị trí**, không phải số dư vật lý bị trừ lần hai.

| Checkpoint | MAIN: A/B đang giữ | TRIP: A/B đang giữ | Ý nghĩa |
|---|---:|---:|---|
| T0 | A40 / B30 | A0 / B0 | MAIN100, free30; A Order Confirm giữ40; B quota giữ30 |
| T1_LOAD | A0 / B0 | A40 / B30 | Chuyển vật lý70 và quyền placement tương ứng, không tạo AR/COGS |
| T2_REJECT | A0 / B0 | A40 / B30 | Yêu cầu B31 vượt B quota30, không đăng ledger |
| T3_B20 | A0 / B0 | A40 / B10 | B chỉ tiêu quota B20; không dùng A40 |
| T4_A25 | A0 / B0 | A15 / B10 | A giao25, hold còn15; không dùng B10 |
| T5_HANDOVER | A0 / B0 | A15 / B10 | Chỉ chuyển tiền custody→fund |
| T6_RETURN | A15 / B0 | A0 / B0 | Xe trả A15+B10 về MAIN; A vẫn giữ15 tại MAIN, B10 **release** thành hàng free; B quota cuối=0 |

**Tại T6 phải làm hai việc riêng:** (1) chuyển 25 đơn vị hàng/giá trị từ TRIP về MAIN, (2) chuyển A placement 15 về MAIN và release 10 quyền B. Không coi đây là Customer Return/QA; không tự release A15 vì oracle còn A held15. Cần chính sách/hồ sơ nguồn quyết định A hold15 sẽ được xử lý thế nào khi Trip đóng (xem câu hỏi mở).

## 5. Khóa logic, cardinality và tính bất biến

- Mọi entity nghiệp vụ mang tenantId; ID tuyệt đối chỉ có nghĩa cùng tenant. Mọi quan hệ giữa chứng từ, customer, SKU, trip, right, ledger/source phải **cùng tenant**. Không lấy database topology làm bằng chứng kiểm tra boundary ở mức logic.
- A_ORDER (1) → A_ORDER_LINE (1..n) → A_RESERVATION (0..n); DELIVERY_LINE A có đúng một A_ORDER_LINE, nhưng một order line có nhiều delivery lines/lần giao.
- TRIP (1) → B_QUOTA (0..n)/MANIFEST_LINE (0..n)/DELIVERY (0..n); quota có thể nhiều grant sources, **không giả định khóa duy nhất chỉ theo trip+SKU** khi chưa phê duyệt.
- DELIVERY_LINE B có đúng một B_SALE_LINE; command B gồm sale/delivery/receipt (nếu có)/AR/stock/cost/right/grant trong một boundary, không có nửa giao dịch.
- RECEIPT (1) → RECEIPT_ALLOCATION (0..n), AR_OPEN_ITEM (1) ← allocations (0..n); một Receipt có thể trả nhiều AR item, một AR item có thể nhận nhiều allocation sources.
- Stock transfer MAIN↔TRIP là hai leg giá trị/lượng bù nhau; một transaction nguồn, không hai sale. Một lot có thể phải được quản lý sau, nhưng **AC-03 chưa cung cấp lot source** nên không bịa lot/FEFO vào fixture.
- Định danh duy nhất và scale đề xuất xem [invariants.md](invariants.md), transaction và lock xem [transaction-boundaries.md](transaction-boundaries.md), đối chiếu từng checkpoint xem [ac03-mapping.md](ac03-mapping.md).

## 6. Chủ động hoãn (không suy là đã hoàn tất)

Không mở rộng physical SQL-02 sang: lot/expiry/FEFO thực (AC-05), return từ Customer vào quarantine và cost adjustment (AC-06), gift/VAT/pricing engine (AC-07/19), nhiều lần giao A + thay terms (AC-08), AC-09 concurrency và credit dư, advance (AC-20), credit allocations đa bước (AC-21), invoice provider thực, accounting sync, offline journal, cutover và IAM/RBAC production. Chỉ để **điểm nối nguồn** khi AC-03 cần.

## 7. OPEN QUESTION trước hoặc trong review SQL-02

1. **A hold sau chuyến:** oracle giữ A15 ở T6 dù TRIP0. Mô hình đề xuất đưa A placement về MAIN và giữ reservation gốc. Có cần source re-assignment sang chuyến mới/trạng thái Trip CLOSED_WITH_OPEN_CASES không? Không tự release.
2. **Grant B:** fixture chỉ ghi “grant B100”, chưa định nghĩa đầy đủ scope theo Trip/Customer/writer hay thời hạn grant. Giữ grantId + scope/version có nguồn, không chốt unique vật lý theo Customer.
3. **A terms/credit:** AC-03 không cho N ngày hay approval cụ thể. Chốt logic dueDate = businessDate giao + N snapshot **được duyệt**, nhưng fixture SQL-02 phải có terms synthetic hợp lệ, không tự chọn N mặc định từ UNSET.
4. **Attempt B31:** không cho payment breakdown. SQL-02 phải test quota guard độc lập (đầu vào nhận tiền/credit khác hợp lệ) để không giải thích nhầm reject do grant. Dữ liệu rejected không phải sale/receipt đã posted.
5. **Rounding và value scale:** đơn vị AC-03 là synthetic, không cho currency rounding profile dùng ngoài đời; đề xuất decimal prototype, không dùng VND/VAT seed làm mặc định.

**Điều kiện ra khỏi SQL-01:** review xác nhận mô hình trace đủ 13 cột × 7 bước, XOR/tenant/right/stock/value/ledger/transaction có chiến lược kiểm, open questions có disposition rõ; **không** nâng AC-03 từ MODEL_ONLY lên implementation verified.
