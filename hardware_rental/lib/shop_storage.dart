abstract interface class ShopStorage {
  Map<String, dynamic> read();
  void write(Map<String, dynamic> data);
  void close();
}
