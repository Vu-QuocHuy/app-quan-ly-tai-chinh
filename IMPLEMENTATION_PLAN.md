# Kế hoạch triển khai ứng dụng Quản lý Tài chính

> Trạng thái: Active v2  
> Thời lượng: 8 tuần  
> Nhân sự giả định: 4 người  
> Nền tảng MVP: Flutter, ưu tiên Android  
> Ứng dụng quản lý thu chi cá nhân, trong đó hóa đơn là một nguồn dữ liệu đầu vào.

## 1. Mục tiêu sản phẩm

Xây dựng một ứng dụng Flutter giúp người dùng cá nhân nhập hóa đơn từ nhiều nguồn, chuẩn hóa dữ liệu, xác nhận kết quả và theo dõi chi tiêu. MVP phải chứng minh được lợi thế "structured data first": ưu tiên XML/PDF text, chỉ dùng OCR và AI khi dữ liệu không có cấu trúc.

Luồng giá trị chính:

```text
Nhập hóa đơn
    -> nhận diện nguồn
    -> trích xuất
    -> chuẩn hóa và kiểm tra
    -> người dùng xác nhận nếu cần
    -> lưu cục bộ
    -> phân loại và phân tích chi tiêu
```

### Mục tiêu MVP bắt buộc

- Import và parse hóa đơn XML thành công.
- Chụp/chọn ảnh, OCR trên thiết bị, trích xuất trường bằng AI qua backend.
- Hỗ trợ PDF có text; PDF scan có thể chuyển sang luồng OCR hoặc báo rõ giới hạn.
- Có màn hình review để người dùng sửa dữ liệu trước khi xác nhận.
- Lưu dữ liệu local-first và xem được khi không có mạng.
- Phân loại danh mục, ghi nhớ merchant và cho phép sửa thủ công.
- Phát hiện hóa đơn trùng.
- Dashboard tháng, ngân sách theo danh mục và cảnh báo vượt ngân sách.
- Không để API key hoặc secret trong ứng dụng Flutter.

### Tính năng có điều kiện

- QR lookup chỉ được đưa vào MVP nếu hoàn thành proof-of-concept ổn định trước cuối tuần 6.
- Nếu QR phụ thuộc trang bên thứ ba không ổn định, phát hành dưới nhãn `Experimental` và không dùng làm đường demo chính.

### Ngoài phạm vi MVP

- Đồng bộ gia đình/nhiều thiết bị.
- Hỏi đáp tự nhiên trên dữ liệu chi tiêu.
- Export phục vụ kê khai thuế chính thức.
- Quy trình duyệt chi phí doanh nghiệp.
- Microservices, Kubernetes hoặc data warehouse.
- Flutter Web và desktop.

## 2. Tiêu chí thành công

Sử dụng một bộ dữ liệu kiểm thử cố định, đã loại bỏ hoặc che thông tin nhạy cảm.

| Chỉ số | Mục tiêu MVP |
|---|---:|
| XML parse thành công | >= 95% trên tập fixture đã hỗ trợ |
| Độ chính xác exact-match của `seller`, `date`, `invoiceNumber`, `total` trên ảnh đủ rõ | >= 90% |
| Tổng tiền sau chuẩn hóa khớp dữ liệu chuẩn | >= 95% |
| Import XML local trên thiết bị tham chiếu | < 2 giây |
| OCR + AI trong điều kiện mạng ổn định | p95 < 15 giây |
| Import lặp lại cùng một file | Không tạo bản ghi đã xác nhận thứ hai |
| Sử dụng offline | Xem, thêm thủ công, sửa và xác nhận được |
| Chất lượng release | Không còn bug P0/P1; luồng demo có integration test |

Không dùng accuracy tổng hợp duy nhất. Báo cáo riêng độ chính xác của trường cốt lõi, line item và category.

## 3. Kiến trúc mục tiêu

### 3.1 Flutter app

Áp dụng feature-first, MVVM và repository pattern. UI không gọi trực tiếp database, Supabase hoặc HTTP client.

```text
lib/
  app/
    bootstrap/
    config/
    routing/
    theme/
  core/
    database/
    errors/
    logging/
    network/
    security/
    utils/
  features/
    ingestion/
      data/
      domain/
      presentation/
    review/
    invoices/
    categories/
    budgets/
    dashboard/
    settings/
  shared/
    models/
    ui/
```

