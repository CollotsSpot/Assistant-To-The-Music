import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/debug_logger.dart';

/// A collapsible debug console for viewing application logs
class DebugConsole extends StatelessWidget {
  final VoidCallback onClear;
  final int maxLogs;

  const DebugConsole({
    super.key,
    required this.onClear,
    this.maxLogs = 50,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      constraints: const BoxConstraints(maxHeight: 200),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          const Divider(color: Colors.green, height: 8),
          Expanded(
            child: _buildLogsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.terminal, color: Colors.green, size: 16),
        const SizedBox(width: 8),
        const Text(
          'Debug Console',
          style: TextStyle(
            color: Colors.green,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () => _copyLogs(context),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(50, 20),
          ),
          icon: const Icon(Icons.copy, size: 10, color: Colors.green),
          label: const Text(
            'Copy',
            style: TextStyle(fontSize: 10, color: Colors.green),
          ),
        ),
        TextButton(
          onPressed: () {
            DebugLogger().clear();
            onClear();
          },
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(40, 20),
          ),
          child: const Text(
            'Clear',
            style: TextStyle(fontSize: 10, color: Colors.green),
          ),
        ),
      ],
    );
  }

  void _copyLogs(BuildContext context) {
    final logs = DebugLogger().getAllLogs();
    if (logs.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: logs));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logs copied to clipboard'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No logs to copy'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildLogsList() {
    return SingleChildScrollView(
      reverse: true,
      child: Builder(
        builder: (context) {
          final allLogs = DebugLogger().logs;
          final recentLogs = allLogs.length > maxLogs
              ? allLogs.sublist(allLogs.length - maxLogs)
              : allLogs;

          if (recentLogs.isEmpty) {
            return const Text(
              'No debug logs yet. Try detecting auth.',
              style: TextStyle(
                color: Colors.green,
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: recentLogs
                .map((log) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        log,
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}

/// A toggle button for showing/hiding the debug console
class DebugToggleButton extends StatelessWidget {
  final bool isVisible;
  final VoidCallback onToggle;

  const DebugToggleButton({
    super.key,
    required this.isVisible,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onToggle,
      icon: Icon(
        isVisible ? Icons.bug_report : Icons.bug_report_outlined,
        size: 16,
      ),
      label: Text(
        isVisible ? 'Hide Debug' : 'Show Debug',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
