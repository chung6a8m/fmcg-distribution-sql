# FMCG Distribution — DMS Product Repository

Repository độc lập để triển khai ứng dụng DMS cho doanh nghiệp phân phối hàng tiêu dùng Việt Nam theo hướng **Business-first dành cho solo developer**. Không phải fork, submodule hoặc subtree của repository nguồn.

## Bắt đầu từ Business Baseline

1. Đọc [Business Specification](business/README.md) và [phạm vi MVP](business/scope.md).
2. Tra cứu [quy tắc](business/business-rules.md), [công thức](business/calculations.md) và [quy trình](business/workflows/).
3. Lấy [acceptance criteria](business/acceptance.md), [scenarios và golden data](business/reference-data/README.md) để xác định expected behavior.
4. Xem [hướng dẫn kiểm chứng](business/validation-guide.md) và [chỉ dẫn cho agent](AGENTS.md).

Nguồn snapshot được ghi tại [business.lock.json](business.lock.json). Thư mục `business/` là **read-only** trong repository ứng dụng: mọi thay đổi ngữ nghĩa phải được đề xuất, xem xét và phê duyệt ở canonical repository trước khi chủ động nâng Business Baseline tại đây. Tài liệu, scenario và golden data đã có trong repository này; không cần mở repository nguồn để phát triển hằng ngày.

## Kiểm tra contract

```sh
python3 tools/validate_business.py
git rev-parse HEAD:business
```

Tree SHA phải bằng `businessTreeSha` trong `business.lock.json`. Workflow `.github/workflows/business-contract.yml` chạy validator khi push/PR. Kết quả chỉ xác nhận **document/model**, không phải implementation verified hoặc tenant go-live accepted.

## Trạng thái

Đã cố định **Business Baseline v1.0**; **chưa chọn tech stack, chưa có source ứng dụng và chưa có roadmap triển khai**. Những nội dung này chỉ bổ sung sau khi Owner quyết định.
