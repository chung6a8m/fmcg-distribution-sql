# Ràng buộc, giả định và giới hạn bằng chứng

## 1. Các yêu cầu nghiệp vụ bất biến

- Cô lập tuyệt đối dữ liệu/ủy quyền giữa các tenant; một business seller/tenant trong MVP.
- Không bán trùng lượng A đã giữ cho B; tồn hàng và giá trị có nguồn; mọi biến động Kho-01 sau cutover chỉ có một nguồn ghi sổ có thẩm quyền, kể cả ngoài wave.
- Không tạo AR/doanh thu/cost khi chỉ xác nhận đơn A hoặc chuyển hàng lên xe.
- Không trừ AR lần hai khi nộp quỹ; AR, cash custody và employee advance độc lập.
- Không ghi nhận đã thu khi chỉ có ảnh/chứng từ chuyển khoản chưa xác minh.
- Không tự duyệt tiền mình giao, miễn thu hồi quà, sửa kho, hoàn tiền hoặc mở mode khi phải có checker khác.
- Không phát hành lại hóa đơn mang trạng thái UNKNOWN bằng danh tính giao dịch mới; đối chiếu trạng thái bên ngoài.
- Không xóa sự thật hàng/tiền đã thực trao khi ghi nhận muộn, nhưng mọi ngoại lệ cần case, trách nhiệm và xử lý.
- Không hồi sinh quyền đã thu hồi, không lặp ngoại hiệu ứng sau sự cố hoặc phục hồi.

## 2. Giới hạn và ràng buộc pháp lý

- Mốc lập hóa đơn, hình thức phát hành, hồ sơ seller, thuế suất theo SKU và trách nhiệm chứng từ cần xác minh theo văn bản có hiệu lực, mô hình bán và đơn vị bán **trước giao dịch thật**; không suy từ tài liệu nghiên cứu.
- B_ONLINE chỉ được thực hiện với kênh hóa đơn hợp lệ đã được kiểm chứng. B_NO_CHANNEL là BLOCKED theo MVP; B sử dụng kênh thay thế khi ứng dụng mất mạng là DEFERRED.
- Dữ liệu cá nhân, quyền truy cập, retention, audit/incident phải đáp ứng nghĩa vụ thực tế; bản business không chọn nơi lưu hay công nghệ mã hóa.
- 5 P0 gate của nguồn: G-STOCK, G-CUT, G-IDEMP, G-LEDGER, G-INV — **không miễn trừ để Go-Live**. P1 chỉ có ngoại lệ phạm vi/thời hạn/owner/kiểm soát rõ, không chuyển FAIL thành PASS.

## 3. Những lựa chọn kỹ thuật lịch sử được bảo toàn, không áp đặt trong bản business

| Chủ đề | Quyết định hoặc đề xuất nguồn | Cách xử lý khi bước sang implementation |
|---|---|---|
| Cô lập tenant | D-01 có database-per-tenant | Ghi rõ là quyết định kỹ thuật lịch sử của baseline nguồn; nếu thay đổi, cần Owner quyết định thay thế có phiên bản |
| Kênh người dùng | PWA và web portal từng được chọn | Giữ yêu cầu hành vi ở ngoài hiện trường; khi chọn stack phải đối chiếu quyết định PWA trước khi đổi |
| Đồng bộ bền/chống trùng | Inbox/outbox, journal, command/hash, ACK | Đóng trong thiết kế kỹ thuật, test bằng các hậu điều kiện của business |
| Giá trị tiền và dữ liệu | Decimal source, làm tròn ổn định | Bắt buộc kết quả đúng; biểu diễn cụ thể do implementation chọn, không dùng phép tính nhị phân gây sai số |
| Vận hành | Cloud/provider, storage, RPO/RTO, restore topology | Chưa xác lập trong business; cần yêu cầu phi chức năng/verification riêng trước production |
| Accounting, hóa đơn | API/file/manual adapter và provider-specific mapping | Nghiệp vụ yêu cầu trạng thái và reconciliation đúng, cách tích hợp cụ thể làm tại delivery |

**Không tự diễn giải việc bỏ cấu hình tech khỏi business/ là rút lại quyết định Owner đã ghi ở nguồn.**

## 4. Pending thực tế tại thời điểm chuyển đổi

EV-01..15 chưa có E2E thật đã nghiệm thu; nhiều bộ chỉ MODEL_ONLY. B-CASE-001..003, LEGAL-MEMO EVIDENCE_PENDING; INV-09 NOT_RUN; TADR-01..06 DESIGN_CANDIDATE; Seller NPP-01, quyền stock toàn Kho-01, opening/cutover thật, thông số ngưỡng và tổ hợp thiết bị vẫn cần kiểm.

Nguồn từng có Product Baseline Owner Accepted **ở mức hợp đồng tài liệu**, không phải Product Verified. Business Baseline mới trong repo này còn Owner review. Không cho dữ liệu demo giả làm dữ liệu NPP, bằng chứng pháp lý, chữ ký chuyên môn hay kết quả pilot.
