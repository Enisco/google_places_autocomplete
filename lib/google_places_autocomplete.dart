library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_places_autocomplete/model/place_details.dart';
import 'package:google_places_autocomplete/model/place_type.dart';
import 'package:google_places_autocomplete/model/prediction.dart';
import 'package:rxdart/rxdart.dart';

import 'DioErrorHandler.dart';

class GooglePlaceAutoCompleteTextField extends StatefulWidget {
  final InputDecoration inputDecoration;
  final ItemClick? itemClick;
  final GetPlaceDetailswWithLatLng? getPlaceDetailWithLatLng;
  final bool isLatLngRequired;
  final TextStyle textStyle;
  final String googleAPIKey;
  final int debounceTime;
  final List<String>? countries;
  final TextEditingController textEditingController;
  final ListItemBuilder? itemBuilder;
  final Widget? seperatedBuilder;
  final void clearData;
  final BoxDecoration? boxDecoration;
  final bool isCrossBtnShown;
  final bool showError;
  final double? containerHorizontalPadding;
  final double? containerVerticalPadding;
  final FocusNode? focusNode;
  final PlaceType? placeType;
  final String? language;
  final TextInputAction? textInputAction;
  final VoidCallback? formSubmitCallback;

  final String? Function(String?, BuildContext)? validator;

  final double? latitude;
  final double? longitude;

  /// This is expressed in **meters**
  final int? radius;

  const GooglePlaceAutoCompleteTextField({
    super.key,
    required this.textEditingController,
    required this.googleAPIKey,
    this.debounceTime = 600,
    this.inputDecoration = const InputDecoration(),
    this.itemClick,
    this.isLatLngRequired = true,
    this.textStyle = const TextStyle(),
    this.countries,
    this.getPlaceDetailWithLatLng,
    this.itemBuilder,
    this.boxDecoration,
    this.isCrossBtnShown = true,
    this.seperatedBuilder,
    this.showError = true,
    this.containerHorizontalPadding,
    this.containerVerticalPadding,
    this.focusNode,
    this.placeType,
    this.language = 'en',
    this.validator,
    this.latitude,
    this.longitude,
    this.radius,
    this.formSubmitCallback,
    this.textInputAction,
    this.clearData,
  });

  @override
  _GooglePlaceAutoCompleteTextFieldState createState() =>
      _GooglePlaceAutoCompleteTextFieldState();
}

