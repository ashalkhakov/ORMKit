# Forms: fact selections as XForms

A form is a part of the model that a user fills in or reads: some facts about
one object, what must hold of them, and where they come from and go to. Here
a form is said in the model's terms, as a conceptual query is
([QUERIES.md](QUERIES.md)), and generated as an XForms document: an instance,
its binds, its controls, and its submissions. It runs against a service or,
offline, against the app's own Core Data store. How it looks, and how it is
laid out, is not the model's business; any XForms processor can run it, a
native UI can be laid out over it, and its developers can customize it without
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
  ([Flows](#flows-forms-and-the-ways-between-them)). Refused, each violation is
  shown at its node: the service's 400 details, or the save's validation
  errors (`NSValidationKeyErrorKey` names the property, which names the
  node). Deontic violations come back as warnings and do not refuse it.

A store's changes made elsewhere (a sync, an undo) while a form is open
reach it as a new read of what changed: the form's instance follows its
objects, as the spike's mirror did.

## Flows: forms and the ways between them

An application is more than one form: a list of vehicles leads to a
vehicle, a vehicle to its fill-ups, a fill-up to its form, and a form back
when it is saved. The paper's screen transition diagrams model that: forms
as screens, and transitions between them, each taken on an atomic action (a
submission, a choice, a cancel). What happens within a form is not part of
the diagram; the form says that itself.

It is what a design tool's prototyping does. In Figma a prototype is
frames, connections from a frame's element to another frame on an
interaction, overlays shown over a frame, and a flow's starting point;
people click through it before anything is built. A flow here is the same,
in the model's terms:

| Figma | Here |
| --- | --- |
| a frame | a form, or a list (a query whose rows lead somewhere) |
| a connection, on a click | a transition, on an action: a submission done, refused, cancelled; a row chosen; a trigger |
| what the next frame shows | what the next form is given: its given nodes, bound to the facts of the one before (the vehicle chosen) |
| an overlay | a modal form: it returns to the one it was opened over, with what it made (a new expense kind chosen as soon as it exists) |
| a flow's starting point | an entry: where the app, or a task, begins |

And it can be clicked through before an app exists, more truly than a
prototype: the forms are generated, and they run against the model's sample
population ([POPULATIONS.md](POPULATIONS.md)) in a local store made of it.
A domain expert walks the flow with real-looking facts, a refusal says a
real rule in its own words, and what they ask for that the model lacks is
found there, not in production.

In XForms a transition is what a submission's `xforms-submit-done` or
`xforms-submit-error`, or a trigger's `DOMActivate`, does: load the next form
(`xf:load`), with its given values. A flow is generated into those actions;
the forms themselves do not name each other.

**BPMN** sees the same from the process's side. A user task is performed
with a form or a flow: the task's input data are its entry's given nodes,
its output what was submitted, and a gateway after it reads the facts it
asserted. A flow is one actor's dialogue; a process is who does what, in
which order, across actors. The bridge from BPMN to ORM2 (in the works) is
then a fact selection per data object, which a form already is.

### Flow files

A flow is about screens, which the model is not, so it lives in a file of
its own beside the `.orm`, one file a flow (`Logbook.orm`, `Records.flow`,
`Schedules.flow`). It names its model and refers to the model's forms and
queries by id, with their names beside for a reader; a form or query the
model no longer has is reported, as a customization's is. XML in ORMKit's
own namespace, as the queries in the `.orm` are:

```xml
<flow:Flow xmlns:flow="http://schemas.ormkit.org/2026-10/Flows"
           Name="Records" Model="Logbook.orm">
  <flow:Entry Name="Start" Screen="_s1"/>
  <flow:Screen id="_s1" Query="_qVehicles" Name="Vehicles" X="0" Y="0" Width="390" Height="844"/>
  <flow:Screen id="_s2" Query="_qRecords" Name="Records" X="480" Y="0" Width="390" Height="844"/>
  <flow:Screen id="_s3" Form="_fFillUp" Name="RecordFillUp" X="960" Y="0" Width="390" Height="844"/>
  <flow:Transition From="_s1" On="RowChosen" To="_s2">
    <flow:Give Node="_n.vehicle" From="row"/>
  </flow:Transition>
  <flow:Transition From="_s2" On="Trigger" Control="addFillUp" To="_s3">
    <flow:Give Node="_n.fillUp.vehicle" From="_s2.vehicle"/>
  </flow:Transition>
  <flow:Transition From="_s3" On="SubmitDone" To="_s2"/>
  <flow:Transition From="_s3" On="Cancel" Kind="Back"/>
</flow:Flow>
```

### Its canvas

A flow is drawn on a canvas of its own, not on the model's diagram: a
`.flow` is a document with its own window, opened with the model it names.
Its screens are frames on the canvas, each drawn as its form is (the
generated controls, laid out as the customization lays them out, rendered
by XFormsKit), its transitions arrows from a screen or a control to a
screen, its entries marked. Editing it changes the flow file and nothing
else: a form's layout is edited in XFormsKit's designer, the model in its
own. **Play** runs the flow from an entry over the sample population
([Flows](#flows-forms-and-the-ways-between-them)).

### A little Figma

No standard covers what Figma does: its file format and its prototypes are
its own. The nearest standard is OMG's IFML (Interaction Flow Modeling
Language): view containers, events, navigation flows and their binding to a
domain model. That is a flow's semantics, without any of its look, and a
check on our terms; we do not use its format. So a flow file is our own
small subset of what a design tool keeps, enough to draw a flow and click
through it:

| Kept | Not kept |
| --- | --- |
| a screen: a frame on a canvas, its place and size, the form or list it shows (or a placeholder: a screen not yet a form) | drawing: vectors, styles, effects, images, fonts |
| a transition: from a screen, or a control of its form, on an event, to a screen | auto layout, constraints, variants, component libraries |
| its kind: navigate, overlay (modal), back, close the overlay | animations: a transition is instant |
| what it gives the next screen | comments, versions, collaborators |
| entries (a flow's starting points) | |

What is inside a screen is not in the flow file: the form's controls, and
where they are, are the form's and its customization's
([Customizing](#customizing-generated-forms-and-what-people-add)). A flow
draws each screen from them; it does not keep a copy.

**From Figma.** Figma's REST API reads a file: its pages, the frames on
them, each node's prototype interactions (a trigger, an action: navigate,
open an overlay, back, close, and its destination), and each page's flow
starting points. Importing maps them to a flow:
- a frame named as a form or a query (`RecordFillUp`) is that screen; any
  other frame is a placeholder screen;
- a layer named as a control's id in a frame of a form is that control; its
  place seeds the customization's layout;
- a layer that looks like a field and names nothing the form has is a
  provisional field: the form is under construction
  ([Customizing](#customizing-generated-forms-and-what-people-add)), and
  the modeller is asked;
- interactions become transitions, starting points entries.

**To Figma.** Figma's REST API does not, as far as we know, create frames;
a Figma plugin does (its Plugin API makes frames, layers and prototype
reactions). So exporting is a plugin of its own, given a flow and its forms
(as JSON), that draws each screen as a frame with the form's controls as
labelled placeholders, and the transitions as reactions. It keeps each
element's id in the plugin data Figma stores with a node, so that the
next import matches by id, not by name, and a designer's renaming loses
nothing.

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

An app's developers change a generated form: they lay it out, relabel it,
group and order its fields, hide some, add help, make a field required that
the model leaves optional, add a field the model does not have yet. The
model changes too, and the form is generated again. Neither may undo the
other. Customizing is the developers' work, kept with the app's sources;
the app's users do not change its forms.

**So nobody edits what is generated.** A form is two layers, kept apart and
applied in order when the form is opened:

1. **The generated form:** instances, binds, submissions, default controls.
   Written by `ormtool xforms`, never edited, replaced whole when the model
   changes.
2. **The customization:** a document of its own that refers to the
   generated one and says only what differs, made in XFormsKit's designer
   or by hand.

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
| add a field the model does not have | makes the form **under construction** (below) |

XForms 1.1 does not allow two binds to set the same property of one node,
so layers are not two documents at run time: opening a form applies them in
order to the generated document and runs the result. A native layout (a
XIB, a storyboard) is a customization too: its controls name the generated
ones by id, and whatever it does not lay out is not shown.

**A form under construction does not run.** A field the model has no fact
type for has nowhere to go: no property in the store, none in the service,
no rule that says what it may hold. So a customization that adds one marks
its form under construction, and the form is refused when it is opened,
saying which fields are provisional, until the model has the fact types
they ask for and the form is generated again with them. Nothing provisional
is ever stored.

Under construction, a form is still useful where nothing is stored: in the
designer, and walked through over the sample population
([Flows](#flows-forms-and-the-ways-between-them)), where its provisional
fields are shown as such. Each one is a question for the modeller: the
paper's first direction again, a form seeding the model.

## Seeding the model from forms

The other direction, the paper's first: an existing form (an XForms
document, or a sample filled in) proposes fact types. Its instance's
elements are candidate object types and roles, its binds candidate
constraints, and a filled instance a sample population to check them
against ([POPULATIONS.md](POPULATIONS.md)). So does a form under
construction: each provisional field, with the sample values it was walked
through with. Later, after forms are generated.

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
8. **Customizations:** stable ids, the layer applied over the generated
   form, the binds combined, references to what is gone reported; a form
   with provisional fields under construction and refused; the designer
   editing the layer, not the form.
9. **Logbook:** one form generated and laid out natively, offline; then the
   checklists, whose questions are data, as forms of their own.
10. **Flows:** `.flow` files read and written; screens, transitions,
    entries; generated into the forms' actions; walked through over the
    sample population; a modal form returning what it made. Their canvas:
    a document window of its own, screens drawn from their forms, Play.
11. **Figma:** import through its REST API (frames, interactions, starting
    points, layers named as controls); export through a plugin of our own,
    ids kept in plugin data.
12. **Processes:** a BPMN user task performed with a form or a flow.
13. **Later:** provisional fields, with their walked-through values,
    proposed to the modeller as fact types.

## Open questions

Settled:
- a form may have several anchors;
- deontic constraints warn and never prevent a submission;
- labels are the form's own or the roles' names;
- a form runs against a local store as well as a service;
- customizing is the developers' work, not the users';
- a form with fields the model lacks is under construction and does not
  run; nothing provisional is stored.

- flows live in files of their own beside the `.orm`, a small subset of
  what Figma keeps, imported from and exported to Figma.
- a flow is drawn on a canvas of its own, not on the model's diagram.

Open:
- **What Figma's API allows.** That its REST API reads prototypes but
  cannot create frames, so that export needs a plugin, is to be checked
  against its current documentation before either is built.
- **Where the plugin lives.** A Figma plugin is TypeScript, built and
  published apart: a repository of its own.

- **The paper itself.** Everything above taken from it comes from its
  abstract and summaries; the full text may say otherwise, and should be
  read if it can be had.