Stack dự kiến:

| Nhu cầu | Lựa chọn |
|---|---|
| State/DI | Riverpod |
| Navigation | `go_router` |
| Local database | Drift + SQLite |
| Immutable models | Freezed + JSON serialization |
| HTTP | Dio hoặc HTTP client có interceptor |
| File/camera | `file_picker`, `image_picker` hoặc `camera` |
| OCR/barcode | Flutter plugin bọc ML Kit |
| Background job | WorkManager; isolate cho CPU-bound Dart code |
| Chart | `fl_chart` |
| Secure local values | secure storage |
| Monitoring | Crashlytics + Performance Monitoring |

Không khóa version package trong tài liệu. Version cụ thể được pin trong `pubspec.lock` khi khởi tạo dự án và chỉ nâng sau khi test.

### 3.2 Backend MVP

Dùng modular monolith serverless, ưu tiên Supabase Edge Functions hoặc Cloud Run. Không gọi Gemini trực tiếp từ mobile.

Các module logic:

```text
API
  -> authentication/App Check
  -> rate limiting
  -> extraction service
  -> classification service
  -> QR provider adapters
  -> audit/metrics
```

API tối thiểu:

| Endpoint | Mục đích |
|---|---|
| `POST /v1/extractions/ocr-text` | Nhận OCR text, trả dữ liệu theo schema |
| `POST /v1/classifications` | Phân loại merchant chưa có mapping |
| `POST /v1/qr/resolve` | Tra cứu QR qua provider adapter, experimental |
| `GET /health` | Health check cho CI/demo |

Mọi request tạo extraction phải có `requestId`/idempotency key. Log không được chứa ảnh gốc, toàn bộ OCR text, MST cá nhân hoặc dữ liệu thanh toán nhạy cảm.

### 3.3 Pipeline ingestion

```text
Input
  -> fingerprint SHA-256
  -> source detector
  -> adapter XML | PDF text | QR | OCR
  -> canonical normalizer
  -> deterministic validation
  -> duplicate detector
  -> needsReview hoặc confirmed
  -> enrichment/category
```

Mỗi adapter implement cùng contract:

```text
canHandle(input) -> bool
extract(input) -> ExtractionResult
parserName -> string
parserVersion -> string
```

AI structured output chỉ bảo đảm hình dạng dữ liệu. Các kiểm tra nghiệp vụ như tổng tiền, ngày, mã số thuế, thuế suất và line-item sum phải là code xác định.

## 4. Canonical data model

### Invoice

- `id`: UUID local.
- `cloudId`: nullable, dành cho giai đoạn sync.
- `sellerName`, `sellerTaxCode`.
- `invoiceNumber`, `invoiceSymbol`.
- `issuedAt`, `timezone`.
- `currencyCode`.
- `subtotalMinor`, `taxMinor`, `totalMinor`: integer, không dùng `double`.
- `sourceType`: `xml`, `pdfText`, `qr`, `imageOcr`, `manual`.
- `sourceHash`: SHA-256 phục vụ idempotency.
- `status`: `queued`, `extracting`, `validating`, `needsReview`, `confirmed`, `failed`.
- `categoryId`.
- `createdAt`, `updatedAt`, `confirmedAt`.
- `syncState`: để sẵn cho giai đoạn sau, chưa cần cloud sync trong MVP.

### Các bảng liên quan

- `InvoiceLine`: mô tả, số lượng, đơn giá, giảm giá, thuế, thành tiền.
- `TaxBreakdown`: thuế suất và số tiền theo từng nhóm.
- `ExtractionAttempt`: adapter/model/version, thời gian, trạng thái lỗi.
- `FieldEvidence`: field, raw value, normalized value, source, confidence, correctedByUser.
- `Category`: danh mục hệ thống và danh mục tùy chỉnh.
- `MerchantRule`: normalized merchant -> category, ưu tiên rule do người dùng tạo.
- `Budget`: tháng, category, hạn mức minor unit.
- `DuplicateCandidate`: hai invoice và lý do/ngưỡng match.

Schema phải có migration test ngay từ migration đầu tiên.

## 5. Quy tắc nghiệp vụ nền tảng

