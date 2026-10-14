<div dir="rtl">

[English](README.md)

<h1 align="center">Flutter Store Check</h1>

<p align="center">
  امسك أسباب رفض Google Play و App Store في مشروع Flutter بتاعك قبل ما ترفع.
</p>

كل رفضة بتاكل أيام: ترفع، تستنى الـ review، تقرا رقم guideline، تصلّح، وترفع تاني. ومعظم الرفض
بييجي من حاجات سكريبت يقدر يشوفها: privacy manifest مش موجود، permission حساسة محدش بيستخدمها،
release متوقّع بالـ debug key، أو coins بتتباع بـ Stripe على iOS. `store_check` بيقرا مشروعك زي ما
الـ reviewer هيقراه، وبيفشل على الحاجات دي قبل ما ترفع.

مفيش حاجة تقدر تقلّد الـ reviewer البشري ١٠٠٪. اللي السكريبت مش شايفه، زي الـ demo account
والـ screenshots وفورم الـ Data safety، بيتحول لـ checklist في تقرير الـ HTML، ومتولّد من الـ SDKs
اللي في `pubspec.yaml` بتاعك فعلاً.

## التسطيب

</div>

```bash
dart pub global activate --source git https://github.com/youssef336/flutter_store_check
cd my_flutter_app
store_check init          # بيكتب store_check.yaml (اختياري، كل حاجة ليها default)
store_check --html store_check_report.html
```

<div dir="rtl">

الـ exit codes: `0` مفيش FAIL · `1` فيه FAIL على الأقل (أو WARN مع `--strict`) · `2` غلط في الاستخدام أو الـ config.

## بيفحص إيه

- **App Store:** الـ privacy manifest (I1)، الـ purpose strings لكل permission (I2)، الـ ATT (I3)،
  Sign in with Apple ومسح الحساب (I4)، الـ ATS والـ export compliance والـ AdMob id (I5).
- **Google Play:** الـ targetSdk (A1)، رقم الـ build (A2)، الـ permissions الحساسة (A3)، الـ
  foreground services (A4)، الـ `exported` (A5)، والـ signing (A6).
- **Policy:** الدفع برا IAP على iOS (P1)، والدفع برا Play Billing (P2)، والـ switches اللي بتخبّي
  حاجات وقت الـ review (P3)، والـ report والـ block في المحتوى اللي اليوزرز بيعملوه (P4)، والـ consent
  للإعلانات (P5)، وملفات `.env` جوه الأبلكيشن (P6)، والـ AdMob id الحقيقي (P7).
- **يدوي (M1–M6):** الـ Data safety والـ App Privacy قصاد الـ SDKs، الـ demo account، تجربة على iPad،
  الـ screenshots، ملاحظات الـ reviewer، والـ pre-launch report.
- **على الملف النهائي:** `--aab` بيفحص الـ 16KB والـ merged manifest، و`--ipa` بيفحص الـ manifests
  جوه الـ IPA والـ signing.

الجدول الكامل في [README.md](README.md). و`store_check explain P1` بيشرح أي قاعدة وإزاي تصلّحها.

## التصليح الأوتوماتيك

</div>

```bash
store_check fix --dry-run   # يعرض اللي هيتغير
store_check fix             # ينفّذ
```

<div dir="rtl">

`fix` بيشيل الـ permissions الحساسة اللي محدش بيستخدمها، ويحط `maxSdkVersion` لـ
`READ_EXTERNAL_STORAGE`، ويزوّد الـ foreground-service permissions الناقصة، ويعمل
`PrivacyInfo.xcprivacy` مبدئي. القواعد اللي محتاجة قرار، زي الدفع والـ review switches والـ ATT،
عمره ما بيلمسها لوحده.

## الإعدادات

أهم المفاتيح في `store_check.yaml`:

</div>

```yaml
payments:
  sells_digital_goods: true      # coins أو subscriptions أو محتوى premium → IAP / Play Billing
ugc:
  dirs: [lib/features/feed, lib/features/chat]
android:
  min_target_sdk: 35
waivers:
  P2: Enrolled in User Choice Billing (EEA)
disabled: [P5]
```

<div dir="rtl">

## GitHub Action

</div>

```yaml
- uses: youssef336/flutter_store_check@v1
  with:
    args: --strict
```

<div dir="rtl">

## لو اترفضت برضه

افتح issue فيها رقم الـ guideline ونص الرفض. كل رفضة حقيقية لازم تتحول لقاعدة، عشان نفس الغلطة
ماتتكررش.

</div>
