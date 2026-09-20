import 'package:flutter/material.dart';
import '../../domain/farm_domain.dart';
import '../../core/widgets/components.dart';
import '../../app/theme/farm_theme.dart';
import '../workspace/workspace_controller.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key, required this.state});
  final WorkspaceController state;
  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final question = TextEditingController();
  final replies = <(String, String, String)>[];
  bool busy = false;
  @override
  void dispose() {
    question.dispose();
    super.dispose();
  }

  Future<void> ask([String? prompt]) async {
    final text = (prompt ?? question.text).trim();
    if (text.isEmpty || text.length > 2000 || busy) return;
    final state = widget.state;
    final snapshot = state.farm!;
    final optimization = state.optimization;
    final risk = state.risk?.alternative ?? state.risk?.current;
    setState(() => busy = true);
    String response;
    var source = 'Local explanation · calculated farm context';
    try {
      final local = LocalExplanationEngine().explain(
        text,
        snapshot,
        optimization: optimization,
        selected: state.selected,
        risk: risk,
      );
      final cloud = state.cloud;
      response = local;
      if (!state.sampleMode &&
          cloud != null &&
          cloud.features.cloudAssistantEnabled &&
          cloud.privacy.current.cloudAssistantConsent) {
        final f = FinancialEngine().evaluate(snapshot, snapshot.currentPlan);
        try {
          response = await cloud.explanations.explain(
            farmId: snapshot.id,
            question: text,
            context: {
              'revenue': f.revenue,
              'operatingExpense': f.operatingExpense,
              'operatingIncome': f.operatingIncome,
              'debtService': f.debtService,
              'cashAfterDebtService': f.cashAfterDebt,
              'waterUsage': f.waterUsage,
              'nitrogenUsage': f.nitrogenUsage,
              'acreage': snapshot.acreage,
              if (risk != null) 'mean': risk.mean,
              if (risk != null)
                'probabilityNegativeCashFlow': risk.negativeCashProbability,
            },
          );
          source = 'Cloud explanation · supplied calculation context';
        } catch (_) {
          source = 'Local explanation · cloud service unavailable';
        }
      }
    } catch (failure) {
      response = failure.toString();
      source = 'Unable to explain';
    }
    if (mounted) {
      setState(() {
        replies.add((text, response, source));
        question.clear();
        busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading(
        'Understand the reasoning.',
        'Explanations grounded in your farm’s calculated results.',
      ),
      const Notice(
        'The local assistant explains finances, allocation changes, constraints, risk, and modeled scenarios. It does not calculate an optimal plan or verify farm inputs.',
      ),
      const SizedBox(height: 24),
      SectionCard(
        title: 'Ask about your farm',
        subtitle: 'No cloud service is needed for local explanations.',
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  [
                        'Explain my farm finances',
                        'Why did the crop allocation change?',
                        'Which constraints are limiting the plan?',
                        'Explain my risk results',
                      ]
                      .map(
                        (text) => ActionChip(
                          label: Text(text),
                          onPressed: busy ? null : () => ask(text),
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: question,
              maxLength: 2000,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Your question',
                hintText: 'What is driving my cash after debt?',
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: busy ? null : ask,
                icon: const Icon(Icons.arrow_upward, size: 18),
                label: const Text('Explain'),
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
      for (final reply in replies.reversed) ...[
        const SizedBox(height: 20),
        SectionCard(
          title: reply.$1,
          subtitle: reply.$3,
          child: SelectableText(
            reply.$2,
            style: const TextStyle(color: FarmTheme.ink, height: 1.7),
          ),
        ),
      ],
    ],
  );
}
