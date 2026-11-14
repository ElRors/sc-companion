import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

late SharedPreferences prefs;

final lang = ValueNotifier<String>('es');
String tr(String es, String en) => lang.value == 'en' ? en : es;

String hangarLabel(String s) => switch (s) {
      'valores integrados' => tr(s, 'built-in values'),
      'caché local' => tr(s, 'local cache'),
      _ => tr(s, 'synced with exec.xyxyll.com'),
    };

const _seqEn = {'Arranque': 'Startup', 'Apagado': 'Shutdown', 'Despegue': 'Takeoff'};
String seqName(String n) => lang.value == 'en' ? (_seqEn[n] ?? n) : n;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  lang.value = prefs.getString('lang') ?? 'es';
  startPing();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: lang,
        builder: (_, l, __) => MaterialApp(
          title: 'StarCitizen Companion',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            colorSchemeSeed: Colors.cyan,
            scaffoldBackgroundColor: const Color(0xFF050B14),
            useMaterial3: true,
          ),
          home: Home(key: ValueKey(l)),
        ),
      );
}

// ---------- Cliente del servidor de la PC ----------
class Pc {
  static String get host => prefs.getString('host') ?? '192.168.1.10:8765';
  static String get token => prefs.getString('token') ?? 'cambia-esto';

  static Future<String?> _post(String path, Map body) async {
    try {
      final r = await http
          .post(Uri.parse('http://$host$path'),
              headers: {'X-Token': token, 'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 60));
      return r.statusCode == 200 ? null : r.body;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> key(String keys, {int hold = 60}) =>
      _post('/key', {'keys': keys, 'hold': hold});
  static Future<String?> down(String keys) => _post('/down', {'keys': keys});
  static Future<String?> up(String keys) => _post('/up', {'keys': keys});
  static Future<String?> sequence(List<Map> steps) =>
      _post('/sequence', {'steps': steps});
}

void toast(BuildContext c, String m) => ScaffoldMessenger.of(c)
    .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

// ---------- Home ----------
class Home extends StatelessWidget {
  const Home({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 8,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('StarCitizen Companion'),
          actions: [
            ValueListenableBuilder<int?>(
              valueListenable: latency,
              builder: (_, ms, __) => Icon(
                  ms == null ? Icons.wifi_off : Icons.wifi,
                  color: ms == null ? Colors.redAccent : Colors.greenAccent),
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => showDialog(
                  context: context, builder: (_) => const SettingsDialog()),
            ),
          ],
          bottom: TabBar(tabs: [
            Tab(icon: Icon(Icons.gps_fixed), text: 'Control'),
            Tab(icon: Icon(Icons.grid_view), text: 'Macros'),
            Tab(icon: Icon(Icons.playlist_play), text: tr('Secuencias', 'Sequences')),
            Tab(icon: Icon(Icons.local_shipping), text: tr('Comercio', 'Trade')),
            Tab(icon: Icon(Icons.calculate), text: tr('Calculadora', 'Calculator')),
            Tab(icon: Icon(Icons.timer), text: 'Timers'),
            Tab(icon: Icon(Icons.warehouse), text: 'Hangar'),
            Tab(icon: Icon(Icons.checklist), text: tr('Notas', 'Notes')),
          ]),
        ),
        body: const TabBarView(physics: NeverScrollableScrollPhysics(), children: [
          ControlTab(),
          PanelTab(),
          SequencesTab(),
          TradeTab(),
          CalculatorTab(),
          TimersTab(),
          HangarTab(),
          NotesTab(),
        ]),
      ),
    );
  }
}

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});
  @override
  Widget build(BuildContext context) {
    final h = TextEditingController(text: Pc.host);
    final t = TextEditingController(text: Pc.token);
    return AlertDialog(
      title: Text(tr('Conexión con la PC', 'PC connection')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: h,
            decoration: InputDecoration(labelText: tr('IP:puerto de la PC', 'PC IP:port'))),
        TextField(
            controller: t, decoration: const InputDecoration(labelText: 'Token')),
        ValueListenableBuilder<String>(
          valueListenable: lang,
          builder: (_, l, __) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'es', label: Text('Español')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {l},
              onSelectionChanged: (v) {
                lang.value = v.first;
                prefs.setString('lang', v.first);
              },
            ),
          ),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () async {
              String msg;
              try {
                final r = await http
                    .get(Uri.parse('http://${h.text.trim()}/'))
                    .timeout(const Duration(seconds: 4));
                msg = tr('Conectado (${r.statusCode})', 'Connected (${r.statusCode})');
              } catch (e) {
                msg = tr('Sin conexión', 'No connection');
              }
              if (context.mounted) toast(context, msg);
            },
            child: Text(tr('Probar', 'Test'))),
        FilledButton(
            onPressed: () async {
              await prefs.setString('host', h.text.trim());
              await prefs.setString('token', t.text.trim());
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(tr('Guardar', 'Save'))),
      ],
    );
  }
}

