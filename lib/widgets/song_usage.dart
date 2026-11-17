// Song usage: which songs were up on the projector and how often, for a
// period, with their CCLI numbers: what a church reports to CCLI. Kept on
// this device only; nothing is sent anywhere.

import 'package:flutter/material.dart';

import '../browser.dart';
import '../state.dart';
import '../eink.dart';

/// The "Useful for reporting" badge.
class ReportingBadge extends StatelessWidget {
  const ReportingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(inkR(999)),
      ),
      child: Text(
        'Useful for reporting',
        style: TextStyle(fontSize: 11, color: scheme.onTertiaryContainer),
      ),
    );
  }
}

Future<void> showSongUsage(BuildContext context, PresenterModel model) async {
  await model.loadUsage();
  if (!context.mounted) return;
  await showAppDialog<void>(
    context: context,
    builder: (_) => _UsageDialog(model: model),
  );
}

enum _Period {
  month('Last 30 days', 30),
  quarter('Last 3 months', 91),
  half('Last 6 months', 182),
  year('Last 12 months', 365),
  all('Everything', 0);

  final String label;
  final int days;
  const _Period(this.label, this.days);
}

class _Row {
  final String title, artist, ccli;
  final List<DateTime> dates;
  _Row(this.title, this.artist, this.ccli, this.dates);
}

class _UsageDialog extends StatefulWidget {
  final PresenterModel model;
  const _UsageDialog({required this.model});

  @override
  State<_UsageDialog> createState() => _UsageDialogState();
}

class _UsageDialogState extends State<_UsageDialog> {
  _Period _period = _Period.quarter;

  List<SongUse> get _uses {
    final from = _period.days == 0
        ? null
        : DateTime.now().subtract(Duration(days: _period.days));
    return [
      for (final u in widget.model.usage)
        if (from == null || u.at.isAfter(from)) u,
    ];
  }

  List<_Row> get _rows {
    final bySong = <String, _Row>{};
    for (final u in _uses) {
      bySong
          .putIfAbsent(u.songId, () => _Row(u.title, u.artist, u.ccli, []))
          .dates
          .add(u.at);
    }
    return bySong.values.toList()..sort((a, b) {
      final c = b.dates.length.compareTo(a.dates.length);
      return c != 0
          ? c
          : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  }

  String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _csv() {
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('Title,Artist,CCLI Song #,Times used,Dates\n');
    for (final r in _rows) {
      b.writeln(
        [
          q(r.title),
          q(r.artist),
          q(r.ccli),
          '${r.dates.length}',
          q(r.dates.map(_day).join('; ')),
        ].join(','),
      );
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _rows;
    final total = _uses.length;
    final noCcli = rows.where((r) => r.ccli.isEmpty).length;
    return AlertDialog(
      title: const Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [Text('Song usage'), ReportingBadge()],
      ),
      content: SizedBox(
        width: 620,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Text(
              'Songs whose words went up on the projector, counted once per '
              'service. Kept on this device only.',
              style: theme.textTheme.bodySmall,
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in _Period.values)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: p == _period,
                    onSelected: (_) => setState(() => _period = p),
                  ),
              ],
            ),
            Text(
              '$total use${total == 1 ? '' : 's'} of ${rows.length} song${rows.length == 1 ? '' : 's'}'
              '${noCcli > 0 ? ' · $noCcli without a CCLI number' : ''}',
              style: theme.textTheme.labelMedium,
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Text(
                        'Nothing yet. Songs are counted when their words are '
                        'projected.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        return ListTile(
                          dense: true,
                          title: Text(r.title),
                          subtitle: Text(
                            [
                              if (r.artist.isNotEmpty) r.artist,
                              r.ccli.isEmpty ? 'No CCLI #' : 'CCLI # ${r.ccli}',
                              'last ${_day(r.dates.last)}',
                            ].join(' · '),
                          ),
                          trailing: Text(
                            '×${r.dates.length}',
                            style: theme.textTheme.titleMedium,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.model.usage.isEmpty
              ? null
              : () async {
                  final ok = await showAppDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Clear song usage?'),
                      content: const Text('This forgets every recorded use.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await widget.model.clearUsage();
                    if (mounted) setState(() {});
                  }
                },
          child: const Text('Clear…'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.table_view_outlined, size: 18),
          label: const Text('Export CSV'),
          onPressed: rows.isEmpty
              ? null
              : () => downloadTextFile(
                  'song usage ${_day(DateTime.now())}.csv',
                  _csv(),
                  mime: 'text/csv',
                ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
