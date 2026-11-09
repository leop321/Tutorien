import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SemesterApp());
}

// ============================================================
//  APP ROOT
// ============================================================
class SemesterApp extends StatelessWidget {
  const SemesterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tutorien Planer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1A73E8),
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1A73E8),
        brightness: Brightness.dark,
      ),
      home: const AppShell(),
    );
  }
}

// ============================================================
//  MODELS
// ============================================================
class Tutorial {
  final String id;
  final String category;
  final String name;
  bool done;
  Tutorial({required this.id, required this.category, required this.name, this.done = false});
  Map<String, dynamic> toJson() => {'id': id, 'category': category, 'name': name, 'done': done};
  factory Tutorial.fromJson(Map<String, dynamic> j) =>
      Tutorial(id: j['id'], category: j['category'], name: j['name'], done: j['done'] ?? false);
}

class Slot {
  final int weekday;        // 1=Mo … 7=So
  final int startH, startM, endH, endM;
  final String label;
  final String? category;   // null = fixed
  final bool isFixed;
  final Color color;

  const Slot({
    required this.weekday,
    required this.startH, required this.startM,
    required this.endH,   required this.endM,
    required this.label,
    this.category,
    this.isFixed = false,
    required this.color,
  });

  int get startMin => startH * 60 + startM;
  int get endMin   => endH   * 60 + endM;
  int get durMin   => endMin - startMin;
  String get startStr => '${startH.toString().padLeft(2,'0')}:${startM.toString().padLeft(2,'0')}';
  String get endStr   => '${endH.toString().padLeft(2,'0')}:${endM.toString().padLeft(2,'0')}';

  bool isNow(DateTime t) => t.weekday == weekday && t.hour*60+t.minute >= startMin && t.hour*60+t.minute < endMin;
  bool isUpcoming(DateTime t) => t.weekday == weekday && t.hour*60+t.minute < startMin;
}

// ============================================================
//  SCHEDULE DATA
// ============================================================
const Color cGym   = Color(0xFFF4511E);
const Color cFood  = Color(0xFFFB8C00);
const Color cWarm  = Color(0xFFD81B60);
const Color cFEM   = Color(0xFF00897B);
const Color cKSat  = Color(0xFF5E35B1);
const Color cSys   = Color(0xFF43A047);
const Color cRaum  = Color(0xFF1E88E5);
const Color cStrom = Color(0xFF3949AB);
const Color cLFA   = Color(0xFF8E24AA);

const List<Slot> kSchedule = [
  // Dienstag
  Slot(weekday:2, startH:8,  startM:30, endH:10, endM:0,  label:'Gym',          isFixed:true, color:cGym),
  Slot(weekday:2, startH:11, startM:30, endH:12, endM:30, label:'Essen',         isFixed:true, color:cFood),
  Slot(weekday:2, startH:13, startM:0,  endH:14, endM:30, label:'Wärme',         category:'Wärme',     color:cWarm),
  Slot(weekday:2, startH:15, startM:0,  endH:16, endM:30, label:'FEM / Statik',  category:'FEM/Statik',color:cFEM),
  Slot(weekday:2, startH:17, startM:0,  endH:18, endM:30, label:'KSat',          isFixed:true, color:cKSat),
  // Mittwoch
  Slot(weekday:3, startH:9,  startM:0,  endH:10, endM:30, label:'Systeme 1',     category:'Systeme 1', color:cSys),
  Slot(weekday:3, startH:11, startM:0,  endH:12, endM:30, label:'Raumfahrt',     category:'Raumfahrt', color:cRaum),
  Slot(weekday:3, startH:13, startM:30, endH:15, endM:0,  label:'Raumfahrt',     category:'Raumfahrt', color:cRaum),
  Slot(weekday:3, startH:16, startM:30, endH:18, endM:0,  label:'(Gym) opt.',    isFixed:true, color:cGym),
  // Donnerstag
  Slot(weekday:4, startH:9,  startM:0,  endH:10, endM:30, label:'Strömung',      category:'Strömung',  color:cStrom),
  Slot(weekday:4, startH:12, startM:0,  endH:13, endM:0,  label:'Essen Uni',     isFixed:true, color:cFood),
  Slot(weekday:4, startH:13, startM:30, endH:15, endM:0,  label:'Systeme 1',     category:'Systeme 1', color:cSys),
  Slot(weekday:4, startH:16, startM:30, endH:18, endM:0,  label:'Gym',           isFixed:true, color:cGym),
  // Freitag
  Slot(weekday:5, startH:10, startM:0,  endH:11, endM:30, label:'Raumfahrt',     category:'Raumfahrt', color:cRaum),
  Slot(weekday:5, startH:13, startM:30, endH:15, endM:0,  label:'LFA Vidi',      category:'LFA',       color:cLFA),
];