// ---------- Panel de macros ----------
class Macro {
  String name, keys;
  Macro(this.name, this.keys);
  Map toJson() => {'n': name, 'k': keys};
}

// Teclas por defecto aproximadas: ajústalas con pulsación larga a tus keybinds.
List<Macro> defaultMacros() => [
      Macro(tr('Energía (nave)', 'Ship power'), 'u'),
      Macro(tr('Motores', 'Engines'), 'i'),
      Macro(tr('Escudos', 'Shields'), 'o'),
      Macro(tr('Armas', 'Weapons'), 'p'),
      Macro(tr('Luces', 'Lights'), 'l'),
      Macro(tr('Tren de aterrizaje', 'Landing gear'), 'n'),
      Macro(tr('Puertas/Rampa', 'Doors/Ramp'), 'k'),
      Macro(tr('Modo Quantum', 'Quantum mode'), 'b'),
      Macro(tr('Bloqueo de puertas', 'Door lock'), 'ctrl+k'),
    ];

class PanelTab extends StatefulWidget {
  const PanelTab({super.key});
  @override
  State<PanelTab> createState() => _PanelTabState();
}

class _PanelTabState extends State<PanelTab> {
  late List<Macro> macros;
  @override
  void initState() {
    super.initState();
    final s = prefs.getString('macros');
    macros = s == null
        ? defaultMacros()
        : (jsonDecode(s) as List).map((e) => Macro(e['n'], e['k'])).toList();
  }

  void save() =>
      prefs.setString('macros', jsonEncode(macros.map((m) => m.toJson()).toList()));

  Future<void> edit(Macro? m) async {
    final n = TextEditingController(text: m?.name);
    final k = TextEditingController(text: m?.keys);
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: Text(m == null ? tr('Nueva macro', 'New macro') : tr('Editar macro', 'Edit macro')),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: n,
                    decoration: InputDecoration(labelText: tr('Nombre', 'Name'))),
                TextField(
                    controller: k,
                    decoration: InputDecoration(
                        labelText: tr('Tecla (ej: u, ctrl+k, alt+n)', 'Key (e.g. u, ctrl+k, alt+n)'))),
              ]),
              actions: [
                if (m != null)
                  TextButton(
                      onPressed: () {
                        setState(() => macros.remove(m));
                        save();
                        Navigator.pop(context, false);
                      },
                      child: Text(tr('Borrar', 'Delete'))),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('OK')),
              ],
            ));
    if (ok != true) return;
    setState(() {
      if (m == null) {
        macros.add(Macro(n.text, k.text));
      } else {
        m.name = n.text;
        m.keys = k.text;
      }
    });
    save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton:
          FloatingActionButton(onPressed: () => edit(null), child: const Icon(Icons.add)),
      body: GridView.count(
        padding: const EdgeInsets.all(12),
        crossAxisCount: 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.8,
        children: [
          for (final m in macros)
            FilledButton.tonal(
              onPressed: () async {
                HapticFeedback.mediumImpact();
                final err = await Pc.key(m.keys);
                if (mounted && err != null) toast(context, 'Error: $err');
              },
              onLongPress: () => edit(m),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(m.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16)),
                Text('[${m.keys}]', style: const TextStyle(fontSize: 11)),
              ]),
            ),
        ],
      ),
    );
  }
}

// ---------- Secuencias ----------
class Step {
  final String keys;
  final double delay;
  const Step(this.keys, this.delay);
}

const sequences = <String, List<Step>>{
  'Arranque': [Step('u', 3), Step('i', 3), Step('o', 2), Step('p', 1), Step('l', 1)],
  'Apagado': [Step('l', 1), Step('n', 5), Step('p', 1), Step('o', 1), Step('i', 2), Step('u', 1)],
  'Despegue': [Step('k', 2), Step('n', 4)],
};

class SequencesTab extends StatefulWidget {
  const SequencesTab({super.key});
  @override
  State<SequencesTab> createState() => _SequencesTabState();
}

class _SequencesTabState extends State<SequencesTab> {
  String status = tr('Listo (teclas definidas en sequences, en main.dart)', 'Ready');
  bool running = false;

