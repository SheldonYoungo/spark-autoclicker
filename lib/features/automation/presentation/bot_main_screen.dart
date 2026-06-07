import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spark_autoclicker/core/theme/app_theme.dart';
import 'package:spark_autoclicker/features/automation/presentation/sandbox_screen.dart';
import 'package:spark_autoclicker/features/automation/presentation/widgets/filter_card.dart';
import 'package:spark_autoclicker/features/automation/data/activation_service.dart';
import '../../../core/utils/overlay_util.dart';
import '../data/filter_service.dart';
import '../domain/filter_model.dart';
import '../../admin/data/admin_service.dart';
import '../../admin/presentation/admin_dashboard.dart';
import 'widgets/help_menu_modal.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BotMainScreen extends StatefulWidget {
  const BotMainScreen({super.key});

  @override
  State<BotMainScreen> createState() => _BotMainScreenState();
}

class _BotMainScreenState extends State<BotMainScreen>
    with WidgetsBindingObserver {
  final FilterService _filterService = FilterService();
  StreamSubscription? _overlaySubscription;
  Timer? _ticker;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _filterService.loadFilters();
    _checkAdminStatus();

    // Escuchar eventos del Overlay para sincronizar estado en tiempo real
    _overlaySubscription = _filterService.overlayEvents.listen((event) {
      debugPrint("BotMainScreen: Evento recibido del stream -> $event");
      if (event == 'refresh_filters') {
        _filterService.loadFilters(forceReload: true);
      }
    });

    // Log diagnóstico: verificar que el notifier cambia cuando el Overlay hace toggle
    _filterService.isBotActiveNotifier.addListener(_onBotActiveChanged);

    // Ticker para actualizar el contador de tiempo restante cada minuto
    _ticker = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint(
          "BotMainScreen: App RESUMED -> Forzando sincronización con SharedPreferences");
      _filterService.loadFilters(forceReload: true);
    }
  }

  Future<void> _checkAdminStatus() async {
    final isAdmin = await AdminService().isCurrentDeviceAdmin();
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
      });
    }
  }

  void _onBotActiveChanged() {
    debugPrint(
        "BotMainScreen: ⚡ isBotActiveNotifier CAMBIÓ -> ${_filterService.isBotActiveNotifier.value}");
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _filterService.isBotActiveNotifier.removeListener(_onBotActiveChanged);
    _overlaySubscription?.cancel();
    super.dispose();
  }

  String _getRemainingTime(DateTime? expiration) {
    if (expiration == null) return '---';
    final now = DateTime.now();
    final diff = expiration.difference(now);
    if (diff.isNegative) return 'Expirado';
    if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m restantes';
  }

  Color _getRemainingColor(DateTime? expiration) {
    if (expiration == null) return Colors.white24;
    final diff = expiration.difference(DateTime.now());
    if (diff.inHours < 24) return Colors.orangeAccent;
    return AppColors.secondaryCian;
  }

  void _showStoreModal(String? currentVal) {
    final List<String> validStores = (currentVal ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final TextEditingController inputController = TextEditingController();
    final ValueNotifier<bool> errorNotifier = ValueNotifier<bool>(false);
    String? localError;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => _KeyboardPadding(
        child: StatefulBuilder(builder: (context, setModalState) {
          return _StyledModalContainer(
            title: 'Códigos de Tienda',
            subtitle: 'Ingresa 4 dígitos y presiona + para agregar',
            hasErrorNotifier: errorNotifier,
            onSave: () async {
              final val = inputController.text.trim();
              if (val.isNotEmpty) {
                if (val.length != 4) {
                  setModalState(() {
                    localError = '⚠️ El código debe tener exactamente 4 dígitos.';
                  });
                  errorNotifier.value = true;
                  await Future.delayed(const Duration(milliseconds: 1000));
                  errorNotifier.value = false;
                  if (context.mounted) {
                    setModalState(() { localError = null; });
                  }
                  return;
                }
                if (validStores.length < 3) {
                  if (validStores.contains(val)) {
                    inputController.clear();
                  } else {
                    validStores.add(val);
                  }
                }
              }

              Navigator.pop(context);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (validStores.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: validStores.map((store) {
                        return Chip(
                          label: Text('#$store',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          backgroundColor:
                              AppColors.primarySpark.withValues(alpha: 0.2),
                          deleteIconColor: Colors.redAccent,
                          side: BorderSide(
                              color: AppColors.primarySpark
                                  .withValues(alpha: 0.5)),
                          onDeleted: () {
                            setModalState(() {
                              validStores.remove(store);
                              localError = null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                if (localError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Text(localError!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: inputController,
                        enabled: validStores.length < 3,
                        autofocus: false,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        style: TextStyle(
                            color: validStores.length < 3
                                ? Colors.white
                                : Colors.white54,
                            fontSize: 24,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          prefixText: '#',
                          prefixStyle: TextStyle(
                              color: validStores.length < 3
                                  ? AppColors.primarySpark
                                  : Colors.grey,
                              fontSize: 24),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none),
                          hintText: validStores.length < 3
                              ? '0000'
                              : 'Límite',
                          hintStyle: const TextStyle(color: Colors.white24),
                        ),
                        onSubmitted: (val) {
                          if (val.length == 4) {
                            if (validStores.contains(val)) {
                              setModalState(() {
                                localError = '⚠️ La tienda #$val ya está en la lista';
                              });
                              inputController.clear();
                              Future.delayed(const Duration(seconds: 2), () {
                                if (context.mounted) {
                                  setModalState(() { localError = null; });
                                }
                              });
                              return;
                            }
                            if (validStores.length < 3) {
                              setModalState(() {
                                localError = null;
                                validStores.add(val);
                                inputController.clear();
                              });
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: validStores.length < 3
                            ? AppColors.primarySpark.withValues(alpha: 0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.add,
                            color: validStores.length < 3
                                ? AppColors.primarySpark
                                : Colors.grey,
                            size: 28),
                        onPressed: validStores.length >= 3
                            ? null
                            : () {
                                final val = inputController.text.trim();
                                if (val.length == 4) {
                                  if (validStores.contains(val)) {
                                    setModalState(() {
                                      localError = '⚠️ La tienda #$val ya está en la lista';
                                    });
                                    inputController.clear();
                                    Future.delayed(const Duration(seconds: 2), () {
                                      if (context.mounted) {
                                        setModalState(() { localError = null; });
                                      }
                                    });
                                    return;
                                  }
                                  setModalState(() {
                                    localError = null;
                                    validStores.add(val);
                                    inputController.clear();
                                  });
                                } else if (val.length > 0 && val.length < 4) {
                                  setModalState(() {
                                    localError = '⚠️ El código debe tener 4 dígitos';
                                  });
                                  Future.delayed(const Duration(seconds: 2), () {
                                    if (context.mounted) {
                                      setModalState(() { localError = null; });
                                    }
                                  });
                                }
                              },
                      ),
                    )
                  ],
                ),
              ],
            ),
          );
        }),
      ),
    ).whenComplete(() {
      final finalString = validStores.join(',');
      _filterService.saveFilters(_filterService.filtersNotifier.value.copyWith(storeCode: finalString));
    });
  }

  void _showDistanceModal(double currentVal) {
    double tempVal = currentVal;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => _StyledModalContainer(
          title: 'Distancia Máxima',
          subtitle: 'Radio máximo para aceptar órdenes',
          onSave: () {
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${tempVal.toStringAsFixed(1)} mi',
                style: GoogleFonts.inter(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white),
              ),
              Slider(
                value: tempVal,
                min: 0,
                max: 100,
                divisions: 1000,
                activeColor: AppColors.secondaryCian,
                inactiveColor: Colors.white10,
                onChanged: (val) => setModalState(() => tempVal = val),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('0 mi', style: TextStyle(color: Colors.white24)),
                    Text('100 mi', style: TextStyle(color: Colors.white24)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      _filterService.saveFilters(_filterService.filtersNotifier.value.copyWith(maxDistance: tempVal));
    });
  }

  void _showPayModal(double currentVal) {
    double tempVal = currentVal < 13 ? 13 : currentVal;
    final TextEditingController controller =
        TextEditingController(text: tempVal.toStringAsFixed(0));

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: _StyledModalContainer(
              title: 'Tarifa Mínima',
              subtitle:
                  'Tarifa mínima aceptable por orden (Rango: \$13 - \$150)',
              onSave: () {
                Navigator.pop(context);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStepperButton(
                        icon: Icons.remove,
                        onPressed: tempVal <= 13
                            ? null
                            : () {
                                setModalState(() {
                                  tempVal -= 0.5;
                                  if (tempVal < 13) tempVal = 13;
                                  controller.text = tempVal.toStringAsFixed(2);
                                });
                              },
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,2}')),
                            _MinPayInputFormatter(min: 13, max: 150),
                          ],
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            prefixText: '\$',
                            prefixStyle: TextStyle(
                                color: AppColors.primarySpark, fontSize: 28),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (val) {
                            final double? p = double.tryParse(val);
                            if (p != null) {
                              setModalState(() {
                                tempVal = p;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      _buildStepperButton(
                        icon: Icons.add,
                        onPressed: tempVal >= 150
                            ? null
                            : () {
                                setModalState(() {
                                  tempVal += 0.5;
                                  if (tempVal > 150) tempVal = 150;
                                  controller.text = tempVal.toStringAsFixed(2);
                                });
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [13, 25, 50, 100]
                        .map((val) => ActionChip(
                              label: Text('\$$val'),
                              labelStyle: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.05),
                              side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.1)),
                              onPressed: () {
                                setModalState(() {
                                  tempVal = val.toDouble();
                                  controller.text = val.toString();
                                });
                              },
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      double? p = double.tryParse(controller.text);
      if (p == null || p < 13) p = 13;
      if (p > 150) p = 150;
      _filterService.saveFilters(_filterService.filtersNotifier.value.copyWith(minPay: p));
    });
  }

  Widget _buildStepperButton(
      {required IconData icon, VoidCallback? onPressed}) {
    final bool isDisabled = onPressed == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isDisabled
                    ? Colors.white.withValues(alpha: 0.05)
                    : AppColors.primarySpark.withValues(alpha: 0.3)),
            color: isDisabled
                ? Colors.white.withValues(alpha: 0.02)
                : AppColors.primarySpark.withValues(alpha: 0.05),
          ),
          child: Icon(
            icon,
            color: isDisabled
                ? Colors.white.withValues(alpha: 0.1)
                : AppColors.primarySpark,
            size: 24,
          ),
        ),
      ),
    );
  }

  void _showOrderTypeModal(List<String> currentTypes) {
    List<String> tempTypes = List.from(currentTypes);
    final options = ['compras', 'recolección', 'multiviajes'];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => _StyledModalContainer(
          title: 'Tipos de Orden',
          subtitle: 'Selecciona los textos exactos que el bot debe buscar',
          onSave: () {
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: options.map((opt) {
                  final isSelected = tempTypes.contains(opt);
                  return FilterChip(
                    label: Text(opt.toUpperCase()),
                    selected: isSelected,
                    onSelected: (val) {
                      setModalState(() {
                        if (val) {
                          tempTypes.add(opt);
                        } else {
                          tempTypes.remove(opt);
                        }
                      });
                    },
                    selectedColor:
                        AppColors.primarySpark.withValues(alpha: 0.2),
                    checkmarkColor: AppColors.primarySpark,
                    labelStyle: TextStyle(
                      color: isSelected ? AppColors.primarySpark : Colors.white,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primarySpark.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setModalState(() => tempTypes.clear()),
                child: const Text('DESELECCIONAR TODOS',
                    style: TextStyle(
                        color: AppColors.secondaryCian, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      _filterService.saveFilters(_filterService.filtersNotifier.value.copyWith(orderTypes: tempTypes));
    });
  }

  void _showStyledModal(
      {required String title,
      required String subtitle,
      required Widget child,
      required VoidCallback onSave}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _StyledModalContainer(
          title: title,
          subtitle: subtitle,
          onSave: () {
            onSave();
            Navigator.pop(context);
          },
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(color: AppColors.background),
        child: SafeArea(
          child: ValueListenableBuilder<BotFilters>(
            valueListenable: _filterService.filtersNotifier,
            builder: (context, filters, _) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header con Logo y Estado de Suscripción
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Hero(
                              tag: 'app_logo',
                              child: Image.asset(
                                'public/images/SPARK-LOGO-BIG.png',
                                height: 42,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SPARK APP',
                                  style: GoogleFonts.inter(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.white,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                ValueListenableBuilder<DateTime?>(
                                  valueListenable:
                                      ActivationService.expirationDateNotifier,
                                  builder: (context, expiration, _) {
                                    return Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: _isAdmin
                                                ? AppColors.secondaryCian
                                                : _getRemainingColor(
                                                    expiration),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _isAdmin
                                              ? 'Suscripción: Ilimitada'
                                              : 'Suscripción: ${_getRemainingTime(expiration)}',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: _isAdmin
                                                ? AppColors.secondaryCian
                                                : _getRemainingColor(expiration)
                                                    .withValues(alpha: 0.8),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            if (_isAdmin)
                              IconButton(
                                icon: const Icon(Icons.admin_panel_settings,
                                    color: Colors.orangeAccent),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const AdminDashboard()),
                                ),
                              ),
                            IconButton(
                              icon: const Icon(Icons.help_outline,
                                  color: AppColors.secondaryCian),
                              onPressed: () => HelpMenuModal.show(context),
                            ),
                            IconButton(
                              icon: const Icon(Icons.logout,
                                  color: Colors.white54, size: 20),
                              onPressed: () async {
                                final bool confirm = await showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                              backgroundColor:
                                                  AppColors.background,
                                              title: const Text('Cerrar Sesión',
                                                  style: TextStyle(
                                                      color: Colors.white)),
                                              content: const Text(
                                                  '¿Estás seguro de que deseas desvincular este dispositivo?',
                                                  style: TextStyle(
                                                      color: Colors.white70)),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, false),
                                                    child:
                                                        const Text('CANCELAR')),
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, true),
                                                    child: const Text(
                                                        'CERRAR SESIÓN',
                                                        style: TextStyle(
                                                            color: Colors
                                                                .redAccent))),
                                              ],
                                            )) ??
                                    false;
                                if (confirm) {
                                  if (_isAdmin) {
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setBool('bypass_revoked', true);
                                    await prefs.setBool(
                                        'is_admin_device', false);
                                    final deviceId =
                                        await ActivationService().getDeviceId();
                                    try {
                                      await FirebaseDatabase.instance
                                          .ref('config/admin_devices/$deviceId')
                                          .remove();
                                    } catch (_) {}
                                    await FirebaseAuth.instance.signOut();
                                    AdminService.forceReloadNotifier.value++;
                                  } else {
                                    await ActivationService().clearLocalLink();
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    _buildHeroCard(filters),
                    const SizedBox(height: 32),

                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.85,
                      children: [
                        FilterCard(
                          title: 'Tienda Walmart',
                          value: filters.storeCode != null &&
                                  filters.storeCode!.isNotEmpty
                              ? (filters.storeCode!.contains(',')
                                  ? '${filters.storeCode!.split(',').length} tiendas'
                                  : '#${filters.storeCode}')
                              : 'FALTA',
                          icon: Icons.storefront_outlined,
                          accentColor: (filters.storeCode == null ||
                                  filters.storeCode!.isEmpty)
                              ? Colors.redAccent
                              : AppColors.secondaryCian,
                          onTap: () => _showStoreModal(filters.storeCode),
                        ),
                        FilterCard(
                          title: 'Distancia Máx.',
                          value: filters.maxDistance.toStringAsFixed(1),
                          unit: 'mi',
                          icon: Icons.map_outlined,
                          accentColor: AppColors.primarySpark,
                          onTap: () => _showDistanceModal(filters.maxDistance),
                        ),
                        FilterCard(
                          title: 'Tipos de Orden',
                          value: filters.orderTypes.isEmpty
                              ? 'TODAS'
                              : filters.orderTypes.length.toString(),
                          unit: filters.orderTypes.isEmpty
                              ? null
                              : (filters.orderTypes.length == 1
                                  ? 'categoría'
                                  : 'categorías'),
                          icon: Icons.shopping_bag_outlined,
                          onTap: () => _showOrderTypeModal(filters.orderTypes),
                        ),
                        FilterCard(
                          title: 'Pago Mín.',
                          value: '\$${filters.minPay.toStringAsFixed(0)}',
                          icon: Icons.payments_outlined,
                          accentColor: AppColors.primarySpark,
                          onTap: () => _showPayModal(filters.minPay),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    _buildSpeedBoostCard(filters),
                    const SizedBox(height: 40),

                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.primarySpark.withValues(alpha: 0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () async {
                            final String? message =
                                await OverlayUtil.showOverlay();
                            if (message != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(message),
                                  backgroundColor: AppColors.borderBlue,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primarySpark,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: Text(
                            'ABRIR PANEL FLOTANTE',
                            style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SandboxScreen()),
                        ),
                        icon: const Icon(Icons.bug_report_outlined,
                            size: 16, color: Colors.white38),
                        label: Text(
                          'MODO PRUEBAS (SANDBOX)',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white38,
                              letterSpacing: 1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(BotFilters filters) {
    return ValueListenableBuilder<bool>(
      valueListenable: _filterService.isBotActiveNotifier,
      builder: (context, isActive, _) {
        return GestureDetector(
          onTap: () {
            if (!isActive &&
                (filters.storeCode == null || filters.storeCode!.isEmpty)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      '⚠️ Debes ingresar un Código de Tienda primero para activar el bot.'),
                  backgroundColor: Colors.redAccent,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            _filterService.toggleBot(!isActive);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isActive
                    ? [
                        AppColors.primarySpark.withValues(alpha: 0.8),
                        const Color(0xFF0043AA),
                      ]
                    : [
                        const Color(0xFF0043AA).withValues(alpha: 0.8),
                        AppColors.background,
                      ],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isActive ? AppColors.primarySpark : AppColors.borderBlue,
                width: 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isActive
                          ? AppColors.primarySpark
                          : const Color(0xFF0043AA))
                      .withValues(alpha: 0.3),
                  blurRadius: 25,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color:
                            (isActive ? Colors.white : AppColors.primarySpark)
                                .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isActive ? Icons.pause : Icons.play_arrow,
                            color: isActive
                                ? Colors.white
                                : AppColors.primarySpark,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isActive ? 'DETENER BOT' : 'ACTIVAR BOT',
                            style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: isActive
                                    ? Colors.white
                                    : AppColors.primarySpark),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isActive ? Icons.bolt : Icons.power_settings_new,
                      color: isActive ? AppColors.primarySpark : Colors.white24,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  isActive
                      ? 'Motor de Búsqueda Activo'
                      : 'Auto-Aceptación de Alta Velocidad',
                  style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  isActive
                      ? 'El bot está escaneando órdenes en tiempo real. Toca para pausar.'
                      : 'Abre el cuadro flotante y pulsa Activar. Seguirá revisando la pantalla hasta tomar una oferta que coincida.',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.7),
                      height: 1.4),
                ),
                if (filters.orderTypes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Tipo de orden: ${filters.orderTypes.join(" · ")}',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color:
                              isActive ? Colors.white : AppColors.secondaryCian,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSpeedModal(double currentMultiplier) {
    double tempVal = currentMultiplier;
    final tiers = [
      {
        'val': 1.0,
        'label': 'Tortuga',
        'desc': 'Escaneo normal (1s)',
        'icon': Icons.hourglass_empty
      },
      {
        'val': 1.5,
        'label': 'Seguro',
        'desc': 'Recomendado (500ms)',
        'icon': Icons.check_circle_outline
      },
      {
        'val': 2.0,
        'label': 'Liebre',
        'desc': 'Muy rápido (300ms)',
        'icon': Icons.bolt
      },
      {
        'val': 3.0,
        'label': 'Extremo',
        'desc': 'IA Máxima (100ms)',
        'icon': Icons.whatshot
      },
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => _StyledModalContainer(
          title: 'Velocidad de Escaneo',
          subtitle: 'Ajusta qué tan rápido el bot revisa la pantalla',
          onSave: () {
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: tiers.map((tier) {
              final isSelected = tempVal == tier['val'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: InkWell(
                  onTap: () =>
                      setModalState(() => tempVal = tier['val'] as double),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: isSelected
                          ? AppColors.secondaryCian.withValues(alpha: 0.1)
                          : Colors.white.withValues(alpha: 0.03),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.secondaryCian
                            : Colors.white.withValues(alpha: 0.05),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(tier['icon'] as IconData,
                            color: isSelected
                                ? AppColors.secondaryCian
                                : Colors.white38),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tier['label'] as String,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              Text(tier['desc'] as String,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 12)),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle,
                              color: AppColors.secondaryCian),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    ).whenComplete(() {
      _filterService.saveFilters(_filterService.filtersNotifier.value.copyWith(speedMultiplier: tempVal));
    });
  }

  Widget _buildSpeedBoostCard(BotFilters filters) {
    String label = 'Normal';
    if (filters.speedMultiplier >= 3.0)
      label = 'Extremo';
    else if (filters.speedMultiplier >= 2.0)
      label = 'Liebre';
    else if (filters.speedMultiplier >= 1.5) label = 'Seguro';

    return GestureDetector(
      onTap: () => _showSpeedModal(filters.speedMultiplier),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1629),
          borderRadius: BorderRadius.circular(24),
          border:
              Border.all(color: AppColors.borderBlue.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.secondaryCian.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.speed, color: AppColors.secondaryCian),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Impulso de Velocidad IA',
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.white),
                  ),
                  Text(
                    'Frecuencia: ${filters.speedMultiplier}x ($label)',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.secondaryCian),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white12, size: 16),
          ],
        ),
      ),
    );
  }
}

class _MinPayInputFormatter extends TextInputFormatter {
  final int min;
  final int max;

  _MinPayInputFormatter({required this.min, required this.max});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    if (newValue.text == '0') return oldValue;

    String text = newValue.text;
    if (text.startsWith('0') && text.length > 1) {
      text = text.replaceFirst(RegExp(r'^0+'), '');
    }

    final int? val = int.tryParse(text);
    if (val == null) return oldValue;

    // Solo forzamos el máximo inmediatamente para no impedir la escritura del mínimo
    if (val > max) {
      return TextEditingValue(
        text: max.toString(),
        selection: TextSelection.collapsed(offset: max.toString().length),
      );
    }

    if (text != newValue.text) {
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }

    return newValue;
  }
}

class _StyledModalContainer extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback onSave;
  final ValueNotifier<bool>? hasErrorNotifier;

  const _StyledModalContainer(
      {required this.title,
      required this.subtitle,
      required this.child,
      required this.onSave,
      this.hasErrorNotifier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white12, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 24),
          Text(title,
              style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.white)),
          const SizedBox(height: 8),
          Text(subtitle,
              style: GoogleFonts.inter(
                  fontSize: 14, color: Colors.white.withValues(alpha: 0.6)),
              textAlign: TextAlign.center),
          const SizedBox(height: 32),
          child,
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: hasErrorNotifier != null
                ? ValueListenableBuilder<bool>(
                    valueListenable: hasErrorNotifier!,
                    builder: (context, hasError, _) => ElevatedButton(
                      onPressed: onSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasError
                            ? Colors.redAccent
                            : AppColors.primarySpark,
                        foregroundColor: hasError ? Colors.white : Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('CONFIRMAR CAMBIOS',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  )
                : ElevatedButton(
                    onPressed: onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primarySpark,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('CONFIRMAR CAMBIOS',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
          ),
        ],
      ),
    );
  }
}

class _KeyboardPadding extends StatelessWidget {
  final Widget child;
  const _KeyboardPadding({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: child,
    );
  }
}
