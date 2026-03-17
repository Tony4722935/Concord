import 'package:flutter_test/flutter_test.dart';

import 'package:concord/data/state/concord_state.dart';

void main() {
  test('Seed state includes friends, server and channel data', () {
    final state = ConcordState.seed();

    expect(state.friends.isNotEmpty, isTrue);
    expect(state.servers.isNotEmpty, isTrue);
    expect(state.channelsForSelectedServer.isNotEmpty, isTrue);
  });
}
