import 'package:flutter_test/flutter_test.dart';
import 'package:opendeck/core/services/app_focus.dart';

void main() {
  bool hit(String target, String exe, [String? aumid]) => AppMatcher.forTarget(target)?.matches(exePath: exe, aumid: aumid) ?? false;

  test('bare commands match the executable name', () {
    expect(hit('chrome', r'C:\Program Files\Google\Chrome\Application\chrome.exe'), isTrue);
    expect(hit('code', r'C:\Users\me\AppData\Local\Programs\Microsoft VS Code\Code.exe'), isTrue);
    expect(hit('explorer', r'C:\Windows\explorer.exe'), isTrue);
    expect(hit('chrome', r'C:\Program Files\Mozilla Firefox\firefox.exe'), isFalse);
  });

  test('full paths must match exactly', () {
    expect(hit(r'"C:\Games\game.exe"', r'c:\games\game.exe'), isTrue);
    expect(hit(r'C:\Games\game.exe', r'D:\Other\game.exe'), isFalse);
  });

  test('Start menu entries match by app ID or by their program path', () {
    expect(hit(r'shell:AppsFolder\com.squirrel.Discord.Discord', r'C:\Users\me\AppData\Local\Discord\app-1.0\Discord.exe',
        'com.squirrel.Discord.Discord'), isTrue);
    expect(hit(r'shell:AppsFolder\{6D809377-6AF0-444B-8957-A3773F02200E}\obs-studio\bin\64bit\obs64.exe',
        r'C:\Program Files\obs-studio\bin\64bit\obs64.exe'), isTrue);
    expect(hit(r'shell:AppsFolder\Microsoft.Windows.Explorer', r'C:\Windows\explorer.exe'), isTrue);
  });

  test('documents, folders, shortcuts and websites are always opened', () {
    for (final t in [r'C:\Users\me\notes.txt', r'C:\Users\me\Downloads', r'C:\Users\me\Desktop\Game.lnk', 'https://example.com', '']) {
      expect(AppMatcher.forTarget(t), isNull, reason: t);
    }
  });

  test('protocol handlers', () {
    final discord = AppMatcher.forProtocolCommand(r'"C:\Users\me\AppData\Local\Discord\Update.exe" --processStart Discord.exe --process-start-args "%1"');
    expect(discord?.matches(exePath: r'C:\Users\me\AppData\Local\Discord\app-1.0.9\Discord.exe'), isTrue);
    final spotify = AppMatcher.forProtocolCommand(r'"C:\Users\me\AppData\Roaming\Spotify\Spotify.exe" --protocol-uri="%1"');
    expect(spotify?.matches(exePath: r'C:\Users\me\AppData\Roaming\Spotify\Spotify.exe'), isTrue);
    expect(AppMatcher.forProtocolCommand(r'"C:\Program Files\Google\Chrome\Application\chrome.exe" -- "%1"'), isNull);
  });

  test('schemeOf', () {
    expect(schemeOf('discord:'), 'discord');
    expect(schemeOf('https://x.com'), 'https');
    expect(schemeOf(r'C:\file.txt'), isNull);
    expect(schemeOf('plain'), isNull);
  });
}
