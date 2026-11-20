import 'package:flutter/widgets.dart';

class EspacioPublicitario extends StatelessWidget {
  const EspacioPublicitario({super.key, required this.hueco, required this.ancho, required this.alto});
  final String hueco;
  final double ancho, alto;

  static bool get activo => false;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
