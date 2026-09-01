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

  Widget _buildNavItem(int index, IconData inactiveIcon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: () => _onTabTapped(index),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              color: color,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex == 2 ? 0 : _currentIndex,
        children: _screens,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onTabTapped(2),
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        elevation: 4,
        child: const Icon(
          Icons.add,
          color: Colors.white,
          size: 28,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 8,
        height: 72,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Trang chủ'),
            _buildNavItem(1, Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Giao dịch'),
            const SizedBox(width: 68), // Khoảng trống cho nút "+" nổi ở giữa
            _buildNavItem(3, Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'Trợ lý AI'),
            _buildNavItem(4, Icons.person_outline_rounded, Icons.person_rounded, 'Cá nhân'),
          ],
        ),
      ),
    );
  }
}
