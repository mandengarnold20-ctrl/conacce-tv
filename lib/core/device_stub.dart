bool _tv = false;

/// L'appli tourne-t-elle sur un téléviseur ?
bool get isTvDevice => _tv;

Future<void> detectDevice() async {
  _tv = false;
}