- Giá trị do người dùng xác nhận luôn ưu tiên hơn AI và rule mặc định.
- XML/PDF text được ưu tiên trước OCR, nhưng vẫn phải validation.
- Confidence lưu theo field; không suy ra một điểm cố định chỉ từ loại nguồn.
- Nếu `subtotal + tax - discount` lệch `total` quá tolerance, chuyển `needsReview`.
- Duplicate exact hash được chặn tự động; fuzzy duplicate chỉ cảnh báo người dùng.
- Category resolution theo thứ tự: user merchant rule -> local rule -> backend/AI -> `other`.
- Ảnh/file gốc mặc định chỉ lưu local. Upload phải có mục đích rõ ràng và sự đồng ý của người dùng.
- Có thể xóa file gốc mà không làm mất dữ liệu hóa đơn đã xác nhận.

## 6. Backlog và thứ tự triển khai

Quy ước:

- `P0`: bắt buộc để MVP hoạt động.
- `P1`: cần cho bản demo/release tốt.
- `P2`: chỉ làm sau khi P0/P1 ổn định.
- Mỗi task chỉ được đánh dấu hoàn thành khi đạt Definition of Done ở mục 9.

### Epic A — Product discovery và dữ liệu chuẩn

- [ ] `PRD-001 P0` Chốt persona chính và ba user journey: XML, ảnh, review.
- [ ] `PRD-002 P0` Thu thập tối thiểu 20 mẫu đã ẩn danh từ ít nhất 3 biến thể/provider.
- [ ] `PRD-003 P0` Tạo ground-truth JSON cho từng fixture.
- [x] `PRD-004 P0` Chốt canonical schema, enum và tolerance tiền/thuế.
- [x] `PRD-005 P1` Vẽ wireframe cho Home, Import, Processing, Review, Detail, Dashboard, Budget và Settings.

### Epic B — Foundation Flutter

- [x] `APP-001 P0` Khởi tạo Flutter project và pin Flutter SDK cho cả nhóm.
- [x] `APP-002 P0` Tạo flavors `dev`, `staging`, `production` và cấu hình riêng từng môi trường.
- [x] `APP-003 P0` Thiết lập lint, formatter, code generation và pre-commit checks.
- [x] `APP-004 P0` Thiết lập feature-first folders, Riverpod, router và theme.
- [x] `APP-005 P0` Thiết lập Drift schema, migration v1 -> v2 và repository interfaces.
- [x] `APP-006 P1` Error model thống nhất, logging có redaction và UI loading/error/offline.
- [x] `APP-007 P1` CI chạy analyze, unit test, widget test và Android debug build.

### Epic C — XML vertical slice

- [x] `XML-001 P0` Định nghĩa `InvoiceSource` và `InvoiceExtractor` contract.
- [x] `XML-002 P0` File picker và kiểm tra extension/MIME/size an toàn.
- [x] `XML-003 P0` Tính source hash và exact duplicate guard.
- [x] `XML-004 P0` Viết XML adapter đầu tiên từ fixture thực.
- [x] `XML-005 P0` Canonical normalizer cho số tiền, ngày, MST và tax breakdown.
- [x] `XML-006 P0` Deterministic validator và trạng thái `needsReview`.
- [x] `XML-007 P0` Màn hình review/edit/confirm.
- [x] `XML-008 P0` Lưu transaction Invoice + lines + evidence vào Drift.
- [ ] `XML-009 P1` Thêm adapter/schema variants thứ hai và thứ ba.
- [~] `XML-010 P1` Fixture tests và báo cáo parse accuracy.

### Epic D — Image OCR + AI vertical slice

