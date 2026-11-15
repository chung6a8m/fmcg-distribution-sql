# Business Rules v1 — Quy tắc bắt buộc

Đây là hợp đồng **hành vi nghiệp vụ và bất biến**, không quy định database, API, UI framework, hàng đợi hay kiến trúc. 24 ID giữ theo baseline nguồn. Các quy tắc L0 không thể bị cấu hình tenant vô hiệu hóa. Tính toán và các expected numeric oracle chi tiết thuộc B02.

| Rule | Điều phải đúng và mốc phát sinh | Cách xử lý sai/thiếu |
|---|---|---|
| **BR-01** | Một seller/tenant; phân quyền và membership tenant độc lập, không cho truy cập chéo kể cả qua tìm kiếm/xuất báo cáo | Chặn, ghi audit; không suy quyền từ người trả phí SaaS |
| **BR-02** | Customer là bên chịu nợ; có 0..n Outlet; mọi Order/Delivery có ShipTo snapshot, không viết lại lịch sử khi Outlet đổi chủ/địa chỉ | Không post chứng từ thiếu Customer/ShipTo hợp lệ |
| **BR-03** | A Order Confirm chỉ chốt điều khoản và giữ hàng, **không tạo AR/doanh thu/giá vốn**; mỗi Delivery thực giao sinh hiệu ứng theo phần giao, không vượt lượng nguồn | Giữ remainder hoặc đóng phần còn lại có chứng cứ |
| **BR-04** | Trip có AReservation và BQuota không chồng nhau; kho→xe chuyển custody hàng/giá trị, không là bán; B không dùng A đã giữ | Chặn release khi thiếu manifest hoặc lượng phân bổ |
| **BR-05** | Sau cutover mọi biến động **toàn Kho-01** chỉ do nguồn ghi có thẩm quyền, bao gồm ngoài pilot/wave | Một đường ghi cũ còn độc lập hoạt động = P0 NO-GO |
| **BR-06** | Lượng dùng base UoM, conversion/step snapshot; truy xuất lot/expiry, FEFO theo profile; hàng trả thực nhận vào quarantine, không mặc nhiên available | Sai số lượng/lô/hạn → kiểm và case |
| **BR-07** | Giá vốn vận hành tính bình quân di động theo SKU × StockLocation; xuất/hoàn dùng nguồn và phiên bản cost; kỳ khóa chỉ điều chỉnh forward có nguồn | Không ép phương pháp kế toán bình quân kỳ thành giá vốn vận hành hoặc viết lại kỳ khóa |
| **BR-08** | Giá, discount, tax profile, UoM, terms cần snapshot đúng mốc nghiệp vụ; A khóa giá/discount tại Confirm cho lượng đã chốt | Không tái tính chứng từ đã ghi từ master mới |
| **BR-09** | Quà theo số mua ròng đủ điều kiện; quà khách còn giữ = delivered − acceptedBack; waived gift còn giữ **không làm tăng quyền quà** | Waiver phải có nguồn, người duyệt và scope; không cấp hai lần |
| **BR-10** | Hạn nợ của từng khoản giao A = businessDate giao hợp lệ + N ngày trong terms snapshot khi Confirm | Không hồi tố khi thay Customer terms master |
| **BR-11** | B sale + delivery + receipt/allocation và hiệu ứng stock/AR/credit/grant là **một hành vi không tách rời**; không chấp nhận một phần | Nếu đã thực trao mà chưa ghi được, lưu occurred-event/case |
| **BR-12** | B: received được xác minh mới giảm exposure; CustomerCredit chỉ dùng khi đã giữ riêng; grant B giảm đúng phần AR phát sinh, không đếm held+AR hai lần | Không âm quota/grant/credit, không ghi trùng khi retry/tranh quyền |
| **BR-13** | Ba sổ độc lập: AR Customer, cash custody, employee advance. Receipt confirmed phân bổ nhiều khoản nợ; handover chỉ chuyển custody→quỹ khi thủ quỹ nhận thực | Không tự cấn trừ sổ, không trừ AR khi nộp tiền lần hai |
| **BR-14** | Receipt confirmed chưa phân bổ là CustomerCredit có nguồn; dùng credit và refund là hiệu ứng riêng, refund chỉ giảm credit khi **đã chi thực** | Không AR/credit âm hoặc hoàn vượt nguồn |
| **BR-15** | Chỉ một writer/trip theo quyền có giới hạn; chuyển writer/thiết bị sau đối chiếu; offline mặc định không có quyền ghi | Ý định chưa thực hiện ngoài quyền bị từ chối; sự thật đã xảy ra vào case |
| **BR-16** | Lệnh/chứng từ đã phát sinh phải được giữ tới khi bên nhận xác nhận **đã giữ bền**, không coi đã nhận là đã hoàn tất nghiệp vụ; lặp cùng ID/nội dung chỉ một hiệu ứng | ID trùng nhưng nội dung khác → conflict; phụ thuộc thiếu → pending/case, không mất |
| **BR-17** | Phục hồi không hồi sinh quyền bị thu hồi hoặc yêu cầu riêng tư; không lặp hóa đơn/hiệu ứng ngoài đã tồn tại | Thiếu dữ liệu kiểm quyền/ngoại hiệu ứng → khóa tác vụ cho tới đối chiếu |
| **BR-18** | Hóa đơn gắn với giao/chuyển quyền hợp lệ, theo hồ sơ seller/provider; kho→xe hoặc thu nợ cũ không tạo hóa đơn bán mới; UNKNOWN phải xác minh cùng identity | B thiếu kênh hợp lệ không tiếp tục giao dịch thật; event đã xảy ra ghi case, không backdate |
| **BR-19** | Kế toán phân biệt tiếp nhận, đã ghi sổ, đã đối soát đạt/chênh; theo source line, cutoff và giá trị | ACK/POSTED không tự thành RECONCILED_OK; sai lệch có case và correction |
| **BR-20** | Return Request/Held không làm giảm AR hoặc tăng tồn available; thương mại chấp nhận và hàng thực nhận cần phân biệt; cost hoàn lũy kế theo nguồn; QA release riêng | Thiếu delivery source giữ cách ly/case; không tự đưa vào hàng bán |
| **BR-21** | Cutover sạch: freeze, kiểm kê/manifest, kiểm nguồn và số dư, ký nhiều bên, khóa ghi cũ; sau business effect đầu tiên chỉ forward correction | Không replay hoặc rollback xóa sự kiện thật/hiệu ứng ngoài |
| **BR-22** | Visit có thể kết thúc không đơn: lưu outcome/reason/observation/return request với nguồn | Không sinh đơn 0 đồng, sale, AR, stock movement giả |
| **BR-23** | Báo cáo/đóng ngày công khai asOf, phạm vi nguồn, pending, n/N và case owner | Không coi thiếu sync là số 0 hay “realtime” đã xác nhận |
| **BR-24** | Pilot NPP-01 3A+3B_ONLINE+2Mixed/ngày trong ≥5 ngày khi mỗi mode đạt gate; stock authority trên **toàn Kho-01** | Không tự dùng thông số pilot cho tenant khác; P0 chưa đạt → NO-GO |

