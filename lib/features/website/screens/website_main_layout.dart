import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/sidebar_parts.dart';
import '../data/website_models.dart';
import '../providers/website_providers.dart';
import '../widgets/website_cards.dart';
import '../widgets/website_common.dart';
import '../widgets/website_footer.dart';
import 'academics_section.dart';
import 'activities_section.dart';
import 'contact_section.dart';
import 'facilities_section.dart';
import 'faq_section.dart';
import 'home_section.dart';
import 'information_section.dart';
import 'ppdb_section.dart';
import 'profile_section.dart';

const _wideBreakpoint = 1280.0;

class WebsiteMainLayout extends ConsumerStatefulWidget {
  const WebsiteMainLayout({super.key});

  @override
  ConsumerState<WebsiteMainLayout> createState() => _WebsiteMainLayoutState();
}

class _WebsiteMainLayoutState extends ConsumerState<WebsiteMainLayout> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(activeNavProvider);
    final canGoBack = ref.watch(canGoBackProvider);
    final newsId = ref.watch(newsDetailSlugProvider);
    final activityId = ref.watch(activityDetailSlugProvider);
    final profil = ref.watch(selectedProfilSectionProvider);
    final c = context.colors;

    ref.listen(activeNavProvider, (_, _) => _toTop());
    ref.listen(newsDetailSlugProvider, (_, _) => _toTop());
    ref.listen(activityDetailSlugProvider, (_, _) => _toTop());

    final wide = MediaQuery.sizeOf(context).width > _wideBreakpoint;
    final narrow = isNarrow(context);

    final body = switch (nav) {
      WebsiteNav.beranda => const HomeSection(),
      WebsiteNav.profil => const ProfileSection(),
      WebsiteNav.akademik => const AcademicsSection(),
      WebsiteNav.informasi => const InformationSection(),
      WebsiteNav.kegiatan => const ActivitiesSection(),
      WebsiteNav.fasilitas => const FacilitiesSection(),
      WebsiteNav.ppdb => const PpdbSection(),
      WebsiteNav.faq => const FaqSection(),
      WebsiteNav.kontak => const ContactSection(),
    };

    return PopScope(
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(activeNavProvider.notifier).back();
      },
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: 68,
          titleSpacing: 0,
          centerTitle: false,
          backgroundColor: c.su,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          shape: Border(bottom: BorderSide(color: c.mi)),
          title: _HeaderBar(
            wide: wide,
            active: nav,
            onMenu: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ),
        endDrawer: wide
            ? null
            : _NavDrawer(
                active: nav,
                onClose: () => Navigator.of(context).pop(),
              ),
        floatingActionButton: narrow
            ? FloatingActionButton.extended(
                heroTag: 'whatsapp-fab',
                backgroundColor: c.ink,
                foregroundColor: c.su,
                elevation: 2,
                onPressed: () => openWhatsApp(context, WhatsAppTopic.umum),
                label: Text(
                  'WhatsApp',
                  style: context.styleBold.copyWith(color: c.su, fontWeight: FontWeight.w600),
                ),
              )
            : null,
        body: SingleChildScrollView(
          controller: _scroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyedSubtree(
                key: ValueKey('$nav-$newsId-$activityId-${nav == WebsiteNav.profil ? profil : ''}'),
                child: body,
              ),
              WebsiteFooter(onBackToTop: _toTop),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderBar extends ConsumerWidget {
  const _HeaderBar({required this.wide, required this.active, required this.onMenu});

  final bool wide;
  final WebsiteNav active;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(activeNavProvider.notifier);

    final logo = InkWell(
      onTap: () => nav.open(WebsiteNav.beranda),
      child: SizedBox(
        width: 200,
        child: SidebarLogo(title: ref.watch(schoolInfoValueProvider).nama),
      ),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: wide
              ? Row(
                  children: [
                    logo,
                    const SizedBox(width: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final item in WebsiteNav.values)
                              _NavButton(
                                label: item.label,
                                selected: item == active,
                                onTap: () => nav.open(item),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    CustomButton(
                      label: 'Login Orang Tua',
                      variant: ButtonVariant.secondary,
                      compact: true,
                      onPressed: () => openParentLogin(context),
                    ),
                    const SizedBox(width: 8),
                    const WhatsAppButtonCompact(),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: Align(alignment: Alignment.centerLeft, child: logo)),
                    CustomButton(
                      label: '☰ Menu',
                      variant: ButtonVariant.secondary,
                      compact: true,
                      onPressed: onMenu,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class WhatsAppButtonCompact extends StatelessWidget {
  const WhatsAppButtonCompact({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomButton(
      label: 'Hubungi Admin via WhatsApp',
      compact: true,
      onPressed: () => openWhatsApp(context, WhatsAppTopic.umum),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: selected ? c.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Text(
              label,
              style: context.styleBody.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: selected ? c.su : c.sl,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavDrawer extends ConsumerWidget {
  const _NavDrawer({required this.active, required this.onClose});

  final WebsiteNav active;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final nav = ref.read(activeNavProvider.notifier);

    return Drawer(
      backgroundColor: c.su,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(ref.watch(schoolInfoValueProvider).nama, style: context.styleBold),
                ),
                CustomButton(
                  label: '✕ Tutup',
                  variant: ButtonVariant.secondary,
                  compact: true,
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in WebsiteNav.values)
              InkWell(
                onTap: () {
                  onClose();
                  nav.open(item);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.mi)),
                  ),
                  child: Text(
                    item.label,
                    style: context.styleBold.copyWith(
                      fontSize: 18,
                      fontWeight: item == active ? FontWeight.w700 : FontWeight.w600,
                      decoration: item == active ? TextDecoration.underline : null,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            CustomButton(
              label: 'Login Orang Tua',
              variant: ButtonVariant.secondary,
              expanded: true,
              onPressed: () {
                onClose();
                openParentLogin(context);
              },
            ),
            const SizedBox(height: 8),
            CustomButton(
              label: 'Hubungi Admin via WhatsApp',
              expanded: true,
              onPressed: () {
                onClose();
                openWhatsApp(context, WhatsAppTopic.umum);
              },
            ),
          ],
        ),
      ),
    );
  }
}
