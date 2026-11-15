# Vai trò, trách nhiệm và phân nhiệm

Mô tả **quyền kinh doanh logic**, không chỉ định cơ chế đăng nhập hoặc hệ thống RBAC nào.

## Vai trò vận hành

| Vai trò | Công việc chính | Không được tự suy quyền |
|---|---|---|
| Tenant Owner | Chính sách, mode/cutover/pilot, chịu trách nhiệm kinh doanh | Không thể miễn P0 hoặc luật |
| Tenant Admin | Danh mục, nhân sự, cấu hình theo quyền | Không thể tự sửa chứng từ posted |
| Sales | Visit, A Order, Customer/ShipTo, return request | Không tự xác nhận giao/thu đã thực |
| Warehouse Clerk/Manager | Stock/lô, A hold, B quota, cấp/nhận chuyến và kiểm kê | Không chuyển hàng trả thẳng available |
| Delivery/Trip Writer | Giao A, bán B, nhận tiền thực, source event và đóng chuyến | Không tự có quyền ký quỹ hoặc phê duyệt |
| Driver | Lái xe và xác nhận sự kiện vận chuyển theo assignment | Không mặc nhiên là Trip Writer |
| Cashier | Kiểm tiền, xác nhận tiền nộp và hoàn advance | Không tự nhận thay nếu không thực đếm |
| Accountant/Finance | Kiểm bank, công nợ, phân bổ thu, advance, cost, invoice/accounting reconciliation | Không suy provider accepted = posted/reconciled |
| Pricing/Returns Approver | Duyệt discount/waiver/return/refund ngoại lệ | Không duyệt chính mình khi yêu cầu checker |
| Ops/Security/QA | Quyền, sự cố, dữ liệu/pilot evidence, xử lý phục hồi | Không cấp go-live từ CI synthetic |

**Xe máy:** người giao có thể kiêm lái. **Xe tải:** người lái và người giao có thể là hai người. Quyền là theo assignment/scope, không suy từ phương tiện.

## 10 lớp phê duyệt AP

| ID | Trigger | Điều kiện trước khi có hiệu lực |
|---|---|---|
| AP-01 CREDIT_OVERRIDE | Điều khoản/hạn mức bán chịu vượt chính sách | Finance/checker được ủy quyền; không tự cấp quyền khi UNSET |
| AP-02 STOCK_ADJUST | Điều chỉnh tồn, write-off, giải phóng hàng cách ly | Warehouse manager và chứng từ kiểm kê/QA |
| AP-03 PRICE_DISCOUNT | Giá ngoài tập auto/chiết khấu vượt biên | Pricing approver khác maker khi bắt buộc |
| AP-04 GIFT_WAIVER | Miễn thu hồi quà khách đang giữ | Có nguồn GiftHeld, lý do, phạm vi và checker |
| AP-05 RETURN_REFUND | Chấp nhận trả/hoàn Credit | Return/QA theo vai; refund phải phê duyệt và **chi thực** |
| AP-06 CASH_ACCEPT | Nộp tiền thu hộ/hoàn ứng | Thủ quỹ thực nhận, không self-accept |
| AP-07 ADVANCE_EXPENSE | Chi phí quyết toán tạm ứng | Finance approver; không giảm sổ vì đề nghị chi |
| AP-08 CUTOVER_GO | Chuyển quyền ghi và opening | Kho + kế toán + thủ quỹ + IT + Owner theo hồ sơ |
| AP-09 MODE_RELEASE | Mở mode ở tenant | Product/tenant authority + evidence theo mode; không bypass B_NO_CHANNEL |
| AP-10 RESTORE_REOPEN | Mở lại sau restore/incident | Ops/Security kiểm authority hiện hành và effects ngoài |

## RACI rút gọn

| Quy trình | Người thực hiện | Người chịu trách nhiệm/kiểm tra |
|---|---|---|
| Customer/price/terms | Sales/Admin | Tenant owner, approver hoặc Finance theo loại |
| Cấp hàng và A/B allocation | Warehouse | Warehouse manager + người nhận chuyến |
| Giao/bán và receipt | Trip Writer | Sales supervisor/Accountant; cashier cho nộp quỹ |
| Hoàn quà/đổi trả | Returns clerk | Pricing/Returns approver, Warehouse QA, Finance |
| Reconciliation kế toán | Accountant | Accounting owner với nguồn POSTED và cutoff |
| Opening/cutover | Warehouse/Accounting/IT | Tenant Owner và các bên xác nhận thực tế |
| Pilot admission | Ops/QA/Finance/Legal theo phạm vi | Product Owner + Tenant authority, per-mode |

Mỗi approval phải truy được: approval ID, source/case, proposer, checker, scope, policy version, quyết định, lý do, bằng chứng và mốc có hiệu lực. Nếu không có checker độc lập khi bắt buộc, giữ PENDING/CASE; không giảm cấp phân nhiệm cho tiện solo dev.
