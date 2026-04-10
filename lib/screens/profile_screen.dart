import 'package:flutter/material.dart';
import 'package:ciaccola_frontend/screens/login_screen.dart';
import 'package:ciaccola_frontend/services/auth_service.dart';
import 'package:ciaccola_frontend/services/connection_manager.dart';
import 'package:ciaccola_frontend/models/user.dart';

class ProfileScreen extends StatefulWidget {
  final String token;
  const ProfileScreen({super.key, required this.token});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  User? _user;
  bool _loading = true;
  String? _error;
  bool _updatingRole = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final user = await _authService.getProfile(widget.token);
      if (mounted) setState(() { _user = user; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _updateProfile() async {
    if (_user == null) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (password.isNotEmpty && password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    try {
      final updated = await _authService.updateProfile(
        widget.token,
        email: email != (_user!.email ?? '') ? email : null,
        password: password.isNotEmpty ? password : null,
      );
      if (mounted) {
        setState(() {
          _user = updated;
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    }
  }

  void _showEditProfileDialog() {
    _emailController.text = _user?.email ?? '';
    _passwordController.clear();
    _confirmPasswordController.clear();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'New password (leave blank to keep current)',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: _updateProfile, child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _updateRole(String newRole) async {
    setState(() => _updatingRole = true);
    try {
      final updated = await _authService.updateProfile(widget.token, role: newRole);
      if (mounted) setState(() => _user = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update subscription: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingRole = false);
    }
  }

  Future<void> _confirmRoleChange(String newRole) async {
    final isPremium = newRole == 'premium';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isPremium ? 'Upgrade to Premium' : 'Cancel Premium'),
        content: Text(
          isPremium
              ? 'You are about to upgrade your account to Premium.'
              : 'You are about to downgrade to the Standard plan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isPremium ? 'Upgrade' : 'Confirm'),
          ),
        ],
      ),
    );
    if (confirm == true) await _updateRole(newRole);
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure? This action cannot be undone and all your data will be permanently removed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _authService.deleteProfile(widget.token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted'), backgroundColor: Colors.green),
      );
      ConnectionManager().stop();
      await _authService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete account: $e')),
        );
      }
    }
  }

  Future<void> _logout() async {
    ConnectionManager().stop();
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Error: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _loadProfile, child: const Text('Retry')),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('Logout', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      );
    }

    final isPremium = _user?.role == 'premium';

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Profile Information',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _infoRow('Username', _user?.username ?? ''),
                  const SizedBox(height: 12),
                  _infoRow('Email', _user?.email ?? 'Not set'),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showEditProfileDialog,
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit Profile'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Subscription
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Subscription',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        isPremium ? Icons.star : Icons.star_border,
                        color: isPremium ? Colors.amber : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isPremium ? 'Premium' : 'Standard',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isPremium ? Colors.amber : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: _updatingRole
                        ? const Center(child: CircularProgressIndicator())
                        : isPremium
                            ? OutlinedButton.icon(
                                onPressed: () => _confirmRoleChange('standard'),
                                icon: const Icon(Icons.cancel_outlined),
                                label: const Text('Cancel Premium'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                ),
                              )
                            : FilledButton.icon(
                                onPressed: () => _confirmRoleChange('premium'),
                                icon: const Icon(Icons.star),
                                label: const Text('Upgrade to Premium'),
                              ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Delete Account', style: TextStyle(color: Colors.red)),
            subtitle: const Text('This action cannot be undone'),
            onTap: _deleteAccount,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
