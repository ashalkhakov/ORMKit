# The runtime: tables and a driver

An app built from an ORM model needs the model's behaviour at run time:
- its queries;
- the rules Core Data cannot check ([RULES.md](RULES.md), [COREDATA-MAPPING.md](COREDATA-MAPPING.md));
- the derived and stored fact types kept up to date ([DERIVATION.md](DERIVATION.md));
- the entity types kept in several entities ([JOINED-ENTITIES.md](JOINED-ENTITIES.md)).

It does not need the full ORMKit framework: the `.orm` document, the
model, the editors, the mapper or the verbalizer.

Today that behaviour is generated as Objective-C, written as text by
`ORMCoreDataValidation` and `ORMJoinedFacade`:
- about 300 lines of helpers live in `@"..."` literals;
- each rule, derivation and joined type is emitted as code around them.

This does not hold up:
- The emitted code is compiled only when a model generates it. Tests
  build it with clang and load it, on Apple only, so GNUstep never runs
  it.
- Each new shape needs an emitter of its own. A derivation is a key-path
  walk (`PFXDerive`) because that is all the emitter writes. A count, a
  not or a join through a member would each be another emitter.
- The same behaviour is written twice: once as the interpreter ORMKit runs
  for the designer and sample populations, and once as emitted text.

## The parser generators' answer

Lexer and parser generators met this long ago. They take one of three
approaches:
- **Code.** re2c, and ANTLR's recursive descent, emit the logic itself.
- **Tables.** flex and yacc/bison emit tables, read by a driver written
  and tested once (`yylex`, `yyparse`).
- **Both.** bison writes tables for the automaton, and code where the
  grammar has its own: the semantic actions, and `y.tab.h` with the token
  numbers and `YYSTYPE`.

ORMKit takes the third: tables for behaviour, code for the typed surface.

- **The tables** are the plans: queries, rules, derivations and joined
  types as data, in property lists in the app's resources.
- **The driver** is a small library, `ORMRuntime`, that runs them. It is
  ordinary Objective-C, compiled and tested on both platforms.
- **The generated code** is declarations, as `y.tab.h` is: the façade
  classes' properties, typed query methods, the validation categories
  that call into the driver, and loading the tables.

The tables are trees, not a stream of instructions. Parser tables are
flat because an automaton is; a plan nests, as a not around a count around
a join does. A plan is to `ORMRuntime` what an archived `NSPredicate` in a
compiled Core Data model is to Core Data: a tree, interpreted. Flattening
it would gain nothing, since running a plan costs its fetches, not its
dispatch. It would also lose `-[ORMQueryPlan text]`, which prints a plan
for reading.

## What is there already

The plan is already model free. `ORMQueryPlan.h`, `ORMQueryInterpreter`
and `ORMCursor` import only Foundation, Core Data and ODataKit's
`ODataPropertyMapper`, and each other. Nothing of `ORMModel`, `ORMCDModel`
or NSXML is in them. The planner, which needs the model, makes plans; the
interpreter only runs them. So the split is where the code already divides:

| | ORMKit (tools, designer) | ORMRuntime (apps, and ORMKit) |
| --- | --- | --- |
| queries | `ORMQuery`, `ORMQueryPlanner`: from the model to plans | `ORMQueryPlan`, `ORMQueryInterpreter`, `ORMCursor`: plans run |
| tables | written: the generator | read: the archive |
| rules | which constraints, as which plans or checks | the checks, at validation and at save |
| derivations | which, in what order, reached back from which changes | the save hook: affected roots, derive, store |
| joined types | members, correlations, held properties | the façade's base class, member rows kept up |

ORMKit links ORMRuntime. Its own dynamic path (`ORMDeriver`,
`ORMRuleChecker`, the population store) runs on the same driver as
the apps, so one implementation is tested by both.

## The tables

One property list for each mapping, `<Name>.ormplans`, written beside the
validation files and added to the app's resources. It is an XML plist, so
a change to the model shows as a readable diff.

```
{
  format = 1;                      // the driver refuses a later major
  model = "Company";
  queries = { Reporting = { read = Employee; where = {...}; columns = (...); }; ... };
  rules = { Employee = ( { constraint = "..."; text = "..."; keys = (...); check = {...}; deontic = NO; } ); ... };
  derivations = ( { text = "..."; root = Employee; plan = {...}; target = reportsTo; kind = objects; backs = (...); } );
  joined = { Customer = { hub = CRMCustomer; members = ( { entity = BillingAccount; via = CRMCustomer; on = ((userId, userId)); outer = YES; holds = (balance); } ); }; };
}
```