  Future<void> run(String name) async {
    setState(() {
      running = true;
      status = tr('Ejecutando ${seqName(name)}…', 'Running ${seqName(name)}…');
    });
    final err = await Pc.sequence([
      for (final s in sequences[name]!) {'keys': s.keys, 'delay': s.delay}
    ]);
    if (mounted) {
      setState(() {
        running = false;
        status = err == null ? tr('${seqName(name)} completada', '${seqName(name)} completed') : 'Error: $err';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          if (running) const LinearProgressIndicator(),
          Text(status),
          const SizedBox(height: 16),
          Wrap(spacing: 16, runSpacing: 16, children: [
            for (final n in sequences.keys)
              SizedBox(
                width: 220,
                height: 90,
                child: FilledButton(
                    onPressed: running ? null : () => run(n),
                    child: Text('${seqName(n)}\n${sequences[n]!.map((s) => s.keys).join(' → ')}',
                        textAlign: TextAlign.center)),
              ),
          ]),
        ]),
      );
}

// ---------- Calculadora (erkul.games) ----------
class CalculatorTab extends StatefulWidget {
  const CalculatorTab({super.key});
  @override
  State<CalculatorTab> createState() => _CalculatorTabState();
}

class _CalculatorTabState extends State<CalculatorTab>
    with AutomaticKeepAliveClientMixin {
  static const url = 'https://erkul.games/calculator';
  late final WebViewController web;
  int progress = 0;
  bool failed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF09090B))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => failed = false),
        onProgress: (p) => setState(() => progress = p),
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? false) setState(() => failed = true);
        },
      ))
      ..loadRequest(Uri.parse(url));
  }

  Widget bar() => Row(children: [
        IconButton(
            icon: const Icon(Icons.arrow_back, color: _accent),
            onPressed: () async {
              if (await web.canGoBack()) web.goBack();
            }),
        IconButton(
            icon: const Icon(Icons.refresh, color: _accent),
            onPressed: () {
              setState(() => failed = false);
              web.reload();
            }),
        const SizedBox(width: 6),
        const Expanded(
            child: Text('// ERKUL DPS CALCULATOR',
                style: TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    fontSize: 13))),
        IconButton(
            tooltip: tr('Abrir en el navegador', 'Open in browser'),
            icon: const Icon(Icons.open_in_new, color: _accent),
            onPressed: () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
      ]);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
            border: Border.all(color: _accent.withOpacity(0.45)),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(4)),
            boxShadow: [BoxShadow(color: _accent.withOpacity(0.18), blurRadius: 12)]),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(color: const Color(0xFF0A1626), child: bar()),
          SizedBox(
              height: 2,
              child: progress < 100 && !failed
                  ? LinearProgressIndicator(value: progress / 100, color: _accent)
                  : const ColoredBox(color: _accent)),
          Expanded(
            child: failed
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_off, size: 48, color: Colors.redAccent),
                    const SizedBox(height: 8),
                    Text(tr('Sin conexión a internet', 'No internet connection')),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                        onPressed: () {
                          setState(() => failed = false);
                          web.reload();
                        },
                        icon: const Icon(Icons.refresh),
                        label: Text(tr('Reintentar', 'Retry'))),
                  ]))
                : WebViewWidget(controller: web),
          ),
        ]),
      ),
    );
  }
}

// ---------- Comercio ----------
class TradeTab extends StatefulWidget {
  const TradeTab({super.key});
  @override
  State<TradeTab> createState() => _TradeTabState();
}

class _TradeTabState extends State<TradeTab> {
  final scu = TextEditingController(text: prefs.getString('scu') ?? '96');
  final buy = TextEditingController();
  final sell = TextEditingController();
  final minutes = TextEditingController();

