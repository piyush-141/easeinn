import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/property.dart';
import 'hotel_store.dart';

class AuthResult {
  final bool success;
  final String? errorMessage;
  final bool requiresEmailConfirmation;
  final User? user;

  AuthResult({
    required this.success,
    this.errorMessage,
    this.requiresEmailConfirmation = false,
    this.user,
  });
}

class AuthService {
  static const String _keyOnboardingCompleted =
      'easeinn_onboarding_completed_v1';
  static const String _keyIsAuthenticated = 'easeinn_is_authenticated_v1';
  static const String _keyUserEmail = 'easeinn_user_email';
  static const String _keyUserName = 'easeinn_user_name';
  static const String _keyUserRole = 'easeinn_user_role';
  static const String _keyPropertyName = 'easeinn_property_name';
  static const String _keyPropertyId = 'easeinn_property_id';

  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// Check whether first-time onboarding has been shown/completed
  Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboardingCompleted) ?? false;
  }

  /// Mark onboarding as completed
  Future<void> setCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingCompleted, true);
  }

  /// Reset onboarding (useful for testing or switching accounts)
  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyOnboardingCompleted);
  }

  /// Update cached property details when switching properties
  Future<void> updateCachedProperty(
    String propertyId,
    String propertyName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPropertyId, propertyId);
    await prefs.setString(_keyPropertyName, propertyName);
  }

  /// Update cached manager profile details when edited in ManagerProfileScreen
  Future<void> updateCachedProfile({
    required String name,
    required String role,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserName, name);
    await prefs.setString(_keyUserRole, role);
    await prefs.setString(_keyUserEmail, email);
  }

  /// Check if user has an active, valid session
  Future<bool> checkInitialSession(HotelStore store) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Check Supabase session first if connected
    final client = SupabaseConfig.client;
    if (client != null && client.auth.currentSession != null) {
      try {
        final user = client.auth.currentUser;
        if (user != null) {
          final userEmail = user.email?.trim().toLowerCase() ?? '';

          // Built-in offline demo account
          if (userEmail == 'frontdesk@easeinn.com') {
            store.loadDemoAccount();
            await prefs.setBool(_keyIsAuthenticated, true);
            return true;
          }

          // Real user session: fetch profile and linked property
          Map<String, dynamic>? profileRes;
          try {
            profileRes = await client
                .from('user_profiles')
                .select('full_name, role, property_id, properties(*)')
                .eq('id', user.id)
                .maybeSingle();
          } catch (e) {
            debugPrint('[AuthService] Supabase profile fetch notice: $e');
          }

          final fullName =
              profileRes?['full_name'] as String? ??
              prefs.getString(_keyUserName) ??
              'General Manager';
          final role =
              profileRes?['role'] as String? ??
              prefs.getString(_keyUserRole) ??
              'General Manager / Owner';
          final propData = profileRes?['properties'] as Map<String, dynamic>?;

          // Determine property ID - NEVER allow prop-001 for real users!
          var assignedPropId =
              profileRes?['property_id']?.toString() ??
              propData?['id']?.toString() ??
              prefs.getString(_keyPropertyId);

          if (assignedPropId == null || assignedPropId == 'prop-001') {
            assignedPropId =
                'prop-${user.id.length >= 8 ? user.id.substring(0, 8) : userEmail.hashCode.abs()}';
            await prefs.setString(_keyPropertyId, assignedPropId);
          }

          final propName =
              propData?['name']?.toString() ??
              prefs.getString(_keyPropertyName) ??
              'My Hotel';

          final prop = Property(
            id: assignedPropId,
            name: propName,
            address: propData?['address']?.toString() ?? '',
            city: propData?['city']?.toString() ?? 'Bengaluru',
            state: propData?['state']?.toString() ?? 'Karnataka',
            pincode: propData?['pincode']?.toString() ?? '560001',
            phone: propData?['phone']?.toString() ?? '',
            email: propData?['email']?.toString() ?? userEmail,
            totalRooms: 12,
            upiId: 'piyushpal427@okaxis',
            upiPayeeName: propName,
          );

          // CRITICAL: Initialize 100% clean account with ZERO demo seed data!
          store.initCleanAccount(
            property: prop,
            managerName: fullName,
            managerEmail: userEmail,
            managerPhone: store.staffPhone,
            managerRole: role,
          );

          await _saveSessionLocally(
            email: userEmail,
            name: fullName,
            role: role,
            propertyName: propName,
            propertyId: assignedPropId,
          );

          store.isAuthenticated = true;
          await prefs.setBool(_keyIsAuthenticated, true);
          return true;
        }
      } catch (e) {
        debugPrint('[AuthService] Supabase profile fetch fallback: $e');
      }
    }

    // 2. Check cached local session
    final isAuth = prefs.getBool(_keyIsAuthenticated) ?? false;
    if (isAuth) {
      final cachedName = prefs.getString(_keyUserName);
      final cachedEmail = prefs.getString(_keyUserEmail);
      final cachedRole = prefs.getString(_keyUserRole);
      final cachedPropName = prefs.getString(_keyPropertyName);
      var cachedPropId = prefs.getString(_keyPropertyId);

      // Demo account
      if (cachedEmail != null &&
          cachedEmail.trim().toLowerCase() == 'frontdesk@easeinn.com') {
        store.loadDemoAccount();
        return true;
      }

      // Real user account
      if (cachedEmail != null && cachedEmail.isNotEmpty) {
        if (cachedPropId == null || cachedPropId == 'prop-001') {
          cachedPropId =
              'prop-${cachedEmail.trim().toLowerCase().hashCode.abs()}';
          await prefs.setString(_keyPropertyId, cachedPropId);
        }

        final prop = Property(
          id: cachedPropId,
          name: cachedPropName ?? 'My Hotel',
          address: '',
          city: 'Bengaluru',
          state: 'Karnataka',
          pincode: '560001',
          phone: '',
          email: cachedEmail,
          totalRooms: 12,
          upiId: 'piyushpal427@okaxis',
          upiPayeeName: cachedPropName ?? 'My Hotel',
        );

        // CRITICAL: Initialize 100% clean account with ZERO demo seed data!
        store.initCleanAccount(
          property: prop,
          managerName: cachedName ?? 'General Manager',
          managerEmail: cachedEmail,
          managerPhone: store.staffPhone,
          managerRole: cachedRole ?? 'General Manager / Owner',
        );
        return true;
      }
    }

    store.isAuthenticated = false;
    return false;
  }

  /// Sign In with Email and Password
  Future<AuthResult> signIn({
    required String email,
    required String password,
    required HotelStore store,
  }) async {
    final trimmedEmail = email.trim().toLowerCase();
    final client = SupabaseConfig.client;

    // Check online Supabase sign in
    if (client != null) {
      try {
        final authResponse = await client.auth.signInWithPassword(
          email: trimmedEmail,
          password: password,
        );

        if (authResponse.user != null) {
          final user = authResponse.user!;

          // If demo account
          if (trimmedEmail == 'frontdesk@easeinn.com') {
            store.loadDemoAccount();
            await _saveSessionLocally(
              email: trimmedEmail,
              name: 'Devika Rao',
              role: 'General Manager',
              propertyName: 'EaseInn Boutique & Suites',
              propertyId: 'prop-001',
            );
            return AuthResult(success: true, user: user);
          }

          // Real user sign in
          String activePropId =
              'prop-${user.id.length >= 8 ? user.id.substring(0, 8) : trimmedEmail.hashCode.abs()}';
          String activePropName = 'My Hotel';
          String fullName = 'General Manager';
          String role = 'General Manager / Owner';
          String phone = '';

          try {
            final profileRes = await client
                .from('user_profiles')
                .select('full_name, role, property_id, properties(*)')
                .eq('id', user.id)
                .maybeSingle();

            if (profileRes != null) {
              fullName = profileRes['full_name'] as String? ?? fullName;
              role = profileRes['role'] as String? ?? role;
              final propData =
                  profileRes['properties'] as Map<String, dynamic>?;
              activePropId =
                  profileRes['property_id']?.toString() ??
                  propData?['id']?.toString() ??
                  activePropId;

              if (propData != null) {
                activePropName = propData['name']?.toString() ?? activePropName;
                phone = propData['phone']?.toString() ?? phone;
              }
            }
          } catch (e) {
            debugPrint('[AuthService] Profile retrieval warning: $e');
          }

          final prop = Property(
            id: activePropId,
            name: activePropName,
            address: '',
            city: 'Bengaluru',
            state: 'Karnataka',
            pincode: '560001',
            phone: phone,
            email: trimmedEmail,
            totalRooms: 12,
            upiId: 'piyushpal427@okaxis',
            upiPayeeName: activePropName,
          );

          // CRITICAL: Initialize clean account with ZERO demo seed data!
          store.initCleanAccount(
            property: prop,
            managerName: fullName,
            managerEmail: trimmedEmail,
            managerPhone: phone.isNotEmpty ? phone : store.staffPhone,
            managerRole: role,
          );

          await _saveSessionLocally(
            email: trimmedEmail,
            name: fullName,
            role: role,
            propertyName: activePropName,
            propertyId: activePropId,
          );

          return AuthResult(success: true, user: authResponse.user);
        }
      } on AuthException catch (e) {
        debugPrint('[AuthService] Supabase AuthException: ${e.message}');
        // If not demo credentials, return the real error
        if (trimmedEmail != 'frontdesk@easeinn.com') {
          return AuthResult(success: false, errorMessage: e.message);
        }
      } catch (e) {
        debugPrint('[AuthService] Network/Auth error: $e');
        if (trimmedEmail != 'frontdesk@easeinn.com') {
          return AuthResult(
            success: false,
            errorMessage: 'Network error: Please verify your connection.',
          );
        }
      }
    }

    // Offline / Demo account fallback - STRICTLY frontdesk@easeinn.com with easeinn2026
    if (trimmedEmail == 'frontdesk@easeinn.com' && password == 'easeinn2026') {
      store.loadDemoAccount();
      await _saveSessionLocally(
        email: 'frontdesk@easeinn.com',
        name: 'Devika Rao',
        role: 'General Manager',
        propertyName: 'EaseInn Boutique & Suites',
        propertyId: 'prop-001',
      );
      return AuthResult(success: true);
    }

    // Offline / Locally registered account fallback
    final prefs = await SharedPreferences.getInstance();
    final cachedEmail = prefs.getString(_keyUserEmail);
    if (cachedEmail != null &&
        cachedEmail.trim().toLowerCase() == trimmedEmail) {
      final cachedName = prefs.getString(_keyUserName) ?? 'General Manager';
      final cachedRole =
          prefs.getString(_keyUserRole) ?? 'General Manager / Owner';
      final cachedPropName = prefs.getString(_keyPropertyName) ?? 'My Hotel';
      var cachedPropId = prefs.getString(_keyPropertyId);
      if (cachedPropId == null || cachedPropId == 'prop-001') {
        cachedPropId = 'prop-${trimmedEmail.hashCode.abs()}';
        await prefs.setString(_keyPropertyId, cachedPropId);
      }

      final prop = Property(
        id: cachedPropId,
        name: cachedPropName,
        address: '',
        city: 'Bengaluru',
        state: 'Karnataka',
        pincode: '560001',
        phone: '',
        email: trimmedEmail,
        totalRooms: 12,
        upiId: 'piyushpal427@okaxis',
        upiPayeeName: cachedPropName,
      );

      store.initCleanAccount(
        property: prop,
        managerName: cachedName,
        managerEmail: trimmedEmail,
        managerPhone: store.staffPhone,
        managerRole: cachedRole,
      );

      await prefs.setBool(_keyIsAuthenticated, true);
      return AuthResult(success: true);
    }

    return AuthResult(
      success: false,
      errorMessage: 'Invalid email or password. Please check your credentials.',
    );
  }

  /// Sign Up Hotel & Manager Account
  Future<AuthResult> signUpHotel({
    required String fullName,
    required String email,
    required String password,
    required String phone,
    required String hotelName,
    required String city,
    required String state,
    required String address,
    required int totalRooms,
    required String upiId,
    required String upiPayeeName,
    required HotelStore store,
  }) async {
    final trimmedEmail = email.trim().toLowerCase();
    final client = SupabaseConfig.client;

    if (client != null) {
      try {
        // 1. Supabase Auth Sign Up
        final authResponse = await client.auth.signUp(
          email: trimmedEmail,
          password: password,
          data: {
            'full_name': fullName.trim(),
            'phone': phone.trim(),
            'hotel_name': hotelName.trim(),
          },
        );

        final user = authResponse.user;
        if (user != null) {
          // 2. Insert into properties table
          String? createdPropertyId;
          try {
            final propertyInsert = await client
                .from('properties')
                .insert({
                  'name': hotelName.trim(),
                  'city': city.trim(),
                  'state': state.trim(),
                  'address': address.trim(),
                  'phone': phone.trim(),
                  'email': trimmedEmail,
                  'currency': 'INR',
                  'timezone': 'Asia/Kolkata',
                })
                .select('id')
                .single();

            createdPropertyId = propertyInsert['id']?.toString();

            // 3. Insert into user_profiles table
            await client.from('user_profiles').insert({
              'id': user.id,
              if (createdPropertyId != null) 'property_id': createdPropertyId,
              'full_name': fullName.trim(),
              'role': 'admin',
              'is_active': true,
            });
          } catch (dbErr) {
            debugPrint('[AuthService] Database record creation notice: $dbErr');
          }

          // 4. Update local HotelStore state with guaranteed clean property
          final assignedPropId =
              createdPropertyId ??
              'prop-${DateTime.now().millisecondsSinceEpoch}';
          final newProp = Property(
            id: assignedPropId,
            name: hotelName.trim(),
            city: city.trim(),
            state: state.trim(),
            address: address.trim(),
            pincode: '560001',
            phone: phone.trim(),
            email: trimmedEmail,
            totalRooms: totalRooms > 0 ? totalRooms : 12,
            upiId: upiId.trim().isNotEmpty
                ? upiId.trim()
                : 'piyushpal427@okaxis',
            upiPayeeName: upiPayeeName.trim().isNotEmpty
                ? upiPayeeName.trim()
                : hotelName.trim(),
          );

          // CRITICAL: Initialize 100% clean account with ZERO demo seed data!
          store.initCleanAccount(
            property: newProp,
            managerName: fullName.trim(),
            managerEmail: trimmedEmail,
            managerPhone: phone.trim(),
            managerRole: 'General Manager / Owner',
          );

          await _saveSessionLocally(
            email: trimmedEmail,
            name: fullName.trim(),
            role: 'General Manager / Owner',
            propertyName: newProp.name,
            propertyId: newProp.id,
          );

          // Check if session was granted immediately (auto-confirm on Supabase)
          final hasSession = authResponse.session != null;

          return AuthResult(
            success: true,
            user: user,
            requiresEmailConfirmation: !hasSession,
          );
        }
      } on AuthException catch (e) {
        debugPrint('[AuthService] SignUp AuthException: ${e.message}');
        return AuthResult(success: false, errorMessage: e.message);
      } catch (e) {
        debugPrint('[AuthService] SignUp error: $e');
        return AuthResult(
          success: false,
          errorMessage: 'Could not complete registration: ${e.toString()}',
        );
      }
    }

    // Offline / Local registration mode
    final assignedPropId = 'prop-${DateTime.now().millisecondsSinceEpoch}';
    final newProp = Property(
      id: assignedPropId,
      name: hotelName.trim(),
      city: city.trim(),
      state: state.trim(),
      address: address.trim(),
      pincode: '560001',
      phone: phone.trim(),
      email: trimmedEmail,
      totalRooms: totalRooms > 0 ? totalRooms : 12,
      upiId: upiId.trim().isNotEmpty ? upiId.trim() : 'piyushpal427@okaxis',
      upiPayeeName: upiPayeeName.trim().isNotEmpty
          ? upiPayeeName.trim()
          : hotelName.trim(),
    );

    // CRITICAL: Initialize 100% clean account with ZERO demo seed data!
    store.initCleanAccount(
      property: newProp,
      managerName: fullName.trim(),
      managerEmail: trimmedEmail,
      managerPhone: phone.trim(),
      managerRole: 'General Manager / Owner',
    );

    await _saveSessionLocally(
      email: trimmedEmail,
      name: fullName.trim(),
      role: 'General Manager / Owner',
      propertyName: newProp.name,
      propertyId: newProp.id,
    );

    return AuthResult(success: true);
  }

  /// Sign Out
  Future<void> signOut(HotelStore store) async {
    final prefs = await SharedPreferences.getInstance();
    final client = SupabaseConfig.client;

    try {
      if (client != null) {
        await client.auth.signOut();
      }
    } catch (e) {
      debugPrint('[AuthService] SignOut error: $e');
    }

    await prefs.setBool(_keyIsAuthenticated, false);
    await prefs.remove(_keyUserEmail);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyUserRole);
    await prefs.remove(_keyPropertyName);
    await prefs.remove(_keyPropertyId);

    store.logout();
  }

  Future<void> _saveSessionLocally({
    required String email,
    required String name,
    required String role,
    required String propertyName,
    required String propertyId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsAuthenticated, true);
    await prefs.setString(_keyUserEmail, email);
    await prefs.setString(_keyUserName, name);
    await prefs.setString(_keyUserRole, role);
    await prefs.setString(_keyPropertyName, propertyName);
    await prefs.setString(_keyPropertyId, propertyId);
  }
}