- **A plan** is archived node for node: conditions by kind, paths as
  variable and steps, values, definitions by name, columns.
  `-[ORMQueryPlan propertyList]` writes it, and
  `+planWithPropertyList:error:` reads it back, checking each part.
- **A rule's check** is a plan: the object violates the rule where the
  plan, run from it, finds a row. A ring property (acyclic, intransitive)
  needs a closure no plan says. It is a check of its own kind, with its
  keys, which the driver knows (`ring = acyclic; key = reportsTo`).
  Few kinds are needed: the current `PFXAcyclic` and the like become them.
- **A derivation** is its plan, the property it sets, and the trails back
  from what it reads to its root. The generator writes the derivations
  in dependency order.
- **A joined type** is its members as the mapper names them: the
  table `ORMJoinedFacade` turns into code today.

The tables are made when the code is: by Synchronize, `ormtool coredata`
and `ormtool validation`. Planning stays in ORMKit, and the driver never
plans.

## The generated code

Declarations, and calls into the driver:

```objc
// CompanyValidation.m
@implementation Employee (ORMValidation)
- (BOOL)orm_validateConstraints:(NSError **)error
{
    return [ORMRuntime validate:self tables:CompanyTables() error:error];
}
@end

// Customer.h / .m: the façade, typed; its properties are the driver's
@interface Customer : ORMJoinedObject
@property (nonatomic, copy) NSNumber *userId;
@property (nonatomic, copy) NSNumber *balance;
@end
@implementation Customer
@dynamic userId, balance;      // resolved by ORMJoinedObject from the table
+ (NSString *)joinedType { return @"Customer"; }
@end
```

- `CompanyTables()` loads `Company.ormplans` once, from the bundle of the
  generated classes.
- A query becomes a typed method that runs its plan by name.
- `orm_prepareForSave:` is the driver's, with nothing generated.

## Testing

- **The driver:** its own tests, on Apple and GNUstep, over SQLite stores.
  They cover the derivations, rules and joined-object cases the emitted
  code covers today, and the gaps listed in JOINED-ENTITIES.md.
- **The generator:** tables compared as property lists. No clang, no
  `dlopen`.
- **End to end:** the tables a model makes, loaded into the driver,
  against a store: on both platforms, where today it is Apple only.
- **The archive:** every plan the query tests make goes through an XML
  property list and back unchanged (`-[ORMTestCase archived:]`). The
  plans the query tests run, and every query of every sample model, are
  run from the copy read back.

## Costs

- **The format has a version.** A driver refuses tables of a later major
  version, and reads every earlier one it knows. The generator writes the
  latest.
- **Apps link ORMRuntime.** It is small, has no model, and depends on
  Foundation, Core Data, and ODataKit's property mapper. The mapper could
  be dropped if an app does not use OData.
- **OData:** `ORMQueryOData` still reads the mapper's `ORMCDModel`. An app
  that runs plans against a service needs a model-free version, reading
  what it needs from the `NSManagedObjectModel`, as the interpreter does.
- **Speed:** a plan interpreted, not compiled. It costs its fetches. If a
  plan ever shows up in a profile, it can be compiled to code behind the
  same interface (re2c's answer for a hot lexer), but nothing asks for
  that now.

## Steps

1. **Extract** (done). `ORMQueryPlan`, `ORMQueryInterpreter` and
   `ORMCursor` are in `ORMRuntime/`, with no change in behaviour. ORMKit
   links it, and imports `<ORMRuntime/ORMRuntime.h>` where the framework
   is, `"ORMRuntime.h"` from the tree beside it otherwise. Build it
   before ORMKit on GNUstep (`make -C ORMRuntime`).
2. **Archive** (done). Plans had a property list form already. Every plan
   the tests make now goes through it, written as XML and read back, and
   is run from what is read. That found the reader refusing a
   calculation's `value` and `distinct`.
3. **Derivations and the save hook** in the driver. The generator writes
   their tables, and `PFXDerive`, `PFXRoots` and `PFXWalk` go.
4. **Rules:** checks as plans, and ring checks as kinds. The validation
   category forwards to the driver.
5. **Joined types:** `ORMJoinedObject` and its table. The façade classes
   are generated as declarations, and `ORMJoinedFacade`'s emitted code goes.
6. **Queries for apps:** typed methods, and the model-free OData path.
7. **Remove the emitters.** `-helpers` and its string literals go.

Each step keeps the tests passing, and steps 3 to 5 each replace one
emitter.