class _GooglePlaceAutoCompleteTextFieldState
    extends State<GooglePlaceAutoCompleteTextField> {
  final subject = PublishSubject<String>();
  OverlayEntry? _overlayEntry;
  List<Prediction> alPredictions = [];

  TextEditingController controller = TextEditingController();
  final LayerLink _layerLink = LayerLink();
  bool isSearched = false;

  bool isCrossBtn = true;
  late var _dio;

  CancelToken? _cancelToken = CancelToken();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.containerHorizontalPadding ?? 0,
          vertical: widget.containerVerticalPadding ?? 0,
        ),
        alignment: Alignment.centerLeft,
        decoration:
            widget.boxDecoration ??
            BoxDecoration(
              shape: BoxShape.rectangle,
              border: Border.all(color: Colors.grey, width: 0.6),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextFormField(
                decoration: widget.inputDecoration,
                style: widget.textStyle,
                controller: widget.textEditingController,
                focusNode: widget.focusNode ?? FocusNode(),
                textInputAction: widget.textInputAction ?? TextInputAction.done,
                onFieldSubmitted: (value) {
                  if (widget.formSubmitCallback != null) {
                    widget.formSubmitCallback!();
                  }
                },
                validator: (inputString) {
                  return widget.validator?.call(inputString, context);
                },
                onChanged: (string) {
                  subject.add(string);
                  if (widget.isCrossBtnShown) {
                    isCrossBtn = string.isNotEmpty ? true : false;
                    setState(() {});
                  }
                },
              ),
            ),
            (!widget.isCrossBtnShown)
                ? SizedBox()
                : isCrossBtn && _showCrossIconWidget()
                ? IconButton(onPressed: clearData, icon: Icon(Icons.close))
                : SizedBox(),
          ],
        ),
      ),
    );
  }

  // Fixed getLocation method
  getLocation(String text) async {
    print("🔍 Making API request for: '$text'");

    String apiURL =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$text&key=${widget.googleAPIKey}&language=${widget.language}";

    if (widget.countries != null) {
      for (int i = 0; i < widget.countries!.length; i++) {
        String country = widget.countries![i];
        if (i == 0) {
          apiURL = "$apiURL&components=country:$country";
        } else {
          apiURL = "$apiURL|country:$country";
        }
      }
    }

    if (widget.placeType != null) {
      apiURL += "&types=${widget.placeType?.apiString}";
    }

    if (widget.latitude != null &&
        widget.longitude != null &&
        widget.radius != null) {
      apiURL =
          "$apiURL&location=${widget.latitude},${widget.longitude}&radius=${widget.radius}";
    }

    if (_cancelToken?.isCancelled == false) {
      _cancelToken?.cancel();
      _cancelToken = CancelToken();
    }

    print("📡 API URL: $apiURL");

    try {
      String proxyURL = "https://cors-anywhere.herokuapp.com/";
      String url = kIsWeb ? proxyURL + apiURL : apiURL;

      print("🌐 Final URL: $url");
      print("⏳ Sending request...");

      Response response = await _dio.get(url, cancelToken: _cancelToken);

      print("✅ Response received: ${response.statusCode}");
      print("📄 Response data: ${response.data}");

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Map map = response.data;
      if (map.containsKey("error_message")) {
        print("❌ API returned error: ${map['error_message']}");
        throw response.data;
      }

      PlacesAutocompleteResponse subscriptionResponse =
          PlacesAutocompleteResponse.fromJson(response.data);

      if (text.isEmpty) {
        print("📝 Text became empty during request, clearing overlay");
        alPredictions.clear();
        _removeOverlay();
        return;
      }

      isSearched = false;
      alPredictions.clear();

      if (subscriptionResponse.predictions!.isNotEmpty &&
          (widget.textEditingController.text.toString().trim()).isNotEmpty) {
        alPredictions.addAll(subscriptionResponse.predictions!);
        print("📍 Found ${alPredictions.length} predictions");
      } else {
        print("📍 No predictions found");
      }

      _showOverlay();
    } catch (e) {
      print("❌ API Error: $e");
      var errorHandler = ErrorHandler.internal().handleError(e);
      _showSnackBar("${errorHandler.message}");
    }
  }

  // Helper method to show overlay
  void _showOverlay() {
    _removeOverlay(); // Remove existing overlay first

    if (alPredictions.isNotEmpty) {
      _overlayEntry = _createOverlayEntry();
      if (_overlayEntry != null) {
        Overlay.of(context).insert(_overlayEntry!);
        print("✨ Overlay shown with ${alPredictions.length} items");
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _dio = Dio();
    subject.stream
        .distinct()
        .debounceTime(Duration(milliseconds: widget.debounceTime))
        .listen(textChanged);
  }

  textChanged(String text) async {
    print("🔄 Text changed: '$text'");

    if (text.isNotEmpty) {
      getLocation(text);
    } else {
      print("📝 Text is empty, clearing predictions");
      alPredictions.clear();
      _removeOverlay();
    }
  }

  // Helper method to safely remove overlay
  void _removeOverlay() {
    if (_overlayEntry != null) {
      try {
        _overlayEntry!.remove();
        _overlayEntry = null;
        print("🗑️ Overlay removed");
      } catch (e) {
        print("⚠️ Error removing overlay: $e");
      }
    }
  }

  OverlayEntry? _createOverlayEntry() {
    if (context.findRenderObject() != null) {
      RenderBox renderBox = context.findRenderObject() as RenderBox;
      var size = renderBox.size;
      var offset = renderBox.localToGlobal(Offset.zero);
      return OverlayEntry(
        builder: (context) => Positioned(
          left: offset.dx,
          top: size.height + offset.dy,
          width: size.width,
          child: CompositedTransformFollower(
            showWhenUnlinked: false,
            link: _layerLink,
            offset: Offset(0.0, size.height + 5.0),
            child: Material(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: alPredictions.length,
                separatorBuilder: (context, pos) =>
                    widget.seperatedBuilder ?? SizedBox(),
                itemBuilder: (BuildContext context, int index) {
                  return InkWell(
                    onTap: () async {
                      var selectedData = alPredictions[index];
                      if (index < alPredictions.length) {
                        widget.itemClick!(selectedData);

                        if (widget.isLatLngRequired) {
                          await getPlaceDetailsFromPlaceId(selectedData);
                        }
                        removeOverlay();
                      }
                    },
                    child: widget.itemBuilder != null
                        ? widget.itemBuilder!(
                            context,
                            index,
                            alPredictions[index],
                          )
                        : Container(
                            padding: EdgeInsets.all(10),
                            child: Text(alPredictions[index].description!),
                          ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }
    return null;
  }

  removeOverlay() {
    alPredictions.clear();
    _overlayEntry = _createOverlayEntry();

    Overlay.of(context).insert(_overlayEntry!);
    _overlayEntry!.markNeedsBuild();
  }

  Future<void> getPlaceDetailsFromPlaceId(Prediction prediction) async {
    //String key = GlobalConfiguration().getString('google_maps_key');

    var url =
        "https://maps.googleapis.com/maps/api/place/details/json?placeid=${prediction.placeId}&key=${widget.googleAPIKey}";
    try {
      Response response = await _dio.get(url);

      PlaceDetails placeDetails = PlaceDetails.fromJson(response.data);

      prediction.lat = placeDetails.result!.geometry!.location!.lat.toString();
      prediction.lng = placeDetails.result!.geometry!.location!.lng.toString();

      widget.getPlaceDetailWithLatLng!(prediction);
    } catch (e) {
      var errorHandler = ErrorHandler.internal().handleError(e);
      _showSnackBar("${errorHandler.message}");
    }
  }

  // Fixed clearData method
  void clearData() {
    widget.textEditingController.clear();
    if (_cancelToken?.isCancelled == false) {
      _cancelToken?.cancel();
    }

    setState(() {
      alPredictions.clear();
      isCrossBtn = false;
    });

    _removeOverlay();
    print("🧽 All data cleared");
  }

  _showCrossIconWidget() {
    return (widget.textEditingController.text.isNotEmpty);
  }

  _showSnackBar(String errorData) {
    if (widget.showError) {
      final snackBar = SnackBar(content: Text(errorData));

      // Find the ScaffoldMessenger in the widget tree
      // and use it to show a SnackBar.
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
  }
}

PlacesAutocompleteResponse parseResponse(Map responseBody) {
  return PlacesAutocompleteResponse.fromJson(
    responseBody as Map<String, dynamic>,
  );
}

PlaceDetails parsePlaceDetailMap(Map responseBody) {
  return PlaceDetails.fromJson(responseBody as Map<String, dynamic>);
}

typedef ItemClick = void Function(Prediction postalCodeResponse);
typedef GetPlaceDetailswWithLatLng =
    void Function(Prediction postalCodeResponse);

typedef ListItemBuilder =
    Widget Function(BuildContext context, int index, Prediction prediction);
