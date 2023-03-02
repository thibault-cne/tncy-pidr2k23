import 'dart:developer';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'preview_page.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({Key? key, required this.cameras}) : super(key: key);

  final List<CameraDescription>? cameras;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  late CameraController _cameraController;
  VideoPlayerController? videoController;

  File? _imageFile;
  File? _videoFile;
  bool _isCameraInitialized = true;
  bool _isRearCameraSelected = true;
  bool _isVideoCameraSelected = false;
  bool _isRecordingInProgress = false;
  double _minAvailableExposureOffset = 0.0;
  double _maxAvailableExposureOffset = 0.0;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;

  // Current values
  double _currentZoomLevel = 1.0;
  double _currentExposureOffset = 0.0;
  FlashMode? _currentFlashMode;

  List<File> allFileList = [];

  final resolutionPresets = ResolutionPreset.values;

  ResolutionPreset currentResolutionPreset = ResolutionPreset.high;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    initCamera(widget.cameras![0]);
  }

   refreshAlreadyCapturedImages() async {
    final directory = await getApplicationDocumentsDirectory();
    List<FileSystemEntity> fileList = await directory.list().toList();
    allFileList.clear();
    List<Map<int, dynamic>> fileNames = [];

    fileList.forEach((file) {
      if (file.path.contains('.jpg') || file.path.contains('.mp4')) {
        allFileList.add(File(file.path));

        String name = file.path.split('/').last.split('.').first;
        fileNames.add({0: int.parse(name), 1: file.path.split('/').last});
      }
    });

    if (fileNames.isNotEmpty) {
      final recentFile =
          fileNames.reduce((curr, next) => curr[0] > next[0] ? curr : next);
      String recentFileName = recentFile[1];
      if (recentFileName.contains('.mp4')) {
        _videoFile = File('${directory.path}/$recentFileName');
        _imageFile = null;
        super.initState();
        //_startVideoPlayer();
      } else {
        _imageFile = File('${directory.path}/$recentFileName');
        _videoFile = null;
      }

      setState(() {});
    }
  }
  Future<XFile?> takePicture() async {
    final CameraController? cameraController = _cameraController;

    if (cameraController!.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      XFile file = await cameraController.takePicture();
      return file;
    } on CameraException catch (e) {
      print('Error occured while taking picture: $e');
      return null;
    }
  }
  Future<void> _startVideoPlayer() async {
    if (_videoFile != null) {
      videoController = VideoPlayerController.file(_videoFile!);
      await videoController!.initialize().then((_) {
        // Ensure the first frame is shown after the video is initialized,
        // even before the play button has been pressed.
        setState(() {});
      });
      await videoController!.setLooping(true);
      await videoController!.play();
    }
  }
  Future<void> startVideoRecording() async {
    final CameraController? cameraController = _cameraController;

    if (_cameraController!.value.isRecordingVideo) {
      // A recording has already started, do nothing.
      return;
    }

    try {
      await cameraController!.startVideoRecording();
        print(_isRecordingInProgress);
    }on CameraException catch (e) {
      print('Error starting to record video: $e');
    }
  }
  Future<XFile?> stopVideoRecording() async {
    if (!_cameraController!.value.isRecordingVideo) {
      // Recording is already is stopped state
      return null;
    }

    try {
      XFile file = await _cameraController!.stopVideoRecording();
      setState(() {
        _isRecordingInProgress = false;
      });
      return file;
    } on CameraException catch (e) {
      print('Error stopping video recording: $e');
      return null;
    }
  }
  Future<void> pauseVideoRecording() async {
    if (!_cameraController!.value.isRecordingVideo) {
      // Video recording is not in progress
      return;
    }

    try {
      await _cameraController!.pauseVideoRecording();
    } on CameraException catch (e) {
      print('Error pausing video recording: $e');
    }
  }

  Future<void> resumeVideoRecording() async {
    if (!_cameraController!.value.isRecordingVideo) {
      // No video recording was in progress
      return;
    }

    try {
      await _cameraController!.resumeVideoRecording();
    } on CameraException catch (e) {
      print('Error resuming video recording: $e');
    }
  }

  void resetCameraValues() async {
    _currentZoomLevel = 1.0;
    _currentExposureOffset = 0.0;
  }

  void onNewCameraSelected(CameraDescription cameraDescription) async {
    final previousCameraController = _cameraController;

    final CameraController cameraController = CameraController(
      cameraDescription,
      currentResolutionPreset,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await previousCameraController?.dispose();

    resetCameraValues();

    if (mounted) {
      setState(() {
        _cameraController = cameraController;
      });
    }

    // Update UI if controller updated
    cameraController.addListener(() {
      if (mounted) setState(() {});
    });

    try {
      await cameraController.initialize();
      await Future.wait([
        cameraController
            .getMinExposureOffset()
            .then((value) => _minAvailableExposureOffset = value),
        cameraController
            .getMaxExposureOffset()
            .then((value) => _maxAvailableExposureOffset = value),
        cameraController
            .getMaxZoomLevel()
            .then((value) => _maxAvailableZoom = value),
        cameraController
            .getMinZoomLevel()
            .then((value) => _minAvailableZoom = value),
      ]);

      _currentFlashMode = _cameraController!.value.flashMode;
    } on CameraException catch (e) {
      print('Error initializing camera: $e');
    }

    if (mounted) {
      setState(() {
        _isCameraInitialized = _cameraController!.value.isInitialized;
      });
    }
  }

  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (_cameraController == null) {
      return;
    }

    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    _cameraController!.setExposurePoint(offset);
    _cameraController!.setFocusPoint(offset);
  }

  

  Future initCamera(CameraDescription cameraDescription) async {
    _cameraController =
        CameraController(cameraDescription, ResolutionPreset.high);
    try {
      await _cameraController.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
      });
    } on CameraException catch (e) {
      debugPrint("camera error $e");
    }
  }

 @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _isCameraInitialized
                ? Column(
                    children: [
                      AspectRatio(
                        aspectRatio: 1 / _cameraController!.value.aspectRatio,
                        child: Stack(
                          children: [
                            CameraPreview(
                              _cameraController!,
                              child: LayoutBuilder(builder:
                                  (BuildContext context,
                                      BoxConstraints constraints) {
                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapDown: (details) =>
                                      onViewFinderTap(details, constraints),
                                );
                              }),
                            ),
                            // TODO: Uncomment to preview the overlay
                            // Center(
                            //   child: Image.asset(
                            //     'assets/camera_aim.png',
                            //     color: Colors.greenAccent,
                            //     width: 150,
                            //     height: 150,
                            //   ),
                            // ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16.0,
                                8.0,
                                16.0,
                                8.0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Align(
                                    alignment: Alignment.topRight,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius:
                                            BorderRadius.circular(10.0),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 8.0,
                                          right: 8.0,
                                        ),
                                        child: DropdownButton<ResolutionPreset>(
                                          dropdownColor: Colors.black87,
                                          underline: Container(),
                                          value: currentResolutionPreset,
                                          items: [
                                            for (ResolutionPreset preset
                                                in resolutionPresets)
                                              DropdownMenuItem(
                                                child: Text(
                                                  preset
                                                      .toString()
                                                      .split('.')[1]
                                                      .toUpperCase(),
                                                  style: TextStyle(
                                                      color: Colors.white),
                                                ),
                                                value: preset,
                                              )
                                          ],
                                          onChanged: (value) {
                                            setState(() {
                                              currentResolutionPreset = value!;
                                              _isCameraInitialized = false;
                                            });
                                            onNewCameraSelected(
                                                _cameraController!.description);
                                          },
                                          hint: Text("Select item"),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Spacer(),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        right: 8.0, top: 16.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(10.0),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Text(
                                          _currentExposureOffset
                                                  .toStringAsFixed(1) +
                                              'x',
                                          style: TextStyle(color: Colors.black),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: RotatedBox(
                                      quarterTurns: 3,
                                      child: Container(
                                        height: 30,
                                        child: Slider(
                                          value: _currentExposureOffset,
                                          min: _minAvailableExposureOffset,
                                          max: _maxAvailableExposureOffset,
                                          activeColor: Colors.white,
                                          inactiveColor: Colors.white30,
                                          onChanged: (value) async {
                                            setState(() {
                                              _currentExposureOffset = value;
                                            });
                                            await _cameraController!
                                                .setExposureOffset(value);
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Slider(
                                          value: _currentZoomLevel,
                                          min: _minAvailableZoom,
                                          max: _maxAvailableZoom,
                                          activeColor: Colors.white,
                                          inactiveColor: Colors.white30,
                                          onChanged: (value) async {
                                            setState(() {
                                              _currentZoomLevel = value;
                                            });
                                            await _cameraController!
                                                .setZoomLevel(value);
                                          },
                                        ),
                                      ),
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8.0),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black87,
                                            borderRadius:
                                                BorderRadius.circular(10.0),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Text(
                                              _currentZoomLevel
                                                      .toStringAsFixed(1) +
                                                  'x',
                                              style: TextStyle(
                                                  color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      InkWell(
                                        onTap: _isRecordingInProgress
                                            ? () async {
                                                if (_cameraController!
                                                    .value.isRecordingPaused) {
                                                  await resumeVideoRecording();
                                                } else {
                                                  await pauseVideoRecording();
                                                }
                                              }
                                            : () {
                                                setState(() {
                                                  _isCameraInitialized = false;
                                                });
                                                /*onNewCameraSelected(cameras[
                                                    _isRearCameraSelected
                                                        ? 1
                                                        : 0].description);*/
                                                setState(() {
                                                  _isRearCameraSelected =
                                                      !_isRearCameraSelected;
                                                });
                                              },
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Icon(
                                              Icons.circle,
                                              color: Colors.black38,
                                              size: 60,
                                            ),
                                            _isRecordingInProgress
                                                ? _cameraController!
                                                        .value.isRecordingPaused
                                                    ? Icon(
                                                        Icons.play_arrow,
                                                        color: Colors.white,
                                                        size: 30,
                                                      )
                                                    : Icon(
                                                        Icons.pause,
                                                        color: Colors.white,
                                                        size: 30,
                                                      )
                                                : Icon(
                                                    _isRearCameraSelected
                                                        ? Icons.camera_front
                                                        : Icons.camera_rear,
                                                    color: Colors.white,
                                                    size: 30,
                                                  ),
                                          ],
                                        ),
                                      ),
                                      InkWell(
                                        onTap: _isVideoCameraSelected
                                            ? () async {
                                                if (_isRecordingInProgress) {
                                                  XFile? rawVideo =
                                                      await stopVideoRecording();
                                                  File videoFile =
                                                      File(rawVideo!.path);

                                                  int currentUnix = DateTime
                                                          .now()
                                                      .millisecondsSinceEpoch;

                                                  final directory =
                                                      await getApplicationDocumentsDirectory();

                                                  String fileFormat = videoFile
                                                      .path
                                                      .split('.')
                                                      .last;

                                                  _videoFile =
                                                      await videoFile.copy(
                                                    '${directory.path}/$currentUnix.$fileFormat',
                                                  );

                                                  _startVideoPlayer();
                                                } else {
                                                  await startVideoRecording();
                                                }
                                              }
                                            : () async {
                                                XFile? rawImage =
                                                    await takePicture();
                                                File imageFile =
                                                    File(rawImage!.path);

                                                int currentUnix = DateTime.now()
                                                    .millisecondsSinceEpoch;

                                                final directory =
                                                    await getApplicationDocumentsDirectory();

                                                String fileFormat = imageFile
                                                    .path
                                                    .split('.')
                                                    .last;

                                                print(fileFormat);

                                                await imageFile.copy(
                                                  '${directory.path}/$currentUnix.$fileFormat',
                                                );

                                                refreshAlreadyCapturedImages();
                                              },
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Icon(
                                              Icons.circle,
                                              color: _isVideoCameraSelected
                                                  ? Colors.white
                                                  : Colors.white38,
                                              size: 80,
                                            ),
                                            Icon(
                                              Icons.circle,
                                              color: _isVideoCameraSelected
                                                  ? Colors.red
                                                  : Colors.white,
                                              size: 65,
                                            ),
                                            _isVideoCameraSelected &&
                                                    _isRecordingInProgress
                                                ? Icon(
                                                    Icons.stop_rounded,
                                                    color: Colors.white,
                                                    size: 32,
                                                  )
                                                : Container(),
                                          ],
                                        ),
                                      ),
                                      InkWell(
                                        onTap: _imageFile != null ||
                                                _videoFile != null
                                            ? () {
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        PreviewPage(
                                                      imageFile: _imageFile!,
                                                      fileList: allFileList,
                                                    ),
                                                  ),
                                                );
                                              }
                                            : null,
                                        child: Container(
                                          width: 60,
                                          height: 60,
                                          decoration: BoxDecoration(
                                            color: Colors.black,
                                            borderRadius:
                                                BorderRadius.circular(10.0),
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                            image: _imageFile != null
                                                ? DecorationImage(
                                                    image:
                                                        FileImage(_imageFile!),
                                                    fit: BoxFit.cover,
                                                  )
                                                : null,
                                          ),
                                          child: videoController != null &&
                                                  videoController!
                                                      .value.isInitialized
                                              ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          8.0),
                                                  child: AspectRatio(
                                                    aspectRatio:
                                                        videoController!
                                                            .value.aspectRatio,
                                                    child: VideoPlayer(
                                                        videoController!),
                                                  ),
                                                )
                                              : Container(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: BouncingScrollPhysics(),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 8.0,
                                          right: 4.0,
                                        ),
                                        child: TextButton(
                                          onPressed: _isRecordingInProgress
                                              ? null
                                              : () {
                                                  if (_isVideoCameraSelected) {
                                                    setState(() {
                                                      _isVideoCameraSelected =
                                                          false;
                                                    });
                                                  }
                                                },
                                          style: TextButton.styleFrom(
                                            primary: _isVideoCameraSelected
                                                ? Colors.black54
                                                : Colors.black,
                                            backgroundColor:
                                                _isVideoCameraSelected
                                                    ? Colors.white30
                                                    : Colors.white,
                                          ),
                                          child: Text('IMAGE'),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                            left: 4.0, right: 8.0),
                                        child: TextButton(
                                          onPressed: () {
                                            if (!_isVideoCameraSelected) {
                                              setState(() {
                                                _isVideoCameraSelected = true;
                                              });
                                            }
                                          },
                                          style: TextButton.styleFrom(
                                            primary: _isVideoCameraSelected
                                                ? Colors.black
                                                : Colors.black54,
                                            backgroundColor:
                                                _isVideoCameraSelected
                                                    ? Colors.white
                                                    : Colors.white30,
                                          ),
                                          child: Text('VIDEO'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    16.0, 8.0, 16.0, 8.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    InkWell(
                                      onTap: () async {
                                        setState(() {
                                          _currentFlashMode = FlashMode.off;
                                        });
                                        await _cameraController!.setFlashMode(
                                          FlashMode.off,
                                        );
                                      },
                                      child: Icon(
                                        Icons.flash_off,
                                        color:
                                            _currentFlashMode == FlashMode.off
                                                ? Colors.amber
                                                : Colors.white,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () async {
                                        setState(() {
                                          _currentFlashMode = FlashMode.auto;
                                        });
                                        await _cameraController!.setFlashMode(
                                          FlashMode.auto,
                                        );
                                      },
                                      child: Icon(
                                        Icons.flash_auto,
                                        color:
                                            _currentFlashMode == FlashMode.auto
                                                ? Colors.amber
                                                : Colors.white,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () async {
                                        setState(() {
                                          _currentFlashMode = FlashMode.always;
                                        });
                                        await _cameraController!.setFlashMode(
                                          FlashMode.always,
                                        );
                                      },
                                      child: Icon(
                                        Icons.flash_on,
                                        color: _currentFlashMode ==
                                                FlashMode.always
                                            ? Colors.amber
                                            : Colors.white,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () async {
                                        setState(() {
                                          _currentFlashMode = FlashMode.torch;
                                        });
                                        await _cameraController!.setFlashMode(
                                          FlashMode.torch,
                                        );
                                      },
                                      child: Icon(
                                        Icons.highlight,
                                        color:
                                            _currentFlashMode == FlashMode.torch
                                                ? Colors.amber
                                                : Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Text(
                      'LOADING',
                      style: TextStyle(color: Colors.white),
                    ),
                  )

      ),
    );
  }
}