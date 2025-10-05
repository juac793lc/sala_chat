import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/chat_principal_screen.dart';
import 'screens/simple_chat_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'services/platform_audio_service.dart';

void main() {
  // Inicializar el servicio de audio para la plataforma correcta
  PlatformAudioService.initialize();
  
  runApp(const SalaChatApp());
}

class SalaChatApp extends StatelessWidget {
  const SalaChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: MaterialApp(
        title: 'Sala Chat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
          fontFamily: 'System',
        ),
        home: const AuthChecker(),
        routes: {
          '/welcome': (context) => const WelcomeScreen(),
          '/chat': (context) => const ChatPrincipalScreen(),
          '/simple-chat': (context) => const SimpleChatScreen(),
        },
      ),
    );
  }
}

// Widget para verificar el estado de autenticación
class AuthChecker extends StatefulWidget {
  const AuthChecker({super.key});

  @override
  State<AuthChecker> createState() => _AuthCheckerState();
}

class _AuthCheckerState extends State<AuthChecker> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    
    // Usar addPostFrameCallback para evitar setState durante build
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Verificar si hay una sesión guardada
      await authProvider.initAuth();
      
      // Inicializar chat provider
      chatProvider.init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Mostrar splash mientras carga
        if (authProvider.isLoading) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Cargando...'),
                ],
              ),
            ),
          );
        }

        // Si está autenticado, ir al chat principal (con mapa y videos)
        if (authProvider.isAuthenticated) {
          return const ChatPrincipalScreen();
        }

        // Si no está autenticado, mostrar pantalla de bienvenida
        return const WelcomeScreen();
      },
    );
  }
}