## Quy tắc tính toán then chốt (không thay bản công thức B02)

- BR-09: entitlement = floor(netQualifiedPurchases / threshold); giftHeld = giftDelivered − giftAcceptedBack; giftToDeliver = max(0, entitlement − giftHeld).
- BR-10: dueDate = localBusinessDate(delivery) + N ngày (snapshot), không là cộng N×24h vào timestamp thiết bị.
- BR-12: verifiedReceiptApplied + reservedCustomerCreditApplied ≤ salePayable; creditExposureConsumed = salePayable − hai phần đã áp; grantRemaining' = grantRemaining − creditExposureConsumed.
- BR-13: advanceOutstanding = issuedTotal − approvedExpenses − cashierAcceptedAdvanceReturns ≥ 0.
- BR-14: confirmedReceipt = allocationsToAR + availableCustomerCredit + approvedActuallyDisbursedRefund (theo cùng nguồn, xét correction có chứng từ).
- BR-07: giá trị hoàn từng phần phải cộng đúng tổng giá trị nguồn, xử lý phần dư làm tròn, không tự tính lại giá gốc sau khi posted.

## Phân loại lỗi

**Reject/pending trước hiệu ứng:** thiếu quyền, stock/quota, giá/thuế, bằng chứng tiền, invoice channel, người duyệt. **Recorded exception sau hiệu ứng đời thực:** hàng/tiền đã trao ngoài quyền, nguồn giấy tới muộn, mất thiết bị, chênh kiểm kê, đối tác UNKNOWN. Tuyệt đối không xóa sự kiện có thật để khiến các sổ cân giả.

## Kiểm soát phiên bản

Thay đổi business rule phải có lý do, phương án cũ/mới, impact lên SOP/POL/AC/scenario và Owner review. Evidence chạy model không chứng minh ứng dụng đã đúng.