// ============================================================
//  APP SHELL (Nav)
// ============================================================
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  List<Tutorial> _tutorials = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('tutorials_v2');
    if (saved != null) {
      final List<dynamic> d = jsonDecode(saved);
      setState(() { _tutorials = d.map((e) => Tutorial.fromJson(e)).toList(); _loading = false; });
    } else {
      final list = <Tutorial>[];
      void add(String cat, String pfx, int n, [List<int> done = const []]) {
        for (int i = 1; i <= n; i++) {
          list.add(Tutorial(id:'$cat-$pfx-$i', category:cat, name:'$pfx #$i', done:done.contains(i)));
        }
      }
      add('Strömung',   'Strömung',  12);
      add('LFA',        'Vidi',      10, [1,2]);
      add('LFA',        'Struktur',   6);
      add('Wärme',      'Strahlung',  6);
      add('Wärme',      'Übertragung',6);
      add('Raumfahrt',  'Raumfahrt', 12);
      add('FEM/Statik', 'FEM',        6);
      add('Systeme 1',  'Sys 1',      6, [1,2]);
      add('Regelung 1', 'Regelung',   6);
      for (var n in [24,23,22]) { list.add(Tutorial(id:'Thermo-$n', category:'Thermo', name:'Thermo #$n')); }
      for (int i=1;i<=3;i++) { list.add(Tutorial(id:'Statik-WgV-$i', category:'FEM/Statik', name:'WgV #$i')); }
      for (int i=1;i<=2;i++) { list.add(Tutorial(id:'Statik-FEM-$i', category:'FEM/Statik', name:'Statik FEM #$i')); }
      for (int i=1;i<=3;i++) { list.add(Tutorial(id:'Statik-Theo-$i',category:'FEM/Statik', name:'Theorie #$i')); }
      setState(() { _tutorials = list; _loading = false; });
      _save();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tutorials_v2', jsonEncode(_tutorials.map((t) => t.toJson()).toList()));
  }

  void _toggle(String id, bool? v) {
    setState(() { final i = _tutorials.indexWhere((t) => t.id == id); if (i!=-1) _tutorials[i].done = v??false; });
    _save();
  }

  Tutorial? _next(String? cat) {
    if (cat == null) return null;
    try { return _tutorials.firstWhere((t) => t.category == cat && !t.done); } catch(_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      body: _tab == 0
          ? HomeScreen(tutorials: _tutorials, getNext: _next, onToggle: _toggle)
          : SubjectScreen(tutorials: _tutorials, onToggle: _toggle),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_view_week_outlined), selectedIcon: Icon(Icons.calendar_view_week), label: 'Kalender'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Fächer'),
        ],
      ),
    );
  }
}

// ============================================================
//  HOME SCREEN  (Google-Week-View + Timer)
// ============================================================
class HomeScreen extends StatefulWidget {
  final List<Tutorial> tutorials;
  final Tutorial? Function(String?) getNext;
  final Function(String, bool?) onToggle;
  const HomeScreen({super.key, required this.tutorials, required this.getNext, required this.onToggle});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _now = DateTime.now();
  Timer? _clock;

  // Fokus-Timer
  int _secs = 90 * 60;
  Timer? _ftimer;
  bool _fRunning = false;
  Tutorial? _task;

