# MT5 Backtest Farm (80 agents)

تسريع باكتست MetaTrader 5 عبر GitHub Actions — حتى **80 عامل باكتست متزامن** (20 رنر × 4 وكلاء)، مجاناً وبلا بطاقة وبلا حاسوبك الشخصي.

## لماذا هذا أفضل من البور.pub القديم؟

| | القديم (rdp_workflow) | الجديد (هذا المستودع) |
|---|---|---|
| عدد الوكلاء | 12 | **80** |
| قوة كل جهاز | 2 نواة فقط | **4 نواة / 16GB** |
| التكلفة | مجاني لكن محدود | **مجاني + غير محدود** |
| رابط الوصول | عشوائي (bore.pub:xxxxx يموت كل ساعة) | **ثابت** agent-1 .. agent-20 |
| مدة التشغيل | يتوقف بعد ساعات | حتى 6 ساعات + **إعادة تشغيل تلقائية** |

> السبب الجذري لمشكلة "2 cores": المستودع كان **خاص** (private). المستودع **العام** يعطيك 4 نوى مجاناً وبلا حدود دقائق.

## خطوات التشغيل (مرة واحدة)

### 1) تسجيل حساب Tailscale مجاناً (دقيقتان)
1. افتح https://login.tailscale.com/start وسجّل بحساب Google/مايكروسوفت/بريدك.
2. اذهب إلى **Settings → Keys → Generate auth key**.
3. اترك الخيارات الافتراضية (Reusable = ON إن أمكن) واضغط **Generate**.
4. انسخ المفتاح (يبدأ بـ `tskey-`).

### 2) إضافة المفتاح كسرّ في GitHub
1. افتح https://github.com/lefraich/mt5-farm/settings/secrets/actions
2. **New repository secret**
3. الاسم: `TAILSCALE_AUTHKEY`
4. القيمة: الصق مفتاح `tskey-...` الذي نسخته → **Add secret**

### 3) تشغيل المزرعة
- افتح https://github.com/lefraich/mt5-farm/actions
- اضغط **MT5 Agent Farm v2** → **Run workflow** → **Run workflow** (اترك العدد 20)

انتظر 5-10 دقائق حتى تظهر عناوين الوكلاء في قائمة الـ runs.

### 4) توصيل MT5 المحلي بالوكلاء
1. ثبّت Tailscale على **حاسوبك** من https://tailscale.com/download وسجّل الدخول **بنفس الحساب**.
2. افتح MT5 على جهازك → أدوات → خيارات → قسم **Strategy Tester / Agents**.
3. أضف كل عامل:
   - عنوان: `agent-1` … `agent-20`
   - كلمة مرور: `Test12345!`
   - المنافذ: 3000، 3001، 3002، 3003
4. شغّل الباكتست كما تفعل عادةً — سيتوزع تلقائياً على 80 عامل.

## إعادة التشغيل التلقائية (اختياري)

لجعل المزرعة تعاود التشغيل كل 5 ساعات بدون تدخلك:

1. أنشئ ملفاً فارغاً باسم `KEEP_FARM` في جذر المستودع (Add file → Create new file → اكتب `KEEP_FARM` كاسم).
2. أنشئ **Personal Access Token** من https://github.com/settings/tokens
   (Classic → Scopes: `repo` + `workflow`) وأضفه كسرّ باسم `FARM_PAT`.
3. سيبدأ **Farm Watchdog** بإعادة التشغيل تلقائياً. حذف ملف `KEEP_FARM` يوقفها.

## ملفات المستودع
- `.github/workflows/farm_v2.yml` — المزرعة الرئيسية (80 عامل)
- `.github/workflows/watchdog.yml` — إعادة تشغيل تلقائية كل 5 ساعات
- `gpterra.mq5` — الـ EA الخاص بك للمرجعية