  List<Map> commodities = [];
  Map? selected;
  List<Map> buyAt = [], sellAt = [];
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    loadCommodities();
  }

  Future<List> uex(String path) async {
    final r = await http
        .get(Uri.parse('https://api.uexcorp.space/2.0/$path'))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw tr('UEX respondió ${r.statusCode}', 'UEX replied ${r.statusCode}');
    return jsonDecode(r.body)['data'] as List;
  }

  Future<void> loadCommodities() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = (await uex('commodities'))
          .map((e) => Map.from(e))
          .where((e) => e['is_visible'] == 1)
          .toList()
        ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
      setState(() => commodities = d);
    } catch (e) {
      setState(() => error = tr('No se pudo cargar UEX: $e', 'Could not load UEX: $e'));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> loadPrices(Map c) async {
    setState(() {
      selected = c;
      loading = true;
      error = null;
    });
    try {
      final rows = (await uex('commodities_prices?id_commodity=${c['id']}'))
          .map((e) => Map.from(e))
          .toList();
      num p(Map m, String k) => (m[k] ?? 0) as num;
      setState(() {
        buyAt = rows.where((m) => p(m, 'price_buy') > 0).toList()
          ..sort((a, b) => p(a, 'price_buy').compareTo(p(b, 'price_buy')));
        sellAt = rows.where((m) => p(m, 'price_sell') > 0).toList()
          ..sort((a, b) => p(b, 'price_sell').compareTo(p(a, 'price_sell')));
      });
    } catch (e) {
      setState(() => error = tr('No se pudo cargar precios: $e', 'Could not load prices: $e'));
    }
    if (mounted) setState(() => loading = false);
  }

  double n(TextEditingController c) => double.tryParse(c.text) ?? 0;

  Widget terminalList(String title, List<Map> rows, String priceKey,
      String scuKey, TextEditingController target) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: _accent, fontWeight: FontWeight.bold)),
        const Divider(color: _line),
        if (rows.isEmpty) Text(tr('Sin datos', 'No data'), style: TextStyle(color: Colors.white54)),
        for (final r in rows.take(8))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${r['terminal_name']}'),
            subtitle: Text('${r['star_system_name'] ?? ''} · ${r[scuKey] ?? 0} SCU',
                style: const TextStyle(fontSize: 11)),
            trailing: Text('${r[priceKey]}',
                style: const TextStyle(fontSize: 16)),
            onTap: () => setState(() => target.text = '${r[priceKey]}'),
          ),
      ]),
    );
  }

  Widget market() {
    final best = (buyAt.isNotEmpty && sellAt.isNotEmpty)
        ? (sellAt.first['price_sell'] as num) - (buyAt.first['price_buy'] as num)
        : null;
    return ListView(children: [
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<Map>(
            isExpanded: true,
            initialValue: selected,
            decoration: InputDecoration(labelText: tr('Mercancía (UEX Corp)', 'Commodity (UEX Corp)')),
            items: [
              for (final c in commodities)
                DropdownMenuItem(value: c, child: Text('${c['name']}'))
            ],
            onChanged: (c) => c == null ? null : loadPrices(c),
          ),
        ),
        IconButton(
            onPressed: selected == null ? loadCommodities : () => loadPrices(selected!),
            icon: const Icon(Icons.refresh)),
      ]),
      if (loading) const LinearProgressIndicator(),
      if (error != null)
        Text(error!, style: const TextStyle(color: Colors.redAccent)),
      if (best != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(tr('Mejor margen: $best aUEC/SCU (toca un terminal para usar su precio)', 'Best margin: $best aUEC/SCU (tap a terminal to use its price)'),
              style: const TextStyle(color: Colors.greenAccent)),
        ),
      if (selected != null)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          terminalList(tr('COMPRAR en (más barato)', 'BUY at (cheapest)'), buyAt, 'price_buy', 'scu_buy', buy),
          const SizedBox(width: 16),
          terminalList(tr('VENDER en (más caro)', 'SELL at (priciest)'), sellAt, 'price_sell', 'scu_sell', sell),
        ]),
      Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(tr('Datos de uexcorp.space (aportados por jugadores).', 'Data from uexcorp.space (player-submitted).'),
            style: TextStyle(fontSize: 11, color: Colors.white54)),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cap = n(scu), b = n(buy), s = n(sell), m = n(minutes);
    final cost = cap * b, rev = cap * s, profit = rev - cost;
    final perHour = m > 0 ? profit / m * 60 : 0;
    Widget f(String l, TextEditingController c) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        onChanged: (_) {
          prefs.setString('scu', scu.text);
          setState(() {});
        },
        decoration: InputDecoration(labelText: l));
    final calc = ListView(children: [
      f(tr('Capacidad (SCU)', 'Capacity (SCU)'), scu),
      f(tr('Compra/SCU (aUEC)', 'Buy/SCU (aUEC)'), buy),
      f(tr('Venta/SCU (aUEC)', 'Sell/SCU (aUEC)'), sell),
      f(tr('Duración ruta (min)', 'Route time (min)'), minutes),
      const SizedBox(height: 16),
      Text(tr('Inversión: ${cost.toStringAsFixed(0)} aUEC', 'Investment: ${cost.toStringAsFixed(0)} aUEC'), style: const TextStyle(fontSize: 18)),
      Text(tr('Ingreso: ${rev.toStringAsFixed(0)} aUEC', 'Revenue: ${rev.toStringAsFixed(0)} aUEC'), style: const TextStyle(fontSize: 18)),
      Text(tr('Ganancia: ${profit.toStringAsFixed(0)} aUEC', 'Profit: ${profit.toStringAsFixed(0)} aUEC'),
          style: TextStyle(
              fontSize: 22, color: profit >= 0 ? Colors.greenAccent : Colors.redAccent)),
      Text(tr('Por hora: ${perHour.toStringAsFixed(0)} aUEC/h', 'Per hour: ${perHour.toStringAsFixed(0)} aUEC/h'),
          style: const TextStyle(fontSize: 18)),
    ]);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 280, child: calc),
        const VerticalDivider(width: 32, color: _line),
        Expanded(child: market()),
      ]),
    );
  }
}