  // Week
  late DateTime _weekStart; // Monday of displayed week

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(DateTime.now());
    _clock = Timer.periodic(const Duration(seconds:1), (_) { if(mounted) setState(() => _now = DateTime.now()); });
  }
  @override void dispose() { _clock?.cancel(); _ftimer?.cancel(); super.dispose(); }

  DateTime _mondayOf(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

  void _startF() { _ftimer?.cancel(); setState(()=>_fRunning=true); _ftimer=Timer.periodic(const Duration(seconds:1),(_){if(_secs>0){setState(()=>_secs--);}else{_stopF();}}); }
  void _stopF()  { _ftimer?.cancel(); setState(()=>_fRunning=false); }
  void _resetF() { _ftimer?.cancel(); setState((){_fRunning=false;_secs=90*60;}); }

  String _fmt(int s) { final h=s~/3600; final m=((s%3600)~/60).toString().padLeft(2,'0'); final sec=(s%60).toString().padLeft(2,'0'); return h>0?'$h:$m:$sec':'$m:$sec'; }

  // Detect what's active right now
  Map<String,dynamic> _status() {
    for (final s in kSchedule) {
      if (s.isNow(_now)) {
        final t = s.isFixed ? null : widget.getNext(s.category);
        return {'now':true,'slot':s,'tut':t,'text':'Gerade aktiv – bis ${s.endStr}'};
      }
    }
    final today = kSchedule.where((s)=>s.isUpcoming(_now)).toList();
    today.sort((a,b)=>a.startMin.compareTo(b.startMin));
    if (today.isNotEmpty) {
      final s = today.first;
      final t = s.isFixed ? null : widget.getNext(s.category);
      return {'now':false,'slot':s,'tut':t,'text':'Als Nächstes um ${s.startStr} Uhr'};
    }
    return {'now':false,'slot':null,'tut':null,'text':'Kein Termin mehr heute'};
  }

  // ──── WEEK VIEW constants ────
  static const double kHourH  = 56.0;   // height per hour
  static const double kTimeW  = 40.0;   // left time column width
  static const int    kStartH = 7;      // 07:00
  static const int    kEndH   = 20;     // 20:00
  static const int    kHours  = kEndH - kStartH; // 13 hours shown

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total  = widget.tutorials.length;
    final done   = widget.tutorials.where((t)=>t.done).length;
    final remain = total - done;
    const goalAvg = 74.0 / 11;
    final status = _status();
    final activeTask = _task ?? (status['tut'] as Tutorial?);

    // Build week days list (Mo=1 … So=7)
    final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));

    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        title: Row(children: [
          Text(
            '${_now.hour.toString().padLeft(2,'0')}:${_now.minute.toString().padLeft(2,'0')}',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: cs.primary),
          ),
          const SizedBox(width: 8),
          Text(_dateStr(_now), style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha:0.6))),
        ]),
        actions: [
          // Week navigator
          IconButton(icon: const Icon(Icons.chevron_left),  onPressed: () => setState(()=>_weekStart=_weekStart.subtract(const Duration(days:7)))),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(()=>_weekStart=_weekStart.add(const Duration(days:7)))),
          const SizedBox(width:4),
        ],
      ),
      body: Column(children: [
        // ── Status banner ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12,6,12,4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal:14, vertical:10),
            decoration: BoxDecoration(
              color: (status['now'] as bool) ? cs.primaryContainer : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(
                (status['now'] as bool) ? Icons.radio_button_checked : Icons.schedule,
                size: 18,
                color: cs.primary,
              ),
              const SizedBox(width:10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(status['text'], style: TextStyle(fontSize:11, color: cs.primary, fontWeight:FontWeight.w600)),
                Text(
                  status['slot'] == null
                      ? 'Kein Termin'
                      : status['slot'].isFixed
                          ? (status['slot'] as Slot).label
                          : '${(status['slot'] as Slot).label}  ·  ${(status['tut'] as Tutorial?)?.name ?? "Alle erledigt 🎉"}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize:14),
                  overflow: TextOverflow.ellipsis,
                ),
              ])),
              if (status['tut'] != null)
                TextButton(
                  onPressed: () => setState(() { _task = status['tut']; _resetF(); }),
                  child: const Text('Start'),
                ),
            ]),
          ),
        ),

        // ── KPI row ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal:12, vertical:4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _kpi('Erledigt',    '$done / $total'),
            _kpi('Offen',       '$remain'),
            _kpi('Goal',        '${goalAvg.toStringAsFixed(1)}/W'),
            _kpi('Ø erreicht',  '${done.toDouble().toStringAsFixed(1)}/W'),
            Flexible(child: LinearProgressIndicator(value: done/total, minHeight:6, borderRadius:BorderRadius.circular(4))),
          ]),
        ),
        const SizedBox(height:4),

        // ── Week header (day names + date numbers) ──
        Padding(
          padding: const EdgeInsets.only(left: kTimeW+4, right:0),
          child: Row(children: days.map((d) {
            final isToday = d.day==_now.day && d.month==_now.month && d.year==_now.year;
            return Expanded(child: Column(children: [
              Text(_dayShort(d.weekday), style: TextStyle(fontSize:11, color: isToday ? cs.primary : cs.onSurface.withValues(alpha:0.5), fontWeight: FontWeight.w600)),
              const SizedBox(height:2),
              Container(
                width:28, height:28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isToday ? cs.primary : Colors.transparent,
                ),
                alignment: Alignment.center,
                child: Text('${d.day}', style: TextStyle(fontSize:13, fontWeight:FontWeight.bold, color: isToday ? Colors.white : cs.onSurface)),
              ),
              const SizedBox(height:4),
            ]));
          }).toList()),
        ),
        Divider(height:1, color: cs.outlineVariant),

        // ── WEEK GRID ──
        Expanded(child: _buildWeekGrid(context, days)),

        // ── Bottom timer bar ──
        _buildTimerBar(context, activeTask, cs),
      ]),
    );
  }

  Widget _kpi(String l, String v) => Padding(
    padding: const EdgeInsets.only(right:10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(v, style: const TextStyle(fontWeight:FontWeight.bold, fontSize:13)),
      Text(l, style: TextStyle(fontSize:10, color: Colors.grey.shade600)),
    ]),
  );

  Widget _buildWeekGrid(BuildContext context, List<DateTime> days) {
    final cs = Theme.of(context).colorScheme;
    final totalH = kHours * kHourH;

    return SingleChildScrollView(
      child: SizedBox(
        height: totalH + 16,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Time labels
          SizedBox(
            width: kTimeW,
            child: Stack(children: [
              for (int h = kStartH; h <= kEndH; h++)
                Positioned(
                  top: (h - kStartH) * kHourH - 6,
                  left: 0, right: 4,
                  child: Text('${h.toString().padLeft(2,'0')}:00', textAlign: TextAlign.right,
                    style: TextStyle(fontSize:9, color: cs.onSurface.withValues(alpha:0.4))),
                ),
            ]),
          ),

          // Day columns
          ...days.map((day) {
            final isToday = day.day==_now.day && day.month==_now.month && day.year==_now.year;
            final daySlots = kSchedule.where((s) => s.weekday == day.weekday).toList();

            return Expanded(
              child: LayoutBuilder(builder: (ctx, box) {
                final colW = box.maxWidth;
                return Stack(children: [
                  // Hour lines
                  ...List.generate(kHours+1, (i) => Positioned(
                    top: i*kHourH, left:0, right:0, height:0.5,
                    child: Container(color: cs.outlineVariant.withValues(alpha:0.5)),
                  )),
                  // Today highlight
                  if (isToday)
                    Positioned.fill(child: Container(color: cs.primaryContainer.withValues(alpha:0.15))),
                  // Event blocks
                  ...daySlots.map((slot) {
                    final top  = (slot.startMin - kStartH*60) / 60 * kHourH;
                    final h    = slot.durMin / 60 * kHourH;
                    final tut  = slot.isFixed ? null : widget.getNext(slot.category);
                    final isActive = slot.isNow(_now) && isToday;
                    return Positioned(
                      top: top + 1, left:1, right:1, height: h - 2,
                      child: GestureDetector(
                        onTap: () {
                          if (tut != null) setState(() { _task = tut; _resetF(); });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal:4, vertical:3),
                          decoration: BoxDecoration(
                            color: slot.color.withValues(alpha: isActive ? 0.9 : 0.18),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isActive ? slot.color : slot.color.withValues(alpha:0.4),
                              width: isActive ? 1.5 : 0.8,
                            ),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              slot.label,
                              style: TextStyle(
                                fontSize: colW < 40 ? 7 : 9,
                                fontWeight: FontWeight.bold,
                                color: isActive ? Colors.white : slot.color,
                              ),
                              maxLines:1, overflow: TextOverflow.ellipsis,
                            ),
                            if (h > 35 && tut != null)
                              Text(tut.name, style: TextStyle(fontSize:7, color: isActive ? Colors.white70 : slot.color.withValues(alpha:0.8)), maxLines:1, overflow:TextOverflow.ellipsis),
                          ]),
                        ),
                      ),
                    );
                  }),
                  // Red "now" line
                  if (isToday && _now.hour >= kStartH && _now.hour < kEndH)
                    Positioned(
                      top: (_now.hour*60+_now.minute - kStartH*60) / 60 * kHourH,
                      left:0, right:0,
                      child: Row(children: [
                        Container(width:6, height:6, decoration: const BoxDecoration(color:Colors.red, shape:BoxShape.circle)),
                        Expanded(child: Container(height:1, color: Colors.red)),
                      ]),
                    ),
                ]);
              }),
            );
          }),
        ]),
      ),
    );
  }

  Widget _buildTimerBar(BuildContext context, Tutorial? task, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16,8,16,16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant, width:0.5)),
      ),
      child: SafeArea(top:false, child: Column(mainAxisSize:MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
            Text(task != null ? task.category : 'Kein Task gewählt', style: TextStyle(fontSize:11, color:cs.primary, fontWeight:FontWeight.w600)),
            Text(task != null ? task.name : 'Tippe auf einen Slot im Kalender', style: const TextStyle(fontSize:15, fontWeight:FontWeight.bold), overflow:TextOverflow.ellipsis),
          ])),
          Text(_fmt(_secs), style: const TextStyle(fontSize:22, fontWeight:FontWeight.bold, letterSpacing:1)),
          const SizedBox(width:8),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white, minimumSize: const Size(40,40)),
            icon: Icon(_fRunning ? Icons.pause : Icons.play_arrow, size:20),
            onPressed: _fRunning ? _stopF : _startF,
          ),
          IconButton(icon: const Icon(Icons.refresh, size:18), onPressed: _resetF),
        ]),
        const SizedBox(height:8),
        SizedBox(
          width: double.infinity, height:42,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E8E3E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: task==null ? null : () {
              widget.onToggle(task.id, true);
              _resetF();
              setState(()=>_task=null);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${task.name} erledigt ✓'), duration: const Duration(seconds:2)));
            },
            icon: const Icon(Icons.check, size:18),
            label: const Text('Als erledigt abhaken ✓', style: TextStyle(fontWeight:FontWeight.bold)),
          ),
        ),
      ])),
    );
  }

  String _dateStr(DateTime d) {
    const m = ['','Jan','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez'];
    return '${d.day}. ${m[d.month]} ${d.year}';
  }

  String _dayShort(int wd) => ['','Mo','Di','Mi','Do','Fr','Sa','So'][wd];
}