- [x] `OCR-001 P0` Chụp ảnh/chọn ảnh, xử lý permission và giới hạn dung lượng.
- [x] `OCR-002 P0` OCR on-device, chuẩn hóa line breaks và loại bỏ noise tối thiểu.
- [x] `BE-001 P0` Khởi tạo backend, environment secrets và health endpoint.
- [x] `BE-002 P0` Xác thực Supabase JWT, request schema và rate limit.
- [x] `AI-001 P0` Định nghĩa structured output schema khớp canonical model.
- [x] `AI-002 P0` Implement action `extract` trong Supabase Edge Function `ai-api`, timeout, retry có giới hạn và error mapping.
- [x] `AI-003 P0` Validate AI response trước khi trả mobile.
- [x] `OCR-003 P0` Kết nối OCR text -> backend -> review -> save.
- [x] `OCR-004 P1` Field confidence/evidence và highlight field cần kiểm tra.
- [~] `OCR-005 P1` Đã có inference/evaluation cho exact match, CER/WER, confidence, coverage, metric theo field và release gate; còn chạy fixture ảnh thật để chốt ngưỡng `seller/date/total`.
- [~] `OCR-006 P1` Pipeline fine-tune `PP-OCRv5_mobile_rec`: đã có cropper, converter MC-OCR Kaggle v17, preflight, split chống leakage, train-only charset, resolved YAML, baseline, train/export/inference, notebook Kaggle end-to-end và ZIP provenance; còn GPU run và weights đạt gate.
- [ ] `OCR-007 P1` Tích hợp model fine-tuned có version vào backend/on-device adapter, benchmark latency và giữ ML Kit fallback.
- [~] `OCR-008 P1` Dataset governance: đã có schema line/document, duplicate split guard, cảnh báo PII, manifest/hash, source-version/license flag và hướng dẫn private Kaggle Dataset; dataset MC-OCR hiện ghi license `Unknown`, còn xác minh quyền sử dụng/phát hành và bổ sung dữ liệu thật đã ẩn danh.
- [ ] `OCR-009 P1` Adapter nhãn KIE MC-OCR: khảo sát `mcocr_train_df.csv`, liên kết bbox/line với `seller/date/total`, thêm field-level test gate; không dùng test recognition để tune.

### Epic E — PDF

- [~] `PDF-001 P0` Technical spike: kiểm tra text extraction trên Android và iOS target.
- [x] `PDF-002 P0` Adapter cho PDF có text layer.
- [x] `PDF-003 P0` Phát hiện PDF không có đủ text và hướng người dùng sang OCR.
- [x] `PDF-004 P1` Parse text -> canonical schema bằng deterministic rules hoặc AI fallback.
- [~] `PDF-005 P1` Đã có test chữ ký `%PDF-` cho file hợp lệ/rỗng/giả mạo; fixture text-layer, corrupt và password-protected thực còn cần chạy với PDF engine trên thiết bị.

### Epic F — Category, duplicate và analytics

- [x] `CAT-001 P0` Seed danh mục mặc định và cho phép sửa category.
- [x] `CAT-002 P0` Merchant normalization và `MerchantRule` local cache.
- [x] `CAT-003 P1` Backend classification cho merchant mới; không gọi lại khi đã có rule.
- [x] `DUP-001 P0` Exact duplicate bằng source hash.
- [x] `DUP-002 P1` Fuzzy duplicate theo MST/seller, số hóa đơn, ngày và tổng tiền.
- [x] `DBO-001 P0` Dashboard tổng tháng và breakdown theo category.
- [x] `DBO-002 P0` Budget CRUD và progress theo tháng.
- [x] `DBO-003 P1` So sánh tháng hiện tại/tháng trước và cảnh báo vượt ngân sách.
- [~] `DBO-004 P2` Dự báo cuối tháng và nhận diện recurring expense (đã có engine, SQL window, UI và unit test; chờ debug thiết bị).

### Epic G — QR experimental

- [~] `QR-001 P1` Đọc QR on-device và phân loại payload URL/text (đã có camera + ML Kit + parser, chưa tra cứu provider).
- [ ] `QR-002 P1` Thiết kế provider adapter và SSRF-safe URL allowlist ở backend.
- [ ] `QR-003 P1` Proof-of-concept với một provider thực.
- [ ] `QR-004 P2` Cache, timeout, circuit breaker và provider thứ hai.
- [~] `QR-005 P2` Cached demo fixture và nhãn `Experimental` (đã có nhãn/guard UX, chưa có fixture provider).

Decision gate cuối tuần 6:

- Nếu success rate trên fixture/provider đã chọn >= 90% và không phụ thuộc thao tác CAPTCHA, tiếp tục QR-004/005.
- Nếu không đạt, đóng scope QR ở proof-of-concept và chuyển nguồn lực sang hardening P0/P1.

### Epic H — Security, quality và release

