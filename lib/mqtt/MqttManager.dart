import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:ubilab_scavenger_hunt/framework/game.dart';
import 'package:ubilab_scavenger_hunt/globals.dart';
import 'package:uuid/uuid.dart';
import 'package:ubilab_scavenger_hunt/framework/beaconScanner.dart';
import 'dart:async';
import 'dart:convert';

final String topicTest = "testID/scavenger_hunt";
final String topicMacs = "config/#";

class MQTTManager {
  Timer _gameDetailsTimer;
  String _hostName;
  MqttServerClient _client;
  bool _connected;
  Map _mapTeamDetails = Map();

  MQTTManager(String hostName) {
    Uuid uuid = Uuid();
    String uuidString = uuid.v1();
    _hostName = hostName;
    _client = MqttServerClient(_hostName, uuidString);
    _client.useWebSocket = true;
    _client.port = 443;
    _client.logging(on: false);
    _client.keepAlivePeriod = 5;
    _client.autoReconnect = true;
    _client.resubscribeOnAutoReconnect = true;
    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;
    _client.onUnsubscribed = _onUnsubscribed;
    _client.onSubscribed = _onSubscribed;
    _client.onSubscribeFail = _onSubscribeFail;
    _connected = false;
  }

  /// Connects to the server.
  void connect() async {
    if (_connected) {
      return;
    }
    try {
      if (globalIsTesting) {
        print("MQTT: Connecting");
      }
      await _client.connect("ubilab", "ubilab");
    } on Exception catch (e) {
      if (globalIsTesting) {
        print("MQTT: Exception during connection establishment ($e)");
      }
      disconnect();
      return;
    }
    _client.updates.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final MqttPublishMessage payload = c[0].payload;
      final String message =
          MqttPublishPayload.bytesToStringAsString(payload.payload.message);
      _onReceivedMessage(c[0].topic, message);
    });
    _gameDetailsTimer = Timer.periodic(Duration(seconds: 3), (Timer t) {
      if (_client.connectionStatus.state != MqttConnectionState.connected) {
        _connected = false;
      } else {
        _connected = true;
      }
      if (double.parse(
              Game.getInstance().getAlreadyPlayedTime().split(":")[0]) >=
          globalMaxTime) {
        disconnect();
      }
      publishGameDetails();
    });
  }

  /// Publish Message to given topic on the server.
  void publishString(String topic, String message) {
    final builder = MqttClientPayloadBuilder();
    if (globalIsTesting) {
      print("MQTT: Publishing message '$message'");
    }
    builder.addString(message);
    _client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload);
  }

  /// Disconnects from the server.
  void disconnect() {
    if (!_connected) {
      return;
    }
    if (globalIsTesting) {
      print('MQTT: Disconnecting');
    }
    _mapTeamDetails["connected"] = false;
    publishString(topicTest, json.encode(_mapTeamDetails));
    _client.disconnect();
    _gameDetailsTimer.cancel();
    _mapTeamDetails.clear();
  }

  /// If currently connected to the server.
  bool isConnected() {
    return _connected;
  }

  /// Subscribe to all needed topics.
  void subscribeToTopics() {
    if (!_connected) {
      return;
    }
    _client.subscribe(topicTest, MqttQos.atMostOnce);
    _client.subscribe(topicMacs, MqttQos.atMostOnce);
  }

  /// Sends the current game details to the server.
  void publishGameDetails() {
    Game game = Game.getInstance();
    if (!_connected) {
      return;
    }
    _mapTeamDetails["teamID"] = _client.clientIdentifier;
    _mapTeamDetails["teamName"] = game.getTeamName();
    _mapTeamDetails["teamSize"] = game.getTeamSize().toString();
    _mapTeamDetails["hintsUsed"] = game.getAlreadyUsedHints();
    _mapTeamDetails["gameProgress"] = game.getProgress().toString();
    _mapTeamDetails["currentPuzzle"] = game.getCurrentPuzzleInfo().toString();
    _mapTeamDetails["latitude"] = game.getCurrentLocation().latitude;
    _mapTeamDetails["longitude"] = game.getCurrentLocation().longitude;
    _mapTeamDetails["connected"] = true;
    _mapTeamDetails["timeStamp"] = game.getAlreadyPlayedTime();
    publishString(topicTest, json.encode(_mapTeamDetails));
  }

  /// Callback if connection was successful.
  void _onConnected() {
    if (globalIsTesting) {
      print("MQTT: Connected");
    }
    _connected = true;
    subscribeToTopics();
  }

  /// Callback if disconnected from server.
  void _onDisconnected() {
    if (globalIsTesting) {
      print("MQTT: Disconnected");
    }
    _connected = false;
  }

  /// Callback if subscription to topic succeeded.
  void _onSubscribed(String topic) {
    if (globalIsTesting) {
      print("MQTT: Subscribed to topic '$topic'");
    }
  }

  /// Callback if subscription to topic failed.
  void _onSubscribeFail(String topic) {
    if (globalIsTesting) {
      print("MQTT: Failed to subscribe to topic '$topic'");
    }
  }

  /// Callback if unsubscribed from topic.
  void _onUnsubscribed(String topic) {
    if (globalIsTesting) {
      print("MQTT: Unsubscribed from topic '$topic'");
    }
  }

  /// Callback for received messages.
  void _onReceivedMessage(String topic, String message) {
    String beaconName;
    if (globalIsTesting) {
      print("MQTT: Received message '$message' from topic '$topic'");
    }
    if (topic.startsWith("config/tag/") && topic.endsWith("/mac")) {
      beaconName = topic;
      beaconName = beaconName.replaceAll("config/tag/", "");
      beaconName = beaconName.replaceAll("/mac", "");
      BeaconScanner.getInstance().addBeacon(beaconName, message);
    }
  }
}
