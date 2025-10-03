import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Describes the current network reachability state of the device.
enum ConnectivityStatus {
  online,
  offline,
  unknown,
}

/// Centralized connectivity observer that promotes internet reachability
/// updates through a [ValueNotifier].
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final ValueNotifier<ConnectivityStatus> statusNotifier =
      ValueNotifier<ConnectivityStatus>(ConnectivityStatus.unknown);

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final Connectivity _connectivity = Connectivity();
  Timer? _debounce;

  Future<void> initialize() async {
    final results = await _connectivity.checkConnectivity();
    statusNotifier.value = await _resolveStatus(results);

    _subscription = _connectivity.onConnectivityChanged.listen((event) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 200), () async {
        final newStatus = await _resolveStatus(event);
        if (statusNotifier.value != newStatus) {
          statusNotifier.value = newStatus;
        }
      });
    });
  }

  Future<ConnectivityStatus> _resolveStatus(
    List<ConnectivityResult> connectivity,
  ) async {
    if (connectivity.isEmpty ||
        connectivity.every((result) => result == ConnectivityResult.none)) {
      return ConnectivityStatus.offline;
    }

    final reachable = await _hasReachableInternet();
    return reachable ? ConnectivityStatus.online : ConnectivityStatus.offline;
  }

  Future<bool> _hasReachableInternet() async {
    try {
      final lookup = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 3));
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _debounce?.cancel();
    statusNotifier.dispose();
  }
}
