import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Represents a camera discovered on the local Wi-Fi / LAN network.
class DiscoveredCamera {
  final String ip;
  final int port;
  final String name;
  final String brand; // 'Hikvision', 'CP Plus / Dahua', 'TP-Link Tapo', 'ONVIF / IP Camera', 'Mobile IP Webcam'
  final String? model;
  final String? mac;
  final String discoveryMethod; // 'SADP', 'ONVIF', 'LAN Sweep'
  final String? suggestedStreamUrl;

  const DiscoveredCamera({
    required this.ip,
    required this.port,
    required this.name,
    required this.brand,
    this.model,
    this.mac,
    required this.discoveryMethod,
    this.suggestedStreamUrl,
  });

  @override
  String toString() => '$name ($ip:$port) via $discoveryMethod';
}

/// Autonomous Network Camera Discovery Service (Hik-Partner Pro / SADP / ONVIF Discovery).
/// Automatically scans the local network using:
/// 1. Hikvision SADP UDP multicast / broadcast (Port 37020)
/// 2. ONVIF WS-Discovery UDP multicast (Port 3702)
/// 3. Lightning-fast Local Subnet Ping Sweep (Ports 554, 8000, 37777, 8080, 80)
class CctvDiscoveryService {
  static const String _sadpMulticast = '239.255.255.250';
  static const int _sadpPort = 37020;
  static const String _onvifMulticast = '239.255.255.250';
  static const int _onvifPort = 3702;

