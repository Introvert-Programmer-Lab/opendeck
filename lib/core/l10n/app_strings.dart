import 'package:flutter/widgets.dart';

/// All UI text in English and Arabic. Use `S.of(context).someKey`.
class S {
  const S._(this.ar);
  final bool ar;

  static const en = S._(false);
  static const arabic = S._(true);

  static S of(BuildContext context) => Localizations.localeOf(context).languageCode == 'ar' ? arabic : en;

  String _t(String e, String a) => ar ? a : e;

  String get appName => _t('OpenDeck', 'أوبن ديك');

  // top bar / device
  String get syncToDeck => _t('Sync to deck', 'مزامنة مع اللوحة');
  String get syncing => _t('Syncing…', 'جارٍ المزامنة…');
  String get synced => _t('Deck updated', 'تم تحديث اللوحة');
  String get connect => _t('Connect', 'اتصال');
  String get disconnect => _t('Disconnect', 'قطع الاتصال');
  String get notConnected => _t('No deck connected', 'لا توجد لوحة متصلة');
  String get connectedVia => _t('Connected via', 'متصل عبر');
  String get usbCable => _t('USB cable', 'كابل USB');
  String get wifi => _t('Wi-Fi', 'واي فاي');
  String get usbPorts => _t('USB ports', 'منافذ USB');
  String get noPorts => _t('No serial ports found. Plug the deck in with a data cable.', 'لا توجد منافذ. وصّل اللوحة بكابل بيانات.');
  String get network => _t('On your network', 'على شبكتك');
  String get scan => _t('Scan', 'بحث');
  String get scanning => _t('Searching…', 'جارٍ البحث…');
  String get noDecksFound => _t('No decks found on the network yet.', 'لم يتم العثور على لوحات في الشبكة بعد.');
  String get manualAddress => _t('IP address', 'عنوان IP');
  String get wifiSetup => _t('Deck Wi-Fi', 'شبكة اللوحة');
  String get wifiSetupHint =>
      _t('Send your network to the deck so it can connect without a cable.', 'أرسل بيانات شبكتك للوحة لتتصل بدون كابل.');
  String get networkName => _t('Network name (SSID)', 'اسم الشبكة');
  String get password => _t('Password', 'كلمة المرور');
  String get send => _t('Send', 'إرسال');
  String get deckInfo => _t('Deck', 'اللوحة');
  String get storage => _t('Storage', 'التخزين');
  String get firmware => _t('Firmware', 'البرنامج الثابت');
  String get board => _t('Board', 'اللوحة الإلكترونية');
  String get address => _t('Address', 'العنوان');
  String get hotspotHint => _t('Setup hotspot', 'نقطة الإعداد');
  String get hostOnlyNote => _t(
      'Actions like opening apps or muting the mic run on the computer where this app is open.',
      'الأوامر مثل فتح التطبيقات أو كتم المايك تعمل على الحاسوب الذي يعمل عليه هذا التطبيق.');

  // editor
  String get pages => _t('Pages', 'الصفحات');
  String get addPage => _t('Add page', 'إضافة صفحة');
  String get newPage => _t('New page', 'صفحة جديدة');
  String get page => _t('Page', 'الصفحة');
  String get key => _t('Key', 'الزر');
  String get selectKeyHint => _t('Select a key on the deck to edit it, or tap an empty slot to add one.',
      'اختر زرًا في اللوحة لتعديله، أو اضغط على خانة فارغة لإضافة زر.');
  String get pageName => _t('Page name', 'اسم الصفحة');
  String get layout => _t('Layout', 'التخطيط');
  String get sections => _t('Sections', 'الأقسام');
  String get addSection => _t('Add section', 'إضافة قسم');
  String get sectionTitle => _t('Section title', 'عنوان القسم');
  String get rows => _t('Rows', 'الصفوف');
  String get columns => _t('Columns', 'الأعمدة');
  String get size => _t('Size', 'الحجم');
  String get background => _t('Background', 'الخلفية');
  String get backgroundImage => _t('Background image', 'صورة الخلفية');
  String get chooseImage => _t('Choose image', 'اختر صورة');
  String get remove => _t('Remove', 'إزالة');
  String get dim => _t('Dim', 'تعتيم');
  String get duplicate => _t('Duplicate', 'تكرار');
  String get delete => _t('Delete', 'حذف');
  String get moveUp => _t('Move up', 'للأعلى');
  String get moveDown => _t('Move down', 'للأسفل');
  String get label => _t('Label', 'النص');
  String get showLabel => _t('Show label', 'إظهار النص');
  String get icon => _t('Icon', 'الأيقونة');
  String get pickIcon => _t('Pick icon', 'اختر أيقونة');
  String get imageIcon => _t('Image', 'صورة');
  String get noIcon => _t('None', 'بدون');
  String get searchIcons => _t('Search icons', 'ابحث عن أيقونة');
  String get colors => _t('Colors', 'الألوان');
  String get keyColor => _t('Key color', 'لون الزر');
  String get iconColor => _t('Icon & text', 'الأيقونة والنص');
  String get defaultColor => _t('Default', 'افتراضي');
  String get action => _t('Action', 'الإجراء');
  String get onState => _t('When on', 'عند التفعيل');
  String get onStateHint => _t('How the key looks while active (e.g. mic muted).', 'شكل الزر أثناء التفعيل (مثل كتم المايك).');
  String get test => _t('Test', 'تجربة');
  String get clearKey => _t('Remove key', 'حذف الزر');
  String get addKey => _t('Add key', 'إضافة زر');
  String get swipeHint => _t('Swipe left/right on the deck to change pages. Swipe down for connection info.',
      'اسحب يمينًا أو يسارًا على اللوحة لتغيير الصفحة، واسحب للأسفل لمعلومات الاتصال.');