- [x] `SEC-001 P0` Không có secret trong source/app bundle; secret chỉ ở backend environment.
- [x] `SEC-002 P0` Redact PII khỏi log và crash report breadcrumbs.
- [x] `SEC-003 P0` Database/file retention và chức năng xóa dữ liệu người dùng.
- [x] `SEC-004 P1` Supabase JWT enforcement cho Edge Function và secret server-side.
- [x] `SEC-005 P1` Threat review cho upload, XML entity, malformed file, SSRF và abuse AI quota.
- [x] `QA-001 P0` Unit tests cho parser, normalizer, validators, money và duplicate logic.
- [x] `QA-002 P0` Widget tests cho review form và validation errors.
- [~] `QA-003 P0` Integration tests cho XML và OCR happy path.
- [~] `QA-004 P1` Đã test chatbot chưa cấu hình/timeout, backup rỗng/sai UTF-8 và PDF sai chữ ký; API quota, PDF engine corrupt/password và process restart trên thiết bị còn pending.
- [~] `REL-001 P1` Staging build, Crashlytics, performance traces và release checklist.
- [~] `REL-002 P1` Demo dataset, kịch bản demo chính và fallback không cần mạng.

### Epic I — Data scale và hiệu năng local

- [x] `SCALE-DB-001 P0` Drift schema v2: search text, notes, tags, revision, sync state và soft-delete.
- [x] `SCALE-DB-002 P0` Migration test v1 -> v2, backfill search text và index cho list/dashboard/job.
- [x] `SCALE-DB-003 P0` Lọc kết hợp và tìm kiếm chạy trong SQL, không nạp toàn bộ danh sách vào Dart.
- [x] `SCALE-DB-004 P0` Cursor pagination ổn định theo `updatedAt + id`, giới hạn tối đa mỗi page.
- [x] `SCALE-DB-005 P0` Dashboard dùng SQL aggregation theo tháng/category/ngày.
- [ ] `SCALE-DB-006 P1` Benchmark 10k/50k/100k hóa đơn trên thiết bị cấu hình thấp và lưu artifact CI.
- [ ] `SCALE-DB-007 P1` Chuyển tìm kiếm sang SQLite FTS5 khi benchmark LIKE vượt ngưỡng 150 ms.
- [ ] `SCALE-DB-008 P2` Chính sách archive dữ liệu cũ và VACUUM có kiểm soát theo dung lượng thực tế.

### Epic J — Backup, phục hồi và khả năng chuyển dữ liệu

- [x] `BACKUP-001 P0` Xuất JSON versioned gồm invoice, line, evidence, notes và tags.
- [~] `BACKUP-002 P0` Preview/validate restore JSON, bỏ trùng ID/hash, map category và ghi batch transaction (chờ debug file picker trên Android).
- [x] `BACKUP-003 P0` Parser restore có partial failure report và unit test regression.
- [~] `BACKUP-004 P1` Backup mã hóa bằng khóa người dùng và kiểm tra integrity checksum (đã có AES-256-GCM, PBKDF2-HMAC-SHA256, checksum envelope và luồng nhập mật khẩu; còn debug thiết bị, secure storage/key rotation cho cloud).
- [~] `BACKUP-005 P1` Export Excel/PDF có template báo cáo; đã có CSV tương thích Excel và PDF local gồm tổng quan, ngân sách, danh mục, danh sách hóa đơn; không dùng làm chứng từ thuế chính thức.
- [~] `BACKUP-006 P2` Đã có local provider, catalog metadata và private Supabase provider chỉ nhận `.hdbak`, gồm upload/list/download/preview/restore/delete và retention file thực tế 90 ngày/tối đa 20 file; scheduler và restore drill trên thiết bị còn pending.

### Epic K — Job reliability, notification và vận hành offline

- [~] `JOB-001 P0` Persist import job, trạng thái, số lần thử, exponential backoff và phục hồi job bị gián đoạn (chờ process-restart/device test).
- [~] `JOB-002 P0` Màn hình lịch sử import, lỗi rút gọn và thao tác retry ngay (chờ debug thiết bị).
- [x] `JOB-003 P1` Tự compact outbox pending theo aggregate để không tăng vô hạn khi sửa nhiều lần.
- [x] `NOTIF-001 P1` Budget alert policy 80%/vượt mức, dedup key và preference bật/tắt.
- [~] `NOTIF-002 P1` Local notification Android/iOS, permission UX và deep-link vào ngân sách (đã có service, permission runtime, dedup, trigger từ dashboard và route `/budgets`; còn debug thiết bị/background reliability).
- [ ] `JOB-004 P1` WorkManager/background execution có constraint mạng/pin và giới hạn thời gian.
- [~] `JOB-005 P2` Import job vượt retry budget có trạng thái terminal, replay từng job/hàng loạt và dọn lịch sử thành công; dead-letter/replay cho cloud job còn pending.