// ---------- Hangar ejecutivo ----------
// Ciclo calculado igual que exec.xyxyll.com (MIT, Xyxyll). Si tras un parche
// los tiempos se desfasan, hay que actualizar _hangarInitialOpen/_hangarDriftMs.
// Parámetros del ciclo; se sincronizan con app.js de la página (ver syncHangar).
DateTime _hangarInitialOpen = DateTime.utc(2026, 11, 12, 19, 1, 40, 977);
int _hangarDriftMs = 295;
int _onlineMin = 65, _offlineMin = 120, _cycleOffset = 2;
String hangarSync = 'valores integrados';
int get _cycleMs => (_onlineMin + _offlineMin) * 60000 + _hangarDriftMs;
int get _openMs => (_cycleMs * _onlineMin / (_onlineMin + _offlineMin)).round();
int get _closeMs => _cycleMs - _openMs;

bool _applyHangarJs(String js) {
  int? n(String k) {
    final m = RegExp('const $k\\s*=\\s*(\\d+)').firstMatch(js);
    return m == null ? null : int.parse(m.group(1)!);
  }

  final drift = n('CYCLE_DRIFT_MS'), on = n('DESIGN_ONLINE_MIN'), off = n('DESIGN_OFFLINE_MIN');
  final t = RegExp(r"INITIAL_OPEN_TIME\s*=\s*new Date\('([^']+)'\)").firstMatch(js);
  final o = RegExp(r'CYCLE_DURATION\)\s*\+\s*(\d+)').firstMatch(js);
  final init = t == null ? null : DateTime.tryParse(t.group(1)!);
  if (drift == null || on == null || off == null || init == null) return false;
  _hangarDriftMs = drift;
  _onlineMin = on;
  _offlineMin = off;
  _hangarInitialOpen = init.toUtc();
  if (o != null) _cycleOffset = int.parse(o.group(1)!);
  return true;
}

Future<void> syncHangar() async {
  final cached = prefs.getString('hangar_js');
  if (cached != null && _applyHangarJs(cached)) hangarSync = 'caché local';
  try {
    final r = await http
        .get(Uri.parse('https://exec.xyxyll.com/app.js'))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode == 200 && _applyHangarJs(r.body)) {
      await prefs.setString('hangar_js', r.body);
      hangarSync = 'sincronizado con exec.xyxyll.com';
    }
  } catch (_) {}
}

class HangarState {
  final bool online;
  final Duration left;
  final List<int> lights; // 1 verde, 2 rojo, 0 vacío
  final int cycle;
  HangarState(this.online, this.left, this.lights, this.cycle);
}

HangarState hangarAt(DateTime now) {
  final elapsed = now.difference(_hangarInitialOpen).inMilliseconds;
  final t = elapsed % _cycleMs;
  final cycle = elapsed ~/ _cycleMs + _cycleOffset;
  if (t < _openMs) {
    final frac = t / _openMs * _onlineMin;
    final greens = frac < 12 ? 5 : frac < 24 ? 4 : frac < 36 ? 3 : frac < 48 ? 2 : frac < 60 ? 1 : 0;
    return HangarState(true, Duration(milliseconds: _openMs - t),
        [for (var i = 0; i < 5; i++) i < greens ? 1 : 0], cycle);
  }
  final c = t - _openMs;
  final greens = (c / _closeMs * 5).floor().clamp(0, 4);
  return HangarState(false, Duration(milliseconds: _closeMs - c),
      [for (var i = 0; i < 5; i++) i < greens ? 1 : 2], cycle);
}

class HangarTab extends StatefulWidget {
  const HangarTab({super.key});
  @override
  State<HangarTab> createState() => _HangarTabState();
}

class _HangarTabState extends State<HangarTab> {
  Timer? tick;
  bool? last;

  @override
  void initState() {
    super.initState();
    syncHangar().then((_) {
      if (mounted) setState(() {});
    });
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = hangarAt(DateTime.now());
      if (last != null && last != s.online) {
        HapticFeedback.vibrate();
        SystemSound.play(SystemSoundType.alert);
        if (mounted) {
          toast(context, s.online ? tr('¡Hangares ejecutivos ONLINE!', 'Executive hangars ONLINE!') : tr('Hangares ejecutivos OFFLINE', 'Executive hangars OFFLINE'));
        }
      }
      last = s.online;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    tick?.cancel();
    super.dispose();
  }

  String fmt(Duration d) {
    String t(int x) => x.toString().padLeft(2, '0');
    return '${t(d.inHours)}:${t(d.inMinutes % 60)}:${t(d.inSeconds % 60)}';
  }

