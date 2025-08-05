import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';
import 'package:http/http.dart' as http;

class MapSmsRutaPage extends StatefulWidget {
  const MapSmsRutaPage({super.key});

  @override
  State<MapSmsRutaPage> createState() => _MapSmsRutaPageState();
}

class _MapSmsRutaPageState extends State<MapSmsRutaPage> {
  final MapController _mapController = MapController();
  final Telephony telephony = Telephony.instance;
  late final SharedPreferences preferences;

  LatLng? _miUbicacion;
  LatLng? _ubicacionRecibida;
  late Future<LatLng> _ubicacionInicialFuture;
  List<LatLng> _ruta = [];

  String? _numeroVinculado;
  bool _autoEnvioActivado = false;

  final String apiKeyORS =
      '5b3ce3597851110001cf6248627feed9a1c04d9f81e7b717bb1d3107';

  @override
  void initState() {
    super.initState();
    _ubicacionInicialFuture = _obtenerUbicacionActual();
    _escucharSmsEntrantes();
  }

  Future<void> _solicitarPermisos() async {
    await [Permission.location, Permission.sms, Permission.phone].request();
    await telephony.requestPhoneAndSmsPermissions;
  }

  Future<LatLng> _obtenerUbicacionActual() async {
    preferences = await SharedPreferences.getInstance();
    _solicitarPermisos();
    _numeroVinculado = preferences.getString("numeroVinculado");
    bool gpsActivo = await Geolocator.isLocationServiceEnabled();
    if (!gpsActivo) {
      return const LatLng(-31.5406, -68.5767);
    }

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever) {
      permiso = await Geolocator.requestPermission();
      if (permiso != LocationPermission.whileInUse &&
          permiso != LocationPermission.always) {
        return const LatLng(-31.5406, -68.5767);
      }
    }

    final posicion = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // Empezamos a escuchar cambios en tiempo real:
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      final nueva = LatLng(pos.latitude, pos.longitude);
      setState(() => _miUbicacion = nueva);
    });

    final inicial = LatLng(posicion.latitude, posicion.longitude);
    _miUbicacion = inicial;
    return inicial;
  }

  void _escucharSmsEntrantes() {
    telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        // Verificamos que haya un número vinculado
        if (_numeroVinculado == null) return;

        // Normalizamos ambos números para comparar (por si uno tiene +54 y otro no)
        final remitente = message.address?.replaceAll(RegExp(r'\D'), '');
        final vinculado = _numeroVinculado?.replaceAll(RegExp(r'\D'), '');

        if (remitente == null || !remitente.endsWith(vinculado!)) return;

        // Procesamos la ubicación si viene del número vinculado
        print("MENSAJE RECIBIDO: ${message.body}");
        final partes = message.body?.split(',');
        if (partes != null && partes.length == 2) {
          final lat = double.tryParse(partes[0]);
          final lng = double.tryParse(partes[1]);
          if (lat != null && lng != null) {
            setState(() {
              _ubicacionRecibida = LatLng(lat, lng);
            });
          }
        }
      },
      listenInBackground: false,
    );
  }

  Future<void> _enviarSms() async {
    if (_miUbicacion == null || _numeroVinculado == null) return;
    final mensaje = "${_miUbicacion!.latitude},${_miUbicacion!.longitude}";
    await telephony.sendSms(to: _numeroVinculado!, message: mensaje);
  }

  Future<void> _toggleAutoEnvio() async {
    setState(() {
      _autoEnvioActivado = !_autoEnvioActivado;
    });

    if (_autoEnvioActivado) {
      final service = FlutterBackgroundService();
      await service.startService();
      service.invoke("setNumber", {"numero": _numeroVinculado});
    } else {
      FlutterBackgroundService().invoke("stopService");
    }
  }

  void _vincularNumero() {
    showDialog(
      context: context,
      builder: (context) {
        String numeroTemporal = '';
        return AlertDialog(
          title: const Text("Vincular usuario"),
          content: TextField(
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: "Ingrese número telefónico",
            ),
            onChanged: (value) {
              numeroTemporal = value;
            },
          ),
          actions: [
            TextButton(
              onPressed:
                  () => () async {
                    setState(() {
                      _numeroVinculado = numeroTemporal;
                    });
                    await preferences.setString(
                      "numeroVinculado",
                      numeroTemporal,
                    );
                    FlutterBackgroundService().invoke("setNumber", {
                      "numero": _numeroVinculado,
                    });

                    Navigator.pop(context);
                  },
              child: const Text("Vincular"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _calcularRuta() async {
    if (_miUbicacion == null || _ubicacionRecibida == null) return;

    final url = Uri.parse(
      'https://api.openrouteservice.org/v2/directions/driving-car',
    );

    final body = {
      'coordinates': [
        [_miUbicacion!.longitude, _miUbicacion!.latitude],
        [_ubicacionRecibida!.longitude, _ubicacionRecibida!.latitude],
      ],
      "instructions": false,
      "geometry": true,
    };

    final headers = {
      'Authorization': apiKeyORS,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final response = await http.post(
      url,
      headers: headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['routes'] != null &&
          data['routes'].isNotEmpty &&
          data['routes'][0]['geometry'] != null) {
        final String encoded = data['routes'][0]['geometry'];
        final points = PolylinePoints().decodePolyline(encoded);

        setState(() {
          _ruta = points.map((p) => LatLng(p.latitude, p.longitude)).toList();
        });
      } else {
        print("⚠️ No se encontró geometría o la ruta está vacía.");
      }
    } else {
      print('Error ORS: ${response.body}');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ubicación por SMS + Ruta"),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            onPressed: _vincularNumero,
            tooltip: "Vincular contacto",
          ),
          if (_numeroVinculado != null) ...[
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _enviarSms,
              tooltip: "Enviar ubicación",
            ),
            IconButton(
              icon: Icon(
                _autoEnvioActivado ? Icons.pause : Icons.play_arrow,
                color: _autoEnvioActivado ? Colors.red : Colors.green,
              ),
              onPressed: _toggleAutoEnvio,
              tooltip:
                  _autoEnvioActivado
                      ? "Detener autoenvío"
                      : "Iniciar autoenvío",
            ),
            IconButton(
              icon: const Icon(Icons.alt_route),
              onPressed: _calcularRuta,
              tooltip: "Calcular Ruta",
            ),
          ],
        ],
      ),
      body: FutureBuilder<LatLng>(
        future: _ubicacionInicialFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final centro = snapshot.data!;

          return FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: centro, initialZoom: 15.0),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.mapas',
              ),
              MarkerLayer(
                markers: [
                  if (_miUbicacion != null)
                    Marker(
                      width: 40,
                      height: 40,
                      point: _miUbicacion!,
                      child: const Icon(Icons.my_location, color: Colors.blue),
                    ),
                  if (_ubicacionRecibida != null)
                    Marker(
                      width: 40,
                      height: 40,
                      point: _ubicacionRecibida!,
                      child: const Icon(Icons.location_pin, color: Colors.red),
                    ),
                ],
              ),
              PolylineLayer(
                polylines: [
                  if (_ruta.isNotEmpty)
                    Polyline(
                      points: _ruta,
                      strokeWidth: 4.0,
                      color: Colors.blueAccent,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
