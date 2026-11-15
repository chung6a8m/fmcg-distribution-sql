# Phạm vi sản phẩm và mục tiêu MVP

**ID:** SCOPE-v1 · **Trạng thái biên tập:** BUSINESS_CANDIDATE · **Ngôn ngữ:** tiếng Việt.

## 1. Đối tượng và công việc cần giải quyết

Sản phẩm là một DMS chuẩn cho **doanh nghiệp vừa và nhỏ phân phối hàng tiêu dùng nhanh (FMCG) tại Việt Nam**, ưu tiên đơn vị phân phối theo địa bàn. Giá trị chính là một chuỗi thông tin có nguồn từ đơn hàng, kho, giao/bán, tiền, công nợ, hóa đơn và đối chiếu kế toán.

Công việc người dùng cần hoàn thành: tạo và theo dõi đơn đặt trước; cấp hàng cho chuyến và giao từng phần; bán hàng theo xe; thu tiền, nộp quỹ, theo dõi khoản phải thu và tạm ứng; quản lý tồn/lô/hạn và hàng trả; nhận diện việc chưa đồng bộ, chưa xác minh hoặc có chênh lệch; báo cáo với độ đầy đủ dữ liệu rõ ràng.

Phương châm Product-first: **một lõi nghiệp vụ tiêu chuẩn**; L0 bất biến, L1 cấu hình hữu hạn, L2 ngoại lệ có kiểm soát. Không tùy biến công thức hoặc quyền chỉ vì một NPP có thói quen khác.

## 2. Đối tượng sử dụng

- Chủ NPP/Owner và quản trị tenant: hồ sơ seller, phân công, chính sách, phê duyệt và điều hành.
- Sales: Customer/Outlet/ShipTo, viếng thăm, đơn A, đề nghị trả.
- Kho: nhận hàng, kiểm kho, giữ A, quota B, cấp/nhận lại hàng trên chuyến, xử lý lô/hạn/cách ly.
- Nhân viên giao/bán/chuyến: giao A, bán B, ghi nhận tiền thực đã nhận, đối soát cuối chuyến.
- Lái xe: có thể đồng thời là nhân viên giao hàng khi đi xe máy; xe tải có thể có người giao hàng và lái xe riêng.
- Thủ quỹ và kế toán: kiểm đếm nộp quỹ, xác nhận ngân hàng, công nợ, tạm ứng, hóa đơn, đối soát.
- Quản lý phê duyệt/Ops/QA: ngoại lệ, audit, phục hồi, kiểm tra chất lượng và ngưỡng đưa vào sử dụng thật.

Một người có thể kiêm vai nhưng không được tự kiểm duyệt giao dịch của mình khi cần maker–checker.

## 3. Phạm vi MVP theo mode

| Mode | Cần hỗ trợ trong sản phẩm | Quyền giao dịch production |
|---|---|---|
| **A** — đặt trước/giao sau | Confirm đơn, giữ hàng, giao nhiều đợt, thu/AR theo phần thực giao | Phụ thuộc xác minh và Tenant Go-Live theo mode |
| **B_ONLINE** — bán theo xe | B quota, bán/giao/thu một nghiệp vụ nhất quán, kênh hóa đơn online hợp lệ | Phụ thuộc xác minh hóa đơn, sổ và Tenant Go-Live |
| **MIXED A+B_ONLINE** | Một chuyến với A reservation và B quota tách biệt | Chỉ khi A, B_ONLINE và Mixed E2E đều đạt |
| **Offline A** | Có định hướng hỗ trợ khi quyền/mode/thiết bị được chứng minh | Tắt mặc định; cần E2E riêng trước khi mở |
| **B dùng kênh thay thế khi mất liên lạc** | Định hướng mở rộng | **DEFERRED** khỏi MVP hiện tại |
| **B_NO_CHANNEL** | Không hỗ trợ giao dịch thật trong MVP | **BLOCKED**, không tự vượt gate bằng cấu hình |

**MVP business workflows** gồm danh mục cơ bản; quản trị Customer/Outlet/ShipTo; A/B/Mixed; nhập/xuất/chuyển/kiểm kho và mọi biến động ngoài pilot sau cutover; UoM/lô/hạn/FEFO/quarantine; bình quân di động; chính sách giá/quà/trả; ba sổ tiền; công nợ; hóa đơn và xác nhận kế toán theo nguồn; visit không đơn; báo cáo asOf; kiểm toán nguồn và nghiệp vụ sửa sai.

## 4. Không bao gồm trong MVP

Nhiều người bán/pháp nhân trong cùng tenant; kế toán tổng hợp thay thế hoàn toàn hệ thống kế toán hiện hữu; WMS nâng cao, AI/tối ưu tuyến tự động; đồng bộ nhiều người ghi cho một chuyến; ký gửi nhiều chủ; mọi nhánh B offline không có bằng chứng kênh hóa đơn thay thế; quy tắc pricing viết script tùy ý; tự động suy luật thuế từ số liệu giả lập.

## 5. Những thành quả quan sát được

Với một luồng thật, người dùng phải truy được chứng từ nguồn, lượng tồn và giá trị đã thay đổi, khoản phải thu đến hạn, ai đang giữ tiền, chứng từ hóa đơn/đối soát ở trạng thái nào và còn case nào chưa xử lý. Mỗi chỉ số hiển thị **asOf, phạm vi, mẫu số n/N, dữ liệu pending** khi thích hợp.

Đề nghị đo: tỷ lệ chứng từ đúng nguồn, đối soát tồn/tiền/nợ, thời gian hoàn thành tác vụ, số case còn mở, tỷ lệ đồng bộ, chênh lệch kế toán, chi phí hỗ trợ. **Ngưỡng SLO/KPI cụ thể vẫn UNSET; không dùng số liệu mẫu làm kết quả pilot.**

## 6. Ranh giới Pilot NPP-01

Blueprint giả định đã chọn: **3 A + 3 B_ONLINE + 2 Mixed mỗi ngày trong ít nhất 5 ngày**, chỉ khi đủ gate tương ứng. Mẫu này chỉ dành cho NPP-01; dù 8 chuyến được dùng ứng dụng, **mọi biến động Kho-01** sau cutover vẫn phải được ghi nhận ở nguồn mới. Chưa có Pilot thực, kết quả n/N, chi phí hoặc chữ ký Tenant.