  // actions
  String actionName(String type) => switch (type) {
        'none' => _t('Nothing', 'لا شيء'),
        'openApp' => _t('Open app / file', 'فتح تطبيق / ملف'),
        'openUrl' => _t('Open website', 'فتح موقع'),
        'runCommand' => _t('Run command', 'تشغيل أمر'),
        'hotkey' => _t('Keyboard shortcut', 'اختصار لوحة المفاتيح'),
        'typeText' => _t('Type text', 'كتابة نص'),
        'media' => _t('Media / volume', 'الوسائط / الصوت'),
        'micMute' => _t('Mute microphone', 'كتم المايك'),
        'speakerMute' => _t('Mute sound', 'كتم الصوت'),
        'nextPage' => _t('Next page', 'الصفحة التالية'),
        'prevPage' => _t('Previous page', 'الصفحة السابقة'),
        'gotoPage' => _t('Go to page', 'الذهاب لصفحة'),
        'brightnessUp' => _t('Brightness up', 'رفع السطوع'),
        'brightnessDown' => _t('Brightness down', 'خفض السطوع'),
        _ => type,
      };
  String mediaName(String op) => switch (op) {
        'volumeUp' => _t('Volume up', 'رفع الصوت'),
        'volumeDown' => _t('Volume down', 'خفض الصوت'),
        'mute' => _t('Mute (system key)', 'كتم (مفتاح النظام)'),
        'playPause' => _t('Play / pause', 'تشغيل / إيقاف مؤقت'),
        'next' => _t('Next track', 'المقطع التالي'),
        'previous' => _t('Previous track', 'المقطع السابق'),
        'stop' => _t('Stop', 'إيقاف'),
        _ => op,
      };
  String get appPath => _t('App, file or shortcut', 'التطبيق أو الملف أو الاختصار');
  String get appPathHint => _t('e.g. code, notepad, C:\\Games\\game.exe', 'مثال: code أو notepad أو مسار ملف exe');
  String get browse => _t('Browse', 'استعراض');
  String get arguments => _t('Arguments (optional)', 'المعاملات (اختياري)');
  String get url => _t('Website address', 'عنوان الموقع');
  String get command => _t('Command', 'الأمر');
  String get shortcut => _t('Shortcut', 'الاختصار');
  String get shortcutHint => _t('e.g. ctrl+shift+m, win+d, f13', 'مثال: ctrl+shift+m أو win+d');
  String get text => _t('Text', 'النص');
  String get pageNumber => _t('Page', 'الصفحة');
  String get mediaOp => _t('Control', 'التحكم');


  // workspace chrome
  String get previewOnState => _t('Preview on-state', 'معاينة حالة التفعيل');
  String get zoomFit => _t('Fit', 'ملاءمة');
  String keyCount(int n) => _t(n == 1 ? '1 key' : '$n keys', '$n أزرار');
  String get lastSync => _t('Last sync', 'آخر مزامنة');
  String get noKeySelected => _t('No key selected', 'لم يتم اختيار زر');
  String get connected => _t('Connected', 'متصل');
  String get connecting => _t('Connecting…', 'جارٍ الاتصال…');
  String get offline => _t('Offline', 'غير متصل');
  String get deck => _t('Deck', 'اللوحة');
  String get display => _t('Display', 'الشاشة');
  String get project => _t('Project', 'المشروع');
  String get presetsHint => _t('Applying a preset keeps your keys in order.', 'تطبيق القالب يحافظ على ترتيب أزرارك.');
  String get chooseAppOnPc => _t('Choose an app on this PC', 'اختر تطبيقًا من هذا الجهاز');
  String get actionType => _t('Type', 'النوع');
  String get appearance => _t('Appearance', 'المظهر');
  String sectionN(int n) => _t('Section $n', 'القسم $n');
  String get general => _t('General', 'عام');