  /// Discovers all online cameras on the local Wi-Fi / LAN.
  static Future<List<DiscoveredCamera>> discoverNetworkCameras({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    final discoveredMap = <String, DiscoveredCamera>{};

    // Run SADP, ONVIF and Subnet Sweep concurrently
    await Future.wait([
      _discoverHikvisionSadp(discoveredMap, timeout: timeout),
      _discoverOnvif(discoveredMap, timeout: timeout),
      _sweepLocalSubnet(discoveredMap, timeout: timeout),
    ]);

    return discoveredMap.values.toList();
  }

  /// 1. Hikvision SADP Protocol Discovery (UDP 37020)
  /// Used by Hikvision, Ezviz, HiLook cameras, NVRs, and DVRs.
  static Future<void> _discoverHikvisionSadp(
    Map<String, DiscoveredCamera> results, {
    required Duration timeout,
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.multicastLoopback = false;

      // SADP XML Inquiry Probe
      const probeXml =
          '<?xml version="1.0" encoding="utf-8"?><Probe><Uuid>a84b0eb1-5a02-4d2a-88fa-051f92e92c4d</Uuid><Types>inquiry</Types></Probe>';
      final probeBytes = utf8.encode(probeXml);

      // Send to both multicast and broadcast
      try {
        socket.send(probeBytes, InternetAddress(_sadpMulticast), _sadpPort);
      } catch (_) {}
      try {
        socket.send(probeBytes, InternetAddress('255.255.255.255'), _sadpPort);
      } catch (_) {}

      final completer = Completer<void>();
      Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
      });

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
          if (dg != null) {
            try {
              final text = utf8.decode(dg.data, allowMalformed: true);
              final ipMatch = RegExp(r'<IPv4Address>([^<]+)</IPv4Address>').firstMatch(text);
              final portMatch = RegExp(r'<HttpPort>([^<]+)</HttpPort>').firstMatch(text);
              final devDescMatch = RegExp(r'<DeviceDescription>([^<]+)</DeviceDescription>').firstMatch(text);
              final devTypeMatch = RegExp(r'<DeviceType>([^<]+)</DeviceType>').firstMatch(text);
              final macMatch = RegExp(r'<MAC>([^<]+)</MAC>').firstMatch(text);

              final ip = ipMatch?.group(1)?.trim() ?? dg.address.address;
              if (ip.isNotEmpty && ip != '0.0.0.0') {
                final port = int.tryParse(portMatch?.group(1) ?? '') ?? 80;
                final model = devDescMatch?.group(1) ?? devTypeMatch?.group(1) ?? 'Hikvision IP Camera';
                final mac = macMatch?.group(1);

                results[ip] = DiscoveredCamera(
                  ip: ip,
                  port: port,
                  name: 'Hikvision ($model)',
                  brand: 'Hikvision',
                  model: model,
                  mac: mac,
                  discoveryMethod: 'Hikvision SADP',
                  suggestedStreamUrl: 'rtsp://$ip:554/Streaming/Channels/101',
                );
              }
            } catch (e) {
              debugPrint('[CctvDiscovery] SADP parse error: $e');
            }
          }
        }
      });

      await completer.future;
    } catch (e) {
      debugPrint('[CctvDiscovery] SADP error: $e');
    } finally {
      socket?.close();
    }
  }

  /// 2. ONVIF WS-Discovery Protocol (UDP 3702)
  /// Used by Dahua, CP Plus, TP-Link Tapo, Uniview, Axis, and all ONVIF cameras.
  static Future<void> _discoverOnvif(
    Map<String, DiscoveredCamera> results, {
    required Duration timeout,
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      const onvifProbe = '''<?xml version="1.0" encoding="utf-8"?>
<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope" xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
  <Header>
    <wsa:MessageID xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">uuid:f0d4ea9b-12d4-4bb0-8a2b-cf0c2e36b801</wsa:MessageID>
    <wsa:To xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">urn:schemas-xmlsoap-org:ws:2005:04:discovery</wsa:To>
    <wsa:Action xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</wsa:Action>
  </Header>
  <Body>
    <Probe xmlns="http://schemas.xmlsoap.org/ws/2005/04/discovery">
      <Types>dn:NetworkVideoTransmitter</Types>
    </Probe>
  </Body>
</Envelope>''';

      final probeBytes = utf8.encode(onvifProbe);
      try {
        socket.send(probeBytes, InternetAddress(_onvifMulticast), _onvifPort);
      } catch (_) {}
      try {
        socket.send(probeBytes, InternetAddress('255.255.255.255'), _onvifPort);
      } catch (_) {}

      final completer = Completer<void>();
      Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
      });

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
          if (dg != null) {
            try {
              final text = utf8.decode(dg.data, allowMalformed: true);
              // Extract service XAddrs: http://192.168.1.x:port/onvif/...
              final xaddrMatch = RegExp(r'http://([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(?::([0-9]+))?').firstMatch(text);
              final ip = xaddrMatch?.group(1) ?? dg.address.address;

              if (ip.isNotEmpty && ip != '0.0.0.0') {
                final port = int.tryParse(xaddrMatch?.group(2) ?? '') ?? 80;

                String brand = 'ONVIF Camera';
                String name = 'IP Camera ($ip)';
                final lower = text.toLowerCase();
                if (lower.contains('dahua') || lower.contains('dh-') || lower.contains('general_')) {
                  brand = 'CP Plus / Dahua';
                  name = 'CP Plus / Dahua ($ip)';
                } else if (lower.contains('hikvision') || lower.contains('ds-')) {
                  brand = 'Hikvision';
                  name = 'Hikvision ($ip)';
                } else if (lower.contains('tapo') || lower.contains('tp-link')) {
                  brand = 'TP-Link Tapo';
                  name = 'Tapo Wi-Fi Cam ($ip)';
                } else if (lower.contains('uniview') || lower.contains('unv')) {
                  brand = 'Uniview (UNV)';
                  name = 'Uniview Cam ($ip)';
                } else if (lower.contains('xm') || lower.contains('xiongmai') || lower.contains('icsee') || lower.contains('sofia')) {
                  brand = 'Chinese XM / iCSee';
                  name = 'Xiongmai / XM ($ip)';
                } else if (lower.contains('tiandy')) {
                  brand = 'Tiandy';
                  name = 'Tiandy IP Cam ($ip)';
                } else if (lower.contains('tuya') || lower.contains('v380') || lower.contains('yoosee') || lower.contains('srihome') || lower.contains('jovision')) {
                  brand = 'Chinese Wi-Fi Cam';
                  name = 'Chinese Smart Cam ($ip)';
                }

                // If not already detected via SADP with more details
                if (!results.containsKey(ip) || results[ip]!.discoveryMethod != 'Hikvision SADP') {
                  results[ip] = DiscoveredCamera(
                    ip: ip,
                    port: port,
                    name: name,
                    brand: brand,
                    discoveryMethod: 'ONVIF WS-Discovery',
                    suggestedStreamUrl: 'rtsp://$ip:554/onvif1',
                  );
                }
              }
            } catch (e) {
              debugPrint('[CctvDiscovery] ONVIF parse error: $e');
            }
          }
        }
      });

      await completer.future;
    } catch (e) {
      debugPrint('[CctvDiscovery] ONVIF error: $e');
    } finally {
      socket?.close();
    }
  }

  /// 3. Lightning-fast Local Subnet Ping Sweep
  /// Scans common CCTV ports (554 RTSP, 8000 Hikvision, 37777 Dahua, 8080 IP Webcam)
  /// on the local subnet to catch any cameras that do not respond to multicast.
  static Future<void> _sweepLocalSubnet(
    Map<String, DiscoveredCamera> results, {
    required Duration timeout,
  }) async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      final localIps = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (!ip.startsWith('127.') && !ip.startsWith('169.254.')) {
            localIps.add(ip);
          }
        }
      }

      if (localIps.isEmpty) return;

      // Extract subnet prefixes (e.g. "192.168.1." or "10.93.237.")
      final prefixes = <String>{};
      for (final ip in localIps) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}.');
        }
      }

      // Check common high-probability camera host numbers first
      final priorityHosts = [
        64, 250, 100, 101, 102, 103, 104, 105, 108, 110, 120, 150, 200, 201, 1, 2, 3, 4, 5, 10, 20, 50
      ];

      // Discover real active network devices from system ARP table (blazing fast, detects mobile hotspots & all connected cameras)
      final discoveredArpIps = <String>{};
      try {
        final arpRes = await Process.run('arp', ['-a']);
        if (arpRes.exitCode == 0) {
          final arpOutput = arpRes.stdout.toString();
          final ipMatches = RegExp(r'([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})').allMatches(arpOutput);
          for (final m in ipMatches) {
            final a = m.group(1);
            if (a != null &&
                !a.startsWith('127.') &&
                !a.startsWith('169.254.') &&
                !a.startsWith('224.') &&
                !a.startsWith('239.') &&
                !a.endsWith('.255') &&
                !localIps.contains(a)) {
              discoveredArpIps.add(a);
            }
          }
        }
      } catch (_) {}

      final candidateTargets = <({String ip, int port})>[];

      // 1. First priority: Real devices found via system ARP table (including mobile phones & connected cameras)
      for (final arpIp in discoveredArpIps) {
        if (results.containsKey(arpIp)) continue;
        candidateTargets.add((ip: arpIp, port: 8080)); // Mobile IP Webcam
        candidateTargets.add((ip: arpIp, port: 554));  // RTSP Universal
        candidateTargets.add((ip: arpIp, port: 80));   // HTTP Web / Snapshot
        candidateTargets.add((ip: arpIp, port: 8000)); // Hikvision SDK
        candidateTargets.add((ip: arpIp, port: 34567));// Xiongmai / XM
        candidateTargets.add((ip: arpIp, port: 8899)); // Chinese ONVIF
      }

      // 2. Second priority: Standard CCTV host numbers on each subnet
      for (final prefix in prefixes) {
        for (final h in priorityHosts) {
          final targetIp = '$prefix$h';
          if (localIps.contains(targetIp) || results.containsKey(targetIp) || discoveredArpIps.contains(targetIp)) continue;
          candidateTargets.add((ip: targetIp, port: 554)); // RTSP Universal
          candidateTargets.add((ip: targetIp, port: 34567)); // Xiongmai / XM Chinese Cam
          candidateTargets.add((ip: targetIp, port: 8899)); // Chinese ONVIF / Yoosee
          candidateTargets.add((ip: targetIp, port: 8080)); // IP Webcam
          candidateTargets.add((ip: targetIp, port: 8000)); // Hikvision SDK
        }
      }

      // Scan concurrently in batches of 30 to avoid OS socket exhaustion
      const batchSize = 30;
      for (int i = 0; i < candidateTargets.length; i += batchSize) {
        final end = (i + batchSize < candidateTargets.length) ? i + batchSize : candidateTargets.length;
        final batch = candidateTargets.sublist(i, end);

        await Future.wait(batch.map((target) async {
          if (results.containsKey(target.ip)) return;
          try {
            final s = await Socket.connect(target.ip, target.port, timeout: const Duration(milliseconds: 300));
            s.destroy();

            String brand = 'CCTV / IP Camera';
            String name = 'Camera (${target.ip})';
            String suggested = 'rtsp://${target.ip}:554/onvif1';

            if (target.port == 8000) {
              brand = 'Hikvision';
              name = 'Hikvision (${target.ip})';
              suggested = 'rtsp://${target.ip}:554/Streaming/Channels/101';
            } else if (target.port == 34567) {
              brand = 'Chinese XM / iCSee';
              name = 'Xiongmai / XM (${target.ip})';
              suggested = 'rtsp://${target.ip}:554/user=admin_password=_channel=1_stream=0.sdp';
            } else if (target.port == 8899) {
              brand = 'Chinese Wi-Fi Cam';
              name = 'Chinese Smart Cam (${target.ip})';
              suggested = 'rtsp://${target.ip}:554/onvif1';
            } else if (target.port == 8080) {
              brand = 'Mobile IP Webcam';
              name = 'Mobile Webcam (${target.ip}:8080)';
              suggested = 'http://${target.ip}:8080/shot.jpg';
            } else if (target.port == 80) {
              brand = 'HTTP / IP Camera';
              name = 'Camera (${target.ip})';
              suggested = 'http://${target.ip}/snapshot.cgi';
            }

            results[target.ip] ??= DiscoveredCamera(
              ip: target.ip,
              port: target.port,
              name: name,
              brand: brand,
              discoveryMethod: 'Subnet Sweep',
              suggestedStreamUrl: suggested,
            );
          } catch (_) {}
        }));
      }
    } catch (e) {
      debugPrint('[CctvDiscovery] Subnet sweep error: $e');
    }
  }

  /// Probes a specific IP address on all common CCTV & Webcam ports.
  /// Used by Auto-Detect in the edit/add modal to instantly identify camera type and working stream.
  static Future<DiscoveredCamera?> probeSingleIp(String rawIpOrUrl) async {
    String host = rawIpOrUrl.trim();
    int customPort = 0;
    try {
      final normalized = (host.startsWith('http://') || host.startsWith('https://') || host.startsWith('rtsp://'))
          ? host
          : 'http://$host';
      final u = Uri.parse(normalized);
      host = u.host.trim();
      if (u.hasPort) customPort = u.port;
    } catch (_) {}

    if (host.isEmpty) return null;

    final portsToCheck = [
      if (customPort > 0) customPort,
      8080, // Mobile IP Webcam
      554,  // RTSP Universal
      80,   // HTTP Web / Snapshot
      8000, // Hikvision
      34567,// Xiongmai / XM
      8899, // Chinese ONVIF
      37777,// Dahua / CP Plus
      4747, // DroidCam
      8081,
    ];

    for (final port in portsToCheck.toSet()) {
      try {
        final s = await Socket.connect(host, port, timeout: const Duration(milliseconds: 350));
        s.destroy();

        if (port == 8080) {
          return DiscoveredCamera(
            ip: host,
            port: 8080,
            name: 'Mobile Webcam ($host:8080)',
            brand: 'Mobile IP Webcam',
            discoveryMethod: 'Active Probe',
            suggestedStreamUrl: 'http://$host:8080/shot.jpg',
          );
        } else if (port == 8000) {
          return DiscoveredCamera(
            ip: host,
            port: 8000,
            name: 'Hikvision ($host)',
            brand: 'Hikvision',
            discoveryMethod: 'Active Probe',
            suggestedStreamUrl: 'rtsp://$host:554/Streaming/Channels/101',
          );
        } else if (port == 34567) {
          return DiscoveredCamera(
            ip: host,
            port: 34567,
            name: 'Chinese XM ($host)',
            brand: 'Chinese XM / iCSee',
            discoveryMethod: 'Active Probe',
            suggestedStreamUrl: 'rtsp://$host:554/user=admin_password=_channel=1_stream=0.sdp',
          );
        } else if (port == 554) {
          return DiscoveredCamera(
            ip: host,
            port: 554,
            name: 'IP Camera ($host)',
            brand: 'Universal RTSP / IP Camera',
            discoveryMethod: 'Active Probe',
            suggestedStreamUrl: 'rtsp://$host:554/onvif1',
          );
        } else if (port == 80) {
          return DiscoveredCamera(
            ip: host,
            port: 80,
            name: 'IP Camera ($host)',
            brand: 'HTTP / Snapshot Camera',
            discoveryMethod: 'Active Probe',
            suggestedStreamUrl: 'http://$host/snapshot.cgi',
          );
        } else {
          return DiscoveredCamera(
            ip: host,
            port: port,
            name: 'Camera ($host:$port)',
            brand: 'IP Camera',
            discoveryMethod: 'Active Probe',
            suggestedStreamUrl: 'http://$host:$port/shot.jpg',
          );
        }
      } catch (_) {}
    }
    return null;
  }
}
