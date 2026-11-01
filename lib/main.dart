import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'questions.dart';

const String kRewardedAdUnit = 'ca-app-pub-3940256099942544/5224354917';
const int kAdReward = 5;
const int kMaxAdsPerDay = 10;
const int kAdCooldownSec = 60;
const int kQuizCoin = 2;
const int kMaxQuizCoinsPerDay = 100;
const int kCoinsPerRupee = 100;
const int kMinWithdrawCoins = 5000;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (d) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error: ${d.exception}'),
          ),
        ),
      );
  final prefs = await SharedPreferences.getInstance();
  runApp(MyApp(store: Store(prefs)));
  try {
    MobileAds.instance.initialize();
  } catch (_) {}
}

String _fmt(DateTime d) => '${d.year}-${d.month}-${d.day}';

class Store extends ChangeNotifier {
  Store(this.p) {
    _rollDay();
  }
  final SharedPreferences p;

  String get _today => _fmt(DateTime.now());

  void _rollDay() {
    if (p.getString('day') != _today) {
      p.setString('day', _today);
      p.setInt('adsToday', 0);
      p.setInt('quizToday', 0);
    }
  }

  int get coins => p.getInt('coins') ?? 0;
  int get adsToday {
    _rollDay();
    return p.getInt('adsToday') ?? 0;
  }

  int get quizToday {
    _rollDay();
    return p.getInt('quizToday') ?? 0;
  }

  int get streak => p.getInt('streak') ?? 0;
  bool get checkedInToday => p.getString('lastCheckin') == _today;
  int get cooldownLeft {
    final last = p.getInt('lastAdMs') ?? 0;
    final passed = (DateTime.now().millisecondsSinceEpoch - last) ~/ 1000;
    final left = kAdCooldownSec - passed;
    return left > 0 ? left : 0;
  }

  List<String> get history => p.getStringList('history') ?? [];
  List<String> get withdrawRequests => p.getStringList('withdraws') ?? [];

  void _add(int n, String why) {
    p.setInt('coins', coins + n);
    final h = history;
    h.insert(0, '+$n coins  -  $why  ($_today)');
    p.setStringList('history', h.take(50).toList());
    notifyListeners();
  }

  bool addQuizCoins() {
    if (quizToday + kQuizCoin > kMaxQuizCoinsPerDay) return false;
    p.setInt('quizToday', quizToday + kQuizCoin);
    _add(kQuizCoin, 'Quiz');
    return true;
  }

  void adWatched() {
    p.setInt('adsToday', adsToday + 1);
    p.setInt('lastAdMs', DateTime.now().millisecondsSinceEpoch);
    _add(kAdReward, 'Ad reward');
  }

  int? checkIn() {
    if (checkedInToday) return null;
    final yesterday = _fmt(DateTime.now().subtract(const Duration(days: 1)));
    final newStreak = p.getString('lastCheckin') == yesterday ? streak + 1 : 1;
    p.setInt('streak', newStreak);
    p.setString('lastCheckin', _today);
    final bonus = 5 + (newStreak > 7 ? 7 : newStreak) * 2;
    _add(bonus, 'Daily check-in (streak $newStreak)');
    return bonus;
  }

  bool requestWithdraw(String upi) {
    if (coins < kMinWithdrawCoins || upi.trim().isEmpty) return false;
    final amount = kMinWithdrawCoins;
    p.setInt('coins', coins - amount);
    final w = withdrawRequests;
    w.insert(0, '${amount ~/ kCoinsPerRupee} Rs -> ${upi.trim()}  ($_today)  PENDING');
    p.setStringList('withdraws', w);
    final h = history;
    h.insert(0, '-$amount coins  -  Withdraw request ($_today)');
    p.setStringList('history', h.take(50).toList());
    notifyListeners();
    return true;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GK Coins',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: Home(store: store),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key, required this.store});
  final Store store;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('GK Coins'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.monetization_on, color: Colors.amber),
                  label: Text('${s.coins}'),
                ),
              ),
            ),
          ],
        ),
        body: IndexedStack(index: _i, children: [
          QuizPage(store: s),
          EarnPage(store: s),
          WalletPage(store: s),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _i,
          onDestinationSelected: (v) => setState(() => _i = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.quiz), label: 'Quiz'),
            NavigationDestination(icon: Icon(Icons.card_giftcard), label: 'Earn'),
            NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
          ],
        ),
      ),
    );
  }
}

class QuizPage extends StatefulWidget {
  const QuizPage({super.key, required this.store});
  final Store store;
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late List<Q> _round;
  int _idx = 0;
  int _score = 0;
  int? _picked;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  void _newRound() {
    final l = List<Q>.from(allQuestions)..shuffle();
    _round = l.take(5).toList();
    _idx = 0;
    _score = 0;
    _picked = null;
  }