  String hm(DateTime d) {
    final l = d.toLocal();
    String t(int x) => x.toString().padLeft(2, '0');
    return '${t(l.day)}/${t(l.month)} ${t(l.hour)}:${t(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final s = hangarAt(now);
    final color = s.online ? Colors.greenAccent : Colors.redAccent;
    final events = <Widget>[];
    var t = now.add(s.left);
    var online = !s.online;
    for (var i = 0; i < 8; i++) {
      events.add(ListTile(
        dense: true,
        leading: Icon(Icons.circle, size: 14, color: online ? Colors.greenAccent : Colors.redAccent),
        title: Text(online ? 'Online' : 'Offline'),
        trailing: Text(hm(t)),
      ));
      t = t.add(Duration(milliseconds: online ? _openMs : _closeMs));
      online = !online;
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(s.online ? 'ONLINE' : 'OFFLINE',
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: color)),
            Text(tr('Próximo cambio en', 'Next change in'), style: TextStyle(color: Colors.white54)),
            Text(fmt(s.left), style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final l in s.lights)
                Container(
                  margin: const EdgeInsets.all(6),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _line),
                      color: l == 1
                          ? const Color(0xFF4CAF50)
                          : l == 2
                              ? const Color(0xFFF44336)
                              : Colors.transparent),
                ),
            ]),
            const SizedBox(height: 8),
            Text('${tr('Ciclo', 'Cycle')} ${s.cycle} · ${hangarLabel(hangarSync)}',
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ]),
        ),
        const VerticalDivider(width: 32, color: _line),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('PRÓXIMOS CAMBIOS', 'UPCOMING CHANGES'),
                style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
            const Divider(color: _line),
            Expanded(child: ListView(children: events)),
          ]),
        ),
      ]),
    );
  }
}

// ---------- Timers ----------
class TimerItem {
  final String name;
  final DateTime end;
  TimerItem(this.name, this.end);
}

class TimersTab extends StatefulWidget {
  const TimersTab({super.key});
  @override
  State<TimersTab> createState() => _TimersTabState();
}

class _TimersTabState extends State<TimersTab> {
  final items = <TimerItem>[];
  Timer? tick;
  final alerted = <TimerItem>{};

  @override
  void initState() {
    super.initState();
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      for (final i in items) {
        if (DateTime.now().isAfter(i.end) && alerted.add(i)) {
          HapticFeedback.vibrate();
          SystemSound.play(SystemSoundType.alert);
          if (mounted) toast(context, tr('¡${i.name} terminó!', '${i.name} finished!'));
        }
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    tick?.cancel();
    super.dispose();
  }

  Future<void> add() async {
    final n = TextEditingController(text: 'Cooldown');
    final m = TextEditingController(text: '10');
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: Text(tr('Nuevo timer', 'New timer')),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: n, decoration: InputDecoration(labelText: tr('Nombre', 'Name'))),
                TextField(
                    controller: m,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr('Minutos', 'Minutes'))),
              ]),
              actions: [
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(tr('Iniciar', 'Start')))
              ],
            ));
    if (ok == true) {
      final mins = double.tryParse(m.text) ?? 1;
      setState(() => items.add(
          TimerItem(n.text, DateTime.now().add(Duration(seconds: (mins * 60).round())))));
    }
  }

  String fmt(Duration d) {
    if (d.isNegative) return tr('¡Listo!', 'Ready!');
    String t(int x) => x.toString().padLeft(2, '0');
    return '${t(d.inHours)}:${t(d.inMinutes % 60)}:${t(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton:
            FloatingActionButton(onPressed: add, child: const Icon(Icons.add_alarm)),
        body: ListView(children: [
          for (final i in items)
            ListTile(
              title: Text(i.name),
              trailing: Text(fmt(i.end.difference(DateTime.now())),
                  style: const TextStyle(fontSize: 24)),
              leading: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => setState(() => items.remove(i))),
            ),
        ]),
      );
}

// ---------- Control ----------
const _bg = Color(0xFF0A1626);
const _line = Color(0xFF1B4F8A);
const _accent = Color(0xFF29B6F6);

final latency = ValueNotifier<int?>(null);

void startPing() {
  Timer.periodic(const Duration(seconds: 4), (_) async {
    final sw = Stopwatch()..start();
    try {
      await http
          .get(Uri.parse('http://${Pc.host}/'))
          .timeout(const Duration(seconds: 3));
      latency.value = sw.elapsedMilliseconds;
    } catch (_) {
      latency.value = null;
    }
  });
}

// Teclas según el mapa de teclado de Star Citizen del usuario.
// "num5" = teclado numérico, "mouse:left"/"mouse:right" = clics del mouse.
final defaultKeys = <String, String>{
  'motores': 'i', 'escudos': 'o', 'armas': 'p', 'luces': 'l', 'energia': 'u',
  'tren': 'n',
  'fuego1': 'mouse:left', 'fuego2': 'mouse:right', 'senuelo': 'h', 'chaff': 'j',
  'sh0': 'num5', 'sh1': 'num8', 'sh2': 'num2', 'sh3': 'num4', 'sh4': 'num6',
  'sh5': 'num7', 'sh6': 'num9',
  't1': '1', 't2': '2', 't3': '3', 'tAtacante': '4', 'tHostil': '5',
  'tAmigo': '6', 'tTodos': '7', 'tHail': '9', 'tVista': 't',
  'vtol': 'k', 'escaneo': 'v', 'aterrizaje': 'alt+n',
  // En el juego del usuario F5 sube armas, F6 motores y F7 escudos.
  'e0+': 'f6', 'e1+': 'f7', 'e2+': 'f5', 'ereset': 'f8',
};

