import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:concord/backend/concord_api_client.dart';

const defaultBackendBaseUrl = String.fromEnvironment(
  'CONCORD_API_BASE',
  defaultValue: 'http://localhost:8001',
);

class BackendSessionState {
  const BackendSessionState({
    required this.baseUrl,
    required this.session,
    required this.isLoading,
    required this.errorMessage,
  });

  final String baseUrl;
  final ApiAuthSession? session;
  final bool isLoading;
  final String? errorMessage;

  BackendSessionState copyWith({
    String? baseUrl,
    ApiAuthSession? session,
    bool clearSession = false,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool updateError = false,
  }) {
    return BackendSessionState(
      baseUrl: baseUrl ?? this.baseUrl,
      session: clearSession ? null : (session ?? this.session),
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearError ? null : (updateError ? errorMessage : this.errorMessage),
    );
  }

  static const initial = BackendSessionState(
    baseUrl: defaultBackendBaseUrl,
    session: null,
    isLoading: false,
    errorMessage: null,
  );
}

final backendSessionProvider =
    StateNotifierProvider<BackendSessionController, BackendSessionState>(
  (ref) => BackendSessionController(),
);

class BackendSessionController extends StateNotifier<BackendSessionState> {
  BackendSessionController() : super(BackendSessionState.initial);

  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    final normalizedIdentifier = identifier.trim();
    final normalizedPassword = password.trim();
    if (normalizedIdentifier.isEmpty || normalizedPassword.isEmpty) {
      state = state.copyWith(
        errorMessage: 'Identifier and password are required.',
        updateError: true,
      );
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearError: true,
    );

    try {
      final client = ConcordApiClient(baseUrl: state.baseUrl.trim());
      final session = await client.login(
        identifier: normalizedIdentifier,
        password: normalizedPassword,
      );
      state = state.copyWith(
        session: session,
        isLoading: false,
        clearError: true,
      );
    } on ApiException catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: error.message,
        updateError: true,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unexpected error while signing in.',
        updateError: true,
      );
    }
  }

  Future<void> register({
    required String username,
    required String password,
    String? displayName,
    String? preferredTag,
  }) async {
    final normalizedUsername = username.trim();
    final normalizedPassword = password.trim();
    final normalizedDisplayName = displayName?.trim();
    final normalizedPreferredTag = preferredTag?.trim();

    if (normalizedUsername.isEmpty || normalizedPassword.isEmpty) {
      state = state.copyWith(
        errorMessage: 'Username and password are required.',
        updateError: true,
      );
      return;
    }

    int? parsedTag;
    if (normalizedPreferredTag != null && normalizedPreferredTag.isNotEmpty) {
      parsedTag = int.tryParse(normalizedPreferredTag);
      if (parsedTag == null || parsedTag < 0 || parsedTag > 9999) {
        state = state.copyWith(
          errorMessage: 'Tag must be a number between 0000 and 9999.',
          updateError: true,
        );
        return;
      }
    }

    state = state.copyWith(
      isLoading: true,
      clearError: true,
    );

    try {
      final client = ConcordApiClient(baseUrl: state.baseUrl.trim());
      final session = await client.register(
        username: normalizedUsername,
        password: normalizedPassword,
        displayName: normalizedDisplayName,
        preferredTag: parsedTag,
      );
      state = state.copyWith(
        session: session,
        isLoading: false,
        clearError: true,
      );
    } on ApiException catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: error.message,
        updateError: true,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unexpected error while registering.',
        updateError: true,
      );
    }
  }

  void logout() {
    state = state.copyWith(
      clearSession: true,
      clearError: true,
      isLoading: false,
    );
  }

  void setBaseUrl(String value) {
    final trimmed = value.trim();
    state = state.copyWith(
      baseUrl: trimmed.isEmpty ? defaultBackendBaseUrl : trimmed,
      clearError: true,
    );
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void updateSessionHandle(String handle) {
    final current = state.session;
    if (current == null) {
      return;
    }

    final trimmed = handle.trim();
    if (trimmed.isEmpty) {
      return;
    }

    state = state.copyWith(
      session: ApiAuthSession(
        userId: current.userId,
        handle: trimmed,
        isPlatformAdmin: current.isPlatformAdmin,
        accessToken: current.accessToken,
        refreshToken: current.refreshToken,
      ),
    );
  }
}
