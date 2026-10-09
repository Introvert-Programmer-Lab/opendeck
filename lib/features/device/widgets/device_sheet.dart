import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/deck_discovery.dart';
import '../../../core/services/deck_transport.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../deck/providers/project_provider.dart';
import '../../onboarding/pages/onboarding_page.dart';
import '../providers/device_provider.dart';

Future<void> showDeviceSheet(BuildContext context) => showDialog(context: context, builder: (_) => const _DeviceDialog());

class _DeviceDialog extends ConsumerStatefulWidget {
  const _DeviceDialog();
  @override
  ConsumerState<_DeviceDialog> createState() => _DeviceDialogState();
}

class _DeviceDialogState extends ConsumerState<_DeviceDialog> {
  List<SerialPortEntry> _ports = [];
  List<DiscoveredDeck> _found = [];
  bool _scanning = false;
  final _host = TextEditingController();
  final _ssid = TextEditingController();
  final _pass = TextEditingController();
  bool _showPass = false;

  @override
  void initState() {
    super.initState();
    _ports = SerialDeckTransport.listPorts();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final r = await DeckDiscovery.scan();
    if (mounted) setState(() => (_found = r, _scanning = false));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final dev = ref.watch(deviceProvider);
    final ctl = ref.read(deviceProvider.notifier);
    final info = dev.info;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 20), shrinkWrap: true, children: [
          Row(children: [
            const AppLogo(size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(s.deckInfo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 8),
          if (dev.connected && info != null) ...[
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const StatusDot(on: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${s.connectedVia} ${dev.isUsb ? s.usbCable : s.wifi} · ${dev.label}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  TextButton(onPressed: ctl.disconnect, child: Text(s.disconnect)),
                ]),
                const Divider(height: 22),
                _info(s.board, info.board),
                _info(s.firmware, info.fw),
                _info(s.storage, '${s.sizeKb(info.fsUsed)} / ${s.sizeKb(info.fsTotal)}'),
                _info(s.wifi, info.wifiAp ? '${s.hotspotHint}: ${info.wifiSsid}' : (info.wifiConnected ? info.wifiSsid : '-')),
                _info(s.address, info.wifiIp),
                const SizedBox(height: 6),
                FieldRow(
                  label: s.brightness,
                  child: SizedBox(
                    width: 200,
                    child: Slider(
                      value: ref.watch(projectProvider).brightness.toDouble().clamp(10, 255),
                      min: 10,
                      max: 255,
                      onChanged: (v) => ref.read(projectProvider.notifier).update((p) => p.copyWith(brightness: v.round())),
                      onChangeEnd: (v) => ctl.setBrightness(v.round()),
                    ),
                  ),
                ),
              ]),
            ),
            SectionLabel(s.wifiSetup),
            Text(s.wifiSetupHint, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(controller: _ssid, decoration: InputDecoration(labelText: s.networkName)),
            const SizedBox(height: 8),
            TextField(
              controller: _pass,
              obscureText: !_showPass,
              decoration: InputDecoration(
                labelText: s.password,
                suffixIcon: IconButton(
                  icon: Icon(_showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                icon: const Icon(Icons.wifi, size: 16),
                label: Text(s.send),
                onPressed: () async {
                  await ctl.setWifi(_ssid.text.trim(), _pass.text);
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.wifiSetup}: ${_ssid.text}')));
                },
              ),
            ),
          ] else ...[
            if (dev.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(s.errorText(dev.error!), style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
              ),
            SectionLabel(s.usbPorts,
                trailing: IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: () => setState(() => _ports = SerialDeckTransport.listPorts()),
                )),
            if (_ports.isEmpty) Text(s.noPorts, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
            for (final p in _ports)
              _ConnectTile(
                icon: Icons.usb_rounded,
                title: p.name,
                subtitle: p.description,
                highlight: p.likelyDeck,
                busy: dev.status == LinkStatus.connecting,
                onTap: () => ctl.connectUsb(p.name),
              ),
            SectionLabel(s.network,
                trailing: _scanning
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(icon: const Icon(Icons.radar_rounded, size: 20), tooltip: s.scan, onPressed: _scan)),
            if (_found.isEmpty && !_scanning) Text(s.noDecksFound, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
            for (final d in _found)
              _ConnectTile(
                icon: Icons.wifi_rounded,
                title: d.info.name,
                subtitle: '${d.host} · ${d.info.board}',
                highlight: true,
                busy: dev.status == LinkStatus.connecting,
                onTap: () => ctl.connectTcp(d.host),
              ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _host, decoration: InputDecoration(labelText: s.manualAddress, hintText: '192.168.1.50'))),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: dev.status == LinkStatus.connecting
                    ? null
                    : () {
                        final h = _host.text.trim();
                        if (h.isNotEmpty) ctl.connectTcp(h);
                      },
                child: Text(s.connect),
              ),
            ]),
            const SizedBox(height: 14),
            Text(s.hostOnlyNote, style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.5)),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.bolt_rounded, size: 16),
                label: Text(s.setupBoard),
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute(builder: (_) => const OnboardingPage(closeWhenDone: true)));
                },
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _info(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: AppTheme.muted, fontSize: 13))),
          Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

class _ConnectTile extends StatelessWidget {
  const _ConnectTile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.highlight = false, this.busy = false});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool highlight, busy;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(AppTheme.rControl),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.rControl),
            onTap: busy ? null : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.rControl),
                border: Border.all(color: highlight ? AppTheme.lineStrong : AppTheme.line),
              ),
              child: Row(children: [
                Icon(icon, color: highlight ? AppTheme.lime : AppTheme.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                  ]),
                ),
                if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) else const Icon(Icons.chevron_right_rounded),
              ]),
            ),
          ),
        ),
      );
}