String keyOf(String id) => prefs.getString('key_$id') ?? defaultKeys[id]!;

Future<void> fire(BuildContext c, String id, {int hold = 60}) async {
  HapticFeedback.mediumImpact();
  final err = await Pc.key(keyOf(id), hold: hold);
  if (c.mounted && err != null) toast(c, 'Error: $err');
}

Future<void> editKey(BuildContext c, String id, String label) async {
  final k = TextEditingController(text: keyOf(id));
  final ok = await showDialog<bool>(
      context: c,
      builder: (_) => AlertDialog(
            title: Text(tr('Tecla para $label', 'Key for $label')),
            content: TextField(
                controller: k,
                decoration:
                    InputDecoration(labelText: tr('Ej: u, ctrl+k, f5', 'E.g. u, ctrl+k, f5'))),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: Text(tr('Guardar', 'Save')))
            ],
          ));
  if (ok == true && k.text.trim().isNotEmpty) {
    await prefs.setString('key_$id', k.text.trim());
  }
}

class Panel extends StatelessWidget {
  final String title;
  final Widget child;
  const Panel(this.title, this.child, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0E2238), Color(0xFF060E1A)]),
            border: Border.all(color: _accent.withOpacity(0.45)),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(4)),
            boxShadow: [
              BoxShadow(color: _accent.withOpacity(0.18), blurRadius: 12)
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.greenAccent,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.greenAccent.withOpacity(0.8), blurRadius: 6)
                    ])),
            const SizedBox(width: 8),
            Expanded(
              child: Text('// ${title.toUpperCase()}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      fontSize: 13,
                      color: _accent)),
            ),
            for (var i = 0; i < 3; i++)
              Container(
                  margin: const EdgeInsets.only(left: 3),
                  width: 14,
                  height: 3,
                  color: _accent.withOpacity(0.3 + i * 0.25)),
          ]),
          Container(
              height: 2,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [_accent, _accent.withOpacity(0)]))),
          Expanded(child: child),
        ]),
      );
}

class ControlTab extends StatefulWidget {
  const ControlTab({super.key});
  @override
  State<ControlTab> createState() => _ControlTabState();
}

class _ControlTabState extends State<ControlTab> {

