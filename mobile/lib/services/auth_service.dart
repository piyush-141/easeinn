import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'supabase_sync_service.dart';
import 'whatsapp_service.dart';
import '../models/property.dart';
import 'hotel_store.dart';

class AuthResult {
  final bool success;
  final String? errorMessage;
  final bool requiresEmailConfirmation;
  final String? email;
  final User? user;

  AuthResult({
    required this.success,
    this.errorMessage,
    this.requiresEmailConfirmation = false,
    this.email,
    this.user,
  });
}

class AuthService {
  static const String _keyOnboardingCompleted = 'easeinn_onboarding_completed_v1';
  static const String _keyIsAuthenticated = 'easeinn_is_authenticated_v1';
  static const String _keyUserEmail = 'easeinn_user_email';
  static const String _keyUserName = 'easeinn_user_name';
  static const String _keyUserRole = 'easeinn_user_role';
  static const String _keyPropertyName = 'easeinn_property_name';
  static const String _keyPropertyId = 'easeinn_property_id';

  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboardingCompleted) ?? false;
  }

  Future<void> setCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingCompleted, true);
  }

  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyOnboardingCompleted);
  }

  Future<void> updateCachedProperty(String propertyId, String propertyName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPropertyId, propertyId);
    await prefs.setString(_keyPropertyName, propertyName);
    WhatsAppService.currentHotelId = propertyId;
  }

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

  // ─────────────────────────────────────────────────────────
  // CORE FIX: Resolve property ID with a strict priority chain.
  // The property ID MUST be stable across every sign-in so that
  // the local cache key never changes. Priority:
  //   1. Supabase user_profiles.property_id  (real UUID from DB)
  //   2. Cached property ID in SharedPrefs   (already stored UUID)
  //   3. Never generate a hash-based fallback for real users
  // ─────────────────────────────────────────────────────────
  Future<String?> _resolveStablePropertyId({
    required String userId,
    required String userEmail,
    required SharedPreferences prefs,
    Map<String, dynamic>? profileRes,
  }) async {
    // 1. Supabase DB is the canonical source
    final dbPropId =
        profileRes?['property_id']?.toString() ??
        (profileRes?['properties'] as Map<String, dynamic>?)?['id']?.toString();
    if (dbPropId != null && dbPropId.isNotEmpty && dbPropId != 'prop-001') {
      // Persist so it's available offline
      await prefs.setString(_keyPropertyId, dbPropId);
      return dbPropId;
    }

    // 2. Previously cached stable ID (e.g., from a prior online login)
    final cachedId = prefs.getString(_keyPropertyId);
    if (cachedId != null && cachedId.isNotEmpty && cachedId != 'prop-001') {
      return cachedId;
    }

    // 3. No stable ID yet — return null; caller handles new account flow
    return null;
  }

  /// Check whether an active Supabase or local session exists on app start
  Future<bool> checkInitialSession(HotelStore store) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Try Supabase session
    final client = SupabaseConfig.client;
    if (client != null && client.auth.currentSession != null) {
      try {
        if (client.auth.currentSession!.isExpired) {
          try {
            await client.auth.refreshSession();
          } catch (refreshErr) {
            debugPrint('[AuthService] Auto-refresh session notice: $refreshErr');
          }
        }
        final user = client.auth.currentUser;
        if (user != null) {
          final userEmail = user.email?.trim().toLowerCase() ?? '';

          if (userEmail == 'frontdesk@easeinn.com') {
            store.loadDemoAccount();
            await prefs.setBool(_keyIsAuthenticated, true);
            return true;
          }

          Map<String, dynamic>? profileRes;
          try {
            profileRes = await client
                .from('user_profiles')
                .select('full_name, role, property_id, properties(*)')
                .eq('id', user.id)
                .maybeSingle();
          } catch (e) {
            debugPrint('[AuthService] Profile fetch notice: $e');
          }

          final fullName = profileRes?['full_name'] as String? ??
              prefs.getString(_keyUserName) ?? 'General Manager';
          final role = profileRes?['role'] as String? ??
              prefs.getString(_keyUserRole) ?? 'General Manager / Owner';
          final propData = profileRes?['properties'] as Map<String, dynamic>?;

          final assignedPropId = await _resolveStablePropertyId(
            userId: user.id,
            userEmail: userEmail,
            prefs: prefs,
            profileRes: profileRes,
          );

          if (assignedPropId == null) {
            // No property linked — user needs to complete onboarding
            debugPrint('[AuthService] No property linked for user $userEmail');
            store.isAuthenticated = false;
            return false;
          }

          // Merge: local cache has the most up-to-date property details
          // (user may have changed name etc. locally). Use local cache for
          // details but always use the stable assignedPropId as key.
          final propName = propData?['name']?.toString() ??
              prefs.getString(_keyPropertyName) ?? 'My Hotel';

          final prop = Property(
            id: assignedPropId,
            name: propName,
            address: propData?['address']?.toString() ?? '',
            city: propData?['city']?.toString() ?? '',
            state: propData?['state']?.toString() ?? '',
            pincode: propData?['pincode']?.toString() ?? '',
            phone: propData?['phone']?.toString() ?? '',
            email: propData?['email']?.toString() ?? userEmail,
            totalRooms: 12,
            upiId: propData?['upi_id']?.toString() ?? '',
            upiPayeeName: propData?['upi_payee_name']?.toString() ?? propName,
          );

          await store.loadForProperty(
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
        debugPrint('[AuthService] Session check fallback: $e');
      }
    }

    // 2. Offline local session
    final isAuth = prefs.getBool(_keyIsAuthenticated) ?? false;
    if (!isAuth) return false;

    final cachedEmail = prefs.getString(_keyUserEmail);
    final cachedName = prefs.getString(_keyUserName);
    final cachedRole = prefs.getString(_keyUserRole);
    final cachedPropName = prefs.getString(_keyPropertyName);
    final cachedPropId = prefs.getString(_keyPropertyId);

    if (cachedEmail == null || cachedEmail.isEmpty) return false;

    if (cachedEmail.trim().toLowerCase() == 'frontdesk@easeinn.com') {
      store.loadDemoAccount();
      return true;
    }

    // Must have a stable property ID saved from a previous online login
    if (cachedPropId == null || cachedPropId.isEmpty || cachedPropId == 'prop-001') {
      debugPrint('[AuthService] Offline session: no stable property ID, clearing session');
      await prefs.setBool(_keyIsAuthenticated, false);
      return false;
    }

    final prop = Property(
      id: cachedPropId,
      name: cachedPropName ?? 'My Hotel',
      address: '',
      city: '',
      state: '',
      pincode: '',
      phone: '',
      email: cachedEmail,
      totalRooms: 12,
      upiId: '',
      upiPayeeName: cachedPropName ?? 'My Hotel',
    );

    await store.loadForProperty(
      property: prop,
      managerName: cachedName ?? 'General Manager',
      managerEmail: cachedEmail,
      managerPhone: store.staffPhone,
      managerRole: cachedRole ?? 'General Manager / Owner',
    );
    return true;
  }

  /// Sign In with Email and Password
  Future<AuthResult> signIn({
    required String email,
    required String password,
    required HotelStore store,
  }) async {
    final trimmedEmail = email.trim().toLowerCase();
    final client = SupabaseConfig.client;

    if (client != null) {
      try {
        final authResponse = await client.auth.signInWithPassword(
          email: trimmedEmail,
          password: password,
        );

        if (authResponse.user != null) {
          final user = authResponse.user!;

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

          String fullName = 'General Manager';
          String role = 'General Manager / Owner';
          String phone = '';
          Map<String, dynamic>? profileRes;

          try {
            profileRes = await client
                .from('user_profiles')
                .select('full_name, role, property_id, properties(*)')
                .eq('id', user.id)
                .maybeSingle();

            if (profileRes != null) {
              fullName = profileRes['full_name'] as String? ?? fullName;
              role = profileRes['role'] as String? ?? role;
              final propData = profileRes['properties'] as Map<String, dynamic>?;
              if (propData != null) {
                phone = propData['phone']?.toString() ?? phone;
              }
            }
          } catch (e) {
            debugPrint('[AuthService] Profile retrieval notice: $e');
          }

          final prefs = await SharedPreferences.getInstance();
          var assignedPropId = await _resolveStablePropertyId(
            userId: user.id,
            userEmail: trimmedEmail,
            prefs: prefs,
            profileRes: profileRes,
          );

          if (assignedPropId == null) {
            // Self-heal: If user signed up but hotel setup was interrupted, recover from user metadata
            final meta = user.userMetadata ?? {};
            final pendingHotelName = meta['hotel_name']?.toString() ??
                prefs.getString(_keyPropertyName) ??
                '$fullName\'s Hotel';
            final pendingCity = meta['city']?.toString() ?? '';
            final pendingPhone = meta['phone']?.toString() ?? phone;

            final autoUuid = SupabaseSyncService.generateUuid();
            try {
              final rpcRes = await client.rpc('register_hotel_with_manager', params: {
                'p_user_id': user.id,
                'p_hotel_name': pendingHotelName,
                'p_city': pendingCity,
                'p_phone': pendingPhone,
                'p_email': trimmedEmail,
                'p_full_name': fullName,
              });
              if (rpcRes != null) {
                assignedPropId = rpcRes.toString();
              }
            } catch (_) {}

            if (assignedPropId == null) {
              try {
                await client.from('properties').insert({
                  'id': autoUuid,
                  'name': pendingHotelName,
                  'city': pendingCity,
                  'phone': pendingPhone,
                  'email': trimmedEmail,
                  'currency': 'INR',
                  'timezone': 'Asia/Kolkata',
                });
                await client.from('user_profiles').upsert({
                  'id': user.id,
                  'property_id': autoUuid,
                  'full_name': fullName,
                  'role': 'admin',
                  'is_active': true,
                });
                assignedPropId = autoUuid;
              } catch (healErr) {
                debugPrint('[AuthService] Self-heal property notice: $healErr');
              }
            }

            if (assignedPropId != null) {
              await prefs.setString(_keyPropertyId, assignedPropId);
            }
          }

          if (assignedPropId == null) {
            return AuthResult(
              success: false,
              errorMessage: 'Your account has no property linked. Please contact support or register a new hotel.',
            );
          }

          final propData = profileRes?['properties'] as Map<String, dynamic>?;
          final propName = propData?['name']?.toString() ??
              prefs.getString(_keyPropertyName) ?? 'My Hotel';

          final prop = Property(
            id: assignedPropId,
            name: propName,
            address: propData?['address']?.toString() ?? '',
            city: propData?['city']?.toString() ?? '',
            state: propData?['state']?.toString() ?? '',
            pincode: propData?['pincode']?.toString() ?? '',
            phone: propData?['phone']?.toString() ?? phone,
            email: propData?['email']?.toString() ?? trimmedEmail,
            totalRooms: 12,
            upiId: propData?['upi_id']?.toString() ?? '',
            upiPayeeName: propData?['upi_payee_name']?.toString() ?? propName,
          );

          await store.loadForProperty(
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
            propertyName: propName,
            propertyId: assignedPropId,
          );

          return AuthResult(success: true, user: authResponse.user);
        }
      } on AuthException catch (e) {
        debugPrint('[AuthService] AuthException: ${e.message}');
        if (trimmedEmail != 'frontdesk@easeinn.com') {
          final isUnconfirmed = e.message.toLowerCase().contains('email not confirmed');
          return AuthResult(
            success: false,
            errorMessage: isUnconfirmed
                ? 'Email not confirmed yet. Tap below to verify.'
                : e.message,
            requiresEmailConfirmation: isUnconfirmed,
            email: trimmedEmail,
          );
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

    // Demo account offline fallback
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

    // Offline session for previously signed-in real users
    final prefs = await SharedPreferences.getInstance();
    final cachedEmail = prefs.getString(_keyUserEmail);
    if (cachedEmail != null && cachedEmail.trim().toLowerCase() == trimmedEmail) {
      final cachedPropId = prefs.getString(_keyPropertyId);
      if (cachedPropId == null || cachedPropId.isEmpty || cachedPropId == 'prop-001') {
        return AuthResult(
          success: false,
          errorMessage: 'Cannot sign in offline: no stable session found. Please connect to the internet.',
        );
      }
      final cachedName = prefs.getString(_keyUserName) ?? 'General Manager';
      final cachedRole = prefs.getString(_keyUserRole) ?? 'General Manager / Owner';
      final cachedPropName = prefs.getString(_keyPropertyName) ?? 'My Hotel';

      final prop = Property(
        id: cachedPropId,
        name: cachedPropName,
        address: '',
        city: '',
        state: '',
        pincode: '',
        phone: '',
        email: trimmedEmail,
        totalRooms: 12,
        upiId: '',
        upiPayeeName: cachedPropName,
      );
      await store.loadForProperty(
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

  /// Sign Up: Hotel (Primary) first, then Manager Account (Secondary).
  /// One hotel can have multiple managers. The property is the primary business entity.
  Future<AuthResult> signUpHotel({
    // ── 1. PRIMARY: Hotel / Property Details ──
    required String hotelName,
    required String city,
    required String state,
    required String address,
    required int totalRooms,
    required String upiId,
    required String upiPayeeName,
    // ── 2. SECONDARY: Manager Account Credentials ──
    required String fullName,
    required String email,
    required String password,
    required String phone,
    required HotelStore store,
  }) async {
    final trimmedEmail = email.trim().toLowerCase();
    final client = SupabaseConfig.client;

    if (client != null) {
      try {
        final authResponse = await client.auth.signUp(
          email: trimmedEmail,
          password: password,
          data: {
            'full_name': fullName.trim(),
            'phone': phone.trim(),
            'hotel_name': hotelName.trim(),
            'city': city.trim(),
            'state': state.trim(),
            'address': address.trim(),
            'total_rooms': totalRooms,
            'upi_id': upiId.trim(),
            'upi_payee_name': upiPayeeName.trim(),
          },
        );

        final user = authResponse.user;
        if (user != null) {
          if (user.identities != null && user.identities!.isEmpty) {
            return AuthResult(
              success: false,
              errorMessage: 'An account with this email already exists. Please sign in instead.',
              email: trimmedEmail,
            );
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('pending_hotel_name', hotelName.trim());
          await prefs.setString('pending_city', city.trim());
          await prefs.setString('pending_state', state.trim());
          await prefs.setString('pending_address', address.trim());
          await prefs.setString('pending_phone', phone.trim());
          await prefs.setString('pending_upi_id', upiId.trim());
          await prefs.setString('pending_upi_payee_name', upiPayeeName.trim());
          await prefs.setString(_keyPropertyName, hotelName.trim());
          await prefs.setString(_keyUserName, fullName.trim());

          // Create property in Supabase
          String? createdPropertyId;
          final propUuid = SupabaseSyncService.generateUuid();

          // 1. Try atomic SECURITY DEFINER RPC first (bypasses RLS SELECT block)
          try {
            final rpcRes = await client.rpc('register_hotel_with_manager', params: {
              'p_user_id': user.id,
              'p_hotel_name': hotelName.trim(),
              'p_city': city.trim(),
              'p_state': state.trim(),
              'p_address': address.trim(),
              'p_phone': phone.trim(),
              'p_email': trimmedEmail,
              'p_upi_id': upiId.trim(),
              'p_upi_payee_name': upiPayeeName.trim(),
              'p_full_name': fullName.trim(),
            });
            if (rpcRes != null) {
              createdPropertyId = rpcRes.toString();
            }
          } catch (rpcErr) {
            debugPrint('[AuthService] RPC register notice: $rpcErr');
          }

          // 2. Direct table insert fallback (without .select('id') to avoid RLS RETURNING check block)
          if (createdPropertyId == null) {
            try {
              await client.from('properties').insert({
                'id': propUuid,
                'name': hotelName.trim(),
                'city': city.trim(),
                'state': state.trim(),
                'address': address.trim(),
                'phone': phone.trim(),
                'email': trimmedEmail,
                'upi_id': upiId.trim(),
                'upi_payee_name': upiPayeeName.trim(),
                'currency': 'INR',
                'timezone': 'Asia/Kolkata',
              });

              createdPropertyId = propUuid;

              await client.from('user_profiles').upsert({
                'id': user.id,
                'property_id': propUuid,
                'full_name': fullName.trim(),
                'role': 'admin',
                'is_active': true,
              });
            } catch (dbErr) {
              debugPrint('[AuthService] Direct insert notice: $dbErr');
            }
          }

          // 3. If session is null (Supabase requires email confirmation)
          if (authResponse.session == null) {
            return AuthResult(
              success: false,
              requiresEmailConfirmation: true,
              email: trimmedEmail,
              errorMessage: 'Account created! Please check your email or enter OTP to verify.',
            );
          }

          // 4. Fallback gracefully to client-generated UUID so account creation never fails
          createdPropertyId ??= propUuid;

          await prefs.setString(_keyPropertyId, createdPropertyId);

          final newProp = Property(
            id: createdPropertyId,
            name: hotelName.trim(),
            address: address.trim(),
            city: city.trim(),
            state: state.trim(),
            pincode: '',
            phone: phone.trim(),
            email: trimmedEmail,
            totalRooms: totalRooms,
            upiId: upiId.trim(),
            upiPayeeName: upiPayeeName.trim(),
          );

          await store.loadForProperty(
            property: newProp,
            managerName: fullName.trim(),
            managerEmail: trimmedEmail,
            managerPhone: phone.trim(),
            managerRole: 'admin',
          );

          await _saveSessionLocally(
            email: trimmedEmail,
            name: fullName.trim(),
            role: 'admin',
            propertyName: hotelName.trim(),
            propertyId: createdPropertyId,
          );

          return AuthResult(success: true, user: user);
        }
      } on AuthException catch (e) {
        final isConfirmation = e.message.toLowerCase().contains('email not confirmed');
        return AuthResult(
          success: false,
          errorMessage: isConfirmation
              ? 'Please check your email to confirm your account before signing in.'
              : e.message,
          requiresEmailConfirmation: isConfirmation,
          email: trimmedEmail,
        );
      } catch (e) {
        debugPrint('[AuthService] SignUp error: $e');
        return AuthResult(
          success: false,
          errorMessage: 'Registration failed. Please check your connection and try again.',
        );
      }
    }

    return AuthResult(
      success: false,
      errorMessage: 'No internet connection. Please connect and try again.',
    );
  }

  /// Add an additional manager/staff to an existing hotel property.
  /// One hotel can have multiple managers.
  Future<AuthResult> addManagerToProperty({
    required String propertyId,
    required String fullName,
    required String email,
    required String password,
    required String phone,
    String role = 'admin',
  }) async {
    final trimmedEmail = email.trim().toLowerCase();
    final client = SupabaseConfig.client;
    if (client == null) {
      return AuthResult(success: false, errorMessage: 'No internet connection.');
    }
    try {
      final authResponse = await client.auth.signUp(
        email: trimmedEmail,
        password: password,
        data: {
          'full_name': fullName.trim(),
          'phone': phone.trim(),
          'property_id': propertyId,
        },
      );
      final user = authResponse.user;
      if (user != null) {
        await client.from('user_profiles').insert({
          'id': user.id,
          'property_id': propertyId,
          'full_name': fullName.trim(),
          'role': role,
          'is_active': true,
        });
        return AuthResult(success: true, user: user);
      }
      return AuthResult(success: false, errorMessage: 'Manager registration failed.');
    } on AuthException catch (e) {
      return AuthResult(success: false, errorMessage: e.message);
    } catch (e) {
      return AuthResult(success: false, errorMessage: e.toString());
    }
  }

  /// Sign out — clears auth session but preserves local hotel data cache
  Future<void> signOut(HotelStore store) async {
    try {
      final client = SupabaseConfig.client;
      if (client != null) {
        await client.auth.signOut();
      }
    } catch (e) {
      debugPrint('[AuthService] SignOut notice: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    // Clear auth flags but KEEP property ID and property name in prefs
    // so offline session can still load the correct local cache
    await prefs.setBool(_keyIsAuthenticated, false);
    // Do NOT remove _keyPropertyId, _keyPropertyName — needed for offline login

    store.logout();
  }

  /// Verify the OTP token sent to the user's email after sign-up
  Future<AuthResult> verifyEmailOtp({
    required String email,
    required String token,
    required HotelStore store,
  }) async {
    final client = SupabaseConfig.client;
    if (client == null) {
      return AuthResult(success: false, errorMessage: 'No internet connection.');
    }
    try {
      final response = await client.auth.verifyOTP(
        email: email.trim().toLowerCase(),
        token: token.trim(),
        type: OtpType.signup,
      );
      final user = response.user;
      if (user == null) {
        return AuthResult(success: false, errorMessage: 'Verification failed. Please try again.');
      }
      // After verification, do a full sign-in flow to load the store properly
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic>? profileRes;
      try {
        profileRes = await client
            .from('user_profiles')
            .select('full_name, role, property_id, properties(*)')
            .eq('id', user.id)
            .maybeSingle();
      } catch (_) {}

      final fullName = profileRes?['full_name'] as String? ?? prefs.getString(_keyUserName) ?? 'General Manager';
      final role = profileRes?['role'] as String? ?? prefs.getString(_keyUserRole) ?? 'General Manager / Owner';
      final propData = profileRes?['properties'] as Map<String, dynamic>?;
      var assignedPropId = await _resolveStablePropertyId(
        userId: user.id,
        userEmail: email,
        prefs: prefs,
        profileRes: profileRes,
      );

      if (assignedPropId == null) {
        final meta = user.userMetadata ?? {};
        final pendingHotelName = meta['hotel_name']?.toString() ??
            prefs.getString('pending_hotel_name') ??
            prefs.getString(_keyPropertyName) ??
            '$fullName\'s Hotel';
        final pendingCity = meta['city']?.toString() ?? prefs.getString('pending_city') ?? '';
        final pendingPhone = meta['phone']?.toString() ?? prefs.getString('pending_phone') ?? '';

        final autoUuid = SupabaseSyncService.generateUuid();
        try {
          final rpcRes = await client.rpc('register_hotel_with_manager', params: {
            'p_user_id': user.id,
            'p_hotel_name': pendingHotelName,
            'p_city': pendingCity,
            'p_phone': pendingPhone,
            'p_email': email.trim().toLowerCase(),
            'p_full_name': fullName,
          });
          if (rpcRes != null) assignedPropId = rpcRes.toString();
        } catch (_) {}

        if (assignedPropId == null) {
          try {
            await client.from('properties').insert({
              'id': autoUuid,
              'name': pendingHotelName,
              'city': pendingCity,
              'phone': pendingPhone,
              'email': email.trim().toLowerCase(),
              'currency': 'INR',
              'timezone': 'Asia/Kolkata',
            });
            await client.from('user_profiles').upsert({
              'id': user.id,
              'property_id': autoUuid,
              'full_name': fullName,
              'role': 'admin',
              'is_active': true,
            });
            assignedPropId = autoUuid;
          } catch (_) {}
        }
      }

      if (assignedPropId == null) {
        return AuthResult(success: false, errorMessage: 'Account verified but hotel setup could not be completed. Please try signing in.');
      }

      final propName = propData?['name']?.toString() ?? prefs.getString(_keyPropertyName) ?? 'My Hotel';
      final prop = Property(
        id: assignedPropId,
        name: propName,
        address: propData?['address']?.toString() ?? '',
        city: propData?['city']?.toString() ?? '',
        state: propData?['state']?.toString() ?? '',
        pincode: propData?['pincode']?.toString() ?? '',
        phone: propData?['phone']?.toString() ?? '',
        email: propData?['email']?.toString() ?? email,
        totalRooms: 12,
        upiId: propData?['upi_id']?.toString() ?? '',
        upiPayeeName: propData?['upi_payee_name']?.toString() ?? propName,
      );

      await store.loadForProperty(
        property: prop,
        managerName: fullName,
        managerEmail: email.trim().toLowerCase(),
        managerPhone: store.staffPhone,
        managerRole: role,
      );

      await _saveSessionLocally(
        email: email.trim().toLowerCase(),
        name: fullName,
        role: role,
        propertyName: propName,
        propertyId: assignedPropId,
      );

      return AuthResult(success: true, user: user);
    } on AuthException catch (e) {
      return AuthResult(success: false, errorMessage: e.message);
    } catch (e) {
      debugPrint('[AuthService] verifyEmailOtp error: $e');
      return AuthResult(success: false, errorMessage: 'Verification failed. Please try again.');
    }
  }

  /// Resend OTP / confirmation email to the user
  Future<bool> resendVerificationEmail(String email) async {
    final client = SupabaseConfig.client;
    if (client == null) return false;
    try {
      await client.auth.resend(
        type: OtpType.signup,
        email: email.trim().toLowerCase(),
      );
      return true;
    } catch (e) {
      debugPrint('[AuthService] resendVerificationEmail error: $e');
      return false;
    }
  }

  Future<void> _saveSessionLocally({
    required String email,
    required String name,
    required String role,
    required String propertyName,
    required String propertyId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserEmail, email);
    await prefs.setString(_keyUserName, name);
    await prefs.setString(_keyUserRole, role);
    await prefs.setString(_keyPropertyName, propertyName);
    await prefs.setString(_keyPropertyId, propertyId);
    await prefs.setBool(_keyIsAuthenticated, true);
  }
}