  // settings
  String get settings => _t('Settings', 'الإعدادات');
  String get language => _t('Language', 'اللغة');
  String get deckSettings => _t('Deck', 'اللوحة');
  String get orientation => _t('Orientation', 'الاتجاه');
  String get portrait => _t('Portrait', 'عمودي');
  String get landscape => _t('Landscape', 'أفقي');
  String get portraitFlipped => _t('Portrait (flipped)', 'عمودي (مقلوب)');
  String get landscapeFlipped => _t('Landscape (flipped)', 'أفقي (مقلوب)');
  String get brightness => _t('Brightness', 'السطوع');
  String get imageQuality => _t('Image quality', 'جودة الصور');
  String get autoQuality => _t('Lower quality automatically if the deck does not fit', 'خفض الجودة تلقائيًا إن لم تتسع اللوحة');
  String get qualityHint => _t('Pages are sent as JPEG. Higher quality looks sharper and uses more of the deck\'s memory.',
      'تُرسل الصفحات كصور JPEG. الجودة الأعلى أوضح لكنها تستهلك ذاكرة أكثر.');
  String get look => _t('Look', 'المظهر');
  String get accent => _t('Accent', 'لون التمييز');
  String get pageBackground => _t('Background', 'الخلفية');
  String get keys => _t('Keys', 'الأزرار');
  String get text2 => _t('Text', 'النص');
  String get corners => _t('Corner radius', 'استدارة الزوايا');
  String get spacing => _t('Spacing', 'المسافات');
  String get labelSize => _t('Label size', 'حجم النص');
  String get showHeader => _t('Show header (logo, page name, page dots)', 'إظهار الترويسة (الشعار واسم الصفحة)');
  String get resetDefault => _t('Restore default deck', 'استعادة اللوحة الافتراضية');
  String get resetConfirm => _t('Replace your current deck with the default one?', 'استبدال لوحتك الحالية بالافتراضية؟');
  String get cancel => _t('Cancel', 'إلغاء');
  String get ok => _t('OK', 'موافق');
  String get pullFromDeck => _t('Load deck from device', 'تحميل اللوحة من الجهاز');
  String get pullDone => _t('Loaded the deck stored on the device', 'تم تحميل اللوحة المخزنة في الجهاز');
  String get about => _t('About', 'حول');
  String get aboutText => _t(
      'Open source stream deck app and firmware for ESP32 touch screens. MIT licensed.',
      'تطبيق وبرنامج ثابت مفتوح المصدر يحوّل شاشات ESP32 اللمسية إلى لوحة تحكم. برخصة MIT.');
  String sizeKb(int bytes) => _t('${(bytes / 1024).toStringAsFixed(0)} KB', '${(bytes / 1024).toStringAsFixed(0)} ك.ب');
  String sizeMb(int bytes) => _t('${(bytes / 1048576).toStringAsFixed(1)} MB', '\u2066${(bytes / 1048576).toStringAsFixed(1)}\u2069 م.ب');
  String deckSize(int bytes, int q) => _t('${sizeKb(bytes)} at quality $q', '${sizeKb(bytes)} بجودة $q');
  // setup and firmware
  String get setupTitle => _t('Set up your deck', 'جهّز لوحتك');
  String get setupIntro => _t('OpenDeck turns an ESP32 touch screen into a stream deck. Start by putting the firmware on your board.',
      'يحوّل OpenDeck شاشة ESP32 اللمسية إلى لوحة تحكم. ابدأ بتثبيت البرنامج الثابت على لوحتك.');
  String get newBoard => _t('Set up a new board', 'إعداد لوحة جديدة');
  String get newBoardHint => _t('Install the OpenDeck firmware over USB. It takes about a minute.',
      'ثبّت برنامج OpenDeck الثابت عبر USB. يستغرق ذلك دقيقة تقريبًا.');
  String get haveBoard => _t('My board already runs OpenDeck', 'لوحتي تعمل بـ OpenDeck مسبقًا');
  String get haveBoardHint => _t('Connect to it and start designing.', 'اتصل بها وابدأ التصميم.');
  String get skipForNow => _t('Skip for now', 'تخطَّ الآن');
  String get back => _t('Back', 'رجوع');
  String get setupBoard => _t('Set up a board', 'إعداد لوحة');
  String get installFirmware => _t('Install firmware', 'تثبيت البرنامج الثابت');
  String get flashIntro => _t(
      'Plug the board into this device with a USB data cable, then press Install firmware. The app finds out which board it is and installs the matching firmware. Everything on the board is replaced.',
      'وصّل اللوحة بهذا الجهاز بكابل بيانات USB، ثم اضغط تثبيت البرنامج الثابت. يتعرّف التطبيق على نوع اللوحة ويثبّت البرنامج المناسب لها. سيُستبدل كل ما على اللوحة.');
  String get flashAndroidHint => _t('On a phone, use a USB-C cable or an OTG adapter, and allow USB access when asked.',
      'على الهاتف، استخدم كابل USB-C أو محوّل OTG، واسمح بالوصول إلى USB عند السؤال.');
  String get flashUnsupported => _t('Installing firmware needs the app on Windows, macOS, Linux or Android.',
      'تثبيت البرنامج الثابت يحتاج التطبيق على ويندوز أو ماك أو لينكس أو أندرويد.');
  String get useFirmwareFile => _t('Use a firmware file', 'استخدام ملف برنامج ثابت');
  String get tryAgain => _t('Try again', 'حاول مجددًا');
  String get flashDone => _t('Firmware installed. The board is restarting.', 'تم التثبيت. اللوحة تعيد التشغيل الآن.');
  String get flashReplugHint => _t(
      'Board stuck? Unplug the USB cable, wait a few seconds, plug it back in, then press Try again.',
      'اللوحة لا تستجيب؟ افصل كابل USB وانتظر بضع ثوانٍ، ثم أعد توصيله واضغط حاول مجددًا.');
  String get flashBootHint => _t('Still stuck? Hold BOOT, tap RST, release BOOT, then try again.',
      'ما زالت المشكلة؟ اضغط BOOT مع الاستمرار، ثم اضغط RST، ثم اترك BOOT وحاول مجددًا.');
  String flashStage(String stage) => switch (stage) {
        'download' => _t('Getting the firmware', 'جارٍ جلب البرنامج الثابت'),
        'findBoard' => _t('Looking for the board', 'جارٍ البحث عن اللوحة'),
        'bootloader' => _t('Restarting the board in download mode', 'إعادة تشغيل اللوحة في وضع التنزيل'),
        'connect' => _t('Connecting', 'جارٍ الاتصال'),
        'identify' => _t('Identifying the board', 'جارٍ التعرّف على اللوحة'),
        'write' => _t('Writing firmware', 'جارٍ كتابة البرنامج الثابت'),
        'verify' => _t('Checking', 'جارٍ التحقق'),
        'restart' => _t('Restarting the board', 'إعادة تشغيل اللوحة'),
        _ => _t('Firmware installed', 'تم تثبيت البرنامج الثابت'),
      };
  String flashError(String error) => switch (error) {
        'noBoard' => _t('No board found. Plug it in with a data cable (some cables only charge).',
            'لم يتم العثور على لوحة. وصّلها بكابل بيانات (بعض الكابلات للشحن فقط).'),
        'portBusy' => _t('The USB port is in use by another program. Close it and try again.',
            'منفذ USB مستخدم من برنامج آخر. أغلقه وحاول مجددًا.'),
        'noBootloader' => _t('The board did not enter download mode. Hold BOOT, tap RST, release BOOT, then try again.',
            'لم تدخل اللوحة وضع التنزيل. اضغط BOOT مع الاستمرار، ثم RST، ثم اترك BOOT وحاول مجددًا.'),
        'download' => _t('Could not get the firmware. Check your internet connection, or use a firmware file.',
            'تعذّر جلب البرنامج الثابت. تحقق من اتصالك بالإنترنت أو استخدم ملفًا.'),
        'badImage' => _t('That file is not an OpenDeck firmware image.', 'هذا الملف ليس صورة برنامج ثابت لـ OpenDeck.'),
        'noStock' => noStockFirmware,
        'wrongBoard' => _t('Nothing was written: the board does not match this firmware.',
            'لم تُكتب أي بيانات: اللوحة لا تطابق هذا البرنامج الثابت.'),
        _ => _t('Installing failed.', 'فشل التثبيت.'),
      };
  String get chooseBoard => _t('Which board is it?', 'ما هي لوحتك؟');
  String get chooseBoardHint => _t(
      'These boards use the same parts and differ only in things the app cannot see, like the screen size. The model number is printed on the back of the board.',
      'هذه اللوحات تستخدم نفس القطع وتختلف فقط في أشياء لا يراها التطبيق مثل حجم الشاشة. رقم الموديل مطبوع على ظهر اللوحة.');
  String installFor(String name) => _t('Install for $name', 'تثبيت لـ $name');
  String get boardUnsupported => _t('This board is not supported', 'هذه اللوحة غير مدعومة');
  String unsupportedReason(String reason) => switch (reason) {
        'chip' => _t('OpenDeck runs on ESP32 and ESP32-S3 boards, and this one has a different chip. Nothing was written to it.',
            'يعمل OpenDeck على لوحات ESP32 و ESP32-S3، وهذه اللوحة بشريحة مختلفة. لم يُكتب عليها شيء.'),
        'hardware' => _t('None of the supported boards has this chip, USB connection and flash size. Nothing was written to it.',
            'لا توجد لوحة مدعومة بهذه الشريحة ونوع USB وحجم الذاكرة. لم يُكتب عليها شيء.'),
        _ => _t(
            'The chip fits, but no touch controller answered where the supported boards have one, so nothing was written. For a capacitive screen, keep a finger on it and try again.',
            'الشريحة مناسبة، لكن لم تستجب وحدة اللمس في المكان الذي تضعها فيه اللوحات المدعومة، لذلك لم يُكتب شيء. إذا كانت الشاشة سعوية فأبقِ إصبعك عليها وحاول مجددًا.'),
      };
  String get whatWasFound => _t('What the app found', 'ما وجده التطبيق');
  String get supportedBoards => _t('Supported boards', 'اللوحات المدعومة');
  String get boardOverride => _t('My board is one of these', 'لوحتي واحدة من هذه');
  String get boardOverrideWarning => _t(
      'Only do this if the model number on the board matches. With the wrong firmware the screen or touch stays dark until you install the right one.',
      'افعل ذلك فقط إذا كان رقم الموديل على اللوحة مطابقًا. مع البرنامج الخاطئ تبقى الشاشة أو اللمس بلا عمل حتى تثبّت البرنامج الصحيح.');
  String get untestedBoard => _t('Not tested on hardware yet: built from the published pinout. Please report how it works.',
      'لم تُختبر على الجهاز بعد: مبنية من مخطط الأطراف المنشور. نرجو إخبارنا بالنتيجة.');
  String get noStockFirmware => _t('No factory firmware is known for this board.', 'لا يوجد برنامج أصلي معروف لهذه اللوحة.');
  String get invertColors => _t('Invert colors', 'عكس الألوان');
  String get invertColorsHint => _t('Turn this on if the deck shows a negative image. The deck restarts.',
      'فعّل هذا إذا ظهرت الصورة على اللوحة بألوان معكوسة. ستعيد اللوحة التشغيل.');
  String get restoreStock => _t('Restore factory firmware', 'استعادة البرنامج الأصلي');
  String get restoreStockConfirm => _t(
      'This puts back the demo firmware the board shipped with and removes OpenDeck and your deck from it. You can install OpenDeck again at any time.',
      'سيعيد هذا البرنامج التجريبي الذي أتت به اللوحة ويحذف OpenDeck ولوحتك منها. يمكنك تثبيت OpenDeck مجددًا في أي وقت.');
  String get restore => _t('Restore', 'استعادة');
  String get stockDone => _t('Factory firmware restored. The board is restarting.', 'تمت استعادة البرنامج الأصلي. اللوحة تعيد التشغيل.');
  String get switchIfOpen => _t('Switch to it if already open', 'انتقل إليه إن كان مفتوحًا');
  String get switchIfOpenHint => _t('Off: every press opens a new window.', 'عند الإيقاف: كل ضغطة تفتح نافذة جديدة.');
  String get connectTitle => _t('Connect to your deck', 'اتصل بلوحتك');
  String get connectUsbHint => _t('Keep the USB cable plugged in. The app connects by itself.',
      'أبقِ كابل USB موصولًا. سيتصل التطبيق تلقائيًا.');
  String get connectWifiHint => _t(
      'Join the board\'s Wi-Fi hotspot (OpenDeck-XXXX, password opendeck), or put the board on your network from the desktop app.',
      'اتصل بنقطة الاتصال الخاصة باللوحة (OpenDeck-XXXX، كلمة المرور opendeck)، أو أضف اللوحة لشبكتك من تطبيق الحاسوب.');
  String get waitingForDeck => _t('Waiting for the deck…', 'بانتظار اللوحة…');
  String get connectionOptions => _t('Connection options', 'خيارات الاتصال');
  String get startDesigning => _t('Start designing', 'ابدأ التصميم');

  String errorText(Object e) => _t('Something went wrong: $e', 'حدث خطأ: $e');
}
