# Danh mục chính sách sản phẩm và cấu hình nghiệp vụ

**L0:** bất biến; **L1:** tenant có thể chọn trong biên đã duyệt, hiệu lực có phiên bản; **L2:** ngoại lệ có case, không vô hiệu L0.

## 1. 24 chính sách POL tương ứng BR

| Policy | Lớp | Ý nghĩa và giới hạn |
|---|---|---|
| POL-01 | L0 | Cô lập tenant và seller; không có quyền dữ liệu mặc định chỉ vì hợp đồng SaaS |
| POL-02 | L0 | Customer chịu nợ; Outlet 0..n và ShipTo snapshot |
| POL-03 | L0 | A Confirm không tạo AR; Delivery là mốc ghi phần giao; không cấp tín dụng mặc định |
| POL-04 | L0 | AReservation/BQuota tách; load/unload không phải bán |
| POL-05 | L0 | Một nguồn ghi cho mọi biến động toàn kho sau cutover |
| POL-06 | L0+L1 | Base UoM/snapshot, lot/FEFO theo SKU profile, quarantine hàng trả |
| POL-07 | L0 | Giá vốn vận hành MOVING_AVG_SKU_LOCATION, nguồn hoàn và điều chỉnh |
| POL-08 | L0+L1 | Price/discount A khóa khi Confirm; thay đổi sau phải có amendment hợp lệ |
| POL-09 | L0+L1 | Gift theo mua ròng, thiếu quà thu hồi phải xử lý/duyệt waiver |
| POL-10 | L0+L1 | Hạn trả per Delivery theo N trong terms snapshot, không hồi tố |
| POL-11 | L0 | B sale/delivery/receipt/ledgers là một hiệu ứng toàn vẹn |
| POL-12 | L0+L1 | Grant/quota và CustomerCredit có nguồn reserve, không dùng quá phần được cấp |
| POL-13 | L0 | AR/custody/advance độc lập; handover cần thủ quỹ xác nhận |
| POL-14 | L0 | Credit dư theo receipt; phân bổ/hoàn theo sự kiện đã xác thực |
| POL-15 | L0+L1 | Một writer/trip, cấp quyền giới hạn và chuyển writer có reconciliation |
| POL-16 | L0 | Chứng từ giao nhận bền/chống trùng, phụ thuộc không bị mất |
| POL-17 | L0 | Restore không khôi phục quyền hoặc phát lại tác động bên ngoài |
| POL-18 | L0+L1 | Hóa đơn theo sự kiện đủ điều kiện; B thiếu kênh bị blocked |
| POL-19 | L0+L1 | Tiếp nhận, ghi sổ và đối soát kế toán là ba mức khác nhau |
| POL-20 | L0 | Hàng trả vào quarantine trước; thương mại và QA quyết định riêng |
| POL-21 | L0 | Cutover sạch/khóa ghi cũ, chỉ correction forward sau hiệu lực đầu |
| POL-22 | L0+L1 | Visit không đơn hợp lệ, lý do/outcome có thể cấu hình |
| POL-23 | L0 | Báo cáo và close thể hiện asOf/pending/n/N, không giả xác nhận |
| POL-24 | L0 + tenant pilot | Gate theo mode; NPP-01 3A+3B+2Mixed/ngày×≥5 ngày chỉ là profile riêng |

## 2. Các tham số nghiệp vụ: giá trị mặc định và thiếu

| Nhóm | Chính sách |
|---|---|
| Tiền/địa phương | MVP hướng tới VND; ngày nghiệp vụ theo múi giờ của seller được xác nhận, không mặc định lấy ngày thiết bị |
| Người bán/hóa đơn | Seller profile hợp lệ là điều kiện cần cho giao dịch thật; không lấy thông tin demo |
| A partial | Cho phép giao nhiều đợt; phần còn lại có thể giữ/đóng có nguồn |
| **Credit terms** | **UNSET** khi chưa có chính sách; N=0 chỉ có nghĩa khi **được duyệt** |
| **Credit limit** | **UNSET** khác **APPROVED=0**; fail-closed với bán chịu, không mặc nhiên cấp hạn mức |
| Modes | A/B_ONLINE/MIXED không tự admitted; offline tắt mặc định; B_NO_CHANNEL BLOCKED |
| Lot/expiry | Bắt buộc tuân thủ profile của SKU, FEFO khi có hạn dùng; hàng trả QUARANTINE |
| Cost | Bình quân di động theo SKU × location, không cho override sang phương pháp khác trong MVP |
| Pricing | 5 nhóm rule hữu hạn: list price, customer group, fixed discount, percentage discount, gift threshold; precedence/tie-break/version cần rõ |
| Rounding | Số thập phân chính xác và phần dư ổn định theo dòng nguồn; profile cụ thể phải được xác nhận |
| Bank receipt | Chỉ tiền mặt thực nhận hoặc ngân hàng được xác minh mới confirmed |
| Cashier | Người thực nhận tiền xác nhận; người giao không tự chấp nhận |
| Advance | Cho phép quyết toán từng phần; duyệt chi và hoàn thực nhận độc lập |
| Operational closure | CLOSED_WITH_OPEN_CASES cần asOf, case owner và next action |
| Approval thresholds | **UNSET**, không tự đặt giá trị tiền/ngưỡng duyệt |
| Pilot thresholds | SLO/UX/n/N phải được thống nhất trước Pilot, không dùng fixture để mặc định |

## 3. Quy tắc precedence và giá trị thiếu

Một policy cụ thể phải chỉ rõ seller/tenant, đối tượng, thời gian hiệu lực, phiên bản, người duyệt. **Không tìm thấy chính sách không có nghĩa giá trị bằng 0 đã phê duyệt.** Tính năng bị block không được mở bằng tenant flag hoặc data import.

Khi nhiều rule giá hợp lệ hoặc xung đột, business phải có thứ tự ưu tiên/tie-break được duyệt trước khi giao dịch. Không tự chồng các ưu đãi hoặc ghi giá âm. Cấu hình không có quyền thay đổi bất biến stock, ba sổ, nguồn chứng từ, thẩm quyền hay hóa đơn.

## 4. Những gì cố ý không nằm trong catalog này

Không có config database, PWA/local store, queue, API adapter, cloud, microservices, hosting hay bảo mật công nghệ. Các lựa chọn này thuộc implementation và cần đối chiếu hồ sơ lịch sử tại constraints.md.
