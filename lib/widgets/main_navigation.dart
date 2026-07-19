import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../screens/home/home_dashboard_screen.dart';
import '../screens/home/transaction_list_screen.dart';
import '../screens/home/add_transaction_screen.dart';
import '../screens/ai/ai_chat_screen.dart';
import '../screens/profile_screen.dart';

/// ============================================================
/// MAIN NAVIGATION
/// Bottom Navigation Bar: Home | Transactions | (+) | AI | Profile
/// ============================================================
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeDashboardScreen(),
    TransactionListScreen(),
    SizedBox.shrink(), // placeholder - nút giữa mở AddTransactionScreen dạng modal
    AiChatScreen(),
    ProfileScreen(),
  ];

  void _onTabTapped(int index) {
    if (index == 2) {
      // Nút "+" ở giữa - mở màn hình thêm giao dịch dạng modal
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
      );
      return;
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex == 2 ? 0 : _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex == 2 ? 0 : _currentIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Trang chủ'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'Giao dịch'),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle, size: 40, color: AppColors.primary),
            label: '',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_rounded), label: 'AI'),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Cá nhân'),
        ],
      ),
    );
  }
}
