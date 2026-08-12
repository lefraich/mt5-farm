# 📺 YouTube 24/7 Live Stream Farm

بث مباشر مستمر 24/7 على YouTube — يعمل بالكامل في السحابة (GitHub Actions) بدون تكلفة.

## كيف يعمل

```
جهازك                             GitHub Actions (مجاني)
  │                                      │
  │  StreamLive.bat start               │
  │  ───────────────────────────►       │  stream-1:
  │                                      │    1. تحميل فيديوهات قناتك (yt-dlp)
  │  أغلق جهازك ✅                      │    2. بث حلقة مستمرة (FFmpeg → RTMP)
  │                                      │    3. ~5h40m ثم ينتهي
  │                                      │
  │                                      │  watchdog (كل 5 ساعات):
  │                                      │    └─ يعيد تشغيل stream-1 → 24/7 ♾️
```

## البدء السريع

### 1. الإعداد (مرة واحدة)

1. **مفتاح البث**: YouTube Studio → Go Live → Stream → Stream Key
2. **أسرار GitHub** (Settings → Secrets → Actions):
   | Secret | القيمة |
   |--------|--------|
   | `YOUTUBE_STREAM_KEY` | مفتاح البث |
   | `FARM_PAT` | [GitHub Token](https://github.com/settings/tokens) (scopes: `repo` + `workflow`) |

3. **ضع الملفات في المستودع**:
   ```
   .github/workflows/stream_farm.yml
   .github/workflows/watchdog.yml
   KEEP_STREAMING
   StreamLive.bat
   ```

### 2. تشغيل البث

```
StreamLive.bat start
```
أو اضغط عليه مرتين واختر `1. START`.

### 3. إيقاف البث

```
StreamLive.bat stop
```

### 4. التحقق من الحالة

```
StreamLive.bat status
```

## الملفات

| الملف | الوظيفة |
|-------|---------|
| `stream_farm.yml` | Workflow البث الرئيسي (yt-dlp + FFmpeg) |
| `watchdog.yml` | إعادة تشغيل تلقائي كل 5 ساعات |
| `StreamLive.bat` | تحكم من جهازك (start/stop/status) |
| `KEEP_STREAMING` | وجوده = بث مستمر، حذفه = يتوقف |
| `archive/` | ملفات MT5 القديمة (احتياط) |

## الإعدادات المتقدمة

### تغيير الجودة
عند تشغيل الـ workflow يدوياً من GitHub Actions، يمكنك اختيار:
- **480p** — أقل استهلاك CPU
- **720p** — الافتراضي (موصى به)
- **1080p** — أعلى جودة

### تغيير عدد الفيديوهات
- `0` = كل فيديوهات القناة (الافتراضي)
- `10` = آخر 10 فيديوهات
- أي رقم آخر

### Channel ID
الافتراضي: `UCEMC9kpN4O2aF9wAHrRMDXw`
يمكن تغييره من inputs الـ workflow.

## استكشاف الأخطاء

| المشكلة | الحل |
|---------|------|
| البث لا يبدأ | تأكد من إضافة `YOUTUBE_STREAM_KEY` كـ secret |
| Watchdog لا يعمل | تأكد من إضافة `FARM_PAT` كـ secret ووجود `KEEP_STREAMING` |
| HTTP 401 | Token منتهي الصلاحية → أنشئ واحد جديد |
| HTTP 404 | الملفات ليست في `.github/workflows/` |
| فيديوهات لا تُحمّل | تحقق من Channel ID |
| جودة منخفضة | غيّر الجودة إلى 1080p من inputs |
