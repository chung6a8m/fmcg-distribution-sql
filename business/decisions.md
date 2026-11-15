# Sổ quyết định nghiệp vụ và ranh giới phê duyệt

**Nguồn:** Product Contract C′ ký ở mức policy/contract; **file này là bản diễn giải độc lập và chưa nhận Owner Acceptance riêng**. Mọi ID giữ ổn định. Các phần triển khai kỹ thuật lịch sử được lưu trong constraints.md.

## 1. D-01..D-15 — quyết định nền tảng

| ID | Ý nghĩa chốt cho nghiệp vụ | Giới hạn |
|---|---|---|
| D-01 | Một seller/tenant; Subscriber không tự là người bán; dữ liệu tenant độc lập | Database riêng là lựa chọn kỹ thuật lịch sử cần đối chiếu |
| D-02 | Customer chịu nợ, Outlet 0..n, ShipTo snapshot | Chưa có mapping NPP thật |
| D-03 | Hỗ trợ chuyến A, B, Mixed với phân bổ hàng riêng | Mixed E2E chưa đạt |
| D-04 | Giá vốn vận hành bình quân di động SKU × nơi tồn, theo nguồn xuất/hoàn; kế toán bình quân kỳ riêng | Reconciliation thực pending |
| D-05 | Giá/chiết khấu/khuyến mại hữu hạn, quà mua ròng, miễn thu hồi có duyệt | Thuế theo hàng, provider pending |
| D-06 | Ba sổ độc lập và hạn trả mỗi lần giao + N ngày theo điều khoản chốt | N/limit thật và approvals pending |
| D-07 | Một writer/chuyến, quyền offline hữu hạn, không mất/lặp nghiệp vụ | TTL/hệ thống kiểm thật pending |
| D-08 | Hóa đơn A/B trong phạm vi; không tự cho B offline khi thiếu kênh hợp lệ | B_NO_CHANNEL BLOCKED |
| D-09 | Phục hồi không hồi sinh quyền thu hồi hoặc hiệu ứng bên ngoài | Runtime proof pending |
| D-10 | Cutover sạch, kiểm kê/đối soát nhiều bên; sau hiệu lực đầu dùng forward correction | Cutover thật pending |
| D-11 | Một writer tồn chính cho **mọi** biến động Kho-01 sau cutover | Kiểm mọi đường ghi cũ pending |
| D-12 | Thu khách, nộp quỹ, tạm ứng, hoàn ứng độc lập | Dữ liệu thủ quỹ thực pending |
| D-13 | Tiếp nhận kế toán khác ghi sổ khác đối soát đạt; chống trùng theo nguồn | Integration thực pending |
| D-14 | Recovery giữ nguồn và các sự kiện thực, không rollback sự thật | Fault injection pending |
| D-15 | Pilot mẫu NPP-01: 3A+3B+2Mixed/ngày × ≥5 ngày khi qua gate | Chưa phải dữ liệu chạy thật |

D-01..06 có lựa chọn phỏng vấn Owner; một số D-07..15 trong hồ sơ nguồn chỉ có bản tóm lược (SUMMARY_ONLY), không được giả làm transcript nguyên văn.

## 2. PADR-01..09 — chính sách sản phẩm

| ID | Chính sách đã được Owner chọn |
|---|---|
| PADR-01 | Lõi Product-first: L0 bất biến, L1 hữu hạn, L2 exception được quản lý |
| PADR-02 | Credit terms/limit mặc định **UNSET**, fail-closed; **APPROVED=0** khác chưa cấu hình |
| PADR-03 | Mode Admission riêng theo seller/tenant/mode/phạm vi và evidence |
| PADR-04 | 5 nhóm pricing hữu hạn, decimal, làm tròn ổn định theo dòng nguồn, override có duyệt |
| PADR-05 | Cho phép kiêm nhiệm vai trò nhưng maker–checker độc lập theo loại duyệt |
| PADR-06 | Tách trạng thái local/được tiếp nhận bền/ghi sổ/hóa đơn/kế toán/đối soát/case |
| PADR-07 | Offline mặc định tắt; chỉ cấp theo mode/chuyến/thiết bị và đủ bằng chứng |
| PADR-08 | Daily close có CLOSED_WITH_OPEN_CASES, asOf, n/N, case owner và next action |
| PADR-09 | Product Pilot Contract chung + Tenant Pilot Profile riêng; giữ D-15 cho NPP-01 |

## 3. EVQ-01..07 — chính sách chấp nhận và kiểm chứng

| ID | Điều kiện |
|---|---|
| EVQ-01 | Product Verification và Tenant Go-Live Acceptance độc lập, theo mode |
| EVQ-02 | P0 không miễn; P1 exception theo scope/timebox/owner/kiểm soát, không nâng status |
| EVQ-03 | Cutover toàn Kho-01, opening ký, khóa mọi writer cũ, Forward Recovery |
| EVQ-04 | Offline E2E theo mode/thiết bị, chống trùng/ACK/revoke/restore |
| EVQ-05 | MVP ưu tiên A, B_ONLINE, MIXED với B_ONLINE; nhánh B thay thế khi mất mạng deferred, B_NO_CHANNEL blocked |
| EVQ-06 | Kiểm giá/giá vốn/ba sổ/accounting thật, có đối soát; tiếp nhận không phải đã cân |
| EVQ-07 | Pilot có n/N, UX/SLO/coverage, ký ngưỡng trước pilot, Go/No-Go riêng theo mode |

## 4. Trạng thái được phép kết luận

**Nguồn:** OWNER_BASELINE_ACCEPTED chỉ cho PRODUCT_POLICY_AND_CONTRACT_ONLY. **Repository này:** BUSINESS_CANDIDATE, chưa được Owner chấp nhận lại về câu chữ biên tập. **Phần mềm:** NOT_VERIFIED. **Tenant production:** NO_GO/PENDING, B_NO_CHANNEL BLOCKED.

Để sửa một ID: ghi phương án cũ, đề xuất mới, tác động rule/SOP/AC/golden và nguồn Owner duyệt; không sửa âm thầm quyết định lịch sử.
