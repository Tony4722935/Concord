import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:concord/backend/concord_api_client.dart';
import 'package:concord/backend/image_asset_picker.dart';
import 'package:concord/l10n/app_strings.dart';
import 'package:concord/l10n/language_provider.dart';

enum _ServerSettingsSection {
  overview,
  channels,
  danger,
}

class BackendServerSettingsResult {
  const BackendServerSettingsResult({
    required this.didChange,
    required this.wasDeleted,
  });

  final bool didChange;
  final bool wasDeleted;
}

class BackendServerSettingsScreen extends ConsumerStatefulWidget {
  const BackendServerSettingsScreen({
    super.key,
    required this.baseUrl,
    required this.session,
    required this.serverId,
  });

  final String baseUrl;
  final ApiAuthSession session;
  final String serverId;

  @override
  ConsumerState<BackendServerSettingsScreen> createState() =>
      _BackendServerSettingsScreenState();
}

class _BackendServerSettingsScreenState
    extends ConsumerState<BackendServerSettingsScreen> {
  final TextEditingController _nameController = TextEditingController();

  _ServerSettingsSection _selectedSection = _ServerSettingsSection.overview;
  List<ApiChannelSummary> _textChannels = const [];
  List<ApiChannelSummary> _voiceChannels = const [];
  ApiServerSummary? _server;
  bool _loading = true;
  bool _saving = false;
  bool _working = false;
  bool _didChange = false;
  String? _error;

  ConcordApiClient get _client => ConcordApiClient(baseUrl: widget.baseUrl);

  AppStrings _strings() => appStringsFor(ref.read(appLanguageProvider));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _closeScreen() {
    Navigator.of(context).pop(
      BackendServerSettingsResult(
        didChange: _didChange,
        wasDeleted: false,
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final servers =
          await _client.listServers(accessToken: widget.session.accessToken);
      ApiServerSummary? current;
      for (final server in servers) {
        if (server.id == widget.serverId) {
          current = server;
          break;
        }
      }
      if (current == null) {
        if (!mounted) {
          return;
        }
        Navigator.of(context).pop(
          const BackendServerSettingsResult(
            didChange: true,
            wasDeleted: true,
          ),
        );
        return;
      }

      final channels = await _client.listServerChannels(
        accessToken: widget.session.accessToken,
        serverId: widget.serverId,
      );
      channels.sort((left, right) => left.position.compareTo(right.position));
      final textChannels = channels
          .where((channel) => channel.kind == 'text')
          .toList(growable: false);
      final voiceChannels = channels
          .where((channel) => channel.kind == 'voice')
          .toList(growable: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _server = current;
        _nameController.text = current!.name;
        _textChannels = textChannels;
        _voiceChannels = voiceChannels;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _strings().t(
          'failed_update_server_settings',
          fallback: 'Failed to update server settings.',
        );
        _loading = false;
      });
    }
  }

  Future<void> _saveServerName() async {
    final server = _server;
    if (_saving || _working || server == null) {
      return;
    }
    final nextName = _nameController.text.trim();
    if (nextName.isEmpty) {
      setState(() {
        _error = _strings().t(
          'server_name_required',
          fallback: 'Server name is required.',
        );
      });
      return;
    }
    if (nextName == server.name) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _strings()
                .t('no_changes', fallback: 'No additional changes to save.'),
          ),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _client.updateServer(
        accessToken: widget.session.accessToken,
        serverId: server.id,
        name: nextName,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _server = updated;
        _nameController.text = updated.name;
        _saving = false;
        _didChange = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _strings().t(
              'server_settings_updated',
              fallback: 'Server settings updated.',
            ),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = _strings().t(
          'failed_update_server_settings',
          fallback: 'Failed to update server settings.',
        );
      });
    }
  }

  Future<void> _createChannel() async {
    if (_working || _server == null) {
      return;
    }
    final strings = _strings();
    final nameController = TextEditingController();
    String selectedKind = 'text';

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  title: Text(
                      strings.t('create_channel', fallback: 'Create Channel')),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: strings.t('channel_name',
                              fallback: 'Channel Name'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedKind,
                        decoration: InputDecoration(
                          labelText: strings.t('channel_kind',
                              fallback: 'Channel Type'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'text',
                            child: Text(strings.t('channel_kind_text',
                                fallback: 'Text')),
                          ),
                          DropdownMenuItem(
                            value: 'voice',
                            child: Text(strings.t('channel_kind_voice',
                                fallback: 'Voice')),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            selectedKind = value;
                          });
                        },
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(strings.t('cancel', fallback: 'Cancel')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text(strings.t('create', fallback: 'Create')),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;

    final channelName = nameController.text.trim();
    nameController.dispose();
    if (!confirmed) {
      return;
    }
    if (channelName.isEmpty) {
      setState(() {
        _error = strings.t('channel_name', fallback: 'Channel Name');
      });
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _client.createServerChannel(
        accessToken: widget.session.accessToken,
        serverId: widget.serverId,
        name: channelName,
        kind: selectedKind,
      );
      _didChange = true;
      await _load();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.tf(
              'channel_created',
              {'name': channelName},
              fallback: 'Channel #{name} created.',
            ),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _working = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _working = false;
        _error = strings.t(
          'failed_create_channel',
          fallback: 'Failed to create channel.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _deleteChannel(ApiChannelSummary channel) async {
    if (_working || _server == null) {
      return;
    }
    final strings = _strings();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title:
                  Text(strings.t('delete_channel', fallback: 'Delete Channel')),
              content: Text(
                strings.tf(
                  'delete_channel_confirm',
                  {'name': channel.name},
                  fallback: 'Delete channel "{name}"?',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(strings.t('cancel', fallback: 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(strings.t('delete', fallback: 'Delete')),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed) {
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _client.deleteServerChannel(
        accessToken: widget.session.accessToken,
        serverId: widget.serverId,
        channelId: channel.id,
      );
      _didChange = true;
      await _load();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.tf(
              'channel_deleted',
              {'name': channel.name},
              fallback: 'Channel #{name} deleted.',
            ),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _working = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _working = false;
        _error = strings.t(
          'failed_delete_channel',
          fallback: 'Failed to delete channel.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _deleteServer() async {
    if (_working || _saving || _server == null) {
      return;
    }
    final server = _server!;
    final strings = _strings();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title:
                  Text(strings.t('delete_server', fallback: 'Delete Server')),
              content: Text(
                strings.tf(
                  'delete_server_confirm',
                  {'name': server.name},
                  fallback: 'Delete "{name}" permanently?',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(strings.t('cancel', fallback: 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(strings.t('delete', fallback: 'Delete')),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed) {
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _client.deleteServer(
        accessToken: widget.session.accessToken,
        serverId: server.id,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(
        const BackendServerSettingsResult(
          didChange: true,
          wasDeleted: true,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _working = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _working = false;
        _error = strings.t(
          'failed_update_server_settings',
          fallback: 'Failed to update server settings.',
        );
      });
    }
  }

  Future<void> _changeServerIcon() async {
    final server = _server;
    if (_working || _saving || server == null) {
      return;
    }
    final strings = _strings();
    final picked = await pickAndCropSquareImage(
      context: context,
      strings: strings,
      withCircleUi: true,
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final uploaded = await _client.uploadImageDirect(
        accessToken: widget.session.accessToken,
        contentType: picked.contentType,
        fileExtension: picked.fileExtension,
        data: picked.data,
      );
      final updated = await _client.updateServerIcon(
        accessToken: widget.session.accessToken,
        serverId: server.id,
        imageUrl: uploaded.imageUrl,
        imageObjectKey: uploaded.imageObjectKey,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _server = updated;
        _didChange = true;
        _working = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _working = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _working = false;
        _error = strings.t(
          'failed_update_server_icon',
          fallback: 'Failed to update server picture.',
        );
      });
    }
  }

  Future<void> _removeServerIcon() async {
    final server = _server;
    if (_working || _saving || server == null) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final updated = await _client.clearServerIcon(
        accessToken: widget.session.accessToken,
        serverId: server.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _server = updated;
        _didChange = true;
        _working = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _working = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _working = false;
        _error = _strings().t(
          'failed_update_server_icon',
          fallback: 'Failed to update server picture.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = appStringsFor(ref.watch(appLanguageProvider));
    final server = _server;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final compactLayout = viewportWidth < 980;
    final compactActions = viewportWidth < 520;
    return PopScope<BackendServerSettingsResult>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        _closeScreen();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _closeScreen,
            icon: const Icon(Icons.arrow_back),
          ),
          title:
              Text(strings.t('server_settings', fallback: 'Server Settings')),
          actions: [
            if (compactActions)
              IconButton(
                tooltip: strings.t('save_changes', fallback: 'Save Changes'),
                onPressed: (_loading || _saving || _working || server == null)
                    ? null
                    : _saveServerName,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
              )
            else
              TextButton(
                onPressed: (_loading || _saving || _working || server == null)
                    ? null
                    : _saveServerName,
                child: Text(_saving
                    ? strings.t('saving', fallback: 'Saving...')
                    : strings.t('save_changes', fallback: 'Save Changes')),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : compactLayout
                ? ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children:
                              _ServerSettingsSection.values.map((section) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(_sectionLabel(strings, section)),
                                selected: _selectedSection == section,
                                onSelected: (_) => _selectSection(section),
                              ),
                            );
                          }).toList(growable: false),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      _buildSelectedSectionContent(),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        width: 240,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF1E1F22)
                            : const Color(0xFFE3E5E8),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            _navTile(
                              label: strings.t('server_settings',
                                  fallback: 'Server Settings'),
                              section: _ServerSettingsSection.overview,
                              icon: Icons.tune_outlined,
                            ),
                            _navTile(
                              label:
                                  strings.t('channels', fallback: 'Channels'),
                              section: _ServerSettingsSection.channels,
                              icon: Icons.forum_outlined,
                            ),
                            _navTile(
                              label: strings.t('delete_server',
                                  fallback: 'Danger Zone'),
                              section: _ServerSettingsSection.danger,
                              icon: Icons.warning_amber_outlined,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error),
                                ),
                              ),
                            _buildSelectedSectionContent(),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  String _sectionLabel(AppStrings strings, _ServerSettingsSection section) {
    switch (section) {
      case _ServerSettingsSection.overview:
        return strings.t('server_settings', fallback: 'Server Settings');
      case _ServerSettingsSection.channels:
        return strings.t('channels', fallback: 'Channels');
      case _ServerSettingsSection.danger:
        return strings.t('delete_server', fallback: 'Danger Zone');
    }
  }

  Widget _buildSelectedSectionContent() {
    if (_selectedSection == _ServerSettingsSection.overview) {
      return _buildOverviewSection();
    }
    if (_selectedSection == _ServerSettingsSection.channels) {
      return _buildChannelsSection();
    }
    return _buildDangerSection();
  }

  void _selectSection(_ServerSettingsSection section) {
    if (_selectedSection == section) {
      return;
    }
    setState(() {
      _selectedSection = section;
      _error = null;
    });
  }

  Widget _navTile({
    required String label,
    required _ServerSettingsSection section,
    required IconData icon,
  }) {
    return ListTile(
      selected: _selectedSection == section,
      leading: Icon(icon),
      title: Text(label),
      onTap: () => _selectSection(section),
    );
  }

  Widget _buildOverviewSection() {
    final strings = _strings();
    final server = _server;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.t('server_settings', fallback: 'Server Settings'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (server != null) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 620;
                  final avatar = CircleAvatar(
                    radius: 34,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundImage: (server.iconUrl != null &&
                            server.iconUrl!.trim().isNotEmpty)
                        ? NetworkImage(server.iconUrl!.trim())
                        : null,
                    child: Text(
                      (server.name.isNotEmpty
                              ? server.name.substring(0, 1)
                              : '?')
                          .toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  );
                  final changeButton = FilledButton.tonalIcon(
                    onPressed: _working ? null : _changeServerIcon,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      strings.t(
                        'change_server_picture',
                        fallback: 'Change Server Picture',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                  final removeButton = FilledButton.tonalIcon(
                    onPressed: (_working ||
                            server.iconUrl == null ||
                            server.iconUrl!.trim().isEmpty)
                        ? null
                        : _removeServerIcon,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(
                      strings.t(
                        'remove_server_picture',
                        fallback: 'Remove Picture',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );

                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(child: avatar),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: changeButton,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: removeButton,
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      avatar,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            changeButton,
                            removeButton,
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                '${strings.t('server_id', fallback: 'ServerID')}: ${server.id}',
              ),
              const SizedBox(height: 6),
              Text(
                'Owner UserID: ${server.ownerUserId}',
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: strings.t('server_name', fallback: 'Server Name'),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_loading || _saving || _working || server == null)
                  ? null
                  : _saveServerName,
              child: Text(strings.t('save_changes', fallback: 'Save Changes')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelsSection() {
    final strings = _strings();
    final channels = <ApiChannelSummary>[
      ..._textChannels,
      ..._voiceChannels,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 520;
                final title = Text(
                  strings.t('channels', fallback: 'Channels'),
                  style: Theme.of(context).textTheme.titleLarge,
                );
                final action = FilledButton.tonalIcon(
                  onPressed: _working ? null : _createChannel,
                  icon: const Icon(Icons.add),
                  label: Text(
                      strings.t('create_channel', fallback: 'Create Channel')),
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 10),
                      SizedBox(width: double.infinity, child: action),
                    ],
                  );
                }
                return Row(
                  children: [
                    title,
                    const Spacer(),
                    action,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            if (channels.isEmpty)
              Text(
                strings.t('no_channels', fallback: 'No channels yet.'),
              )
            else
              ...channels.map((channel) {
                final isVoice = channel.kind == 'voice';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      isVoice ? Icons.volume_up_outlined : Icons.tag,
                    ),
                    title: Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      isVoice
                          ? strings.t('channel_kind_voice', fallback: 'Voice')
                          : strings.t('channel_kind_text', fallback: 'Text'),
                    ),
                    trailing: IconButton(
                      tooltip: strings.t('delete_channel',
                          fallback: 'Delete Channel'),
                      onPressed:
                          _working ? null : () => _deleteChannel(channel),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerSection() {
    final strings = _strings();
    final compactLayout = MediaQuery.sizeOf(context).width < 520;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.t('delete_server', fallback: 'Delete Server'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              strings.t('delete_server_warning',
                  fallback:
                      'This permanently deletes this server and all of its channels and messages.'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
                minimumSize: compactLayout ? const Size.fromHeight(44) : null,
              ),
              onPressed: _working ? null : _deleteServer,
              child:
                  Text(strings.t('delete_server', fallback: 'Delete Server')),
            ),
          ],
        ),
      ),
    );
  }
}
