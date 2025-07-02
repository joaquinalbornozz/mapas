import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late final MapController _mapController;
  LatLng? _ubicacionActual;
  List<LatLng> _ruta = [];
  final LatLng unsj = const LatLng(-31.5336419722084, -68.54444177635682);
  final String apiKeyORS =
      '5b3ce3597851110001cf6248627feed9a1c04d9f81e7b717bb1d3107';

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  /// Este método se llama una vez y devuelve la ubicación inicial (o fallback)
  Future<LatLng> _obtenerUbicacionInicial() async {
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
      setState(() => _ubicacionActual = nueva);
    });

    final inicial = LatLng(posicion.latitude, posicion.longitude);
    _ubicacionActual = inicial;
    return inicial;
  }

  Future<void> _calcularRuta() async {
    if (_ubicacionActual == null) return;

    final url = Uri.parse(
      'https://api.openrouteservice.org/v2/directions/driving-car',
    );

    final body = {
      'coordinates': [
        [_ubicacionActual!.longitude, _ubicacionActual!.latitude],
        [unsj.longitude, unsj.latitude],
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Map')),
      body: FutureBuilder<LatLng>(
        future: _obtenerUbicacionInicial(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final centroInicial = snapshot.data!;

          return FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: centroInicial,
              initialZoom: 16.5,
              onTap: (_, __) => FocusScope.of(context).unfocus(),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.mapas',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: const LatLng(-31.5406, -68.5767),
                    width: 80,
                    height: 80,
                    child: const Icon(
                      Icons.location_pin,
                      size: 40,
                      color: Colors.red,
                    ),
                  ),
                  if (_ubicacionActual != null)
                    Marker(
                      point: _ubicacionActual!,
                      width: 50,
                      height: 50,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 30,
                      ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _calcularRuta,
        label: const Text('Generar Ruta'),
        icon: const Icon(Icons.alt_route),
      ),
    );
  }
}