// ============================================================
//  SUBJECT SCREEN
// ============================================================
class SubjectScreen extends StatelessWidget {
  final List<Tutorial> tutorials;
  final Function(String, bool?) onToggle;
  const SubjectScreen({super.key, required this.tutorials, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final cats = tutorials.map((t) => t.category).toSet().toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Fächer & Tutorien', style: TextStyle(fontWeight:FontWeight.bold))),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: cats.length,
        itemBuilder: (ctx, i) {
          final cat = cats[i];
          final items = tutorials.where((t) => t.category==cat).toList();
          final done = items.where((t) => t.done).length;
          final total = items.length;
          final pct = total>0 ? done/total : 0.0;
          return Card(
            margin: const EdgeInsets.only(bottom:8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ExpansionTile(
              title: Text(cat, style: const TextStyle(fontWeight:FontWeight.bold)),
              subtitle: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
                const SizedBox(height:4),
                Text('$done / $total (${(pct*100).toInt()}%)'),
                const SizedBox(height:4),
                ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct, minHeight:5)),
              ]),
              children: items.map((t) => CheckboxListTile(
                dense: true,
                title: Text(t.name, style: TextStyle(
                  decoration: t.done ? TextDecoration.lineThrough : null,
                  color: t.done ? Colors.grey : null,
                )),
                value: t.done,
                onChanged: (v) => onToggle(t.id, v),
              )).toList(),
            ),
          );
        },
      ),
    );
  }
}
