# Kiểm thử độc lập công nghệ và mức bằng chứng

## 1. Khởi đầu

1. Chọn nghiệp vụ và ID **BR/POL/SOP/AC**, đọc rule và [calculations.md](calculations.md) liên quan.
2. Chọn scenario trong [business-cases.json](reference-data/scenarios/business-cases.json) và expected trong [golden-oracles.json](reference-data/expected-results/golden-oracles.json) hoặc [additional-oracles.json](reference-data/expected-results/additional-oracles.json).
3. Tạo implementation test theo stack đã chọn, **không** đổi expected để hợp với code.
4. Thử cả happy, negative, retries và mỗi trạng thái chưa xác thực; ghi actual cùng environment/build/source/testRunId.
5. Phân biệt docs/model checks, local implementation checks và system E2E/external evidence.

## 2. Validation tài liệu không phải E2E

Có script **tùy chọn** ngoài sản phẩm: chạy `python3 tools/validate_business.py` từ root repo. Script chỉ dùng Python standard library để kiểm ID, link nội bộ, cấu trúc JSON và những bất biến số trong oracle; **không phải lựa chọn Python làm product tech stack**. Chưa chạy app/provider/accounting/pilot khi script này pass.

## 3. Definition of Done tối thiểu cho một vertical slice

| Cấp | Kết quả |
|---|---|
| DOC_DEFINED | BR/SOP/AC/scenario/expected nhất quán và không có quyết định ngầm |
| MODEL_CHECKED | Công thức/số mẫu có thể tái lập và validator pass |
| LOCAL_IMPLEMENTATION_VERIFIED | Test code chạy trên implementation thật với build, logs và actual/expected |
| INTEGRATED_E2E_VERIFIED | Hành vi E2E trên hệ thống hợp lệ, gồm concurrency/fault/ngoại hệ thống theo phạm vi |
| TENANT_GO_LIVE_ACCEPTED | NPP cụ thể đã vượt Product Verification và toàn bộ gate tenant/mode; có hồ sơ chấp nhận riêng |

Một PR implementation ghi tối thiểu: covered BR/AC, input fixture/version, expected, actual, test command, build ID, pending/blocked và Owner decision nếu thay đổi rule. Không tự coi synthetic docs CI là nghiệm thu vận hành.

## 4. Gating thực tế

G-STOCK/G-CUT/G-IDEMP/G-LEDGER/G-INV là P0 không miễn. EV-01..15 còn cần test thực; B-CASE/LEGAL-MEMO và INV-09 không đổi status từ các oracle. Offline A không mở chỉ vì logic local pass; B_NO_CHANNEL vẫn BLOCKED.

## 5. Thay đổi oracle

Khi cần sửa rule hoặc expected, phải nêu ID, snapshot trước, phép tái tính sau, tác động lên những case khác và Owner review. Không xóa test âm hoặc sửa expected chỉ để CI xanh.
