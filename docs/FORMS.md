# Forms: fact selections as XForms

A form is a part of the model that a user fills in or reads: some facts about
one object, what must hold of them, and where they come from and go to. Here
a form is said in the model's terms, as a conceptual query is
([QUERIES.md](QUERIES.md)), and generated as an XForms document: an instance,
its binds, its controls, and its submissions. It runs against a service or,
offline, against the app's own Core Data store. How it looks, and how it is
laid out, is not the model's business; any XForms processor can run it, a
native UI can be laid out over it, and people can customize it without
losing what they did when it is generated again.

This is a design. Nothing in it is built yet; [Steps](#steps) says in what
order it would be, and [Open questions](#open-questions) what is not
settled.

## Why

Halpin and Weber, "Form-and-Fact Based Modeling" (EMMSAD 2012, LNBIP 113,
pp. 285–299), propose joining the two ways of agreeing on a system with its
users: fact-based modelling (ORM, its verbalizations, the CSDP) and
form-based modelling (Weber's form-oriented analysis). We have not read the
full text; from its abstract and the summaries of it:
- **Prototype forms seed the model.** A form, on paper or on screen, is
  verbalized into elementary facts, as the CSDP's first step does with any
  information example.
- **A conceptual form is an ORM subschema:** the fact types a form is about,
  with their constraints, without its layout. A form filled in is a
  population of that subschema.
- **The model generates the final user interface.** Fact types are anchored
  to a major object type, candidate forms are generated and then
  customized, and the constraints are enforced in the form (a drop-down
  that depends on another).
- **Constraints a form does not show are met as errors,** each said in
  words: the rule's verbalization.
- **Screen transition diagrams** show the dialogue of a submit-and-response
  interface: a page changes on an atomic action (a submission), and what
  happens within a page is apart from it. They validate the dynamic
  process: what comes after what, what is modal, where an error leads.

What is ours: the form as a kind of conceptual query, its mapping to an
XForms document, the binds from the constraints, the OData requests in and
out, and the bridge to BPMN.

Why XForms: it is the standard for exactly this split. A form's model
(instances, binds: type, required, relevant, readonly, constraint,
calculate), its intent-level controls (input, select1, output, repeat,
group), and its submissions, with nothing about layout. XFormsKit
(`../XFormsKit`) runs XForms 1.1 natively on macOS, iOS and GNUstep, and
passes the W3C suite; a browser can run the same document with XSLTForms.
And a form is a process's data contract: a BPMN user task's inputs and
outputs.

## What a form is

**A form is a query of its own kind** (`Kind="Form"`): an outline anchored
at an object type, each node one of:
- **entered** (`✎X`): the user gives its value; a role whose fact the form
  asserts;
- **shown** (`✓X`): read, not changed; a derived fact, or one the form
  only reads;
- **neither**: the path to something entered or shown, or a condition.

A node may be **given** (`X = ?`): its value comes in with the form, as the
form is opened, a parameter. The anchor is given when the form edits an
object that exists, and new when it makes one.

```
Form RecordFillUp:
FillUp
  + is of Vehicle = ?
  + was at ✎Moment
  + has mileage ✎Distance
  + has volume ✎Volume
  + is of ✎Fuel
  + was bought at ✎Station
  + filled the tank ✎
  + cost ✎Money
  + charged ✎Money
  + was driven by ✎User
    + drives that Vehicle
  ✓PricePerUnit = Money / Volume
```

- The vehicle is given: the form is opened for one.
- The driver is chosen from those who drive that vehicle: the step under it
  is a condition on the choices, a drop-down that depends on another, as
  the paper has it.
- `PricePerUnit` is a value node ([EXPRESSIONS.md](EXPRESSIONS.md)),
  computed in the form and shown.

**A form may have several anchors:** objects made or changed together that
neither reaches through the other (a car sale and the vehicle's last
odometer reading). Each anchor is an outline of its own in the form, an
instance of its own, and they are submitted together, one change set (or
one save).

A form is verbalized as a query is, and read as its subschema: the fact
types its steps go through, the object types they reach, and the
constraints whose roles are all among them.

## The instance: the form as a document

The form's tree is mapped to an XML instance, as Rmap maps a schema to
tables ([COREDATA-MAPPING.md](COREDATA-MAPPING.md)), but to one tree. Call
it Fmap:

| In the form | In the instance |
| --- | --- |
| the anchor | the document element, named as its entity |
| a step to a value type, functional (at most one) | a child element, named as the property the mapping made of the role (`mileageQuantity`), typed: `xsd:decimal`, `xsd:date`, `xsd:dateTime`, `xsd:boolean`, `xsd:string` |
| a compound value absorbed by the mapping (Money, Distance) | its properties, as the mapping absorbed them (`totalAmount`, `totalCurrency`) |
| a step to an entity the form refers to, functional | an element holding its key (`driver` = the user's email); its choices in an instance of their own |
| a step to an entity the form owns (an item of a service) | a child element, its own steps beneath it |
| a step that is not functional (a service's items) | a repeated element; a repeat in the controls |
| a subtype step (`+ is Service`) | its elements, relevant when the object is of it |
| a given node | an element filled as the form is opened |
| a value node | an element calculated (a bind's `calculate`) |

The names are the OData properties' (the mapping's), so that the instance
is the entity's own representation, read and written as the service has it,
and the same whether a store or the service holds it.

## Binds: the constraints that apply

A constraint is a bind when all its roles are in the form. Each says its
verbalization as the bind's alert, the words a user reads.

| ORM | Bind |
| --- | --- |
| mandatory role (simple) | `required="true()"` |
| inclusive-or | `required` on each: required while all the others are empty |
| value constraint | `type`, and a `constraint` for a range or a list; a list of values is also the choices of a `select1` |
| uniqueness (internal) on a repeated group | `constraint`: no two items alike (`count(../item[x = current()/x]) = 1`) |
| exclusion, exclusive-or | `relevant`: an alternative is not relevant once another is given; or one `select1` of the alternatives |
| subset | `relevant` (or `required`): the second given only where the first is |
| equality; a compound value that is whole | `required` each where the other is given (a quantity and its unit) |
| value comparison | `constraint`: compared when both are given |
| a rule ([RULES.md](RULES.md)) over the form's facts alone | `constraint`: the rule's condition, said in XPath |
| a derivation over the form's facts alone | `calculate`, `readonly` |
| deontic | a warning: shown at its node, never invalid, never in the way of a submission (XForms has none: an extension) |

What a form cannot check alone (uniqueness across objects, a rule through
facts the form does not hold) is checked where it is submitted: by the
service, or by the local store's save ([In and out](#in-and-out-a-service-or-a-local-store)).
Its refusal names the rule and, where it can, the property; the form shows
the verbalization at that node. The paper's point holds either way: a constraint a form does
not show is met as an error said in the model's words.

## Controls

Intent only: an `input` for each entered value, `select1` for a reference
(its itemset the choices' instance) or a value list, `output` for each
shown one, a `repeat` for a group, a `group` for a subtype's part. The
label is the form's own for that node where it gives one, else the role's
name ("Odometer"); a role with neither is labelled by its player's name and
noted. The hint is the fact type's note; the alert, the constraint's
verbalization. Order is the outline's.

Layout is not here. A generated form runs as it is in an XForms processor;
a designer lays it out (XFormsKit's designer, or a native view with its
controls bound to the form's: see [Running one](#running-one)).

## In and out: a service or a local store

A form does not say where its data is. Its inputs and outputs name what
they are (the form's object read; the vehicle's drivers; the fill-up
saved), and the app that runs it says where: the service, when it is
online and works against one; its own Core Data store, when it works
offline and syncs later (Logbook does, through ODataSync). Both are planned
from the same tree, as any query is planned into either
([QUERIES.md](QUERIES.md)).

In the document, each instance's `src` and each submission's `resource` is
a name the app resolves (`form:read`, `form:choices/driver`,
`form:save`), and its XForms submission transport does the work. XFormsKit
takes a transport per model (`XFSubmissionTransport`), so a host chooses:
- **The service.** Reads are the planner's OData requests (`$select`,
  `$expand`); the answer is the instance, in XML. A new object is a `POST`
  of the instance (with its owned items, a deep insert); an existing one a
  `PATCH` of what changed, with its ETag. Both are one change set, so the
  service's rules hold of it as a whole.
- **The local store.** Reads are the same plan as a fetch request, run by
  the interpreter against the app's context, and the objects written as
  the instance. A submission writes the instance back into objects, by the
  same mapping, and saves the context: Core Data's own checks, the
  generated validation code and the rules at save
  ([COREDATA-MAPPING.md](COREDATA-MAPPING.md#validation-code-what-core-data-cannot-enforce),
  [RULES.md](RULES.md)) refuse it as the service would. Sync uploads it
  later, and the service checks it again then.

Either way:
- **In: the instance.** Opening a form for an existing object reads it: the
  form's tree as a query, its entered and shown nodes listed.
- **In: the choices.** Each reference's choices are a query of their own,
  its condition the step under it (the vehicle's drivers), read when the
  form opens and again when what it depends on changes.
- **Out: an action.** A form for a step of a process may submit to an
  action instead (Logbook's `Continue` of a schedule): its parameters are
  the instance's. Offline, the app's own procedure does what the action
  does (Logbook's `LBProcedures`, which its server's action calls too).
- **Back: the response.** Done, the form says so, or leads on
  ([Processes](#processes-screens-and-tasks)). Refused, each violation is
  shown at its node: the service's 400 details, or the save's validation
  errors (`NSValidationKeyErrorKey` names the property, which names the
  node). Deontic violations come back as warnings and do not refuse it.

A store's changes made elsewhere (a sync, an undo) while a form is open
reach it as a new read of what changed: the form's instance follows its
objects, as the spike's mirror did.

## Processes: screens and tasks

The paper's screen transition diagrams are the dialogue between forms: a
submission is the atomic action that changes the screen, and what happens
within a form is not part of the diagram. In XForms that is a submission's
`xforms-submit-done` and `xforms-submit-error`, and what each leads to.

A BPMN user task is the same thing from the process's side: a task with
inputs and outputs (data objects), performed with a form. So:
- a user task names a form; the task's input data is the form's given
  nodes, and its output the submission;
- a gateway after the task reads the facts the form asserted;
- a screen transition diagram is the part of a process that is user tasks
  and the transitions between them.

The bridge from BPMN to ORM2 (in the works) is then a fact selection per
data object, which a form already is.

## Running one

Anything that runs XForms runs a generated form: XFormsKit's own views,
XSLTForms in a browser. For a native UI laid out by hand (a XIB, an iOS
storyboard), XFormsKit's processor runs without its views and each native
control is the view of an `XFControl`: it shows the control's value and its
state (relevant, readonly, required, valid, alert) and commits what is typed
to it. A spike did this on macOS and GNUstep over the fill-up form: about
60 lines of binding, an edit in 0.4 ms (macOS) and 1 ms (GNUstep).

It also found what XFormsKit needs first:
- **Decimal arithmetic.** XPath 1.0's numbers are doubles: 0.1 + 0.2 is
  0.30000000000000004. Money calculated in a form would be wrong. Values
  typed `xsd:decimal` need decimal arithmetic in the engine, the W3C suite
  run with it.
- **A refresh of what changed.** Every edit refreshes every control: 3 ms
  for 100 repeated rows on macOS, 73 ms for 250 on GNUstep, which is too slow
  to type in. Only the controls whose node, or whose binds' dependencies,
  changed need refreshing.

## Customizing: generated forms and what people add

People change a generated form: they lay it out, relabel it, group and
order its fields, hide some, add help, make a field required that the
model leaves optional, add a field of their own. The model changes too, and
the form is generated again. Neither may undo the other.

**So nobody edits what is generated.** A form is layers, each kept apart and
applied in order when the form is opened:

1. **The generated form:** instances, binds, submissions, default controls.
   Written by `ormtool xforms`, never edited, replaced whole when the model
   changes.
2. **Customizations:** a document of its own that refers to the generated
   one and says only what differs. Made by whoever owns the app, in
   XFormsKit's designer or by hand, and kept with the app's sources.
3. **A user's own** (later): the same kind of document, made in the running
   app and kept as data, synced like any other, per user or per team.

**What a customization refers to must survive regeneration.** Every
generated node, bind and control has an id from the model element it comes
from (the role's, the constraint's), not from its name or its place, so a
renamed role or a reordered outline keeps it. A layer that refers to
something the model no longer has is reported, not applied, as a query's
step through a deleted fact type is ([QUERIES.md](QUERIES.md#where-queries-live)).

**What a layer may do:**

| A layer may | How it is applied |
| --- | --- |
| lay out, group, order, hide, relabel, add hints and help | its controls replace the generated ones it names; generated controls it does not name follow, in their order |
| make a field stricter: `required`, a narrower `constraint`, `readonly`, less `relevant` | combined with the generated bind: `required` or'ed, `constraint` and `relevant` and'ed, `readonly` or'ed |
| add a `calculate` where the model has none | taken as it is |
| loosen a rule of the model | refused: the model's rules hold wherever the form is submitted, so a looser form would only fail later |
| add actions, messages, triggers, events | added |
| add a field the model does not have | kept in an instance of its own beside the form's, saved with the form's data where the app keeps such extras; and offered to the modeller as a candidate fact type (below) |

XForms 1.1 does not allow two binds to set the same property of one node,
so layers are not two documents at run time: opening a form applies them in
order to the generated document and runs the result. A native layout (a
XIB, a storyboard) is a layer too: its controls name the generated ones by
id, and whatever it does not lay out is not shown.

A field people keep adding is the model telling its modeller something.
That is the paper's first direction again: a form, as people actually use
it, seeds the model.

## Seeding the model from forms

The other direction, the paper's first: an existing form (an XForms
document, or a sample filled in) proposes fact types. Its instance's
elements are candidate object types and roles, its binds candidate
constraints, and a filled instance a sample population to check them
against ([POPULATIONS.md](POPULATIONS.md)). So does a customization's added
field, with the values people have kept in it. Later, after forms are
generated.

## Where forms live

In the `.orm`, as queries do, `Kind="Form"`, a node's part
`Part="Entered"` or `"Shown"`, a given one `Given="true"`. **Save a Copy
for NORMA** leaves them out. `ormtool xforms model.orm [form] [mapping]`
writes each form's XForms document; generated, never edited, as the
validation code is. Customizations are documents of their own beside it
([Customizing](#customizing-generated-forms-and-what-people-add)).

## Steps

1. **Forms in the file and the model.** `Kind="Form"`, `Part`, `Given`;
   the outline reads and writes `✎`, `✓` and `= ?`; the editor's changes
   undo.
2. **Fmap: the instance.** The form's tree to an XML instance, named as the
   mapping names properties; subtypes, compound values, references, owned
   groups.
3. **Binds.** From the constraints whose roles are all in the form, with
   the verbalization as each alert; rules and derivations over the form's
   facts in XPath; the rest listed as checked where it is submitted.
4. **Controls.** Intent-level, labelled with the form's labels or the
   roles' names.
5. **In and out, both ways.** Two transports from the same plans: the
   service's (OData reads, POST, PATCH, actions) and the local store's
   (fetches, writes into objects, a save). A refusal's violations shown at
   their nodes; deontic ones as warnings.
6. **`ormtool xforms`**, and the fill-up form run in XFormsKit's viewer,
   once against Logbook's test server and once against a local store:
   opened for a vehicle, filled in, refused, corrected, saved.
7. **XFormsKit:** decimal arithmetic, refreshing only what changed, the
   native binding (AppKit, UIKit), deontic warnings.
8. **Customizations:** stable ids, layers applied in order, the binds
   combined, references to what is gone reported; the designer editing a
   layer over a generated form, not the form.
9. **Logbook:** one form generated and laid out natively, offline; then the
   checklists, whose questions are data, as forms of their own.
10. **Processes:** screen transitions as submissions' outcomes; a BPMN user
    task naming a form.
11. **Later:** customizations made by users in the running app, kept as
    data; added fields offered back to the modeller.

## Open questions

Settled: a form may have several anchors; deontic constraints warn and
never prevent a submission; labels are the form's own or the roles' names;
a form runs against a local store as well as a service.

- **Where an added field's values live.** Locally, an instance beside the
  form's is easy; on the service, the model has no property for it. An
  extension property bag per entity, or only in the local store until the
  model has the fact type?
- **Who may make a field stricter.** An app's customization, surely; a
  user's own, in the running app, could make a colleague's form refuse what
  the model allows. Per user only, or per team with someone's say-so?
- **The paper itself.** Everything above taken from it comes from its
  abstract and summaries; the full text may say otherwise, and should be
  read if it can be had.
