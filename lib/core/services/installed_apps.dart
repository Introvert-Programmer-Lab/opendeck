import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// An app installed on this computer, with its real icon.
class InstalledApp {
  const InstalledApp({required this.name, required this.launch, this.iconPath});

  final String name; // display name, e.g. "Google Chrome"
  final String launch; // what HostActions openApp runs (Windows: shell:AppsFolder\<AppID>)
  final String? iconPath; // cached 256x256 PNG with alpha, or null

  Map<String, dynamic> toJson() => {'name': name, 'launch': launch, 'icon': iconPath};

  factory InstalledApp.fromJson(Map<String, dynamic> j) =>
      InstalledApp(name: j['name'] ?? '', launch: j['launch'] ?? '', iconPath: j['icon']);
}

/// Lists installed apps. On Windows this reads the Start menu app list
/// (shell:AppsFolder, the same as Get-StartApps: desktop and Store apps) and
/// extracts each app's official icon through IShellItemImageFactory.
class InstalledApps {
  static Future<List<InstalledApp>>? _running;

  static Future<List<InstalledApp>> scan({bool refresh = false}) {
    if (_running != null) return _running!;
    return _running = _scan(refresh).whenComplete(() => _running = null);
  }

  static Future<List<InstalledApp>> _scan(bool refresh) async {
    try {
      final support = await getApplicationSupportDirectory();
      final cache = File('${support.path}${Platform.pathSeparator}installed_apps.json');
      if (!refresh && await cache.exists()) {
        final age = DateTime.now().difference(await cache.lastModified());
        if (age < const Duration(days: 1)) {
          final list = (jsonDecode(await cache.readAsString()) as List)
              .map((e) => InstalledApp.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          if (list.isNotEmpty) return list;
        }
      }
      List<InstalledApp> apps;
      if (Platform.isWindows) {
        apps = await _scanWindows(support.path);
      } else if (Platform.isMacOS) {
        apps = await _scanMac();
      } else if (Platform.isLinux) {
        apps = await _scanLinux();
      } else {
        return const [];
      }
      final seen = <String>{};
      apps = apps.where((a) => a.name.isNotEmpty && a.launch.isNotEmpty && seen.add(a.name.toLowerCase())).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (apps.isNotEmpty) await cache.writeAsString(jsonEncode(apps.map((a) => a.toJson()).toList()));
      return apps;
    } catch (e) {
      debugPrint('installed apps scan failed: $e');
      return const [];
    }
  }

  static Future<List<InstalledApp>> _scanWindows(String supportDir) async {
    final sep = Platform.pathSeparator;
    final iconDir = '$supportDir${sep}app_icons';
    final script = File('$supportDir${sep}scan_apps.ps1');
    await script.writeAsString(_windowsScript);
    final r = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', script.path, '-IconDir', iconDir],
      stdoutEncoding: utf8,
    );
    var out = (r.stdout as String).trim();
    if (out.startsWith('\uFEFF')) out = out.substring(1);
    final start = out.indexOf('[');
    if (start < 0) {
      debugPrint('app scan: no output (${r.stderr})');
      return const [];
    }
    final list = jsonDecode(out.substring(start)) as List;
    return [
      for (final e in list)
        InstalledApp(
          name: '${e['name']}',
          launch: 'shell:AppsFolder\\${e['appId']}',
          iconPath: e['icon'] is String && File(e['icon']).existsSync() ? e['icon'] : null,
        ),
    ];
  }

  static Future<List<InstalledApp>> _scanMac() async {
    final apps = <InstalledApp>[];
    for (final dir in ['/Applications', '/System/Applications', '${Platform.environment['HOME']}/Applications']) {
      final d = Directory(dir);
      if (!await d.exists()) continue;
      await for (final e in d.list()) {
        if (e.path.endsWith('.app')) {
          final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last.replaceAll('.app', '');
          apps.add(InstalledApp(name: Uri.decodeComponent(name), launch: e.path));
        }
      }
    }
    return apps;
  }

  static Future<List<InstalledApp>> _scanLinux() async {
    final apps = <InstalledApp>[];
    final dirs = ['${Platform.environment['HOME']}/.local/share/applications', '/usr/share/applications'];
    for (final dir in dirs) {
      final d = Directory(dir);
      if (!await d.exists()) continue;
      await for (final e in d.list()) {
        if (e is! File || !e.path.endsWith('.desktop')) continue;
        String? name, exec;
        var hidden = false, inEntry = false;
        for (final line in await e.readAsLines()) {
          if (line.startsWith('[')) inEntry = line.trim() == '[Desktop Entry]';
          if (!inEntry) continue;
          if (line.startsWith('Name=') && name == null) name = line.substring(5).trim();
          if (line.startsWith('Exec=') && exec == null) exec = line.substring(5).replaceAll(RegExp(r'%[a-zA-Z]'), '').trim();
          if (line.startsWith('NoDisplay=true') || line.startsWith('Hidden=true')) hidden = true;
        }
        if (!hidden && name != null && exec != null) apps.add(InstalledApp(name: name, launch: exec));
      }
    }
    return apps;
  }
}