### Epic L — Auth và cloud sync

- [x] `SYNC-001 P1` Soft-delete, revision và transactional outbox cho thay đổi hóa đơn.
- [x] `SYNC-002 P1` `SyncIdentityProvider`/`SyncGateway` abstraction, health state và sync engine theo batch.
- [x] `SYNC-003 P1` Recovery event đang `sending`, retry backoff, terminal failure và cleanup event đã gửi.
- [~] `AUTH-001 P1` Supabase Auth email/password, sign-out, đổi mật khẩu và email khôi phục đã có; OAuth, account linking và account deletion còn pending.
- [~] `SYNC-004 P1` Supabase PostgreSQL gateway thật, RPC nguyên tử, RLS và private Storage đã triển khai; còn debug thiết bị và telemetry production.
- [x] `SYNC-005 P1` Pull delta bằng cursor, idempotency server, tombstone reference và conflict state theo revision; đã có màn hình chọn bản cloud/local.
- [x] `SYNC-008 P1` Auto sync khi app resume, sync sau đăng nhập và local cursor theo user.
- [x] `SYNC-009 P1` Outbox và RPC push cho danh mục, ngân sách và merchant rule; cloud seed danh mục mặc định đã có.
- [x] `SYNC-010 P1` Conflict snapshot, resolve local/cloud và requeue revision mới.
- [x] `SYNC-011 P1` Delta pull cho category, budget và merchant rule bằng cursor riêng từng aggregate.
- [ ] `SYNC-006 P2` Shared wallet, role thành viên và audit trail append-only.
- [x] `SYNC-007 P2` PostgreSQL Supabase schema cho invoice, line, evidence, category, budget và merchant rule; local Drift vẫn là nguồn đọc offline.

### Epic M — Intelligence và product scale

- [~] `DATA-001 P1` Notes/tags có edit, detail, search (seller/MST/số hóa đơn/ghi chú/tag), export và restore (chờ widget/device debug).
- [x] `INSIGHT-001 P1` Forecast cuối tháng và recurring detection có unit test xác định.
- [~] `INSIGHT-002 P1` Cảnh báo chi tiêu bất thường với baseline giải thích được và feedback false-positive (đã có baseline merchant, severity, explanation, dashboard/chat và lưu feedback báo nhầm local; test thiết bị còn pending).
- [~] `AI-JOB-001 P1` Async extraction API: submit/status/result/cancel với idempotency key (đã có mobile contract/client scaffold; backend endpoint còn pending).
- [ ] `AI-JOB-002 P1` Worker queue, timeout budget, dead-letter queue và replay tool phía backend.
- [ ] `AI-JOB-003 P1` Model/prompt version, evaluation gate và cost budget theo môi trường/người dùng.
- [x] `SEARCH-001 P2` Hỏi đáp chi tiêu có citation về hóa đơn nguồn, không tự suy diễn số liệu (chat UI, local query offline, Supabase Edge Function `ai-api`, lịch sử local và connector tỷ giá; câu hỏi local không gọi AI).
- [x] `SEARCH-002 P2` Bộ tool read-only cho chatbot: tool được tách theo summary, budget, insights, categories, recent và search; chỉ tool phù hợp được gọi, facts invoice-level bị chặn trước khi ra ngoài.
- [~] `SEARCH-003 P2` Quản lý nguồn bên ngoài: đã có allowlist tiền tệ, attribution, timeout, cache TTL và feature flag cho connector tỷ giá; quota/audit nhiều provider còn pending.
- [ ] `OPS-001 P1` Crash/performance monitoring, redaction audit, SLO và dashboard latency/error/cost.
- [ ] `OPS-002 P1` Remote config/feature flag cho QR, AI provider, sync và rollout theo phần trăm.

## 7. Roadmap 8 tuần

| Tuần | Kết quả phải demo được | Task trọng tâm |
|---|---|---|
| 1 | App shell chạy, schema và fixture được chốt | PRD-001..005, APP-001..005, PDF-001 |
| 2 | Import XML -> review -> lưu -> danh sách | XML-001..008, QA parser cơ bản |
| 3 | XML variants và backend skeleton | XML-009..010, BE-001..002, APP-006..007 |
| 4 | Ảnh -> OCR -> AI -> review -> lưu | OCR-001..004, AI-001..003 |
| 5 | PDF text, category cache, duplicate | PDF-002..005, CAT-001..003, DUP-001..002 |
| 6 | Dashboard và budget hoàn chỉnh | DBO-001..003, QR-001..003, QR decision gate |
| 7 | Hardening hoặc QR mở rộng nếu qua gate | SEC-001..005, QA-001..004, QR-004..005 |
| 8 | Release candidate và demo ổn định | REL-001..002, sửa bug, đo metric, tài liệu bảo vệ |

