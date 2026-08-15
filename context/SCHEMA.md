# SCHEMA — Finance AI App (Firestore)

Firebase Project: `finance-ai-app-6df28` · Firestore hiện chạy ở **test mode** (xem `firestore.rules` để biết rule production dự kiến).

> **Lưu ý (sau phản biện hội đồng, xem ARCHITECTURE.md mục 3.4):** Financial Analytics Layer (điểm sức khỏe tài chính, danh sách vấn đề phát hiện) **không có collection Firestore riêng** — tính lại on-the-fly mỗi lần mở `AiInsightScreen` từ dữ liệu `transactions` sẵn có, không lưu lịch sử. Đây là quyết định thu hẹp phạm vi có chủ đích (xem PRD.md mục 2.1) để phù hợp thời gian còn lại của khóa luận.

## 1. ERD tổng quan (quan hệ qua `userId`)

```
                          ┌───────────────┐
                          │    users      │
                          │  (doc id=uid) │
                          └───────┬───────┘
                                  │ userId (mọi collection dưới đây
                                  │ đều có field userId trỏ về users/{uid})
        ┌──────────────┬─────────┼─────────────┬──────────────┐
        ▼              ▼         ▼             ▼              ▼
   ┌─────────┐   ┌───────────┐ ┌────────┐  ┌──────────┐  ┌───────────────┐
   │ wallets │   │categories │ │budgets │  │savingGoals│  │ notifications │
   └────┬────┘   └─────┬─────┘ └───┬────┘  └───────────┘  └───────────────┘
        │              │           │
        │   walletId   │categoryId │ categoryId
        └──────┬───────┴─────┬─────┘
               ▼              ▼
          ┌─────────────────────┐
          │    transactions      │
          │ (walletId+categoryId)│
          └─────────────────────┘

   users/{uid}/quickTemplates/{templateId}   ← sub-collection riêng, không phải top-level
```

**Không có** foreign key thật (NoSQL) — mọi liên kết là string ID được lưu như field thường, validate ở tầng ứng dụng (`FirestoreService`), không phải ở tầng database.

## 2. Collections chi tiết

### 2.1. `users/{uid}` — doc ID = Firebase Auth UID
| Field | Type | Bắt buộc | Ghi chú |
|---|---|---|---|
| name | string | ✓ | |
| email | string | ✓ | |
| avatar | string? | | URL Firebase Storage |
| monthlyIncome | number | | default 0 |
| savingGoal | string? | | mô tả tự do, khác với collection `savingGoals` |
| occupation | string? | | |
| createdAt | string (ISO8601) | ✓ | lưu dạng string, không dùng Timestamp Firestore |

### 2.2. `wallets/{walletId}`
| Field | Type | Ghi chú |
|---|---|---|
| userId | string | |
| walletName | string | |
| balance | number | cập nhật qua `FieldValue.increment`, không set trực tiếp khi có giao dịch |
| type | string | enum: `cash` \| `bank` \| `eWallet` \| `other` |
| createdAt | string (ISO8601) | |

### 2.3. `categories/{categoryId}`
| Field | Type | Ghi chú |
|---|---|---|
| userId | string | |
| name | string | |
| type | string | enum: `income` \| `expense` |
| icon | string | tên icon dạng string (VD `restaurant`) — **chưa map sang IconData ở UI** |
| color | number | ARGB int (VD `0xFFD32F2F`) |

### 2.4. `transactions/{transactionId}`
| Field | Type | Ghi chú |
|---|---|---|
| userId | string | |
| walletId | string | FK logic → wallets |
| categoryId | string | FK logic → categories |
| amount | number | |
| type | string | `income` \| `expense` |
| note | string? | |
| image | string? | **Đường dẫn file cục bộ trên thiết bị** (không phải URL cloud — xem PRD.md mục 7). Đọc bằng `Image.file(File(path))`, KHÔNG dùng `Image.network()`. |
| location | string? | |
| date | string (ISO8601) | dùng để filter theo ngày/tuần/tháng và cho biểu đồ 6 tháng |

**⚠️ Composite index bắt buộc** (đã khai báo trong `firestore.indexes.json`):
```json
{ "collectionGroup": "transactions", "fields": [
    { "fieldPath": "userId", "order": "ASCENDING" },
    { "fieldPath": "date", "order": "DESCENDING" }
]}
```
Lý do: `streamTransactions()` luôn `where('userId', isEqualTo: uid)` kết hợp `orderBy('date', descending: true)`, cộng thêm range filter `date >=/<=` khi có `from`/`to`. Thiếu index này → query lỗi runtime, không lỗi biên dịch.

### 2.5. `budgets/{budgetId}`
| Field | Type | Ghi chú |
|---|---|---|
| userId | string | |
| categoryId | string | Nên unique theo cặp (categoryId, month) — hiện **không có constraint DB**, `budget_management_screen.dart` tự kiểm tra trùng ở tầng UI trước khi tạo mới |
| limit | number | |
| month | string | định dạng `MM/yyyy` (string, không phải Timestamp) |
| spent | number | tính/cộng dồn bởi `adjustBudgetSpent()` mỗi khi có giao dịch expense |