  Widget btn(String id, String label, IconData icon,
          {int hold = 60, VoidCallback? also, bool big = false, bool wide = false}) =>
      OutlinedButton(
        style: OutlinedButton.styleFrom(
            padding: wide ? const EdgeInsets.symmetric(horizontal: 6) : null,
            side: BorderSide(color: _accent.withOpacity(0.5)),
            backgroundColor: _accent.withOpacity(0.06),
            shape: const BeveledRectangleBorder(
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10)))),
        onPressed: () {
          also?.call();
          fire(context, id, hold: hold);
        },
        onLongPress: () => editKey(context, id, label),
        child: wide
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: _accent, size: 20),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14))),
              ])
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: _accent, size: big ? 44 : 24),
          SizedBox(height: big ? 8 : 4),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: big ? 20 : 13,
                  fontWeight: big ? FontWeight.bold : FontWeight.normal)),
        ]),
      );

  Widget systems() {
    final items = [
      ['energia', tr('Energía', 'Power'), Icons.power_settings_new],
      ['motores', tr('Motores', 'Engines'), Icons.settings_input_component],
      ['escudos', tr('Escudos', 'Shields'), Icons.shield],
      ['armas', tr('Armas', 'Weapons'), Icons.gps_fixed],
      ['luces', tr('Luces', 'Lights'), Icons.light_mode],
      ['tren', tr('Tren aterrizaje', 'Landing gear'), Icons.flight_land],
    ];
    return Column(children: [
      for (var r = 0; r < 3; r++) ...[
        if (r > 0) const SizedBox(height: 8),
        Expanded(
          child: Row(children: [
            for (var c = 0; c < 2; c++) ...[
              if (c > 0) const SizedBox(width: 8),
              Expanded(
                  child: SizedBox.expand(
                      child: btn(items[r * 2 + c][0] as String,
                          items[r * 2 + c][1] as String,
                          items[r * 2 + c][2] as IconData, big: true))),
            ],
          ]),
        ),
      ],
    ]);
  }

  Widget targets() =>
      SizedBox.expand(child: btn('tVista', tr('Fijar a la vista', 'Lock target'), Icons.visibility));

  final pending = <String, Future<String?>>{};

  Widget holdBtn(String id, String label, IconData icon) => GestureDetector(
        onTapDown: (_) {
          HapticFeedback.mediumImpact();
          pending[id] = Pc.down(keyOf(id));
        },
        // Espera a que "down" llegue antes de soltar, para no dejar la tecla pegada.
        onTapUp: (_) => pending.remove(id)?.then((_) => Pc.up(keyOf(id))),
        onTapCancel: () => pending.remove(id)?.then((_) => Pc.up(keyOf(id))),
        child: Container(
          decoration: BoxDecoration(
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFF0F2A4A)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: _accent, size: 30),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center),
            Text(tr('(mantén pulsado)', '(hold)'), style: TextStyle(fontSize: 10, color: Colors.white54)),
          ]),
        ),
      );

  Widget weapons() => Row(children: [
        Expanded(child: btn('senuelo', tr('Señuelo', 'Decoy'), Icons.flare)),
        const SizedBox(width: 8),
        Expanded(child: btn('chaff', 'Chaff', Icons.grain)),
      ]);

  // El juego no informa la distribución real, así que solo se envían las teclas.
  Widget energy() => Column(children: [
        for (final e in [
          ['e0+', tr('Motores +', 'Engines +'), Icons.rocket],
          ['e1+', tr('Escudos +', 'Shields +'), Icons.shield],
          ['e2+', tr('Armas +', 'Weapons +'), Icons.gps_fixed],
          ['ereset', tr('Reiniciar', 'Reset'), Icons.restart_alt],
        ])
          Expanded(
              child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: btn(e[0] as String, e[1] as String, e[2] as IconData,
                          wide: true)))),
      ]);

  Widget others() => Column(children: [
        for (final o in [
          ['vtol', tr('Modo VTOL', 'VTOL mode'), Icons.flight_takeoff],
          ['escaneo', tr('Modo escaneo', 'Scan mode'), Icons.radar],
          ['aterrizaje', tr('Solicitar aterrizaje', 'Request landing'), Icons.flight_land],
        ])
          Expanded(
              child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: btn(o[0] as String, o[1] as String, o[2] as IconData,
                          wide: true)))),
      ]);

  Widget net() => ValueListenableBuilder<int?>(
        valueListenable: latency,
        builder: (_, ms, __) {
          final c = ms == null ? Colors.redAccent : Colors.greenAccent;
          return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(ms == null ? Icons.signal_wifi_off : Icons.signal_cellular_alt,
                size: 22, color: c),
            const SizedBox(width: 8),
            Text(ms == null ? tr('Sin conexión', 'No connection') : tr('Conexión estable · $ms ms', 'Stable connection · $ms ms'),
                style: TextStyle(color: c)),
          ]);
        },
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          Expanded(flex: 9, child: Panel(tr('Sistemas principales', 'Main systems'), systems())),
          const SizedBox(width: 8),
          Expanded(
            flex: 10,
            child: Column(children: [
              Expanded(
                flex: 5,
                child: Row(children: [
                  Expanded(flex: 5, child: Panel(tr('Armas', 'Weapons'), weapons())),
                  const SizedBox(width: 8),
                  Expanded(flex: 4, child: Panel(tr('Objetivo', 'Target'), targets())),
                ]),
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 6,
                child: Row(children: [
                  Expanded(child: Panel(tr('Energía', 'Power'), energy())),
                  const SizedBox(width: 8),
                  Expanded(child: Panel(tr('Otros', 'Other'), others())),
                ]),
              ),
              const SizedBox(height: 8),
              SizedBox(height: 84, child: Panel(tr('Red', 'Network'), net())),
            ]),
          ),
        ]),
      );
}

// ---------- Notas / checklist ----------
class NotesTab extends StatefulWidget {
  const NotesTab({super.key});
  @override
  State<NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<NotesTab> {
  late List<Map> tasks = (jsonDecode(prefs.getString('tasks') ?? '[]') as List)
      .map((e) => Map.from(e))
      .toList();
  final c = TextEditingController();

  void save() => prefs.setString('tasks', jsonEncode(tasks));

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: c,
            decoration: InputDecoration(
                labelText: tr('Nueva nota / paso de misión', 'New note / mission step'), suffixIcon: Icon(Icons.add)),
            onSubmitted: (v) {
              if (v.trim().isEmpty) return;
              setState(() => tasks.add({'t': v.trim(), 'd': false}));
              c.clear();
              save();
            },
          ),
        ),
        Expanded(
          child: ListView(children: [
            for (final t in tasks)
              CheckboxListTile(
                value: t['d'],
                title: Text(t['t'],
                    style: TextStyle(
                        decoration: t['d'] ? TextDecoration.lineThrough : null)),
                secondary: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      setState(() => tasks.remove(t));
                      save();
                    }),
                onChanged: (v) {
                  setState(() => t['d'] = v);
                  save();
                },
              ),
          ]),
        ),
      ]);
}

