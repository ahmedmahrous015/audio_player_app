import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static final Map<String, Map<String, String>> _translations = {
    'en': {
      'myMusic': 'My Music',
      'allSongs': 'All Songs',
      'folders': 'Folders',
      'noAudioFiles': 'No audio files found',
      'permissionDenied':
          'Permission denied.\nTap Retry to enable file access in Settings.',
      'errorLoading': 'Error loading files: {path}',
      'enablePermission': 'Enable "Files and media" permission in Settings',
      'retry': 'Retry',
      'noTrack': 'No track',
      'unknownArtist': 'Unknown Artist',
      'delete': 'Delete',
      'setAsRingtone': 'Set as Ringtone',
      'sleepTimer': 'Sleep Timer',
      'cancelSleepTimer': 'Cancel Sleep Timer',
      'deleteFile': 'Delete file?',
      'deleteFileMsg': 'This will permanently delete\n{path}',
      'deleteFolder': 'Delete folder?',
      'deleteFolderMsg':
          'This will permanently delete {count} audio files in\n{path}',
      'cancel': 'Cancel',
      'close': 'Close',
      'failedDelete': 'Failed to delete file',
      'fileDeleted': 'File deleted',
      'filesDeleted': '{count} files deleted',
      'filesDeletedPartial': 'Deleted {deleted}, failed {failed}',
      'ringtoneSuccess': 'Ringtone set successfully',
      'ringtoneFailed': 'Failed to set ringtone',
      'ringtonePermission':
          'Allow "Modify system settings" for the app, then try again',
      'playbackError': 'Cannot play this file',
      'minutes': 'minutes',
      'hour': 'hour',
      'endOfTrack': 'End of track',
      'share': 'Share',
      'details': 'Details',
      'fileInfo': 'File info',
      'folderInfo': 'Folder info',
      'name': 'Name',
      'path': 'Path',
      'duration': 'Duration',
      'size': 'Size',
      'artist': 'Artist',
      'modified': 'Modified',
      'files': 'Files',
      'sortBy': 'Sort by',
      'sortDateNewest': 'Date (newest)',
      'sortDateOldest': 'Date (oldest)',
      'sortNameAZ': 'Name (A–Z)',
      'sortNameZA': 'Name (Z–A)',
      'search': 'Search',
      'searchHint': 'Search songs or folders…',
      'noResults': 'No results',
      'play': 'Play',
      'pause': 'Pause',
      'next': 'Next',
      'previous': 'Previous',
      'rewind10': 'Back 10 seconds',
      'forward10': 'Forward 10 seconds',
      'shuffle': 'Shuffle',
      'repeatOff': 'Repeat off',
      'repeatAll': 'Repeat all',
      'repeatOne': 'Repeat one',
      'speed': 'Playback speed',
      'currentFolder': 'Current folder',
      'openSettings': 'Open Settings',
      'ringtone': 'Ringtone',
      'queue': 'Queue',
      'repeat': 'Repeat',
      'repeatAllShort': 'All',
      'repeatOneShort': 'One',
      'on': 'On',
      'off': 'Off',
      'filesCount': '{count} files',
      'ok': 'OK',
      'deleteFiles': 'Delete {count} files?',
      'deleteFilesMsg':
          'This will permanently delete {count} selected audio files.',
      'moveToTrashMsg': 'This file will be moved to the Trash\n{path}',
      'moveFolderToTrashMsg':
          '{count} audio files in\n{path}\nwill be moved to the Trash',
      'moveFilesToTrashMsg':
          '{count} selected audio files will be moved to the Trash.',
      'moveToTrash': 'Move to Trash',
      'movedToTrash': 'Moved to the Trash',
      'filesMovedToTrash': '{count} files moved to the Trash',
      'selectedCount': '{count} selected',
      'selectAll': 'Select all',
      'deselectAll': 'Deselect all',
      'deleteSelected': 'Delete selected',
      'cancelSelection': 'Cancel selection',
    },
    'ar': {
      'myMusic': 'مشغل الصوت',
      'allSongs': 'كل الصوتيات',
      'folders': 'المجلدات',
      'noAudioFiles': 'لم يتم العثور على ملفات صوتية',
      'permissionDenied':
          'تم رفض الإذن.\nاضغط إعادة المحاولة لتمكين الوصول إلى الملفات في الإعدادات.',
      'errorLoading': 'خطأ في تحميل الملفات: {path}',
      'enablePermission': 'فعّل إذن "الملفات والوسائط" في الإعدادات',
      'retry': 'إعادة المحاولة',
      'noTrack': 'لا يوجد مقطع',
      'unknownArtist': 'فنان غير معروف',
      'delete': 'حذف',
      'setAsRingtone': 'تعيين كنغمة',
      'sleepTimer': 'مؤقت النوم',
      'cancelSleepTimer': 'إلغاء مؤقت النوم',
      'deleteFile': 'حذف الملف؟',
      'deleteFileMsg': 'سيتم حذف هذا الملف نهائياً\n{path}',
      'deleteFolder': 'حذف المجلد؟',
      'deleteFolderMsg': 'سيتم حذف {count} ملف صوتي نهائياً من\n{path}',
      'cancel': 'إلغاء',
      'close': 'إغلاق',
      'failedDelete': 'فشل حذف الملف',
      'fileDeleted': 'تم حذف الملف',
      'filesDeleted': 'تم حذف {count} ملف',
      'filesDeletedPartial': 'تم حذف {deleted}، وفشل حذف {failed}',
      'ringtoneSuccess': 'تم تعيين النغمة بنجاح',
      'ringtoneFailed': 'فشل تعيين النغمة',
      'ringtonePermission':
          'اسمح للتطبيق بـ "تعديل إعدادات النظام" ثم حاول مرة أخرى',
      'playbackError': 'تعذّر تشغيل هذا الملف',
      'minutes': 'دقيقة',
      'hour': 'ساعة',
      'endOfTrack': 'نهاية المقطع',
      'share': 'مشاركة',
      'details': 'التفاصيل',
      'fileInfo': 'معلومات الملف',
      'folderInfo': 'معلومات المجلد',
      'name': 'الاسم',
      'path': 'المسار',
      'duration': 'المدة',
      'size': 'الحجم',
      'artist': 'الفنان',
      'modified': 'آخر تعديل',
      'files': 'الملفات',
      'sortBy': 'ترتيب حسب',
      'sortDateNewest': 'التاريخ (الأحدث)',
      'sortDateOldest': 'التاريخ (الأقدم)',
      'sortNameAZ': 'الاسم (أ–ي)',
      'sortNameZA': 'الاسم (ي–أ)',
      'search': 'بحث',
      'searchHint': 'ابحث عن صوتيات أو مجلدات…',
      'noResults': 'لا توجد نتائج',
      'play': 'تشغيل',
      'pause': 'إيقاف مؤقت',
      'next': 'التالي',
      'previous': 'السابق',
      'rewind10': 'رجوع 10 ثوانٍ',
      'forward10': 'تقديم 10 ثوانٍ',
      'shuffle': 'تشغيل عشوائي',
      'repeatOff': 'التكرار متوقف',
      'repeatAll': 'تكرار الكل',
      'repeatOne': 'تكرار المقطع',
      'speed': 'سرعة التشغيل',
      'currentFolder': 'المجلد الحالي',
      'openSettings': 'فتح الإعدادات',
      'ringtone': 'نغمة',
      'queue': 'القائمة',
      'repeat': 'التكرار',
      'repeatAllShort': 'الكل',
      'repeatOneShort': 'مقطع واحد',
      'on': 'مفعّل',
      'off': 'متوقف',
      'filesCount': '{count} ملف',
      'ok': 'حسناً',
      'deleteFiles': 'حذف {count} ملف؟',
      'deleteFilesMsg': 'سيتم حذف {count} ملف صوتي محدد نهائياً',
      'moveToTrashMsg': 'سيتم نقل هذا الملف إلى سلة المهملات\n{path}',
      'moveFolderToTrashMsg':
          'سيتم نقل {count} ملف صوتي من\n{path}\nإلى سلة المهملات',
      'moveFilesToTrashMsg': 'سيتم نقل {count} ملف صوتي محدد إلى سلة المهملات',
      'moveToTrash': 'نقل إلى المهملات',
      'movedToTrash': 'تم النقل إلى سلة المهملات',
      'filesMovedToTrash': 'تم نقل {count} ملف إلى سلة المهملات',
      'selectedCount': '{count} محدد',
      'selectAll': 'تحديد الكل',
      'deselectAll': 'إلغاء تحديد الكل',
      'deleteSelected': 'حذف المحدد',
      'cancelSelection': 'إلغاء التحديد',
    },
  };

  String translate(String key, {Map<String, Object>? args}) {
    final lang = locale.languageCode;
    var text = _translations[lang]?[key] ?? _translations['en']?[key] ?? key;
    args?.forEach((k, v) => text = text.replaceAll('{$k}', '$v'));
    return text;
  }

  String get myMusic => translate('myMusic');
  String get allSongs => translate('allSongs');
  String get folders => translate('folders');
  String get noAudioFiles => translate('noAudioFiles');
  String get permissionDenied => translate('permissionDenied');
  String errorLoading(String path) =>
      translate('errorLoading', args: {'path': path});
  String get enablePermission => translate('enablePermission');
  String get retry => translate('retry');
  String get noTrack => translate('noTrack');
  String get unknownArtist => translate('unknownArtist');
  String get delete => translate('delete');
  String get setAsRingtone => translate('setAsRingtone');
  String get sleepTimer => translate('sleepTimer');
  String get cancelSleepTimer => translate('cancelSleepTimer');
  String get deleteFile => translate('deleteFile');
  String deleteFileMsg(String path) =>
      translate('deleteFileMsg', args: {'path': path});
  String get deleteFolder => translate('deleteFolder');
  String deleteFolderMsg(String path, int count) =>
      translate('deleteFolderMsg', args: {'path': path, 'count': count});
  String get cancel => translate('cancel');
  String get close => translate('close');
  String get failedDelete => translate('failedDelete');
  String get fileDeleted => translate('fileDeleted');
  String filesDeleted(int count) =>
      translate('filesDeleted', args: {'count': count});
  String filesDeletedPartial(int deleted, int failed) => translate(
    'filesDeletedPartial',
    args: {'deleted': deleted, 'failed': failed},
  );
  String get ringtoneSuccess => translate('ringtoneSuccess');
  String get ringtoneFailed => translate('ringtoneFailed');
  String get ringtonePermission => translate('ringtonePermission');
  String get playbackError => translate('playbackError');
  String get minutes => translate('minutes');
  String get hour => translate('hour');
  String get endOfTrack => translate('endOfTrack');
  String get share => translate('share');
  String get details => translate('details');
  String get fileInfo => translate('fileInfo');
  String get folderInfo => translate('folderInfo');
  String get name => translate('name');
  String get path => translate('path');
  String get duration => translate('duration');
  String get size => translate('size');
  String get artist => translate('artist');
  String get modified => translate('modified');
  String get files => translate('files');
  String get sortBy => translate('sortBy');
  String get sortDateNewest => translate('sortDateNewest');
  String get sortDateOldest => translate('sortDateOldest');
  String get sortNameAZ => translate('sortNameAZ');
  String get sortNameZA => translate('sortNameZA');
  String get search => translate('search');
  String get searchHint => translate('searchHint');
  String get noResults => translate('noResults');
  String get play => translate('play');
  String get pause => translate('pause');
  String get next => translate('next');
  String get previous => translate('previous');
  String get rewind10 => translate('rewind10');
  String get forward10 => translate('forward10');
  String get shuffle => translate('shuffle');
  String get repeatOff => translate('repeatOff');
  String get repeatAll => translate('repeatAll');
  String get repeatOne => translate('repeatOne');
  String get speed => translate('speed');
  String get currentFolder => translate('currentFolder');
  String get openSettings => translate('openSettings');
  String get ringtone => translate('ringtone');
  String get queue => translate('queue');
  String get repeat => translate('repeat');
  String get repeatAllShort => translate('repeatAllShort');
  String get repeatOneShort => translate('repeatOneShort');
  String get on => translate('on');
  String get off => translate('off');
  String filesCount(int count) =>
      translate('filesCount', args: {'count': count});
  String get ok => translate('ok');
  String deleteFiles(int count) =>
      translate('deleteFiles', args: {'count': count});
  String deleteFilesMsg(int count) =>
      translate('deleteFilesMsg', args: {'count': count});
  String moveToTrashMsg(String path) =>
      translate('moveToTrashMsg', args: {'path': path});
  String moveFolderToTrashMsg(String path, int count) =>
      translate('moveFolderToTrashMsg', args: {'path': path, 'count': count});
  String moveFilesToTrashMsg(int count) =>
      translate('moveFilesToTrashMsg', args: {'count': count});
  String get moveToTrash => translate('moveToTrash');
  String get movedToTrash => translate('movedToTrash');
  String filesMovedToTrash(int count) =>
      translate('filesMovedToTrash', args: {'count': count});
  String selectedCount(int count) =>
      translate('selectedCount', args: {'count': count});
  String get selectAll => translate('selectAll');
  String get deselectAll => translate('deselectAll');
  String get deleteSelected => translate('deleteSelected');
  String get cancelSelection => translate('cancelSelection');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'ar'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
