import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:mis_medicamentos/screens/history/history_screen.dart';
import 'package:mis_medicamentos/screens/home/home_screen.dart';
import 'package:mis_medicamentos/screens/medications/my_medications_screen.dart';
import 'package:mis_medicamentos/screens/settings/settings_screen.dart';

class Material3BottomNav extends StatefulWidget {
  const Material3BottomNav({super.key});

  @override
  State<Material3BottomNav> createState() => _Material3BottomNavState();
}

class _Material3BottomNavState extends State<Material3BottomNav> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _buildPages()),
      bottomNavigationBar: NavigationBar(
        animationDuration: const Duration(seconds: 1),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        indicatorColor: Theme.of(context).colorScheme.primaryContainer,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: _navBarItems(context),
      ),
    );
  }

  List<Widget> _buildPages() {
    return const [
      HomeScreen(),
      MyMedicationsScreen(),
      HistoryScreen(),
      SettingsScreen(),
    ];
  }

  List<NavigationDestination> _navBarItems(BuildContext context) {
    final selectedIconColor = const Color(0xFF2F80ED);
    return <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded, color: selectedIconColor),
        label: 'Inicio',
      ),
      NavigationDestination(
        icon: const Icon(Symbols.pill, weight: 600),
        selectedIcon: Icon(Symbols.pill, fill: 1, color: selectedIconColor),
        label: 'Medicina',
      ),
      NavigationDestination(
        icon: const Icon(Icons.history_outlined),
        selectedIcon: Icon(Icons.history, color: selectedIconColor),
        label: 'Historial',
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings, color: selectedIconColor),
        label: 'Ajustes',
      ),
    ];
  }
}
