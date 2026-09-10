import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/domain/entities/tag.dart';

/// How a kind is rendered: its name, and a glyph for it.
///
/// **One place, because four screens need both.** The list groups by kind, the row shows one, the detail
/// screen names one and the editor picks one. `ItemKindLabel.of(strings, kind)` and a private `_glyphFor`
/// switch used to do this per file, which was safe only because the set of kinds could not change. It can
/// now, so the resolution has to be shared or the four will drift.
///
/// ## Why the label is not in the ARB
///
/// **A kind's name is user data.** `Vegetables` is a row in `tags` that somebody typed; there is no key for
/// it and there never can be. The six enum members had ARB keys — `itemKindFood` and friends — and those keys
/// are now orphaned, because the seeded tags carry their own names in the database.
///
/// The one string that *is* copy is [unfiledLabel], for items with no kind at all. That is the app speaking,
/// not the user, so it goes through the ARB like any other sentence.
///
/// ## Why the glyph is keyed on the name
///
/// `tags.icon_key` exists and **nothing in the app reads it** — there is no registry mapping a key to an
/// `IconData`, so a tag cannot yet carry its own glyph. Until one exists, [glyphFor] recognises the nine
/// seeded kinds by their normalized name and gives everything else a neutral box.
///
/// **This is presentation, not data.** Rename `Food` to `Comida` and it falls back to the box — which is
/// correct behaviour for a lookup that exists only so the built-ins keep the icons they have today. When
/// `icon_key` gains a reader, this map becomes the default a user can override, and the fallback stops
/// mattering.
///
/// The alternative was one neutral icon for every kind, which would have thrown away information the app
/// already shows. The alternative to *that* was a schema change to carry icons for kinds nobody has made
/// yet — which is the sort of work that arrives before the feature it serves.
abstract final class KindDisplay {
  /// The name to show for [kind], or the unfiled label when there is none.
  static String labelFor(AlayaStrings strings, Tag? kind) =>
      kind?.name ?? strings.inventoryKindUnfiled;

  /// What items with no kind are called.
  static String unfiledLabel(AlayaStrings strings) =>
      strings.inventoryKindUnfiled;

  /// A glyph for [kind] — the seeded nine by name, a neutral box for everything else.
  static IconData glyphFor(Tag? kind) => switch (kind?.normalizedName) {
    'food' => Icons.restaurant_outlined,
    'grocery' => Icons.local_grocery_store_outlined,
    'vegetables' => Icons.eco_outlined,
    'kitchen' => Icons.kitchen_outlined,
    'household' => Icons.cleaning_services_outlined,
    'beauty' => Icons.spa_outlined,
    'medicine' => Icons.medication_outlined,
    'electronics' => Icons.devices_outlined,
    // `other` and anything the user made, including a renamed built-in.
    _ => Icons.inventory_2_outlined,
  };
}
