import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'my_app.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  // End locations
  runApp(MyApp());


}