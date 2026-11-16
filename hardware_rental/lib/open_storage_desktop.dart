import 'package:path_provider/path_provider.dart';

import 'local_database.dart';
import 'shop_storage.dart';

Future<ShopStorage> openStorage() async {
  final folder = await getApplicationSupportDirectory();
  await folder.create(recursive: true);
  return LocalDatabase('${folder.path}/hardware_rental.sqlite');
}