Business rule (trong model, không phải DB):
- `percentUsed = (spent / limit).clamp(0, 1.5)`
- `isOverBudget = spent > limit`
- `isNearLimit = percentUsed >= 0.9 && !isOverBudget`

### 2.6. `savingGoals/{goalId}`
| Field | Type | Ghi chú |
|---|---|---|
| userId | string | |
| name | string | |
| targetAmount | number | |
| savedAmount | number | default 0, cập nhật thủ công qua "Nạp tiền" (không tự động trừ từ transactions) |
| months | number | default 1 |
| createdAt | string (ISO8601) | |

### 2.7. `notifications/{notificationId}`
| Field | Type | Ghi chú |
|---|---|---|
| userId | string | |
| title | string | |
| content | string | |
| status | string | `unread` \| `read`, default `unread` |
| type | string | `budget` \| `reminder` \| `ai_insight`, default `reminder` |
| createdAt | string (ISO8601) | |

Được tạo tự động bởi `FirestoreService` khi ngân sách vượt 90% (xem `adjustBudgetSpent`, `updateTransactionSafely`).

### 2.8. `users/{uid}/quickTemplates/{templateId}` (sub-collection)
| Field | Type | Ghi chú |
|---|---|---|
| title | string | |
| amount | number | |
| type | string | `income` \| `expense` |
| walletId, categoryId | string | |
| note, location | string | default `''` |
| date | string (ISO8601) | |
| imagePath | string? | |

## 3. Firestore Security Rules (`firestore.rules`)

Nguyên tắc chung: **mỗi user chỉ đọc/ghi được document có `userId` (hoặc `uid` với `users`) khớp `request.auth.uid`.**

```
users/{uid}         → allow read, write nếu auth.uid == uid
wallets/{id}        → read/update/delete nếu resource.data.userId == auth.uid
                       create nếu request.resource.data.userId == auth.uid
categories/{id}     → tương tự wallets
transactions/{id}   → tương tự wallets
budgets/{id}        → tương tự wallets
savingGoals/{id}    → tương tự wallets
notifications/{id}  → read/update (không cho user tự xóa), create theo pattern trên
```

Điểm cần lưu ý khi triển khai thật (production hardening — chưa làm):
- Chưa có rule validate schema (field type, giá trị hợp lệ) — hiện chỉ check quyền sở hữu.
- Chưa có rule cho sub-collection `quickTemplates` trong file rules mẫu hiện tại — **cần bổ sung** trước khi rời test mode.
- `notifications` cho phép `create` với `userId` tự khai trong `request.resource.data` — về lý thuyết cho phép user tạo notification giả cho chính mình (chấp nhận được vì không gây hại tới người khác, nhưng nên biết).

## 4. Migrations

Dự án **không dùng công cụ migration chính thức** (không phải SQL). Thay đổi schema là thay đổi field trong model Dart + cập nhật thủ công dữ liệu cũ nếu cần (không có schema versioning). Khi thêm field mới vào model:
1. Thêm field vào class + `fromMap` (luôn có giá trị mặc định an toàn, VD `map['field'] ?? default`) để tương thích ngược với document cũ chưa có field này.
2. Thêm vào `toMap`.
3. Cân nhắc backfill bằng script/batch nếu field bắt buộc cho logic quan trọng (không có sẵn script backfill trong repo hiện tại).

## 5. Lưu trữ ảnh hóa đơn — Local Storage (không dùng Firebase Cloud Storage)

**Đã đổi kiến trúc:** Firebase Cloud Storage yêu cầu gói Blaze (trả phí) từ chính sách mới của Google; project ở gói Spark (miễn phí) nên không dùng được. Chuyển sang lưu ảnh **cục bộ trên thiết bị**:

- Thư mục: `getApplicationDocumentsDirectory()` (từ package `path_provider`, đã có sẵn trong dự án) — **không** dùng `getTemporaryDirectory()` (hệ điều hành có thể tự xóa bất cứ lúc nào, chỉ phù hợp cho file tạm OCR).
- Đường dẫn file: `{documentsDir}/receipts/{userId}_{timestamp}.jpg`.
- Field `image` trong Firestore lưu **đường dẫn file local** (String), không phải URL.
- **Không cần khai báo thêm permission** trong `AndroidManifest.xml` — đây là vùng sandbox riêng của app.
- **Đánh đổi đã biết:** ảnh mất khi gỡ cài đặt app hoặc đổi thiết bị (không đồng bộ qua cloud) — chấp nhận được cho phạm vi khóa luận, ghi rõ trong PRD.md mục 7.
- File `cors.json` trong repo **không còn cần thiết** cho mục đích này nữa (giữ lại trong repo không gây hại, chỉ không có tác dụng).