Checkpoint cuối mỗi tuần:

- Demo trên thiết bị thật, không chỉ emulator.
- Cập nhật checkbox và rủi ro trong file này.
- Chốt bug P0/P1 trước khi kéo thêm P2.
- Lưu metric/test evidence vào repo hoặc CI artifact.

## 8. Phân công 4 người

| Vai trò | Trách nhiệm chính | Trách nhiệm phụ |
|---|---|---|
| A — Flutter/UI lead | App foundation, design system, navigation, review UI | Dashboard, accessibility |
| B — Ingestion lead | XML, PDF, OCR/native plugins, normalization | Fixture và parser tests |
| C — Backend/AI lead | Backend, Gemini, security, QR adapters | Observability và quota |
| D — Data/QA lead | Drift, repository, duplicate, analytics, test automation | CI và release evidence |

Không chia dự án thành bốn khối chỉ ghép vào cuối kỳ. Mỗi tuần chọn một vertical slice; A-D cùng thống nhất contract rồi mỗi người hoàn thành phần của mình để slice chạy end-to-end.

Quy tắc ownership:

- Mỗi task có một owner chính và một reviewer không cùng owner.
- Thay đổi canonical schema cần review của B, C và D.
- Thay đổi public API cần contract test trước khi merge.
- Không merge code generation, migration hoặc parser mới nếu thiếu fixture test.

## 9. Definition of Done

Một task chỉ được đánh dấu `[x]` khi:

- Acceptance criteria của task đã đạt.
- Code đã format, analyze không lỗi và không thêm warning mới.
- Có unit/widget/integration test tương ứng với mức rủi ro.
- Đã test loading, empty, error và offline nếu có liên quan.
- Không log secret hoặc dữ liệu hóa đơn nhạy cảm.
- Migration/API/schema thay đổi đã cập nhật fixture và tài liệu.
- Có reviewer khác owner xác nhận.
- Tính năng chạy trên thiết bị Android thật.

Definition of Done cho một milestone:

- Luồng end-to-end có thể demo từ màn hình đầu đến dữ liệu lưu cuối.
- Không cần chỉnh database hoặc gọi API thủ công để demo.
- Có đường fallback khi mạng/API ngoài bị lỗi.
- Bug P0/P1 của milestone đã đóng.

## 10. Chiến lược test

### Test pyramid

- Nhiều unit test: parser, normalizer, validator, duplicate, repository và ViewModel.
- Đủ widget test: form review, invoice list, dashboard states.
- Một số integration test ổn định: XML happy path, OCR mocked backend, offline reopen.
- Manual/device test: camera, file picker, permission, background/resume và thiết bị cấu hình thấp.

### Fixture policy

```text
test/fixtures/
  xml/
  pdf/
  images/
  ground_truth/
  malformed/
```

- Không commit hóa đơn thật chưa ẩn danh.
- Mỗi bug parser phải tạo một regression fixture trước hoặc cùng lúc sửa lỗi.
- Ground truth được review thủ công bởi ít nhất hai thành viên.
- AI evaluation dùng temperature thấp/ổn định và ghi lại model version.

## 11. Git, CI và quản lý công việc

- Nhánh chính luôn build được.
- Branch ngắn theo dạng `feat/XML-004-first-adapter` hoặc `fix/OCR-003-timeout`.
- Pull request nhỏ, gắn đúng task ID và có bằng chứng test.
- Không commit `.env`, service account, API key hoặc file hóa đơn nhạy cảm.
- CI bắt buộc: format check, analyze, unit/widget tests và Android build.
- Tag milestone theo `week-2-xml-slice`, `week-4-ocr-slice`, `v0.1.0-rc1`.

## 12. Rủi ro và phương án giảm thiểu

