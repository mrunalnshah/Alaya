import 'package:drift/drift.dart';

import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/tables/inventory_tables.dart';
import 'package:alaya/data/db/tables/meta_tables.dart';

/// A recipe: what it makes, how long it takes, and how many it serves.
///
/// [servings] is the anchor for every quantity in [RecipeIngredients]. Storing it explicitly is
/// what lets the engine scale a 4-serving recipe to 3 without the ingredient rows knowing anything
/// about servings — and without a second set of "per serving" columns that could disagree.
@DataClassName('RecipeRow')
class Recipes extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// Display name.
  TextColumn get name => text()();

  /// Casefolded, accent-stripped name for search and duplicate detection. Mirrors [Items] and
  /// [Tags], so "Pav Bhaji" and "pav bhaji" collide the same way everywhere in the app.
  TextColumn get normalizedName => text()();

  /// How many servings the stored ingredient quantities describe. Never zero — the engine divides
  /// by it.
  IntColumn get servings => integer()();

  /// Hands-on time before cooking starts.
  IntColumn get prepMinutes => integer().nullable()();

  /// Time on the heat.
  IntColumn get cookMinutes => integer().nullable()();

  /// Pinned by the user.
  BoolColumn get isFavorite => boolean()();

  /// Free-form notes: a source, a variation, who liked it.
  TextColumn get notes => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One line of a recipe's ingredient list.
///
/// **The [itemId]/[freeText] pair is copied from [ShoppingEntries] deliberately**, field for field.
/// That table already solved "either a catalogued item or a bit of text, with a quantity and a
/// unit", and matching its shape means moving a missing ingredient onto a shopping list is a field
/// copy rather than a translation.
///
/// A null [itemId] is not a deficiency. Nobody tracks the stock level of salt, and a recipe that
/// forced every ingredient into the catalogue would be unusable. The engine reports such a line as
/// *uncheckable* rather than *missing* — see `CookabilityEngine`.
@DataClassName('RecipeIngredientRow')
class RecipeIngredients extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The recipe this line belongs to.
  TextColumn get recipeId => text().references(Recipes, #id)();

  /// The catalogued item, when this ingredient refers to one. Null for anything untracked.
  TextColumn get itemId => text().nullable().references(Items, #id)();

  /// What the ingredient is, when there is no [itemId].
  TextColumn get freeText => text().nullable()();

  /// How much, in base-milli units of [unitCode]'s category. Null for "to taste" — which is a real
  /// ingredient with no quantity, not a quantity of zero.
  IntColumn get quantityMilli => integer().nullable()();

  /// The unit the cook reads. Null when [quantityMilli] is null.
  TextColumn get unitCode => text().nullable().references(Units, #code)();

  /// Excluded from the cookability verdict. A garnish should not make a dish uncookable.
  BoolColumn get isOptional => boolean()();

  /// Preparation note: "finely chopped", "at room temperature".
  TextColumn get note => text().nullable()();

  /// Display order within the recipe.
  IntColumn get sortOrder => integer()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One instruction in a recipe's method.
///
/// A table rather than one block of prose, decided before v1 shipped for a reason that only gets
/// more expensive with time: splitting prose into steps later means parsing text real users have
/// already written, which is lossy in a way that destroys their data. One table now costs a table.
///
/// [durationMinutes] is what a step-by-step cooking view times against.
@DataClassName('RecipeStepRow')
class RecipeSteps extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The recipe this step belongs to.
  TextColumn get recipeId => text().references(Recipes, #id)();

  /// Position in the method, from 1.
  IntColumn get stepNumber => integer()();

  /// What to do.
  TextColumn get instruction => text()();

  /// How long this step takes, when it is worth timing.
  IntColumn get durationMinutes => integer().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A record that a recipe was cooked, and whether stock was deducted for it.
///
/// **[deductedStock] is the column that makes cooking reversible.** A cook that consumed inventory
/// and one that did not look identical afterwards without it, and "undo this cook" would have to
/// guess whether to put anything back.
///
/// The stock movements themselves live in `stock_movements` and are the ledger of record; this
/// table answers "how often do we make this" and gives an undo a single row to work from.
@DataClassName('RecipeCookLogRow')
class RecipeCookLog extends Table {
  /// Row identifier, UUIDv7.
  TextColumn get id => text()();

  /// The recipe that was cooked.
  TextColumn get recipeId => text().references(Recipes, #id)();

  /// The civil date it was cooked on.
  IntColumn get cookedDateKey => integer().map(const DateKeyConverter())();

  /// How many servings were made, which may differ from the recipe's own [Recipes.servings].
  IntColumn get servingsCooked => integer()();

  /// Whether inventory was reduced. False when the user cooked without deducting, or when every
  /// ingredient was untracked.
  BoolColumn get deductedStock => boolean()();

  /// Free-form note: a substitution, how it turned out.
  TextColumn get note => text().nullable()();

  /// Creation instant, epoch millis UTC.
  IntColumn get createdAt => integer()();

  /// Last-modification instant, epoch millis UTC.
  IntColumn get updatedAt => integer()();

  /// Soft-delete instant, epoch millis UTC. Null means active.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
