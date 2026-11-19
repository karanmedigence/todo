import 'package:material_ui/material_ui.dart';
import 'package:frontend/auth/presentation/auth_gate.dart';
import 'package:frontend/core/bloc/bloc_engine.dart';
import 'package:frontend/di/injection.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupDependencies();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const BlocEngine(child: MaterialApp(home: AuthGate()));
  }
}
   