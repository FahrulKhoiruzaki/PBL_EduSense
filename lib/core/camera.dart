import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CameraUnavailable implements Exception {
  const CameraUnavailable([this.message = 'Kamera tidak tersedia pada perangkat ini.']);

  final String message;
}

class CameraPermissionDenied extends CameraUnavailable {
  const CameraPermissionDenied()
      : super('Izin kamera ditolak. Aktifkan izin kamera di pengaturan perangkat.');
}

abstract interface class FaceCamera {
  Future<void> initialize();

  Widget buildPreview(BuildContext context);

  Future<Uint8List> capture();

  Future<void> dispose();
}

class DeviceFaceCamera implements FaceCamera {
  CameraController? _controller;

  @override
  Future<void> initialize() async {
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (e) {
      throw _translate(e);
    }
    if (cameras.isEmpty) throw const CameraUnavailable();

    final description = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      throw _translate(e);
    }
    _controller = controller;
  }

  CameraUnavailable _translate(CameraException e) {
    return e.code.startsWith('CameraAccess')
        ? const CameraPermissionDenied()
        : CameraUnavailable(e.description ?? 'Kamera tidak dapat dibuka.');
  }

  @override
  Widget buildPreview(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return const SizedBox.shrink();

    final size = controller.value.previewSize!;
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: portrait ? size.height : size.width,
          height: portrait ? size.width : size.height,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  @override
  Future<Uint8List> capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) throw const CameraUnavailable();
    try {
      final file = await controller.takePicture();
      return await file.readAsBytes();
    } on CameraException catch (e) {
      throw CameraUnavailable(e.description ?? 'Gagal mengambil gambar.');
    }
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}

final faceCameraFactoryProvider =
    Provider<FaceCamera Function()>((ref) => DeviceFaceCamera.new);