// Enumerates shell:AppsFolder and writes each app's icon as a 256x256 PNG,
// keeping the alpha channel (the shell bitmap is premultiplied BGRA).
const _windowsScript = r'''
param([string]$IconDir)
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class IpIcon {
  [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IShellItemImageFactory { [PreserveSig] int GetImage(SIZE size, int flags, out IntPtr phbm); }
  [StructLayout(LayoutKind.Sequential)] struct SIZE { public int cx, cy; public SIZE(int x, int y) { cx = x; cy = y; } }
  [StructLayout(LayoutKind.Sequential)] struct BITMAP { public int bmType, bmWidth, bmHeight, bmWidthBytes; public ushort bmPlanes, bmBitsPixel; public IntPtr bmBits; }
  [StructLayout(LayoutKind.Sequential)] struct BITMAPINFOHEADER { public int biSize, biWidth, biHeight; public short biPlanes, biBitCount; public int biCompression, biSizeImage, biXPelsPerMeter, biYPelsPerMeter, biClrUsed, biClrImportant; }
  [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
  static extern void SHCreateItemFromParsingName(string path, IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory item);
  [DllImport("gdi32.dll")] static extern int GetObject(IntPtr h, int c, ref BITMAP bm);
  [DllImport("gdi32.dll")] static extern int GetDIBits(IntPtr hdc, IntPtr hbm, uint start, uint lines, byte[] bits, ref BITMAPINFOHEADER bi, uint usage);
  [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
  [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);

  // Writes a 256x256 PNG with real alpha. Returns true on success.
  public static bool Save(string parsingName, string outPath) {
    IShellItemImageFactory f;
    try { SHCreateItemFromParsingName(parsingName, IntPtr.Zero, typeof(IShellItemImageFactory).GUID, out f); } catch { return false; }
    IntPtr hbm;
    // SIIGBF_BIGGERSIZEOK (1) | SIIGBF_ICONONLY (4)
    if (f.GetImage(new SIZE(256, 256), 0x1 | 0x4, out hbm) != 0 || hbm == IntPtr.Zero) { Marshal.ReleaseComObject(f); return false; }
    try {
      BITMAP bm = new BITMAP();
      GetObject(hbm, Marshal.SizeOf(typeof(BITMAP)), ref bm);
      int w = bm.bmWidth, h = bm.bmHeight;
      if (w <= 0 || h <= 0) return false;
      var bi = new BITMAPINFOHEADER { biSize = Marshal.SizeOf(typeof(BITMAPINFOHEADER)), biWidth = w, biHeight = -h, biPlanes = 1, biBitCount = 32 };
      byte[] px = new byte[w * h * 4];
      IntPtr dc = GetDC(IntPtr.Zero);
      GetDIBits(dc, hbm, 0, (uint)h, px, ref bi, 0);
      ReleaseDC(IntPtr.Zero, dc);
      bool anyAlpha = false;
      for (int i = 3; i < px.Length; i += 4) if (px[i] != 0) { anyAlpha = true; break; }
      for (int i = 0; i < px.Length; i += 4) {
        int a = px[i + 3];
        if (!anyAlpha) { px[i + 3] = 255; continue; }  // legacy icon without alpha channel
        if (a > 0 && a < 255) {  // un-premultiply
          px[i] = (byte)Math.Min(255, px[i] * 255 / a);
          px[i + 1] = (byte)Math.Min(255, px[i + 1] * 255 / a);
          px[i + 2] = (byte)Math.Min(255, px[i + 2] * 255 / a);
        }
      }
      using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
        var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        for (int y = 0; y < h; y++) Marshal.Copy(px, y * w * 4, IntPtr.Add(data.Scan0, y * data.Stride), w * 4);
        bmp.UnlockBits(data);
        bmp.Save(outPath, ImageFormat.Png);
      }
      return true;
    } finally { DeleteObject(hbm); Marshal.ReleaseComObject(f); }
  }
}
"@

New-Item -ItemType Directory -Force -Path $IconDir | Out-Null
$sha = [System.Security.Cryptography.SHA1]::Create()
$skip = '(?i)^(uninstall|remove|help|readme|release notes|documentation|license|website|manual)\b|uninstall|\breadme\b'
$seen = @{}
$out = New-Object System.Collections.ArrayList
$folder = (New-Object -ComObject Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}')
foreach ($it in $folder.Items()) {
  $name = $it.Name; $id = $it.Path
  if (-not $name -or -not $id) { continue }
  if ($name -match $skip) { continue }
  if ($id -match '(?i)\.(txt|pdf|htm|html|url|chm|rtf)$') { continue }
  $key = $name.ToLowerInvariant()
  if ($seen.ContainsKey($key)) { continue }
  $seen[$key] = 1
  $hash = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($id)) | Select-Object -First 10 | ForEach-Object { $_.ToString('x2') })
  $png = Join-Path $IconDir "$hash.png"
  if (-not (Test-Path $png)) { if (-not [IpIcon]::Save("shell:AppsFolder\$id", $png)) { $png = $null } }
  [void]$out.Add([ordered]@{ name = $name; appId = $id; icon = $png })
}
ConvertTo-Json -InputObject @($out) -Compress -Depth 3
''';