| Rủi ro | Tác động | Giảm thiểu |
|---|---|---|
| XML khác schema/provider | Parse fail | Adapter registry, fixtures, versioned parser |
| OCR tiếng Việt sai | Dữ liệu sai | Review UI, field confidence, ground-truth evaluation |
| AI trả JSON đúng nhưng giá trị sai | Sai tài chính | Deterministic validation, tolerance, human confirmation |
| Gemini timeout/quota | Luồng bị chặn | Timeout, retry giới hạn, cached demo, manual fallback |
| QR bị CAPTCHA/chặn bot | Demo hỏng | Decision gate, experimental scope, không làm đường demo chính |
| PDF plugin không ổn định | Trễ roadmap | Spike tuần 1, chỉ cam kết text-layer PDF |
| Drift/Firestore sync phức tạp | Conflict dữ liệu | Không làm multi-device sync trong MVP |
| Lộ dữ liệu hóa đơn | Rủi ro bảo mật | Local-first, consent upload, redacted logs, deletion controls |
| Scope creep do AI code nhanh | Chất lượng giảm | P0/P1 trước P2, weekly gate, DoD bắt buộc |

## 13. Hướng phát triển sau MVP

### Phase 2 — Beta cá nhân/gia đình

- Supabase Auth và cloud sync.
- Shared wallet, member role và conflict strategy.
- Export PDF/Excel.
- Recurring expense và cảnh báo bất thường.
- Subscription/freemium và cost limit cho AI.

### Phase 3 — Freelancer/hộ kinh doanh

- Workspace tách biệt dữ liệu cá nhân/công việc.
- Báo cáo chứng từ, tag dự án/khách hàng.
- Audit trail và export cho kế toán.
- Backend chuyển dần sang PostgreSQL nếu relational query/reporting trở thành nhu cầu chính.

### Phase 4 — B2B/API

- Multi-tenancy, RBAC, approval workflow.
- Public ingestion API và webhook.
- Tách asynchronous extraction workers khi có bằng chứng tải.
- Versioned provider parsers, queue, dead-letter queue và replay tool.
- SLA, retention policy, observability và cost allocation theo tenant.

Không tách microservice chỉ vì số người dùng tăng. Chỉ tách khi một module có profile tải, nhu cầu scale hoặc chu kỳ deploy độc lập được đo bằng dữ liệu thực.

## 14. Việc bắt đầu ngay

Thứ tự cho buổi làm việc đầu tiên:

1. Hoàn thành `PRD-001`: chốt persona và ba user journey MVP.
2. Tạo cấu trúc `test/fixtures` và bắt đầu `PRD-002/003`.
3. Chốt canonical schema bằng 3-5 hóa đơn thật đã ẩn danh (`PRD-004`).
4. Chạy spike PDF trên Flutter (`PDF-001`) để loại rủi ro plugin sớm.
5. Sau khi schema được duyệt, thực hiện `APP-001` và scaffold dự án.

Không bắt đầu UI dashboard, QR hoặc prompt tuning trước khi `PRD-004` hoàn tất.

## 15. Scale gates sau MVP

Không chuyển kiến trúc chỉ theo số người dùng đăng ký. Mỗi bước scale phải dựa trên metric:

| Gate | Dấu hiệu | Hành động |
|---|---|---|
| Local data | List/search p95 > 150 ms ở 50k hóa đơn | Bật FTS5, kiểm tra query plan/index, benchmark lại trước khi archive |
| Import | Queue delay p95 > 30 giây hoặc retry tăng liên tục | Tách async worker, idempotency store và dead-letter queue |
| Cloud sync | Conflict > 1% hoặc outbox tồn > 15 phút | Delta pull cursor, conflict telemetry và reconciliation UI |
| Backend | Một module chiếm > 60% CPU/cost hoặc cần deploy độc lập | Tách đúng module đó khỏi modular monolith |
| Reporting | SQLite/Firestore không đáp ứng báo cáo chéo workspace | Read model/PostgreSQL; giữ ingestion path độc lập |
| Team/workspace | Có nhu cầu chia sẻ thật và audit bắt buộc | Multi-tenant boundary, RBAC, append-only audit và retention policy |

Thứ tự thực hiện gần nhất sau vòng debug thiết bị: `BACKUP-002` -> `JOB-001/002` -> `DATA-001/DBO-004` -> benchmark `SCALE-DB-006` -> cấu hình `AUTH-001/SYNC-004`. QR provider và AI async chỉ chạy song song khi fixture/evaluation gate đã sẵn sàng.
