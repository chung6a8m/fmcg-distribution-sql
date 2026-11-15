# SQL-05 — Owner Decision Register cho APP-00/APP-01

- **Ngày Owner quyết định:** 2026-11-15 (UTC+07).
- **Trạng thái:** `OWNER_APPROVED` cho sáu quyết định `OWN-SQL04-01..06` **ở phạm vi thiết kế và triển khai ứng dụng nonproduction**.
- **Nguồn:** Owner lựa chọn trực tiếp qua phiên phỏng vấn sáu quyết định tiếp sau [SQL-04 application handoff](../handoff/sql04-app-handoff.md) và [PR SQL-04 #7 đã review/merge](https://github.com/chung6a8m/fmcg-distribution-sql/pull/7).
- **Ranh giới:** Owner approval ≠ implementation verified ≠ business/product verification ≠ tenant go-live acceptance. APP-00/APP-01 chưa có ứng dụng/CI/evidence khi ghi register này.
- **Contract cố định:** [Business Baseline v1.0](../../business/README.md), [acceptance](../../business/acceptance.md), [golden oracles](../../business/reference-data/expected-results/golden-oracles.json), [lock](../../business.lock.json). Không được đổi `business/`, `business.lock.json` hoặc oracle để phù hợp code.

## Sáu quyết định Owner

| ID | Lựa chọn APPROVED | Phương án không chọn | Lý do và phạm vi |
|---|---|---|---|
| **OWN-SQL04-01** | **SQL Server** làm engine của APP-01 và sản phẩm | PostgreSQL; chỉ dùng SQL Server tạm cho APP-01 | Giữ hệ sinh thái và kinh nghiệm SQL-first; dùng schema ứng dụng mới qua migration, **không** lấy bốn schema SQL scratch làm production DDL. Engine/version/edition, license và workload production còn cần xác minh. |
| **OWN-SQL04-02** | **Database-per-tenant**, tiếp tục D-01 lịch sử | Shared database/shared schema; hybrid | Cách ly database từng seller/tenant. APP-01: ít nhất hai tenant DB để test routing/read/write isolation; tenant context do server xác thực; connection không do client tùy ý chỉ định. |
| **OWN-SQL04-03** | **.NET 10 LTS + ASP.NET Core Web API + Dapper + FluentMigrator**; Modular Monolith, REST/JSON, explicit transaction | EF Core; linq2db; microservices | Một codebase backend nhỏ cho solo developer; SQL/query và transaction boundary rõ, mọi effect nghiệp vụ có nguồn và idempotency. Không bắt buộc stored procedures từ prototype. |
| **OWN-SQL04-04** | **React + TypeScript + Vite + PWA**, responsive, **Online-first** | Web-only không PWA; frontend mobile native riêng | Một frontend cho desktop/kho và mobile/giao bán. Không bật offline business writes; offline A chờ thử riêng, B_NO_CHANNEL vẫn BLOCKED; PWA không phải quyền transaction offline. |
| **OWN-SQL04-05** | **Local-first + GitHub Actions CI** cho dev/nonproduction | Private test server ngay; managed cloud ngay | Giảm chi phí và vận hành sớm. Dùng scratch test DB có guard, secrets ngoài source, audit/evidence trên commit, kịch bản backup/restore synthetic; staging/production provider, access, retention và RPO/RTO cần quyết định/verification riêng. |
| **OWN-SQL04-06** | **Phê duyệt APP-00 + APP-01A..E**, thực hiện từng increment, synthetic nonproduction | Chỉ APP-00; slice A nhỏ; hoãn ứng dụng | Dùng AC-03 Mixed A+B_ONLINE synthetic để kiểm chứng ứng dụng tích hợp đầu tiên, không mô phỏng hóa đơn thật. Exit từng increment theo [roadmap APP](../roadmap/app-00-app-01.md). |

**Hiệu lực:** Đây là quyết định Owner cho phép tiến hành các increment APP-00 và APP-01A..E; từng PR vẫn cần review, CI/tests và evidence thực trên chính HEAD. Không tự miễn yêu cầu nghiệm thu kỹ thuật.

## Phạm vi cho phép

- Khởi tạo app/repository độc lập, giữ local copy của Business Baseline với đúng SHA trong lock; không cần fork, submodule, subtree hoặc runtime dependency tới canonical hay SQL scratch.
- APP-01 dùng fixture `SYNTHETIC_UNITLESS`, `invoiceEligible=false`; bảy checkpoints AC-03 T0..T6; kiểm tất cả **91 field mỗi run** bằng expected JSON nguồn, từ actual database ứng dụng.
- Quyền A, B quota/grant, manifest, stock/source/AR/COGS/cash custody/fund, maker-checker, retry/conflict/fault và tenant boundary phải có hậu điều kiện và negative tests tương ứng.
- Bất biến: A confirm/load không ghi AR/COGS; B sale/delivery/receipt atomic; B31/P465 + offered cash465 từ chối đúng `REJECTED_QUOTA`/`B_QUOTA_INSUFFICIENT` không có business effect.
- Database skeleton mới là app persistence; `ac03`, `ac09`, `ac21`, `ac06` chỉ là executable references độc lập, không phải một integrated schema.
- Repo SQL tiếp tục lưu prototype/evidence; app code và roadmap thực thi nên sống trong một repository ứng dụng độc lập. `chung6a8m/fmcg-distribution-dotnet` là **địa chỉ dự kiến, cần xác minh/tạo và cấp quyền ghi** trước khi push; không coi tồn tại chỉ vì đã được đặt tên.

## Quyết định chưa nằm trong phạm vi phê duyệt

- Chưa chọn edition/version/licensing SQL Server production, hosting/cloud, vùng đặt dữ liệu, SLO, RPO/RTO, retention thực, monitoring/billing, triển khai HA, hóa đơn provider và accounting adapter.
- Chưa có offline write hoặc B_NO_CHANNEL production, chưa có phê duyệt G-STOCK/G-CUT/G-IDEMP/G-LEDGER/G-INV; EV-01..15 và pilot/go-live vẫn pending/not run.
- APP-01 PASS chỉ là **integrated synthetic nonproduction** trong phạm vi đã test, **không** tự suy full AC-03 production E2E hoặc full AC-11 dependency/lost-ACK/restart.

## Khi nào cần Owner quyết định lại

Phải xin quyết định bổ sung nếu đổi DB engine, thay D-01 tenancy, runtime/frontend chính, chuyển sang production/pilot hoặc mở offline write; nếu thay phạm vi APP-01 làm lệch golden oracle; hoặc cần thay đổi bất kỳ semantics/BR/AC nào của Business Baseline. Với thay đổi business, thực hiện ở canonical và nâng lock có phê duyệt, không chỉnh snapshot tại đây.

## Trạng thái bàn giao (2026-11-15)

| Khía cạnh | Trạng thái |
|---|---|
| Owner decisions `OWN-SQL04-01..06` | **OWNER_APPROVED** |
| SQL-04 documents PR #7 | **MERGED / REVIEW_R2_PASS** |
| APP-00 implementation + app CI | **AUTHORIZED / NOT_STARTED tại thời điểm ghi** |
| APP-01A..E integrated implementation | **AUTHORIZED / NOT_STARTED tại thời điểm ghi** |
| Tenant/pilot/production go-live | **NOT_AUTHORIZED** |