  void _pick(int i) {
    if (_picked != null) return;
    setState(() => _picked = i);
    if (i == _round[_idx].a) {
      _score++;
      final ok = widget.store.addQuizCoins();
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aaj ki quiz coin limit poori ho gayi. Kal phir aao!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_idx >= _round.length) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.emoji_events, size: 80, color: Colors.amber),
            const SizedBox(height: 12),
            Text('Score: $_score / ${_round.length}',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => setState(_newRound),
              child: const Text('Naya Quiz Khelo'),
            ),
          ]),
        ),
      );
    }
    final q = _round[_idx];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Sawal ${_idx + 1}/${_round.length}  -  Sahi jawab: +$kQuizCoin coins'),
      const SizedBox(height: 12),
      Text(q.q, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      for (int i = 0; i < q.o.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: _picked == null
                  ? null
                  : i == q.a
                      ? Colors.green.shade200
                      : (i == _picked ? Colors.red.shade200 : null),
            ),
            onPressed: () => _pick(i),
            child: Text(q.o[i]),
          ),
        ),
      if (_picked != null)
        FilledButton(
          onPressed: () => setState(() {
            _idx++;
            _picked = null;
          }),
          child: Text(_idx == _round.length - 1 ? 'Result dekho' : 'Agla sawal'),
        ),
    ]);
  }
}

class EarnPage extends StatefulWidget {
  const EarnPage({super.key, required this.store});
  final Store store;
  @override
  State<EarnPage> createState() => _EarnPageState();
}

class _EarnPageState extends State<EarnPage> {
  RewardedAd? _ad;
  bool _loading = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  void _load() {
    if (_loading || _ad != null) return;
    _loading = true;
    RewardedAd.load(
      adUnitId: kRewardedAdUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
          if (mounted) setState(() {});
        },
        onAdFailedToLoad: (e) {
          _ad = null;
          _loading = false;
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _msg(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  void _showAd() {
    final s = widget.store;
    if (s.adsToday >= kMaxAdsPerDay) {
      _msg('Aaj ki ad limit poori ho gayi. Kal phir aao!');
      return;
    }
    if (s.cooldownLeft > 0) {
      _msg('${s.cooldownLeft} second ruko, phir agla ad.');
      return;
    }
    final ad = _ad;
    if (ad == null) {
      _msg('Ad load ho raha hai, thodi der baad try karo.');
      _load();
      return;
    }
    _ad = null;
    bool earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (earned) {
          s.adWatched();
          _msg('+$kAdReward coins mil gaye!');
        }
        _load();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _load();
      },
    );
    ad.show(onUserEarnedReward: (a, r) => earned = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.local_fire_department, color: Colors.orange),
          title: Text('Daily check-in  (streak: ${s.streak} din)'),
          subtitle: const Text('Roz aao, bonus coins badhte jaayenge'),
          trailing: FilledButton(
            onPressed: s.checkedInToday
                ? null
                : () {
                    final b = s.checkIn();
                    if (b != null) _msg('+$b coins bonus!');
                  },
            child: Text(s.checkedInToday ? 'Ho gaya' : 'Claim'),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          leading: const Icon(Icons.play_circle_fill, color: Colors.indigo),
          title: Text('Ad dekho, $kAdReward coins pao'),
          subtitle: Text('Aaj: ${s.adsToday}/$kMaxAdsPerDay ads'
              '${s.cooldownLeft > 0 ? '  -  ${s.cooldownLeft}s wait' : ''}'),
          trailing: FilledButton(
            onPressed: _showAd,
            child: Text(_ad == null ? 'Loading' : 'Dekho'),
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Card(
        child: ListTile(
          leading: Icon(Icons.group_add),
          title: Text('Refer & Earn'),
          subtitle: Text('Jaldi aa raha hai (server/Firebase ke baad)'),
        ),
      ),
    ]);
  }
}

class WalletPage extends StatefulWidget {
  const WalletPage({super.key, required this.store});
  final Store store;
  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final _upi = TextEditingController();

  @override
  void dispose() {
    _upi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final rupees = (s.coins / kCoinsPerRupee).toStringAsFixed(2);
    final canWithdraw = s.coins >= kMinWithdrawCoins;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text('${s.coins} coins', style: Theme.of(context).textTheme.headlineMedium),
            Text('= Rs $rupees  ($kCoinsPerRupee coins = Rs 1)'),
            const SizedBox(height: 12),
            LinearProgressIndicator(
                value: (s.coins / kMinWithdrawCoins).clamp(0.0, 1.0).toDouble()),
            const SizedBox(height: 6),
            Text('Withdraw ke liye minimum $kMinWithdrawCoins coins (Rs ${kMinWithdrawCoins ~/ kCoinsPerRupee})'),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _upi,
        decoration: const InputDecoration(
          labelText: 'Aapki UPI ID',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: canWithdraw
            ? () {
                final ok = s.requestWithdraw(_upi.text);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok
                        ? 'Withdraw request save ho gayi (manual approval).'
                        : 'UPI ID daalo.')));
              }
            : null,
        child: const Text('Withdraw Request'),
      ),
      if (s.withdrawRequests.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Withdraw requests', style: Theme.of(context).textTheme.titleMedium),
        for (final w in s.withdrawRequests) ListTile(dense: true, title: Text(w)),
      ],
      const SizedBox(height: 16),
      Text('History', style: Theme.of(context).textTheme.titleMedium),
      for (final h in s.history) ListTile(dense: true, title: Text(h)),
    ]);
  }
}
